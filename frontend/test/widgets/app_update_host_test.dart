import 'package:defensys/services/updates/update_service.dart';
import 'package:defensys/services/updates/update_activity.dart';
import 'package:defensys/widgets/updates/app_update_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/app/app_navigator.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

class _Updates extends AppUpdateNotifier {
  @override
  UpdateState build() => const UpdateState(
    current: RunningRelease(
      version: '1.0.0',
      build: 1,
      id: 'web-1',
      isWeb: true,
    ),
    catalog: ReleaseCatalog(
      web: AppRelease(version: '1.0.1', build: 2, id: 'web-2'),
    ),
  );
  @override
  Future<void> check({bool manual = false}) async {}
}

void main() {
  testWidgets(
    'refresh requires an explicit discard confirmation for an open score editor',
    (tester) async {
      var refreshes = 0;
      final score = TextEditingController(text: '94');
      addTearDown(score.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...authTestOverrides(),
            appUpdateProvider.overrideWith(_Updates.new),
            refreshReleaseProvider.overrideWithValue((_) => refreshes++),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            theme: AppTheme.theme,
            builder: (context, child) => AppUpdateHost(child: child!),
            home: Scaffold(body: TextField(controller: score)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Refresh with an open editor?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(score.text, '94');
      expect(refreshes, 0);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes and refresh'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'detection and Later preserve an unsaved score and never refresh',
    (tester) async {
      var refreshes = 0;
      final score = TextEditingController(text: '94');
      addTearDown(score.dispose);
      await pumpDefensysWidget(
        tester,
        AppUpdateHost(
          child: Scaffold(body: TextField(controller: score)),
        ),
        overrides: [
          ...authTestOverrides(),
          appUpdateProvider.overrideWith(_Updates.new),
          refreshReleaseProvider.overrideWithValue((_) => refreshes++),
        ],
      );
      expect(
        find.text('A new version of DefenSYS is available.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(score.text, '94');
      expect(refreshes, 0);
      expect(
        find.text('A new version of DefenSYS is available.'),
        findsNothing,
      );
    },
  );
  testWidgets('ongoing writes disable the update action', (tester) async {
    apiWriteActivity.value = 1;
    addTearDown(() => apiWriteActivity.value = 0);
    var refreshes = 0;
    await pumpDefensysWidget(
      tester,
      const AppUpdateHost(child: SizedBox()),
      overrides: [
        ...authTestOverrides(),
        appUpdateProvider.overrideWith(_Updates.new),
        refreshReleaseProvider.overrideWithValue((_) => refreshes++),
      ],
    );
    await tester.tap(find.text('Refresh'), warnIfMissed: false);
    await tester.pump();
    expect(refreshes, 0);
    expect(
      find.text('Finish saving or uploading before updating.'),
      findsOneWidget,
    );
  });
}
