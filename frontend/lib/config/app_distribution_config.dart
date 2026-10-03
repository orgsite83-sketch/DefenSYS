abstract final class AppDistributionConfig {
  static const androidDownloadUrl = String.fromEnvironment(
    'DEFENSYS_ANDROID_DOWNLOAD_URL',
  );

  static Uri? androidDownload({String value = androidDownloadUrl}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.scheme != 'https') {
      return null;
    }
    return uri;
  }
}
