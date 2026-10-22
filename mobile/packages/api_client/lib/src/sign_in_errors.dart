import 'dart:async';

import 'package:dio/dio.dart';
import 'package:yazan_domain/yazan_domain.dart';

/// What a sign-in screen should say about an error it does not map to a message of its own.
enum SignInTrouble {
  /// The site has no such route yet (404, `rest_no_route`): the website is not updated for the app.
  websiteNotUpdated,

  /// No connection, or the site did not answer in time.
  connection,

  /// Anything else: a generic message plus [signInErrorCode], so the owner can report it.
  other,
}

const _connectionTypes = {
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
  DioExceptionType.connectionError,
};

/// Sorts an error from a sign-in call (password, second step, website code exchange).
SignInTrouble signInTrouble(Object error) {
  if (error is ApiError) {
    if (error.status == 404 || error.code == 'rest_no_route') return SignInTrouble.websiteNotUpdated;
    return SignInTrouble.other;
  }
  if (error is DioException) {
    final type = error.type;
    if (_connectionTypes.contains(type)) return SignInTrouble.connection;
    // A socket failure or a timeout the adapter did not classify (no network, DNS, reset).
    if (type == DioExceptionType.unknown &&
        (error.error is TimeoutException || '${error.error.runtimeType}'.contains('Socket'))) {
      return SignInTrouble.connection;
    }
    return SignInTrouble.other;
  }
  if (error is TimeoutException) return SignInTrouble.connection;
  return SignInTrouble.other;
}

/// A short technical line to show in small print under the generic message, e.g.
/// `code: rest_invalid_param, 400`. Never carries a token, a password or a response body.
String signInErrorCode(Object error) {
  if (error is ApiError) return 'code: ${error.code}, ${error.status}';
  if (error is DioException) return 'code: network_${error.type.name}';
  return 'code: ${error.runtimeType}';
}
