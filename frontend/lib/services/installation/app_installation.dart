import 'package:flutter/foundation.dart';

import 'app_installation_stub.dart'
    if (dart.library.js_interop) 'app_installation_web.dart'
    as platform;

enum InstallPlatform { android, ios, desktop, native }

class InstallationState {
  const InstallationState({
    this.platform = InstallPlatform.native,
    this.isWeb = false,
    this.installed = false,
    this.canPrompt = false,
    this.secure = false,
  });
  final InstallPlatform platform;
  final bool isWeb;
  final bool installed;
  final bool canPrompt;
  final bool secure;
}

abstract class AppInstallation extends ChangeNotifier {
  InstallationState get state;
  Future<String> install();
}

AppInstallation createAppInstallation() => platform.createAppInstallation();
