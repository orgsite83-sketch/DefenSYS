import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/defense_board/components/defense_schedule_bulk_import_view.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_bulk_import.dart';
import 'package:defensys/services/academic/student_teams_provider.dart';

void main() {
  testWidgets('DefenseScheduleBulkImportView blueprint button opens modal without crashing', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DefenseScheduleBulkImportView(
              scope: 'capstone',
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final blueprintBtn = find.text('View Sheet Layout Blueprint');
    expect(blueprintBtn, findsOneWidget);

    await tester.tap(blueprintBtn);
    await tester.pumpAndSettle();

    expect(find.text('Official Capstone Defense Schedule Blueprint'), findsOneWidget);
  });

  testWidgets('StudentTeamsBulkImportView blueprint button opens modal without crashing', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudentTeamsBulkImportView(
              state: const StudentTeamsState(),
              isCapstoneAdmin: true,
              pitLeadYear: null,
              parsedBulkRows: const [],
              bulkCsvDraft: '',
              selectedBulkAdviserFilter: 'All',
              bulkPreview: null,
              showIssuesOnly: false,
              templateWarning: null,
              isBulkImportDirty: false,
              section: null,
              systemName: null,
              projectManager: null,
              onRequestClose: () async {},
              onDownloadTemplate: () {},
              onPickBulkCsvFile: () {},
              onImportBulkTeams: () {},
              onExportBulkCsv: () {},
              onScheduleRowPreview: (_) {},
              onDeleteBulkRow: (_) {},
              onAddBulkRow: () {},
              onAdviserFilterChanged: (_) {},
              onShowIssuesOnlyChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final blueprintBtn = find.text('View Sheet Layout Blueprint');
    expect(blueprintBtn, findsOneWidget);

    await tester.tap(blueprintBtn);
    await tester.pumpAndSettle();

    expect(find.text('Official Capstone Team Sheet Blueprint'), findsOneWidget);

    // Direct Unified Side-by-Side Blueprint shows both BSIT-4A and BSIT-4B without tabs
    expect(find.textContaining('BSIT-4A'), findsWidgets);
    expect(find.textContaining('BSIT-4B'), findsWidgets);
    expect(find.text('Hospital Management System'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsWidgets);

    // Both systems feature 2 advisers (4 teams per adviser)
    expect(find.text('Prof. Alex Santos'), findsWidgets);
    expect(find.text('Prof. Elena Ramos'), findsWidgets);
    expect(find.text('Prof. Roberto Gomez'), findsWidgets);
    expect(find.text('Prof. Cynthia Morales'), findsWidgets);

    expect(find.text('Download Excel Template (.xlsx)'), findsOneWidget);
    expect(find.text('Download Team Roster Template (.csv)'), findsOneWidget);
  });
}
