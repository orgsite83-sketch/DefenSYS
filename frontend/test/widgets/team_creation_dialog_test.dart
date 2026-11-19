import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/screens/web/admin/student_teams/dialogs/team_creation_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

const data = StudentTeamsState(
  capstoneMode: 'capstone_2_continue',
  canAddCapstone2Team: true,
  activeSemester: {'label': '1st Semester'},
  students: [
    {
      'id': 1,
      'name': 'Ana Reyes',
      'username': '2023-0142',
      'requires_capstone2_reference': true,
    },
    {
      'id': 2,
      'name': 'Leo Santos',
      'username': '2023-0281',
      'requires_capstone2_reference': false,
    },
  ],
);

Future<void> openForm(
  WidgetTester tester,
  Future<String?> Function(Map<String, dynamic>) save, {
  ThemeData? theme,
  StudentTeamsState initialData = data,
}) async {
  await pumpDefensysWidget(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => DefensysShadcnScope(
            maroonActions: true,
            child: TeamCreationDialog(
              data: initialData,
              isPitLead: false,
              isCapstoneAdmin: true,
              save: save,
              loadRoster: (_, __) async => initialData.students,
            ),
          ),
        ),
        child: const Text('Open form'),
      ),
    ),
    theme: theme,
  );
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
}

Future<void> selectStudent(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text('Add a student').first);
  await tester.tap(find.text('Add a student').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  testWidgets(
    'one save requires eligibility and reference, retains fields on failure and retries same ID',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Map<String, dynamic>>[];
      await openForm(tester, (payload) async {
        requests.add(payload);
        return 'Ana must be enrolled in the current semester.';
      });
      await tester.enterText(
        find.byKey(const ValueKey('Team name')),
        'Team Meridian',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Project title')),
        'Campus Resource Tracker',
      );
      await selectStudent(tester, 'Ana Reyes (2023-0142)');
      await tester.ensureVisible(find.text('Add team').last);
      await tester.tap(find.text('Add team').last);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.ensureVisible(find.byType(ShadCheckbox));
      await tester.tap(find.byType(ShadCheckbox));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('capstone2-reference')),
        'Approved school grade sheet CS1-2026',
      );
      await tester.tap(find.text('Add team').last);
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('Add Capstone 2 team'), findsOneWidget);
      expect(find.text('Team Meridian'), findsOneWidget);
      expect(
        find.text('Ana must be enrolled in the current semester.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add team').last);
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(
        (requests[0]['capstone2_confirmation'] as Map)['request_id'],
        (requests[1]['capstone2_confirmation'] as Map)['request_id'],
      );
      await selectStudent(tester, 'Leo Santos (2023-0281)');
      expect(
        tester.widget<ShadCheckbox>(find.byType(ShadCheckbox)).value,
        isFalse,
      );
      await capturePreview(
        tester,
        find.byType(TeamCreationDialog),
        'capstone2-add-team-desktop',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recorded member needs no reference and saving prevents a second request',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<String?>();
      var requests = 0;
      await openForm(tester, (_) {
        requests++;
        return pending.future;
      });
      await tester.enterText(
        find.byKey(const ValueKey('Team name')),
        'Team Record',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Project title')),
        'Existing Project',
      );
      await selectStudent(tester, 'Leo Santos (2023-0281)');
      expect(find.byKey(const Key('capstone2-reference')), findsNothing);
      await tester.ensureVisible(find.byType(ShadCheckbox));
      await tester.tap(find.byType(ShadCheckbox));
      await tester.tap(find.text('Add team').last);
      await tester.pump();
      expect(requests, 1);
      expect(find.text('Saving…'), findsOneWidget);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Add Capstone 2 team'), findsNothing);
    },
  );

  testWidgets('dialog fits a small laptop and narrow layout', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(1366, 768), const Size(360, 740)]) {
      tester.view.physicalSize = size;
      await openForm(tester, (_) async => null);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel').last);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'dark dialog preserves contrast and mobile actions remain reachable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openForm(tester, (_) async => null, theme: AppTheme.mistDarkTheme);
      await selectStudent(tester, 'Ana Reyes (2023-0142)');
      await tester.ensureVisible(find.byType(ShadCheckbox));
      await capturePreview(
        tester,
        find.byType(TeamCreationDialog),
        'capstone2-add-team-dark-mobile',
        viewport: true,
      );
      await tester.ensureVisible(find.text('Cancel').last);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add team').last);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal Capstone 1 and PIT keep their original creation payloads',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final pit in [false, true]) {
        Map<String, dynamic>? saved;
        await openForm(
          tester,
          (payload) async {
            saved = payload;
            return null;
          },
          initialData: StudentTeamsState(
            level: pit ? 'PIT' : 'Capstone',
            yearLevel: pit ? '2nd Year' : null,
            capstoneMode: 'capstone_1_intake',
            activeSemester: const {'label': '2nd Semester'},
            students: data.students,
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('Team name')),
          'Existing normal flow',
        );
        await selectStudent(tester, 'Leo Santos (2023-0281)');
        expect(find.byType(ShadCheckbox), findsNothing);
        await tester.tap(find.text('Add team').last);
        await tester.pumpAndSettle();
        expect(saved?['status'], 'Pending');
        expect(saved?.containsKey('capstone2_confirmation'), isFalse);
        if (pit) expect(saved?['level'], '2nd Year PIT');
      }
    },
  );
}
