import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_storage_keys.dart';
import 'session_storage_stub.dart';

class SessionStorageImpl extends SessionStorageBase {
  SessionStorageImpl(this._storage);

  final FlutterSecureStorage _storage;

  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  static Future<SessionStorageBase> create({required bool rememberMe}) async {
    return SessionStorageImpl(
      const FlutterSecureStorage(aOptions: _options),
    );
  }

  @override
  Future<String?> readRefresh() => _storage.read(key: AuthStorageKeys.refresh);

  @override
  Future<void> writeRefresh(String? value) async {
    if (value == null) {
      await _storage.delete(key: AuthStorageKeys.refresh);
    } else {
      await _storage.write(key: AuthStorageKeys.refresh, value: value);
    }
  }

  @override
  Future<String?> readUserJson() => _storage.read(key: AuthStorageKeys.user);

  @override
  Future<void> writeUserJson(String? value) async {
    if (value == null) {
      await _storage.delete(key: AuthStorageKeys.user);
    } else {
      await _storage.write(key: AuthStorageKeys.user, value: value);
    }
  }

  @override
  Future<void> clearAuth() async {
    await _storage.delete(key: AuthStorageKeys.refresh);
    await _storage.delete(key: AuthStorageKeys.user);
  }

  @override
  Future<void> clearOtherWebStores(bool rememberMe) async {}
}

void installWebStorageListener(void Function(Map<String, dynamic> data) onMessage) {}

void broadcastAuthToTabs(Map<String, dynamic> payload) {}
