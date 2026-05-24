import 'package:shared_preferences/shared_preferences.dart';

import 'auth_storage_keys.dart';
import 'terms_constants.dart';

/// Persists mobile terms acceptance per device (survives logout).
class TermsAcceptance {
  TermsAcceptance._();

  static Future<bool> hasAcceptedCurrentTerms() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AuthStorageKeys.termsAcceptedVersion);
    return stored == TermsConstants.currentVersion;
  }

  static Future<void> recordAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AuthStorageKeys.termsAcceptedVersion,
      TermsConstants.currentVersion,
    );
  }

  /// Dev/testing only — not called on logout.
  static Future<void> clearAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthStorageKeys.termsAcceptedVersion);
  }
}
