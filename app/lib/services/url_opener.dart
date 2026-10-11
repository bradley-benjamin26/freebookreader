import 'package:url_launcher/url_launcher.dart';

/// Opens a page outside the app (a source's website, a donation page).
abstract class UrlOpener {
  Future<bool> open(Uri url);
}

class LauncherUrlOpener implements UrlOpener {
  const LauncherUrlOpener();

  @override
  Future<bool> open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}
