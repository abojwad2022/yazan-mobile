import 'package:yazan_domain/yazan_domain.dart';

import '../../l10n/app_localizations.dart';

/// Why an account or favourites request failed, in terms the screens can act on.
enum FailureKind { offline, signedOut, rateLimited, unavailable, notFound, other }

class Failure implements Exception {
  const Failure(this.kind);

  /// Maps whatever a request threw: a server answer ([ApiError]) or a network problem.
  factory Failure.from(Object error) {
    if (error is Failure) return error;
    if (error is ApiError) {
      if (error.status == 429 || error.action == ErrorAction.backOff) {
        return const Failure(FailureKind.rateLimited);
      }
      if (error.status == 401 ||
          error.action == ErrorAction.signIn ||
          error.action == ErrorAction.refreshThenRetry) {
        return const Failure(FailureKind.signedOut);
      }
      if (error.action == ErrorAction.hideFeature || error.status == 403) {
        return const Failure(FailureKind.unavailable);
      }
      if (error.status == 404) return const Failure(FailureKind.notFound);
      return const Failure(FailureKind.other);
    }
    // A malformed answer is a bug or a server problem, not a connection problem.
    if (error is FormatException || error is TypeError) {
      return const Failure(FailureKind.other);
    }
    return const Failure(FailureKind.offline);
  }

  final FailureKind kind;

  bool get isSignedOut => kind == FailureKind.signedOut;

  @override
  String toString() => 'Failure($kind)';
}

/// A short, polite message for a failure.
String failureMessage(AppLocalizations l, Failure f) {
  switch (f.kind) {
    case FailureKind.offline:
      return l.offlineAccount;
    case FailureKind.signedOut:
      return l.sessionEnded;
    case FailureKind.rateLimited:
      return l.tooManyAttempts;
    case FailureKind.unavailable:
      return l.featureUnavailable;
    case FailureKind.notFound:
      return l.notFoundError;
    case FailureKind.other:
      return l.genericError;
  }
}
