import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_lock_controller.dart';

/// Wraps the whole app (use it in `MaterialApp.builder`): feeds the controller the lifecycle,
/// covers the content while the app is away or locked and raises the system prompt.
/// [active] is false while nobody is signed in (nothing to protect on the sign-in screen).
class AppLockScope extends StatefulWidget {
  const AppLockScope({
    super.key,
    required this.controller,
    required this.active,
    required this.child,
  });

  final AppLockController controller;
  final bool active;
  final Widget child;

  /// The controller above [context], or null when the app runs without a lock.
  static AppLockController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LockInherited>()?.controller;

  @override
  State<AppLockScope> createState() => _AppLockScopeState();
}

class _AppLockScopeState extends State<AppLockScope> with WidgetsBindingObserver {
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_maybePrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  @override
  void didUpdateWidget(AppLockScope old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_maybePrompt);
      widget.controller.addListener(_maybePrompt);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_maybePrompt);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.controller.handleLifecycle(state);

  void _maybePrompt() {
    final c = widget.controller;
    if (!mounted || !widget.active || _promptScheduled || !c.wantsPrompt) return;
    _promptScheduled = true;
    Future<void>.microtask(() async {
      _promptScheduled = false;
      if (!mounted) return;
      await c.unlock(AppLocalizations.of(context).lockReason);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return _LockInherited(
      controller: c,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final cover = widget.active && c.shouldGuard && c.covered;
          final notice = widget.active && c.noticePending;
          return Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                excluding: cover,
                child: IgnorePointer(ignoring: cover, child: widget.child),
              ),
              if (cover) _LockCover(controller: c),
              if (notice) _NoticeBanner(controller: c),
            ],
          );
        },
      ),
    );
  }
}

class _LockInherited extends InheritedWidget {
  const _LockInherited({required this.controller, required super.child});

  final AppLockController controller;

  @override
  bool updateShouldNotify(_LockInherited old) => controller != old.controller;
}

class _LockCover extends StatelessWidget {
  const _LockCover({required this.controller});

  final AppLockController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('lock-cover'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(l.lockTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                if (controller.locked) ...[
                  if (controller.lastFailed) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.lockFailed,
                      key: const ValueKey('lock-failed'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('lock-unlock'),
                    onPressed: controller.authenticating
                        ? null
                        : () => controller.unlock(l.lockReason),
                    child: Text(l.lockUnlock),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.controller});

  final AppLockController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: SafeArea(
        child: Material(
          key: const ValueKey('lock-notice'),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.lockUnavailableNotice),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const ValueKey('lock-notice-ok'),
                    onPressed: controller.dismissNotice,
                    child: Text(l.lockNoticeOk),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the person to prove who they are before a sensitive action (refund, price change).
/// True = go ahead. Passes when the app runs without a lock, the owner turned "Require unlock"
/// off, or the phone has nothing to check against.
Future<bool> confirmSensitive(BuildContext context, String reason) async {
  final c = AppLockScope.maybeOf(context);
  if (c == null) return true;
  return c.confirm(reason);
}
