import 'package:web/web.dart' as web;

void refreshWebRelease(String releaseId) {
  final current = Uri.parse(web.window.location.href);
  // Preserve the hash route, invitation code, and all existing query parameters.
  final target = current.replace(
    queryParameters: {...current.queryParameters, 'release': releaseId},
  );
  web.window.location.replace(target.toString());
}
