import 'dart:convert';
import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/deliverable_requirement_card.dart';
import 'package:defensys/widgets/repository/weekly_report_collection.dart';
import 'package:defensys/widgets/repository/shared_deliverables_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';
import '../helpers/file_picker.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Student extends TestAuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 7, 'role': 'student', 'username': 'leader'},
  );
}

Map<String, dynamic> _weekly() => {
  'id': 'WPR',
  'label': 'Weekly Accomplishment Reports',
  'source': 'weekly_reports',
  'type': 'pre',
  'required': true,
  'current_week': 2,
  'template': _template,
  'weekly_summary': {
    'required': 2,
    'uploaded': 0,
    'accepted': 0,
    'missing': 2,
    'pending': 0,
    'rejected': 0,
    'overdue': 1,
    'late': 0,
  },
  'weeks': [
    for (var n = 1; n <= 2; n++)
      {
        'week_number': n,
        'required': true,
        'status': 'missing',
        'can_upload': true,
        'can_review': false,
        'starts_on': n == 1 ? '2026-10-25' : '2026-11-01',
        'ends_on': n == 1 ? '2026-10-31' : '2026-11-07',
        'due_at': n == 1
            ? '2026-10-31T23:59:00+08:00'
            : '2026-11-07T23:59:00+08:00',
        'timing': n == 1 ? 'overdue' : 'open',
      },
  ],
};

const _template = {
  'original_name': 'IT412-Week-12-13-Laboratory-Activity.pdf',
  'file_url': '/media/template.pdf',
  'byte_size': 280576,
};

List<Map<String, dynamic>> _requirements() => [
  {
    'id': 'FORM',
    'label': 'Adviser Acceptance Form',
    'required': true,
    'type': 'pre',
    'can_upload': true,
    'file_format': 'any',
  },
  {
    'id': 'CONCEPTS',
    'label': 'Concept Papers',
    'required': true,
    'type': 'pre',
    'can_upload': true,
    'template': _template,
    'file_format': 'pdf',
    'file_policy': {'mode': 'slots'},
    'document_slots': [
      for (var n = 1; n <= 3; n++)
        {
          'key': 'c$n',
          'label': 'Concept $n · Concept paper',
          'required': true,
          'file_format': 'pdf',
        },
    ],
    'submission': {'files': []},
  },
  _weekly(),
];

class _Deliverables extends CapstoneDeliverablesNotifier {
  final rows = _requirements();
  bool postOpen = true;
  @override
  CapstoneDeliverablesState build() => snapshot();
  CapstoneDeliverablesState snapshot() => CapstoneDeliverablesState(
    selectedStage: 'Proposal',
    stageOptions: const ['Proposal'],
    scope: 'capstone',
    teams: [
      {
        'id': 7,
        'name': 'Team AgriPulse',
        'semester_id': 1,
        'project_version': 1,
        'selected_stage': {
          'stage_label': 'Proposal',
          'deliverables_configured': true,
          'endorsed': false,
          'post_unlocked': postOpen,
          'deliverables': List<Map<String, dynamic>>.from(rows),
        },
      },
    ],
  );
  void refresh() => state = snapshot();
  void saving(bool value) => state = state.copyWith(isSaving: value);
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

Future<void> _pump(
  WidgetTester tester,
  _Deliverables notifier, {
  double width = 390,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  setApiHttpClientForTesting(
    MockClient((request) async => http.Response(jsonEncode(_weekly()), 200)),
  );
  await pumpDefensysWidget(
    tester,
    StudentDeliverablesTab(
      isCapstone: true,
      studentData: null,
      hideHeader: true,
    ),
    overrides: [
      authProvider.overrideWith(() => _Student()),
      capstoneDeliverablesProvider.overrideWith(() => notifier),
    ],
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
  );
}

Future<void> _open(WidgetTester tester, String id) async {
  final card = find.byKey(ValueKey('student-requirement-$id'));
  await tester.ensureVisible(card);
  await tester.tap(
    find.descendant(of: card, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  FilePicker.platform = TestFilePicker();
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'concept popup keeps revision history readable at $width dark=$dark',
        (tester) async {
          final notifier = _Deliverables();
          final item = notifier.rows[1];
          item['template'] = null;
          item['submission'] = {
            'status': 'pending',
            'files': [
              for (var n = 1; n <= 3; n++)
                {
                  'id': 10 + n,
                  'slot_key': 'c$n',
                  'is_current': true,
                  'status': 'pending',
                  'revision': 2,
                  'file_name': 'RiverPixel_Concept_${n}_Paper.pdf',
                  'file_url': '/media/concept-$n.pdf',
                  'uploaded_at': '2026-11-02T09:00:00+08:00',
                },
            ],
            'file_history': [
              for (var n = 1; n <= 3; n++)
                {
                  'id': n,
                  'slot_key': 'c$n',
                  'is_current': false,
                  'status': 'rejected',
                  'revision': 1,
                  'file_name': 'RiverPixel_Concept_${n}_Earlier_Paper.pdf',
                  'file_url': '/media/concept-$n-earlier.pdf',
                },
            ],
          };
          await _pump(tester, notifier, width: width, dark: dark);
          await _open(tester, 'CONCEPTS');
          expect(find.byType(ErrorWidget), findsNothing);
          expect(tester.takeException(), isNull);
          expect(find.text('3/3 Uploaded'), findsWidgets);
          final history = find.text('Earlier file revisions (3)');
          await tester.ensureVisible(history);
          await tester.tap(history);
          await tester.pumpAndSettle();
          for (var n = 1; n <= 3; n++) {
            expect(
              find.text('RiverPixel_Concept_${n}_Earlier_Paper.pdf'),
              findsOneWidget,
            );
          }
          expect(find.byType(ErrorWidget), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(DeliverableRequirementDialog),
            'concept-popup-history-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.byType(DeliverableRequirementDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'small-phone weekly popup remains readable at larger text sizes',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, _Deliverables(), width: 320, dark: true);
      await _open(tester, 'WPR');
      expect(find.text('Upload Week 1 report'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(DeliverableRequirementDialog),
        'weekly-popup-320-dark-large-text',
        viewport: true,
      );
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('shared summaries and popup fit $width dark=$dark', (
        tester,
      ) async {
        await _pump(tester, _Deliverables(), width: width, dark: dark);
        expect(find.byType(DeliverableRequirementCard), findsNWidgets(3));
        expect(find.byType(DeliverableUploadTile), findsNothing);
        expect(find.byType(WeeklyReportCollection), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(StudentDeliverablesTab),
          'deliverable-summary-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await _open(tester, 'CONCEPTS');
        expect(find.byType(DeliverableUploadTile), findsNWidgets(3));
        expect(find.text('Concept 3 · Concept paper'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(DeliverableRequirementDialog),
          'deliverable-popup-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await _open(tester, 'WPR');
        expect(find.text('Upload Week 1 report'), findsOneWidget);
        expect(find.text('Upload Week 2 report'), findsOneWidget);
        expect(find.text('Overdue'), findsOneWidget);
        expect(find.byType(ShadSelect<bool>), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(DeliverableRequirementDialog),
          'weekly-popup-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }

  testWidgets('open single-file popup and summary follow server updates', (
    tester,
  ) async {
    final notifier = _Deliverables();
    await _pump(tester, notifier);
    await _open(tester, 'FORM');
    expect(find.text('Upload Adviser Acceptance Form'), findsOneWidget);
    notifier.rows[0] = {
      ...notifier.rows[0],
      'uploaded': true,
      'can_upload': false,
      'submission': {
        'status': 'accepted',
        'file_name': 'Signed_acceptance.pdf',
        'file_url': '/media/signed.pdf',
      },
    };
    notifier.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Signed_acceptance.pdf'), findsOneWidget);
    expect(find.text('Upload Adviser Acceptance Form'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('student-requirement-FORM')),
        matching: find.text('1/1 Uploaded'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked post requirement loses its upload controls while open', (
    tester,
  ) async {
    final notifier = _Deliverables();
    notifier.rows.add({
      'id': 'POST',
      'label': 'Final paper',
      'required': true,
      'type': 'post',
      'can_upload': true,
    });
    await _pump(tester, notifier);
    await _open(tester, 'POST');
    expect(find.text('Upload Final paper'), findsOneWidget);
    notifier.postOpen = false;
    notifier.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Upload Final paper'), findsNothing);
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'single upload opens the picker and cancelling keeps its requirement open',
    (tester) async {
      final previous = FilePicker.platform;
      final picker = TestFilePicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = previous);
      await _pump(tester, _Deliverables());
      await _open(tester, 'FORM');
      await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.type, FileType.any);
      expect(picker.extensions, isNull);
      expect(find.text('Submit Deliverable'), findsNothing);
      expect(find.text('Upload Adviser Acceptance Form'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared summaries preserve per-file upload ownership', (
    tester,
  ) async {
    await loadPreviewFonts(force: true);
    final group = <String, dynamic>{
      'team_id': 7,
      'stage_label': 'Proposal',
      'section': 'BSIT-3A',
      'systems': <Map<String, dynamic>>[],
      'requirements': [
        {
          'deliverable_id': 'SHARED',
          'label': 'Shared documents',
          'required': true,
          'deliverable_type': 'pre',
          'file_policy': {'mode': 'slots'},
          'documents': [
            {
              'key': 'paper',
              'label': 'System paper',
              'required': true,
              'file_format': 'pdf',
              'can_upload': false,
            },
            {
              'key': 'deck',
              'label': 'System slides',
              'required': true,
              'file_format': 'pdf',
              'can_upload': true,
            },
          ],
        },
      ],
    };
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(child: SharedDeliverablesPanel(group: group)),
      overrides: [authProvider.overrideWith(() => _Student())],
    );
    expect(find.byType(DeliverableUploadTile), findsNothing);
    expect(find.text('0/2 Uploaded'), findsOneWidget);
    await tester.tap(find.text('Manage files'));
    await tester.pumpAndSettle();
    expect(find.byType(DeliverableUploadTile), findsNWidgets(2));
    final uploadButtons = tester
        .widgetList<ShadButton>(find.widgetWithText(ShadButton, 'Upload'))
        .toList();
    expect(uploadButtons.map((button) => button.enabled), [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving blocks close and restores the selected summary afterwards',
    (tester) async {
      final notifier = _Deliverables();
      await _pump(tester, notifier);
      await _open(tester, 'FORM');
      notifier.saving(true);
      await tester.pump();
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Done'))
            .enabled,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(DeliverableRequirementDialog), findsOneWidget);
      notifier.saving(false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(DeliverableRequirementDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('student-requirement-FORM')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
