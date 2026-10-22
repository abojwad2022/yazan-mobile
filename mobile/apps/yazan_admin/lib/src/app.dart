import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../l10n/app_localizations.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'security/app_lock_controller.dart';
import 'security/app_lock_scope.dart';
import 'session_events.dart';
import 'storage/account_lifecycle.dart';
import 'storage/admin_stores.dart';

/// The app shell. The client is injected so tests and previews never touch the network.
///
/// [accounts] turns on the encrypted per-account storage (see [AccountLifecycle]); without it the
/// feeds and the outbox stay in memory, which is what the tests use. [events] is how the client
/// tells the shell that the server ended the session.
class YazanApp extends StatefulWidget {
  const YazanApp({
    super.key,
    required this.client,
    required this.tokens,
    this.accounts,
    this.events,
    this.lock,
    this.webSignIn,
  });

  final YazanApiClient client;
  final TokenStore tokens;
  final AccountLifecycle? accounts;
  final SessionEvents? events;

  /// The app lock (see `security/`); null runs without one, which is what most tests do.
  final AppLockController? lock;

  /// The website sign-in ("Sign in with the website"). Tests inject one with a fake browser; null =
  /// the system auth browser on the site [client] talks to.
  final WebSignIn? webSignIn;

  @override
  State<YazanApp> createState() => _YazanAppState();
}

class _YazanAppState extends State<YazanApp> {
  final _navigator = GlobalKey<NavigatorState>();

  /// null while the session or the account is being worked out.
  bool? _signedIn;
  AdminStores? _stores;
  bool _noticeScheduled = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    widget.events?.onEnded = _onSessionEnded;
    _boot();
  }

  @override
  void dispose() {
    widget.events?.onEnded = null;
    super.dispose();
  }

  Future<void> _boot() async {
    final session = await widget.tokens.read();
    if (!mounted) return;
    final accounts = widget.accounts;
    if (session == null) {
      // Nobody is signed in, so nothing of anybody may be on the phone. This finishes a sign-out
      // or a revocation that was cut short (app killed, wipe failed).
      await accounts?.forget(null);
      if (!mounted) return;
      setState(() => _signedIn = false);
    } else {
      final stores = accounts == null ? MemoryAdminStores() : await accounts.forExistingSession();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _signedIn = true;
      });
      _verify(stores);
    }
    _scheduleStorageNotice();
  }

  /// Once per start, asks the server who this really is. A different account than the cache
  /// belongs to means the cache is wiped; a refusal means the account lost its access.
  Future<void> _verify(AdminStores stores) async {
    final accounts = widget.accounts;
    if (accounts == null) return;
    final check = await accounts.verify(stores);
    if (!mounted || _stores != stores) return;
    switch (check.kind) {
      case AccountCheckKind.same:
      case AccountCheckKind.unknown:
        return;
      case AccountCheckKind.switched:
        _navigator.currentState?.popUntil((r) => r.isFirst);
        setState(() => _stores = check.stores);
      case AccountCheckKind.accessLost:
        _navigator.currentState?.popUntil((r) => r.isFirst);
        _stores = null;
        await widget.client.logout();
        if (mounted) setState(() => _signedIn = false);
    }
  }

  Future<void> _onSignedIn() async {
    // Signing in is proof enough: do not lock the person out of the session they just opened.
    widget.lock?.markUnlocked();
    final accounts = widget.accounts;
    if (accounts == null) {
      setState(() {
        _stores = MemoryAdminStores();
        _signedIn = true;
      });
      return;
    }
    setState(() => _signedIn = null);
    final stores = await accounts.forNewSession();
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _signedIn = true;
    });
  }

  /// A deliberate sign-out: the home screen has already wiped and logged out.
  Future<void> _onSignedOut() async {
    await _discard();
    if (mounted) setState(() => _signedIn = false);
  }

  /// The server ended the session (refresh token refused): same wipe, no questions asked.
  Future<void> _onSessionEnded() async {
    if (_signedIn != true || _ending) return;
    _ending = true;
    try {
      _navigator.currentState?.popUntil((r) => r.isFirst);
      await _discard();
      if (mounted) setState(() => _signedIn = false);
    } finally {
      _ending = false;
    }
  }

  Future<void> _discard() async {
    final stores = _stores;
    _stores = null;
    final accounts = widget.accounts;
    try {
      if (accounts != null) {
        await accounts.forget(stores);
      } else {
        await stores?.wipe();
      }
    } catch (_) {
      // The remembered account id is kept when a wipe fails, so the next start removes the data.
    }
  }

  /// Tells the person, once, that the encrypted file had to be replaced.
  void _scheduleStorageNotice() {
    if (_noticeScheduled || widget.accounts?.storageRecreated != true) return;
    _noticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The overlay sits below the Navigator and the localisations, which `showDialog` needs.
      final overlay = _navigator.currentState?.overlay;
      if (!mounted || overlay == null) return;
      final l = AppLocalizations.of(overlay.context);
      showDialog<void>(
        context: overlay.context,
        builder: (dialog) => AlertDialog(
          key: const ValueKey('storage-reset-notice'),
          title: Text(l.storageResetTitle),
          content: Text(l.storageResetBody),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.storageResetOk)),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final stores = _stores;
    return MaterialApp(
      navigatorKey: _navigator,
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      theme: yazanTheme(YazanThemeVariant.black),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final lock = widget.lock;
        if (lock == null || child == null) return child ?? const SizedBox.shrink();
        return AppLockScope(controller: lock, active: _signedIn != false, child: child);
      },
      home: switch (_signedIn) {
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        true => HomePage(
            // A new account gets a fresh screen: nothing of the previous one is carried over.
            key: ValueKey('home-${stores?.accountId}'),
            client: widget.client,
            stores: stores,
            onSignedOut: _onSignedOut,
            onSessionEnded: _onSessionEnded,
            lock: widget.lock,
          ),
        false => LoginPage(
            client: widget.client,
            webSignIn: widget.webSignIn,
            onSignedIn: _onSignedIn,
          ),
      },
    );
  }
}
