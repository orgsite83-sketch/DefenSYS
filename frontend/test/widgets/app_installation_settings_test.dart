import 'package:defensys/config/app_distribution_config.dart';
import 'package:defensys/screens/app/app_settings_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/installation/app_installation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

class _Auth extends AuthNotifier {
  _Auth(this.user);
  final Map<String, dynamic> user;
  @override
  AuthState build() =>
      AuthState(isRestoring: false, token: testAccessToken, user: user);
}

class _Install extends AppInstallation {
  _Install(this.current);
  InstallationState current;
  int prompts = 0;
  String outcome = 'accepted';
  @override
  InstallationState get state => current;
  @override
  Future<String> install() async {
    prompts++;
    return outcome;
  }

  void installed() {
    current = const InstallationState(isWeb: true, installed: true);
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> show(
    WidgetTester tester,
    _Install install, {
    Map<String, dynamic> user = const {'role': 'student'},
    String? download,
  }) async {
    await pumpDefensysWidget(
      tester,
      AppSettingsScreen(installation: install, androidDownloadUrl: download),
      overrides: [authProvider.overrideWith(() => _Auth(user))],
    );
  }

  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'iPhone guide fits width $width without a fake install prompt',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final install = _Install(
          const InstallationState(
            isWeb: true,
            secure: true,
            platform: InstallPlatform.ios,
          ),
        );
        await show(
          tester,
          install,
          download: 'https://defensys.example/DefenSYS.apk',
        );
        expect(find.text('Add to Home Screen on iPhone'), findsOneWidget);
        expect(
          find.text('Turn on Open as Web App, then tap Add'),
          findsOneWidget,
        );
        expect(find.text('Install DefenSYS'), findsNothing);
        expect(find.text('Download Android app'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Browser install invokes prompt and removes promotion on appinstalled',
    (tester) async {
      final install = _Install(
        const InstallationState(
          isWeb: true,
          secure: true,
          canPrompt: true,
          platform: InstallPlatform.android,
        ),
      );
      await show(
        tester,
        install,
        user: const {'role': 'faculty', 'is_panelist': true},
      );
      await tester.tap(find.text('Install DefenSYS'));
      await tester.pumpAndSettle();
      expect(install.prompts, 1);
      install.installed();
      await tester.pumpAndSettle();
      expect(find.text('Get DefenSYS on your phone'), findsNothing);
      expect(find.text('You’re using the app'), findsOneWidget);
    },
  );
  testWidgets(
    'LAN preview provides browser fallback without an unusable install button',
    (tester) async {
      await show(
        tester,
        _Install(
          const InstallationState(
            isWeb: true,
            platform: InstallPlatform.android,
          ),
        ),
      );
      expect(find.text('Open your browser menu'), findsOneWidget);
      expect(find.textContaining('local address'), findsOneWidget);
      expect(find.text('Install DefenSYS'), findsNothing);
      expect(find.text('Download Android app'), findsNothing);
    },
  );
  testWidgets('Configured release APK is offered on Android', (tester) async {
    await show(
      tester,
      _Install(
        const InstallationState(
          isWeb: true,
          secure: true,
          platform: InstallPlatform.android,
        ),
      ),
      download: 'https://defensys.example/DefenSYS.apk',
    );
    expect(find.text('Download Android app'), findsOneWidget);
  });
  testWidgets(
    'Guests and staff without panelist eligibility see no installation offer',
    (tester) async {
      for (final user in [
        {'role': 'guest_panelist'},
        {'role': 'admin'},
        {'role': 'faculty', 'is_panelist': false},
      ]) {
        await tester.pumpWidget(const SizedBox());
        await show(
          tester,
          _Install(const InstallationState(isWeb: true, canPrompt: true)),
          user: user,
        );
        expect(find.text('Get DefenSYS on your phone'), findsNothing);
      }
    },
  );
  testWidgets('Native app does not offer another installation', (tester) async {
    await show(tester, _Install(const InstallationState()));
    expect(find.text('Get DefenSYS on your phone'), findsNothing);
    expect(find.text('You’re using the app'), findsOneWidget);
  });
  test('APK download accepts only configured HTTPS destinations', () {
    for (final invalid in [
      '',
      '/DefenSYS.apk',
      'javascript:alert(1)',
      'http://192.168.1.3/app.apk',
      'https://user:secret@example.com/app.apk',
    ]) {
      expect(AppDistributionConfig.androidDownload(value: invalid), isNull);
    }
    expect(
      AppDistributionConfig.androidDownload(
        value: 'https://defensys.example/downloads/app.apk',
      )?.host,
      'defensys.example',
    );
  });
}
