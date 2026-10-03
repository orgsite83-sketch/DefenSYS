import 'package:web/web.dart' as web;

import 'package:defensys/config/web_app_config.dart';

bool redirectToSharedWebAddress() {
  final destination = WebAppConfig.canonicalUrl(Uri.base);
  if (destination == null) return false;
  web.window.location.replace(destination.toString());
  return true;
}
