/// What the app should do about a server error. Codes: docs/mobile/03-ARCHITECTURE.md.
enum ErrorAction {
  refreshThenRetry,
  signIn,
  genericLoginFailure,
  hideFeature,
  enrolOnWeb,
  waitAndRetrySameKey,
  showConflict,
  clientBug,
  backOff,
  other,
}

class ApiError implements Exception {
  const ApiError({
    required this.status,
    required this.code,
    this.message = '',
    this.retryAfter,
    this.current,
  });

  factory ApiError.fromJson(int status, Object? body) {
    if (body is Map) {
      final data = body['data'];
      return ApiError(
        status: status,
        code: '${body['code'] ?? 'unknown'}',
        message: '${body['message'] ?? ''}',
        retryAfter: data is Map && data['retry_after'] is int
            ? data['retry_after'] as int
            : null,
        current: data is Map && data['current'] is String
            ? data['current'] as String
            : null,
      );
    }
    return ApiError(status: status, code: 'unknown');
  }

  final int status;
  final String code;
  final String message;
  final int? retryAfter;

  /// Server's current version token on a 412 conflict.
  final String? current;

  ErrorAction get action {
    switch (code) {
      case 'yazan_mobile_bad_token':
      case 'yazan_unauthenticated':
        return ErrorAction.refreshThenRetry;
      case 'yazan_mobile_bad_refresh':
        return ErrorAction.signIn;
      case 'yazan_mobile_bad_login':
      case 'yazan_mobile_bad_code':
        return ErrorAction.genericLoginFailure;
      case 'yazan_mobile_wrong_app':
      case 'yazan_forbidden':
      case 'yazan_mobile_bulk_unsupported':
        return ErrorAction.hideFeature;
      case 'yazan_mobile_enrol_first':
        return ErrorAction.enrolOnWeb;
      case 'yazan_idempotency_busy':
        return ErrorAction.waitAndRetrySameKey;
      case 'yazan_precondition_failed':
        return ErrorAction.showConflict;
      case 'yazan_idempotency_mismatch':
      case 'yazan_precondition_required':
        return ErrorAction.clientBug;
      case 'yazan_rate_limited':
        return ErrorAction.backOff;
    }
    return ErrorAction.other;
  }

  @override
  String toString() => 'ApiError($status $code)';
}
