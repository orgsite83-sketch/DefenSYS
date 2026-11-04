class AppRelease {
  const AppRelease({
    required this.version,
    required this.build,
    required this.id,
    this.download,
    this.sizeBytes,
    this.sha256,
  });
  final String version;
  final int build;
  final String id;
  final Uri? download;
  final int? sizeBytes;
  final String? sha256;
}

class ReleaseCatalog {
  const ReleaseCatalog({this.web, this.android});
  final AppRelease? web;
  final AppRelease? android;

  factory ReleaseCatalog.parse(
    Map<String, dynamic> data,
    Uri origin, {
    String applicationId = 'com.example.user',
  }) {
    if (data['schema_version'] != 1) {
      throw const FormatException('Unsupported release information.');
    }
    AppRelease? read(dynamic raw, bool android) {
      if (raw == null || (android && raw is Map && raw['available'] == false)) {
        return null;
      }
      if (raw is! Map) {
        throw const FormatException('Invalid release information.');
      }
      final version = raw['version'];
      final build = raw['build'];
      if (version is! String ||
          !RegExp(
            r'^\d{1,5}\.\d{1,5}\.\d{1,5}(?:[-+][A-Za-z0-9.-]{1,40})?$',
          ).hasMatch(version) ||
          build is! int ||
          build < 1 ||
          build > 2100000000) {
        throw const FormatException('Invalid release version.');
      }
      if (!android) {
        final id = raw['release_id'];
        if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
          throw const FormatException('Invalid web release.');
        }
        return AppRelease(version: version, build: build, id: id);
      }
      final url = Uri.tryParse('${raw['download_url'] ?? ''}');
      final size = raw['size_bytes'];
      final checksum = raw['sha256'];
      if (raw['available'] != true ||
          raw['application_id'] != applicationId ||
          url == null ||
          url.scheme != 'https' ||
          url.origin != origin.origin ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment ||
          !RegExp(
            r'^/releases/android/[A-Za-z0-9._-]+\.apk$',
          ).hasMatch(url.path) ||
          size is! int ||
          size < 1 ||
          size > 2147483648 ||
          checksum is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        throw const FormatException('Invalid Android release.');
      }
      return AppRelease(
        version: version,
        build: build,
        id: 'android-$build',
        download: url,
        sizeBytes: size,
        sha256: checksum,
      );
    }

    return ReleaseCatalog(
      web: read(data['web'], false),
      android: read(data['android'], true),
    );
  }
}

class RunningRelease {
  const RunningRelease({
    required this.version,
    required this.build,
    required this.id,
    required this.isWeb,
    this.isAndroid = false,
  });
  final String version;
  final int build;
  final String id;
  final bool isWeb;
  final bool isAndroid;
  AppRelease? latest(ReleaseCatalog? catalog) => isWeb
      ? catalog?.web
      : isAndroid
      ? catalog?.android
      : null;
  bool newer(ReleaseCatalog? catalog) =>
      build > 0 && (latest(catalog)?.build ?? 0) > build;
}
