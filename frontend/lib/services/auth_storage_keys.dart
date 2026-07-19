/// Keys for persisted auth material (web session/local storage or secure mobile).
abstract final class AuthStorageKeys {
  static const refresh = 'defensys_refresh';
  static const user = 'defensys_user';
  static const rememberMe = 'remember_me';
  static const legacyJwtToken = 'jwt_token';
  static const legacyUserData = 'user_data';
  static const termsAcceptedVersion = 'defensys_terms_accepted_version';

  /// Unique per-tab identifier stored in sessionStorage.
  static const tabId = '_defensys_tab_id';

  /// Build a localStorage key scoped to a specific tab for remember-me persistence.
  static String scopedKey(String baseKey, String tabId) =>
      'defensys_session_${tabId}_$baseKey';
}
