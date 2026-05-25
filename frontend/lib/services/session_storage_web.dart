// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'auth_storage_keys.dart';
import 'session_storage_stub.dart';

class SessionStorageImpl extends SessionStorageBase {
  SessionStorageImpl(this._persistent);

  final bool _persistent;

  html.Storage get _store =>
      _persistent ? html.window.localStorage : html.window.sessionStorage;

  html.Storage get _otherStore =>
      _persistent ? html.window.sessionStorage : html.window.localStorage;

  static Future<SessionStorageBase> create({required bool rememberMe}) async {
    return SessionStorageImpl(rememberMe);
  }

  @override
  Future<String?> readRefresh() async => _store[AuthStorageKeys.refresh];

  @override
  Future<void> writeRefresh(String? value) async {
    if (value == null) {
      _store.remove(AuthStorageKeys.refresh);
    } else {
      _store[AuthStorageKeys.refresh] = value;
    }
  }

  @override
  Future<String?> readUserJson() async => _store[AuthStorageKeys.user];

  @override
  Future<void> writeUserJson(String? value) async {
    if (value == null) {
      _store.remove(AuthStorageKeys.user);
    } else {
      _store[AuthStorageKeys.user] = value;
    }
  }

  @override
  Future<void> clearAuth() async {
    _store.remove(AuthStorageKeys.refresh);
    _store.remove(AuthStorageKeys.user);
    html.window.sessionStorage.remove(AuthStorageKeys.refresh);
    html.window.sessionStorage.remove(AuthStorageKeys.user);
    html.window.localStorage.remove(AuthStorageKeys.refresh);
    html.window.localStorage.remove(AuthStorageKeys.user);
  }

  @override
  Future<void> clearOtherWebStores(bool rememberMe) async {
    _otherStore.remove(AuthStorageKeys.refresh);
    _otherStore.remove(AuthStorageKeys.user);
  }
}

void installWebStorageListener(void Function(Map<String, dynamic> data) onMessage) {
  html.window.onStorage.listen((event) {
    if (event.key != AuthStorageKeys.refresh && event.key != AuthStorageKeys.user) {
      return;
    }
    final refresh = html.window.localStorage[AuthStorageKeys.refresh];
    final user = html.window.localStorage[AuthStorageKeys.user];
    if (refresh != null && user != null) {
      onMessage({'refresh': refresh, 'userJson': user});
    }
  });
}

void broadcastAuthToTabs(Map<String, dynamic> payload) {
  try {
    html.window.localStorage['_defensys_auth_ping'] = jsonEncode({
      ...payload,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    html.window.localStorage.remove('_defensys_auth_ping');
  } catch (_) {}
}
