import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';

void main() {
  testWidgets('TeamBulkImportReviewTable roster studio enforces 4-member limit and provides safe removal', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final rows = [
      {
        'team_name': 'Team SkyLedger',
        'project_title': 'Alumni Career Tracker',
        'section': 'BSIT-4A',
        'adviser_name': 'Ricardo Fontanilla',
        'member_ids': ['Marcus Villar', 'Patricia Ong'],
        'leader_id': 'Marcus Villar',
      },
      {
        'team_name': 'Team FullQuad',
        'project_title': 'Full Roster Project',
        'section': 'BSIT-4A',
        'adviser_name': 'Ricardo Fontanilla',
        'member_ids': ['Student A', 'Student B', 'Student C', 'Student D'],
        'leader_id': 'Student A',
      },
    ];

    final previewRows = [
      {
        'row': 1,
        'ready': true,
        'section': 'BSIT-4A',
        'adviser_name': 'Ricardo Fontanilla',
        'program_label': 'Capstone • 4th Year',
        'issues': <String>[],
      },
      {
        'row': 2,
        'ready': true,
        'section': 'BSIT-4A',
        'adviser_name': 'Ricardo Fontanilla',
        'program_label': 'Capstone • 4th Year',
        'issues': <String>[],
      },
    ];

    int changeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: rows,
              previewRows: previewRows,
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              searchQuery: '',
              adviserOptions: const [
                {'name': 'Ricardo Fontanilla', 'username': 'rfontanilla'},
                {'name': 'Elena Ramos', 'username': 'eramos'},
              ],
              sectionOptions: const ['BSIT-4A', 'BSIT-4B'],
              studentOptions: const [
                {'name': 'Ethan Salazar', 'student_id': '2024-0003'},
                {'name': 'Zoe Castillo', 'student_id': '2024-0004'},
              ],
              onRowChanged: (_) => changeCount++,
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Header contains Program / Term Badge rather than wasted row input
    expect(find.text('Capstone • 4th Year'), findsWidgets);
    expect(find.text('Sec: BSIT-4A'), findsWidgets);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 2'), findsOneWidget);

    // 2. Row 2 (FullQuad) has 4 members -> shows "4/4 (Max)", no Add Member button for it
    expect(find.text('4/4 (Max)'), findsOneWidget);

    // 3. Row 1 has 2 members -> shows "2/4" and "Add Member" button
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('Add Member'), findsOneWidget);

    // 4. Test 1-click leader designation on Row 1: tap star on 'Patricia Ong'
    final patriciaStar = find.byTooltip('Click star to designate as Leader').first;
    await tester.tap(patriciaStar);
    await tester.pumpAndSettle();

    expect(rows[0]['leader_id'], 'Patricia Ong');
    expect(find.text('Leader: Patricia Ong'), findsOneWidget);

    // 5. Test Searchable Add Member dialog
    await tester.tap(find.text('Add Member'));
    await tester.pumpAndSettle();

    // Dialog appears with search field and candidates
    expect(find.text('Add Member (2/4)'), findsOneWidget);
    expect(find.text('Ethan Salazar'), findsOneWidget);

    // Tap Ethan Salazar to add
    await tester.tap(find.text('Ethan Salazar'));
    await tester.pumpAndSettle();

    expect(rows[0]['member_ids'], contains('Ethan Salazar'));
    expect(find.text('3/4'), findsOneWidget);

    // 6. Test Safe Member Removal with confirmation dialog
    final removeEthan = find.byTooltip('Remove member').first;
    await tester.tap(removeEthan);
    await tester.pumpAndSettle();

    // Confirmation dialog should be visible
    expect(find.text('Remove Team Member'), findsOneWidget);
    expect(find.text('Remove Member'), findsOneWidget);

    // Confirm removal
    await tester.tap(find.widgetWithText(FilledButton, 'Remove Member'));
    await tester.pumpAndSettle();

    // Member removed safely
    expect((rows[0]['member_ids'] as List).length, 2);

    // 7. Test Searchable Adviser dialog
    await tester.tap(find.byKey(const ValueKey('adviser_selector_1')));
    await tester.pumpAndSettle();

    expect(find.text('Assign Faculty Adviser'), findsOneWidget);
    expect(find.text('Search faculty adviser name...'), findsOneWidget);
    expect(find.text('Elena Ramos'), findsOneWidget);

    // Tap Elena Ramos to assign
    await tester.tap(find.text('Elena Ramos'));
    await tester.pumpAndSettle();

    expect(rows[0]['adviser_name'], 'Elena Ramos');
  });

  testWidgets('TeamBulkImportReviewTable allows dynamically adding a class section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final rows = [
      {
        'team_name': 'Team Alpha',
        'project_title': 'Project A',
        'section': 'BSIT-4A',
        'member_ids': ['Student 1'],
        'leader_id': 'Student 1',
      },
    ];

    String? newlyAddedSection;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: rows,
              previewRows: const [],
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
              onSectionAdded: (sec) => newlyAddedSection = sec,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap the "+ Add" section button on row 1
    await tester.tap(find.byKey(const ValueKey('add_section_btn_1')));
    await tester.pumpAndSettle();

    expect(find.text('Add Class Section'), findsOneWidget);

    // Enter new section name
    await tester.enterText(find.byKey(const ValueKey('add_section_name_input')), 'BSIT-4C');
    await tester.tap(find.byKey(const ValueKey('submit_add_section_btn')));
    await tester.pumpAndSettle();

    expect(rows[0]['section'], 'BSIT-4C');
    expect(newlyAddedSection, 'BSIT-4C');
    expect(find.text('Sec: BSIT-4C'), findsOneWidget);
  });

  testWidgets('TeamBulkImportReviewTable pagination limits rows per page and navigates cleanly', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Generate 8 teams
    final rows = List.generate(8, (i) => {
      'team_name': 'Team Number ${i + 1}',
      'project_title': 'Project ${i + 1}',
      'section': 'BSIT-4A',
      'member_ids': ['Leader ${i + 1}'],
      'leader_id': 'Leader ${i + 1}',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: rows,
              previewRows: const [],
              isCapstoneAdmin: true,
              pitLeadYear: null,
              showIssuesOnly: false,
              onRowChanged: (_) {},
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // With default page size 5, only teams 1 through 5 are visible
    expect(find.text('Showing 1–5 of 8 staged teams'), findsWidgets);
    expect(find.text('Team Number 1'), findsWidgets);
    expect(find.text('Team Number 5'), findsWidgets);
    expect(find.text('Team Number 6'), findsNothing);

    // Tap Next page
    await tester.tap(find.byKey(const ValueKey('next_page_top')));
    await tester.pumpAndSettle();

    // Page 2 shows teams 6 through 8
    expect(find.text('Showing 6–8 of 8 staged teams'), findsWidgets);
    expect(find.text('Team Number 6'), findsWidgets);
    expect(find.text('Team Number 8'), findsWidgets);
    expect(find.text('Team Number 1'), findsNothing);
  });
}
