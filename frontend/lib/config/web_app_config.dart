/// Optional shared browser origin for local Wi-Fi sessions.
/// Leave unset for deployments that already use a public address.
class WebAppConfig {
  static const origin = String.fromEnvironment('DEFENSYS_WEB_ORIGIN');

  /// Keeps the route and invitation code when switching to the shared address.
  /// Returns null when no valid origin is configured or the address matches.
  static Uri? canonicalUrl(Uri current, {String configuredOrigin = origin}) {
    final target = Uri.tryParse(configuredOrigin);
    if (target == null ||
        !['http', 'https'].contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty ||
        (target.path.isNotEmpty && target.path != '/') ||
        target.hasQuery ||
        target.hasFragment ||
        (['http', 'https'].contains(current.scheme) &&
            current.origin == target.origin)) {
      return null;
    }
    return Uri(
      scheme: target.scheme,
      host: target.host,
      port: target.hasPort ? target.port : null,
      path: current.path,
      query: current.hasQuery ? current.query : null,
      fragment: current.hasFragment ? current.fragment : null,
    );
  }
}
