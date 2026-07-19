// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:math';

import 'auth_storage_keys.dart';
import 'session_storage_stub.dart';

/// Per-tab session storage for web.
///
/// Each tab gets a unique [_tabId] stored in `sessionStorage` (naturally
/// per-tab).  Auth tokens live in `sessionStorage` so they never leak
/// across tabs.  When `rememberMe` is true a **copy** is also written to
/// `localStorage` under tab-scoped keys so the session survives a full
/// browser restart.
class SessionStorageImpl extends SessionStorageBase {
  SessionStorageImpl._(this._tabId, this._persistent);

  final String _tabId;
  final bool _persistent;

  // ---------- per-tab sessionStorage (primary) ----------
  html.Storage get _session => html.window.sessionStorage;

  // ---------- tab-scoped localStorage (remember-me backup) ----------
  String _scopedKey(String base) => AuthStorageKeys.scopedKey(base, _tabId);

  static Future<SessionStorageBase> create({required bool rememberMe}) async {
    final tabId = _getOrCreateTabId();
    return SessionStorageImpl._(tabId, rememberMe);
  }

  /// Generates a short random ID and stores it in `sessionStorage` so it
  /// survives in-tab refreshes but is unique per tab.
  static String _getOrCreateTabId() {
    final existing = html.window.sessionStorage[AuthStorageKeys.tabId];
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateId();
    html.window.sessionStorage[AuthStorageKeys.tabId] = id;
    return id;
  }

  static String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // -------- read / write --------

  @override
  Future<String?> readRefresh() async => _session[AuthStorageKeys.refresh];

  @override
  Future<void> writeRefresh(String? value) async {
    if (value == null) {
      _session.remove(AuthStorageKeys.refresh);
      html.window.localStorage.remove(_scopedKey('refresh'));
    } else {
      _session[AuthStorageKeys.refresh] = value;
      if (_persistent) {
        html.window.localStorage[_scopedKey('refresh')] = value;
      }
    }
  }

  @override
  Future<String?> readUserJson() async => _session[AuthStorageKeys.user];

  @override
  Future<void> writeUserJson(String? value) async {
    if (value == null) {
      _session.remove(AuthStorageKeys.user);
      html.window.localStorage.remove(_scopedKey('user'));
    } else {
      _session[AuthStorageKeys.user] = value;
      if (_persistent) {
        html.window.localStorage[_scopedKey('user')] = value;
      }
    }
  }

  @override
  Future<void> clearAuth() async {
    // Clear sessionStorage (primary)
    _session.remove(AuthStorageKeys.refresh);
    _session.remove(AuthStorageKeys.user);

    // Clear tab-scoped localStorage (remember-me backup)
    html.window.localStorage.remove(_scopedKey('refresh'));
    html.window.localStorage.remove(_scopedKey('user'));

    // Clear legacy global keys (one-time migration cleanup)
    html.window.localStorage.remove(AuthStorageKeys.refresh);
    html.window.localStorage.remove(AuthStorageKeys.user);
    html.window.sessionStorage.remove(AuthStorageKeys.refresh);
    html.window.sessionStorage.remove(AuthStorageKeys.user);
  }

  @override
  Future<void> clearOtherWebStores(bool rememberMe) async {
    // No-op: each tab is self-contained now.
  }

  // ---------- restore helper ----------

  /// Try to recover auth from this tab's scoped localStorage
  /// (covers the case where the browser was fully closed and sessionStorage
  /// was wiped, but the user had checked "remember me").
  static Future<SessionStorageBase?> tryRestoreFromLocalStorage() async {
    final tabId = html.window.sessionStorage[AuthStorageKeys.tabId];

    if (tabId != null && tabId.isNotEmpty) {
      // Tab already has an ID — check its scoped localStorage backup
      final scopedRefresh =
          html.window.localStorage[AuthStorageKeys.scopedKey('refresh', tabId)];
      if (scopedRefresh != null && scopedRefresh.isNotEmpty) {
        final impl = SessionStorageImpl._(tabId, true);
        // Copy from localStorage backup into sessionStorage for this run
        final scopedUser =
            html.window.localStorage[AuthStorageKeys.scopedKey('user', tabId)];
        impl._session[AuthStorageKeys.refresh] = scopedRefresh;
        if (scopedUser != null) {
          impl._session[AuthStorageKeys.user] = scopedUser;
        }
        return impl;
      }
    }

    // Fresh tab (no tabId yet or no scoped backup) — check if there's
    // ANY scoped session in localStorage we can adopt (browser restart case).
    // Pick the first one found.
    final allKeys = html.window.localStorage.keys.toList();
    for (final key in allKeys) {
      final match = RegExp(r'^defensys_session_(.+)_refresh$').firstMatch(key);
      if (match != null) {
        final existingTabId = match.group(1)!;
        final refreshVal = html.window.localStorage[key];
        if (refreshVal != null && refreshVal.isNotEmpty) {
          // Check if this scoped session is "orphaned" (no tab currently
          // owns it).  We can't perfectly detect this, but if our
          // sessionStorage has no tabId yet, adopt this one.
          if (tabId == null || tabId.isEmpty) {
            final newTabId = _getOrCreateTabId();
            final impl = SessionStorageImpl._(newTabId, true);

            // Copy the orphaned session into our new tab identity
            final userKey = AuthStorageKeys.scopedKey('user', existingTabId);
            final userVal = html.window.localStorage[userKey];

            impl._session[AuthStorageKeys.refresh] = refreshVal;
            if (userVal != null) {
              impl._session[AuthStorageKeys.user] = userVal;
            }

            // Re-key to our new tabId in localStorage
            html.window.localStorage[impl._scopedKey('refresh')] = refreshVal;
            if (userVal != null) {
              html.window.localStorage[impl._scopedKey('user')] = userVal;
            }

            // Remove the old orphaned keys
            html.window.localStorage.remove(key);
            html.window.localStorage.remove(userKey);

            return impl;
          }
        }
      }
    }

    return null;
  }
}

// Cross-tab sync is intentionally removed — each tab owns its own session.
void installWebStorageListener(
    void Function(Map<String, dynamic> data) onMessage) {}

void broadcastAuthToTabs(Map<String, dynamic> payload) {}
