import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/auth_storage_keys.dart';
import 'package:user/services/terms_acceptance.dart';
import 'package:user/services/terms_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hasAcceptedCurrentTerms is false before recordAcceptance', () async {
    expect(await TermsAcceptance.hasAcceptedCurrentTerms(), isFalse);
  });

  test('recordAcceptance persists current version', () async {
    await TermsAcceptance.recordAcceptance();
    expect(await TermsAcceptance.hasAcceptedCurrentTerms(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AuthStorageKeys.termsAcceptedVersion),
      TermsConstants.currentVersion,
    );
  });

  test('clearAcceptance removes stored version', () async {
    await TermsAcceptance.recordAcceptance();
    await TermsAcceptance.clearAcceptance();
    expect(await TermsAcceptance.hasAcceptedCurrentTerms(), isFalse);
  });

  test('stale version does not count as accepted', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthStorageKeys.termsAcceptedVersion, '2024-01');
    expect(await TermsAcceptance.hasAcceptedCurrentTerms(), isFalse);
  });
}
