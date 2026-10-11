import 'package:url_launcher/url_launcher.dart';

/// Opens a page outside the app (a source's website, a donation page).
abstract class UrlOpener {
  Future<bool> open(Uri url);
}

class LauncherUrlOpener implements UrlOpener {
  const LauncherUrlOpener();

  /// Links in book data come from other people's servers, so only web links with a host are opened:
  /// not an `intent:` (Android) or `file:` URL, whatever a record says.
  static bool isWebLink(Uri url) => (url.scheme == 'https' || url.scheme == 'http') && url.host.isNotEmpty;

  @override
  Future<bool> open(Uri url) async =>
      isWebLink(url) && await launchUrl(url, mode: LaunchMode.externalApplication);
}
