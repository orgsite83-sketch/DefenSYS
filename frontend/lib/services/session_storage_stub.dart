import 'auth_storage_keys.dart';

/// Non-web fallback (tests / desktop) — uses in-memory map.
class SessionStorageImpl implements SessionStorageBase {
  SessionStorageImpl._();

  static final Map<String, String> _memory = {};

  static Future<SessionStorageBase> create({required bool rememberMe}) async {
    return SessionStorageImpl._();
  }

  @override
  Future<String?> readRefresh() async => _memory[AuthStorageKeys.refresh];

  @override
  Future<void> writeRefresh(String? value) async {
    if (value == null) {
      _memory.remove(AuthStorageKeys.refresh);
    } else {
      _memory[AuthStorageKeys.refresh] = value;
    }
  }

  @override
  Future<String?> readUserJson() async => _memory[AuthStorageKeys.user];

  @override
  Future<void> writeUserJson(String? value) async {
    if (value == null) {
      _memory.remove(AuthStorageKeys.user);
    } else {
      _memory[AuthStorageKeys.user] = value;
    }
  }

  @override
  Future<void> clearAuth() async {
    _memory.remove(AuthStorageKeys.refresh);
    _memory.remove(AuthStorageKeys.user);
  }

  @override
  Future<void> clearOtherWebStores(bool rememberMe) async {}
}

void installWebStorageListener(void Function(Map<String, dynamic> data) onMessage) {}

void broadcastAuthToTabs(Map<String, dynamic> payload) {}

abstract class SessionStorageBase {
  Future<String?> readRefresh();
  Future<void> writeRefresh(String? value);
  Future<String?> readUserJson();
  Future<void> writeUserJson(String? value);
  Future<void> clearAuth();
  Future<void> clearOtherWebStores(bool rememberMe);
}
