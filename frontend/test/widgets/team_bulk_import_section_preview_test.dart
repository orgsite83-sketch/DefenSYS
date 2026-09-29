import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';

void main() {
  final sampleRows = [
    {
      'team_name': 'Team SkyLedger',
      'project_title': 'Alumni Career Tracker',
      'section': 'BSIT-4A',
      'adviser_name': 'Ricardo Fontanilla',
      'member_ids': ['Marcus Villar', 'Patricia Ong'],
      'leader_id': 'Marcus Villar',
    },
    {
      'team_name': 'Team BioPulse',
      'project_title': 'AI Vital Triage',
      'section': 'BSIT-4B',
      'adviser_name': 'Elena Ramos',
      'member_ids': ['Ryan Torres', 'Nina Villanueva'],
      'leader_id': 'Ryan Torres',
    },
  ];

  final samplePreviewRows = [
    {
      'row': 1,
      'ready': true,
      'section': 'BSIT-4A',
      'adviser_name': 'Ricardo Fontanilla',
      'issues': <String>[],
    },
    {
      'row': 2,
      'ready': true,
      'section': 'BSIT-4B',
      'adviser_name': 'Elena Ramos',
      'issues': <String>[],
    },
  ];

  testWidgets('TeamBulkImportReviewTable renders section badge and editable section field', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: sampleRows,
              previewRows: samplePreviewRows,
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              searchQuery: '',
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Section and Adviser badges in card header
    expect(find.text('Sec: BSIT-4A'), findsOneWidget);
    expect(find.text('Sec: BSIT-4B'), findsOneWidget);
    expect(find.text('Ricardo Fontanilla'), findsWidgets);
    expect(find.text('Elena Ramos'), findsWidgets);

    // Verify editable Section field label and initial value
    expect(find.text('Section'), findsNWidgets(2));
    expect(find.text('BSIT-4A'), findsWidgets);
    expect(find.text('BSIT-4B'), findsWidgets);
  });

  testWidgets('TeamBulkImportReviewTable filters by section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: sampleRows,
              previewRows: samplePreviewRows,
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              searchQuery: '',
              sectionFilter: 'BSIT-4A',
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Team SkyLedger'), findsWidgets);
    expect(find.text('Team BioPulse'), findsNothing);
  });

  testWidgets('TeamBulkImportReviewTable groups by section with header', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: sampleRows,
              previewRows: samplePreviewRows,
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              searchQuery: '',
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

    // Verify section group headers
    expect(find.text('Section BSIT-4A'), findsOneWidget);
    expect(find.text('Section BSIT-4B'), findsOneWidget);
    expect(find.text('Team SkyLedger'), findsWidgets);
    expect(find.text('Team BioPulse'), findsWidgets);
  });

  testWidgets('TeamBulkImportReviewTable groups by adviser with header', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: sampleRows,
              previewRows: samplePreviewRows,
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              searchQuery: '',
              groupBy: 'adviser',
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify adviser group headers
    expect(find.text('Adviser: Ricardo Fontanilla'), findsOneWidget);
    expect(find.text('Adviser: Elena Ramos'), findsOneWidget);
  });
}
