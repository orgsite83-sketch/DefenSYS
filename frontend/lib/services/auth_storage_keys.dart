/// Keys for persisted auth material (web session/local storage or secure mobile).
abstract final class AuthStorageKeys {
  static const refresh = 'defensys_refresh';
  static const user = 'defensys_user';
  static const rememberMe = 'remember_me';
  static const legacyJwtToken = 'jwt_token';
  static const legacyUserData = 'user_data';
  static const termsAcceptedVersion = 'defensys_terms_accepted_version';
}
