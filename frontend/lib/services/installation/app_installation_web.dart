import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'app_installation.dart';

@JS('defensysInstallation.state')
external JSString _readState();
@JS('defensysInstallation.install')
external JSPromise<JSString> _install();

AppInstallation createAppInstallation() => _BrowserInstallation();

class _BrowserInstallation extends AppInstallation {
  late final JSFunction _listener;
  InstallationState _state = const InstallationState(isWeb: true);

  _BrowserInstallation() {
    _refresh();
    _listener = ((web.Event _) => _refresh()).toJS;
    web.window.addEventListener('defensys-install-state', _listener);
  }

  @override
  InstallationState get state => _state;

  void _refresh() {
    try {
      final data = jsonDecode(_readState().toDart) as Map;
      _state = InstallationState(
        platform: switch (data['platform']) {
          'ios' => InstallPlatform.ios,
          'android' => InstallPlatform.android,
          _ => InstallPlatform.desktop,
        },
        isWeb: true,
        installed: data['installed'] == true,
        canPrompt: data['canPrompt'] == true,
        secure: data['secure'] == true,
      );
    } catch (_) {
      // An older cached host page can lack the bridge; browser access still works.
    }
    notifyListeners();
  }

  @override
  Future<String> install() async {
    try {
      return (await _install().toDart).toDart;
    } catch (_) {
      return 'unavailable';
    } finally {
      _refresh();
    }
  }

  @override
  void dispose() {
    web.window.removeEventListener('defensys-install-state', _listener);
    super.dispose();
  }
}
