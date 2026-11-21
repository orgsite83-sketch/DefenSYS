import 'package:defensys/screens/web/admin/student_teams/components/student_teams_bulk_import.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _actionKey = ValueKey('import_ready_teams_btn');
const _barKey = ValueKey('team_import_action_bar');
const _scrollKey = ValueKey('team_import_scroll');

List<Map<String, dynamic>> _rows(int count) => [
  for (var i = 1; i <= count; i++)
    {
      'team_name': 'Team $i',
      'project_title': 'Community project $i',
      'section': 'BSIT-3B',
      'member_ids': ['Student $i'],
      'leader_id': 'Student $i',
    },
];

Widget _view({
  int count = 8,
  bool checking = false,
  bool saving = false,
  String? error,
  String? templateWarning,
  VoidCallback? onImport,
  VoidCallback? onRetry,
  VoidCallback? onSave,
  VoidCallback? onExport,
}) => StudentTeamsBulkImportView(
  state: StudentTeamsState(isSaving: saving, canCreateCapstoneTeams: true),
  isCapstoneAdmin: true,
  pitLeadYear: null,
  parsedBulkRows: _rows(count),
  bulkCsvDraft: '',
  selectedBulkAdviserFilter: 'all',
  bulkPreview: {
    'rows': [
      for (var i = 1; i <= count; i++)
        {
          'row': i,
          'ready': i != 8,
          'issues': i == 8 ? ['Student 8 was not found.'] : <String>[],
          'warnings': i == 2 ? ['Review the proposed title.'] : <String>[],
        },
    ],
  },
  isPreviewLoading: checking,
  fileImportError: error,
  onRetryPreview: onRetry,
  showIssuesOnly: false,
  templateWarning: templateWarning,
  isBulkImportDirty: false,
  section: null,
  systemName: null,
  projectManager: null,
  activeSemester: const {'display_name': '2nd Semester, A.Y. 2025-2026'},
  onRequestClose: () async {},
  onDownloadTemplate: () {},
  onPickBulkCsvFile: () {},
  onImportBulkTeams: onImport ?? () {},
  onExportBulkCsv: onExport ?? () {},
  onSaveDraft: onSave ?? () {},
  onScheduleRowPreview: (_) {},
  onDeleteBulkRow: (_) {},
  onAddBulkRow: () {},
  onAdviserFilterChanged: (_) {},
  onShowIssuesOnlyChanged: (_) {},
);

Future<void> _review(WidgetTester tester) async {
  await Scrollable.ensureVisible(
    tester.element(find.text('Review teams')),
    alignment: 0,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final width in [1440.0, 390.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'import stays reachable while reviewing at $width dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var imports = 0;
          await pumpDefensysWidget(
            tester,
            _view(onImport: () => imports++),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          expect(find.byKey(_actionKey).hitTestable(), findsOneWidget);
          final bar = tester.getRect(find.byKey(_barKey));
          expect(
            tester.getRect(find.byKey(_scrollKey)).bottom,
            lessThanOrEqualTo(bar.top),
          );
          await _review(tester);
          expect(tester.getRect(find.byKey(_barKey)), bar);
          expect(find.byKey(_actionKey).hitTestable(), findsOneWidget);
          expect(find.text('Ready 6'), findsOneWidget);
          expect(find.text('With warnings 1'), findsOneWidget);
          expect(find.text('Needs correction 1'), findsOneWidget);
          expect(find.text('7 of 8 teams ready'), findsOneWidget);
          expect(find.text('Validation Snapshot:'), findsNothing);
          expect(find.text('Issues only'), findsNothing);
          expect(find.byKey(const ValueKey('page_size_top')), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'team-import-clean-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.byKey(_actionKey));
          expect(imports, 1);
        },
      );
    }
  }

  testWidgets(
    'filters keep batch totals and issue navigation restores the list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(tester, _view());
      await _review(tester);
      final search = find.descendant(
        of: find.byKey(const ValueKey('team_import_search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'Team 1');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 team'), findsOneWidget);
      expect(find.text('7 of 8 teams ready'), findsOneWidget);
      await tester.tap(find.text('Go to first issue'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(search).controller.text, isEmpty);
      expect(
        find.textContaining('Student 8 was not found.').hitTestable(),
        findsOneWidget,
      );
      await _review(tester);
      await tester.tap(find.text('Warnings'));
      await tester.pumpAndSettle();
      expect(find.text('Team 2'), findsWidgets);
      expect(find.text('Team 1'), findsNothing);
      expect(find.text('7 of 8 teams ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one-page pagination and bottom bar retain secondary actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = 0, exported = 0;
    await pumpDefensysWidget(
      tester,
      _view(count: 1, onSave: () => saved++, onExport: () => exported++),
    );
    await _review(tester);
    expect(find.text('Showing 1 team'), findsOneWidget);
    expect(find.byKey(const ValueKey('prev_page_bottom')), findsNothing);
    expect(find.byKey(const ValueKey('next_page_bottom')), findsNothing);
    expect(find.text('Go to first issue'), findsNothing);
    await tester.tap(find.byTooltip('More import actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    await tester.tap(find.byTooltip('More import actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(exported, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'validation and import failures remain beside the guarded action',
    (tester) async {
      var retries = 0;
      await pumpDefensysWidget(tester, _view(checking: true));
      expect(
        tester.widget<ShadButton>(find.byKey(_actionKey)).enabled,
        isFalse,
      );
      expect(find.text('Validating teams\u2026').hitTestable(), findsOneWidget);
      await pumpDefensysWidget(
        tester,
        _view(error: 'Preview service unavailable.', onRetry: () => retries++),
      );
      expect(
        tester.widget<ShadButton>(find.byKey(_actionKey)).enabled,
        isFalse,
      );
      expect(
        find.text('Preview service unavailable.').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry validation'));
      expect(retries, 1);
      await pumpDefensysWidget(
        tester,
        _view(templateWarning: 'Check the spreadsheet columns.'),
      );
      expect(
        tester.widget<ShadButton>(find.byKey(_actionKey)).enabled,
        isFalse,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(body: _view(saving: true)),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<ShadButton>(find.byKey(_actionKey)).enabled,
        isFalse,
      );
      expect(find.text('Importing\u2026'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(_barKey))
            .contains(tester.getCenter(find.text('Importing\u2026'))),
        isTrue,
      );
      await pumpDefensysWidget(tester, _view(count: 0));
      expect(find.byKey(_barKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
