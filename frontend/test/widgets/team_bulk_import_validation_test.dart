import 'dart:async';
import 'dart:convert';

import 'package:defensys/screens/web/admin/student_teams/student_teams_screen.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_bulk_import.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';

class _PreviewNotifier extends StudentTeamsNotifier {
  final requests = <List<Map<String, dynamic>>>[];
  final pending = <Completer<Map<String, dynamic>?>>[];
  final imports = <List<Map<String, dynamic>>>[];

  @override
  StudentTeamsState build() =>
      const StudentTeamsState(canCreateCapstoneTeams: true);

  @override
  Future<void> fetchTeams({
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {}

  @override
  Future<Map<String, dynamic>?> bulkImportPreview(
    List<Map<String, dynamic>> rows, {
    String adviserFilter = 'all',
    List<String>? csvColumns,
    String? section,
    String? systemName,
    String? projectManager,
  }) {
    state = state.copyWith(clearError: true);
    requests.add(
      (jsonDecode(jsonEncode(rows)) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
    final completer = Completer<Map<String, dynamic>?>();
    pending.add(completer);
    if (requests.length == 1) completer.complete(_preview());
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>?> bulkImport(
    List<Map<String, dynamic>> rows, {
    String adviserFilter = 'all',
    List<String>? csvColumns,
    String? section,
    String? systemName,
    String? projectManager,
  }) async {
    imports.add(rows);
    return {
      'created_count': 1,
      'error_count': 0,
      'imported_rows': [1],
    };
  }

  void fail(int index) {
    state = state.copyWith(error: 'Preview service unavailable.');
    pending[index].complete(null);
  }
}

Map<String, dynamic> _preview({bool ready = true}) => {
  'rows': [
    for (var row = 1; row <= 2; row++)
      {
        'row': row,
        'ready': ready,
        'issues': ready ? <String>[] : ['Student not found'],
      },
  ],
  'summary': {'total': 2, 'ready': ready ? 2 : 0},
};

void main() {
  Future<_PreviewNotifier> openDraft(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'defensys_user': '{"id":99}',
      'team_bulk_import_draft_99': jsonEncode({
        'rows': [
          for (final name in ['Alpha', 'Beta'])
            {
              'team_name': name,
              'project_title': 'Project $name',
              'section': 'BSIT-4A',
              'member_ids': ['Student $name'],
              'leader_id': 'Student $name',
            },
        ],
        'saved_at': '2026-10-15T10:00:00',
        'is_open': true,
      }),
    });
    final notifier = _PreviewNotifier();
    await pumpDefensysWidget(
      tester,
      const StudentTeamsScreen(),
      overrides: [studentTeamsProvider.overrideWith(() => notifier)],
    );
    await tester.pumpAndSettle();
    expect(notifier.requests, hasLength(1));
    return notifier;
  }

  StudentTeamsBulkImportView view(WidgetTester tester) =>
      tester.widget<StudentTeamsBulkImportView>(
        find.byType(StudentTeamsBulkImportView),
      );

  testWidgets(
    'edits invalidate readiness immediately and revalidate every edited team',
    (tester) async {
      final notifier = await openDraft(tester);
      expect(view(tester).bulkPreview?['summary']['ready'], 2);
      var current = view(tester);
      current.parsedBulkRows[0]['team_name'] = 'Alpha edited';
      current.onScheduleRowPreview(0);
      current.parsedBulkRows[1]['team_name'] = 'Beta edited';
      current.onScheduleRowPreview(1);
      await tester.pump();
      expect(view(tester).bulkPreview, isNull);
      expect(view(tester).isPreviewLoading, isTrue);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('top_import_ready_teams_btn')),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 501));
      expect(notifier.requests.last.map((row) => row['team_name']), [
        'Alpha edited',
        'Beta edited',
      ]);
      notifier.pending.last.complete(_preview());
      await tester.pumpAndSettle();
      expect(view(tester).bulkPreview?['summary']['ready'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('older preview cannot overwrite a newer validation result', (
    tester,
  ) async {
    final notifier = await openDraft(tester);
    view(tester).onRetryPreview!();
    await tester.pump();
    view(tester).onRetryPreview!();
    await tester.pump();
    notifier.pending[2].complete(_preview(ready: false));
    await tester.pumpAndSettle();
    notifier.pending[1].complete(_preview());
    await tester.pumpAndSettle();
    expect(view(tester).bulkPreview?['summary']['ready'], 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'failed validation stays pending, shows its cause, and can be retried',
    (tester) async {
      final notifier = await openDraft(tester);
      view(tester).onRetryPreview!();
      await tester.pump();
      notifier.fail(1);
      await tester.pumpAndSettle();
      expect(find.text('Preview service unavailable.'), findsOneWidget);
      expect(find.text('Awaiting Validation'), findsOneWidget);
      expect(find.text('Needs Fix'), findsNothing);
      expect(find.text('Retry validation'), findsOneWidget);
      view(tester).onRetryPreview!();
      await tester.pump();
      notifier.pending.last.complete(_preview());
      await tester.pumpAndSettle();
      expect(view(tester).bulkPreview?['summary']['ready'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('clearing staged rows rejects an outstanding preview', (
    tester,
  ) async {
    final notifier = await openDraft(tester);
    view(tester).onRetryPreview!();
    await tester.pump();
    view(tester).onClearStaged!();
    await tester.pump();
    notifier.pending.last.complete(_preview());
    await tester.pumpAndSettle();
    expect(view(tester).parsedBulkRows, isEmpty);
    expect(view(tester).bulkPreview, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('importing a ready subset preserves the earlier invalid team', (
    tester,
  ) async {
    final notifier = await openDraft(tester);
    view(tester).onRetryPreview!();
    await tester.pump();
    final preview = _preview();
    (preview['rows'] as List).first['ready'] = false;
    (preview['rows'] as List).first['issues'] = ['Student not found'];
    preview['summary']['ready'] = 1;
    notifier.pending.last.complete(preview);
    await tester.pumpAndSettle();
    view(tester).onImportBulkTeams();
    await tester.pump();
    await tester.pump();
    expect(notifier.imports.single.single['team_name'], 'Beta');
    expect(view(tester).parsedBulkRows.single['team_name'], 'Alpha');
    notifier.pending.last.complete({
      'rows': [
        {
          'row': 1,
          'ready': false,
          'issues': ['Student not found'],
        },
      ],
      'summary': {'total': 1, 'ready': 0},
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(view(tester).parsedBulkRows.single['team_name'], 'Alpha');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
