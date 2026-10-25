import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/team_import_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/capture_preview.dart';

List<Map<String, dynamic>> rows() => [
  for (var i = 0; i < 8; i++)
    {
      'group_key': 'team/$i',
      'team_name': 'Team Societree $i',
      'project_title': 'Module $i',
      'section': i < 4 ? 'BSIT-2A' : 'BSIT-2B',
      'member_ids': ['Student $i'],
      'leader_id': 'Student $i',
      'project_kind': 'module',
      'system_name': i < 4 ? 'Societree' : 'Campus services',
      'project_manager': i < 4 ? 'Nathan Cabahug' : 'Carlo Ramos',
    },
];
List<Map<String, dynamic>> previews() => [
  for (var i = 0; i < 8; i++)
    {
      'row': i + 1,
      'group_key': 'team/$i',
      'ready': i != 6,
      'issues': i == 6
          ? ['Student is enrolled in another section.']
          : <String>[],
      'warnings': i == 5
          ? ['PIT uses assigned section instructors; Adviser input is ignored.']
          : <String>[],
      'notes': i == 0
          ? [
              '1 student will be assigned to BSIT-2A when this roster is applied.',
            ]
          : <String>[],
    },
];

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets('metadata follows section filter and team labels use Module', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: rows(),
              previewRows: previews(),
              isCapstoneAdmin: false,
              pitLeadYear: '2nd Year',
              showIssuesOnly: false,
              sectionFilter: 'BSIT-2B',
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared system · BSIT-2B'), findsOneWidget);
    expect(find.text('Shared system · BSIT-2A'), findsNothing);
    expect(find.text('Carlo Ramos'), findsOneWidget);
    expect(find.text('Module'), findsWidgets);
    expect(find.text('PIT Project Title'), findsNothing);
    expect(
      find.textContaining('Student is enrolled in another section.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue navigation selects a later page in grouped review', (
    tester,
  ) async {
    final key = GlobalKey<TeamBulkImportReviewTableState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              key: key,
              rows: rows(),
              previewRows: previews(),
              isCapstoneAdmin: false,
              pitLeadYear: '2nd Year',
              showIssuesOnly: false,
              groupBy: 'section',
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Student is enrolled in another section.'),
      findsNothing,
    );
    key.currentState!.goToFirstIssue();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Student is enrolled in another section.'),
      findsOneWidget,
    );
    expect(find.text('2 / 2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('stable keys prevent stale row-number reassignment after deletion', () {
    final staged = rows()..removeAt(0);
    expect(teamImportPreviewFor(staged, previews(), 5)?['group_key'], 'team/6');
    expect(teamImportPreviewFor(staged, previews(), 5)?['ready'], isFalse);
  });

  testWidgets(
    'routine section assignment stays green Ready and is excluded from warnings',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final staged = rows().take(1).toList();
      final checked = previews().take(1).toList();
      var filter = 'all';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: DefensysShadcnScope(
              child: StatefulBuilder(
                builder: (context, update) => SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TeamImportValidationToolbar(
                          rows: staged,
                          previewRows: checked,
                          filter: filter,
                          onFilter: (value) => update(() => filter = value),
                          onFirstIssue: () {},
                          action: const Text('Review replacement'),
                        ),
                        TeamBulkImportReviewTable(
                          rows: staged,
                          previewRows: checked,
                          isCapstoneAdmin: false,
                          pitLeadYear: '2nd Year',
                          showIssuesOnly: false,
                          statusFilter: filter,
                          lockAssignments: true,
                          onRowChanged: (_) {},
                          onDeleteRow: (_) {},
                          onAddRow: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Ready 1'), findsOneWidget);
      expect(find.text('With warnings 0'), findsOneWidget);
      expect(
        find.text(
          '1 student will be assigned to BSIT-2A when this roster is applied.',
        ),
        findsOneWidget,
      );
      final card = tester.widget<Container>(
        find.byKey(const ValueKey('bulk_import_row_team/0')),
      );
      expect(
        ((card.decoration as BoxDecoration).border as Border).top.color,
        const Color(0xFF10B981),
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(Scaffold),
        'instructor-section-assignment-ready',
        viewport: true,
      );
      await tester.tap(find.text('Warnings'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bulk_import_row_team/0')),
        findsNothing,
      );
      expect(find.text('Ready 1'), findsOneWidget);
    },
  );

  for (final width in [1440.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('review status and shared details fit $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final anchor = GlobalKey();
        Widget toolbar() => TeamImportValidationToolbar(
          rows: rows(),
          previewRows: previews(),
          filter: 'all',
          onFilter: (_) {},
          onFirstIssue: () {},
          action: const OutlinedButton(
            onPressed: null,
            child: Text('Review replacement'),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            home: Scaffold(
              body: DefensysShadcnScope(
                child: TeamImportStickyReview(
                  anchor: anchor,
                  enabled: true,
                  toolbar: toolbar(),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const SizedBox(height: 180),
                          SizedBox(key: anchor),
                          toolbar(),
                          const SizedBox(height: 14),
                          TeamBulkImportReviewTable(
                            rows: rows(),
                            previewRows: previews(),
                            isCapstoneAdmin: false,
                            pitLeadYear: '2nd Year',
                            showIssuesOnly: false,
                            lockAssignments: true,
                            onRowChanged: (_) {},
                            onDeleteRow: (_) {},
                            onAddRow: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ready 6'), findsOneWidget);
        expect(find.text('With warnings 1'), findsOneWidget);
        expect(find.text('Needs correction 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'team-import-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -450),
        );
        await tester.pumpAndSettle();
        expect(find.text('Go to first issue').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'team-import-review-sticky-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
