import 'package:flutter/widgets.dart';

import 'biometric_gate.dart';
import 'lock_settings_store.dart';

/// How long the app may stay in the background before it asks again.
const Duration defaultLockTimeout = Duration(seconds: 60);

/// Decides when the app is covered and when it is locked.
///
/// * Covered: the app is not in the foreground (or the system is about to snapshot it). The content
///   is hidden at once, so the task switcher shows the cover, not customers.
/// * Locked: it was away for more than [timeout] (or the app was just started). Needs the gate.
///
/// Never a lock-out: when the phone has nothing to check against the app does not lock and says so
/// once; wrong or cancelled attempts keep it locked and offer another try, they never sign out.
class AppLockController extends ChangeNotifier {
  AppLockController({
    required this.gate,
    required this.settings,
    DateTime Function()? now,
    this.timeout = defaultLockTimeout,
  }) : _now = now ?? DateTime.now;

  final BiometricGate gate;
  final LockSettingsStore settings;
  final Duration timeout;
  final DateTime Function() _now;

  bool _enabled = false;
  bool _available = false;
  bool _locked = false;
  bool _hidden = false;
  bool _authenticating = false;
  bool _lastFailed = false;
  bool _notice = false;
  int _failures = 0;
  DateTime? _leftAt;

  /// The "Require unlock" switch (the stored choice; on by default when the phone can check).
  bool get enabled => _enabled;

  /// The phone has something to check against.
  bool get available => _available;

  /// The lock is actually in force.
  bool get shouldGuard => _enabled && _available;
  bool get locked => _locked;
  bool get covered => _locked || _hidden;
  bool get authenticating => _authenticating;
  bool get lastFailed => _lastFailed;
  int get failures => _failures;

  /// The one-time "this phone cannot lock the app" message is waiting to be shown.
  bool get noticePending => _notice;

  /// A prompt should be raised now (locked, nothing running, and the person has not just failed).
  bool get wantsPrompt => _locked && !_authenticating && !_lastFailed;

  /// Reads the stored choice and the phone's capability. Call once before the first frame; the
  /// app starts locked when the lock is on.
  Future<void> init() async {
    _available = await _can();
    final stored = await settings.read();
    _enabled = stored ?? _available;
    if (!_available) {
      _notice = true;
    } else if (_enabled) {
      _locked = true;
    }
    notifyListeners();
  }

  Future<bool> _can() async {
    try {
      return await gate.canCheck();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ask(String reason) async {
    _authenticating = true;
    notifyListeners();
    var ok = false;
    try {
      ok = await gate.authenticate(reason);
    } catch (_) {
      ok = false;
    }
    _authenticating = false;
    return ok;
  }

  void dismissNotice() {
    if (!_notice) return;
    _notice = false;
    notifyListeners();
  }

  /// A fresh sign-in is the person proving who they are: nothing to unlock yet.
  void markUnlocked() {
    _locked = false;
    _hidden = false;
    _lastFailed = false;
    _leftAt = null;
    notifyListeners();
  }

  /// Feed this from `didChangeAppLifecycleState`. Ignored while a system prompt is up (the prompt
  /// itself sends the app through inactive/resumed).
  void handleLifecycle(AppLifecycleState state) {
    if (_authenticating) return;
    switch (state) {
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        _hidden = false;
        if (left != null && shouldGuard && _now().difference(left) > timeout) {
          _locked = true;
          _lastFailed = false;
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _hidden = shouldGuard;
        _leftAt ??= _now();
    }
    notifyListeners();
  }

  /// Raises the prompt. Returns true when the app is unlocked afterwards.
  Future<bool> unlock(String reason) async {
    if (!_locked) return true;
    if (_authenticating) return false;
    if (!await _can()) {
      // The credential was removed meanwhile: never lock the person out.
      _available = false;
      _locked = false;
      _hidden = false;
      _notice = true;
      notifyListeners();
      return true;
    }
    final ok = await _ask(reason);
    if (ok) {
      _locked = false;
      _hidden = false;
      _leftAt = null;
      _lastFailed = false;
    } else {
      _lastFailed = true;
      _failures++;
    }
    notifyListeners();
    return ok;
  }

  /// A one-off check for a sensitive action (refund, price change). True = go ahead. Passes without
  /// asking when the lock is off or the phone cannot check, like the lock itself.
  Future<bool> confirm(String reason) async {
    if (!shouldGuard) return true;
    if (_authenticating) return false;
    if (!await _can()) return true;
    final ok = await _ask(reason);
    notifyListeners();
    return ok;
  }

  /// Turns the lock on or off. On needs a phone that can check; off asks the person first.
  /// Returns whether the switch now has the requested value.
  Future<bool> setEnabled(bool value, {required String reason}) async {
    if (value == _enabled) return true;
    if (value) {
      if (!await _can()) {
        _available = false;
        notifyListeners();
        return false;
      }
      _available = true;
      _enabled = true;
    } else {
      if (shouldGuard && !await _ask(reason)) {
        notifyListeners();
        return false;
      }
      _enabled = false;
      _locked = false;
      _hidden = false;
      _lastFailed = false;
    }
    await settings.write(_enabled);
    notifyListeners();
    return true;
  }
}
