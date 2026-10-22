import 'package:url_launcher/url_launcher.dart';

/// Opens a page of the website outside the app (tests pass a recorder instead).
typedef LinkOpener = Future<void> Function(Uri uri);

/// The phone's browser. A page that cannot be opened is left alone: nothing in the app depends on it.
Future<void> openInBrowser(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No browser, or the platform refused: the customer can open the site themselves.
  }
}

/// The website's own pages the app links to (slugs as published by the site's legal pages).
class SiteLinks {
  const SiteLinks._();

  static Uri terms(String baseUrl) => _page(baseUrl, 'terms-and-conditions');

  static Uri privacy(String baseUrl) => _page(baseUrl, 'privacy-policy');

  /// Where a customer can ask for the account to be deleted without the app (for example an account
  /// that signs in with Google only, or a customer who no longer has the app).
  static Uri accountDeletion(String baseUrl) => _page(baseUrl, 'account-deletion');

  static Uri _page(String baseUrl, String slug) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/$slug/');
  }
}
