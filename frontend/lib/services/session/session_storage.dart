import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_storage_keys.dart';
import 'session_storage_stub.dart' show SessionStorageBase;
import 'session_storage_stub.dart'
    if (dart.library.html) 'session_storage_web.dart'
    if (dart.library.io) 'session_storage_mobile.dart'
    as store;

/// Persists refresh token and user JSON (web: session vs local; mobile: secure).
class SessionStorage {
  SessionStorage._(this._impl, this.rememberMe);

  final SessionStorageBase _impl;
  final bool rememberMe;

  static Future<SessionStorage> create({required bool rememberMe}) async {
    final impl = await store.SessionStorageImpl.create(rememberMe: rememberMe);
    return SessionStorage._(impl, rememberMe);
  }

  /// Restore storage for startup using saved [remember_me] preference.
  static Future<SessionStorage?> createForRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(AuthStorageKeys.rememberMe) ?? false;

    if (kIsWeb) {
      // Try sessionStorage first (survives in-tab refreshes).
      final session =
          await store.SessionStorageImpl.create(rememberMe: rememberMe);
      final sessionRefresh = await session.readRefresh();

      if (sessionRefresh != null && sessionRefresh.isNotEmpty) {
        return SessionStorage._(session, rememberMe);
      }

      // sessionStorage was empty — try to restore from tab-scoped
      // localStorage (covers full browser restart with remember-me).
      if (rememberMe) {
        final restored =
            await store.SessionStorageImpl.tryRestoreFromLocalStorage();
        if (restored != null) {
          return SessionStorage._(restored, true);
        }
      }

      return null;
    }

    // Mobile: single secure store.
    final impl = await store.SessionStorageImpl.create(rememberMe: false);
    final refresh = await impl.readRefresh();
    if (refresh == null || refresh.isEmpty) return null;
    return SessionStorage._(impl, rememberMe);
  }

  Future<String?> readRefresh() => _impl.readRefresh();

  Future<void> writeRefresh(String? value) => _impl.writeRefresh(value);

  Future<String?> readUserJson() => _impl.readUserJson();

  Future<void> writeUserJson(String? value) => _impl.writeUserJson(value);

  Future<void> clearAuth() => _impl.clearAuth();

  Future<void> clearOtherWebStores() =>
      _impl.clearOtherWebStores(rememberMe);

  static Future<void> persistRememberMeChoice(bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthStorageKeys.rememberMe, rememberMe);
  }

  static Future<bool> loadRememberMeChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AuthStorageKeys.rememberMe) ?? false;
  }

  static Future<void> clearLegacyPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthStorageKeys.legacyJwtToken);
    await prefs.remove(AuthStorageKeys.legacyUserData);
  }
}
