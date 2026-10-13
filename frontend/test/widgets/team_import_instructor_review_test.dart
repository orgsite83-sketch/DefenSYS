import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_bulk_import.dart';
import 'package:defensys/services/student_teams_provider.dart';

List<Map<String, dynamic>> rows() => [
  {
    'team_name': 'Team DevCraft',
    'project_title': 'Freshman Interactive Campus Directory & Room Finder Kiosk',
    'section': 'BSIT-1A',
    'instructor_name': 'Eduardo Padilla',
    'level': '1st Year PIT',
    'member_ids': ['Liam Liwanag', 'Chloe Marquez', 'Andrei Catapang', 'Alyssa De Vera'],
    'leader_id': 'Liam Liwanag',
  },
  {
    'team_name': 'Team UniConnectCore',
    'project_title': 'Student Service Desk Module',
    'section': 'BSIT-1B',
    'instructor_name': 'Arsenio Macasaet',
    'level': '1st Year PIT',
    'member_ids': ['Lance San Pedro', 'Kathleen Borja'],
    'leader_id': 'Lance San Pedro',
  },
];

List<Map<String, dynamic>> preview() => [
  for (var i = 1; i <= 2; i++)
    {'row': i, 'ready': true, 'program_label': '1st Year PIT', 'issues': <String>[], 'warnings': <String>[]},
];

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    await text.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('PIT review searches and filters instructors and edits the instructor field', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final staged = rows();
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamBulkImportReviewTable(
              rows: staged,
              previewRows: preview(),
              isCapstoneAdmin: false,
              pitLeadYear: '1st Year',
              showIssuesOnly: false,
              searchQuery: 'eduardo',
              adviserFilter: 'Eduardo Padilla',
              groupBy: 'adviser',
              adviserOptions: const [
                {'name': 'Eduardo Padilla'},
                {'name': 'Florencia Dela Torre'},
              ],
              onRowChanged: (_) => changes++,
              onDeleteRow: (_) {},
              onAddRow: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team DevCraft'), findsWidgets);
    expect(find.text('Team UniConnectCore'), findsNothing);
    expect(find.text('Instructor: Eduardo Padilla'), findsWidgets);
    expect(find.text('Adviser (Optional)'), findsNothing);
    expect(find.byType(ShadInput), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('instructor_selector_1')));
    await tester.pumpAndSettle();
    expect(find.text('Assign Faculty Instructor'), findsOneWidget);
    await tester.tap(find.text('Florencia Dela Torre'));
    await tester.pumpAndSettle();
    expect(staged.first['instructor_name'], 'Florencia Dela Torre');
    expect(staged.first.containsKey('adviser_name'), isFalse);
    expect(changes, 1);
  });

  for (final width in [1200.0, 390.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('PIT review fits $width in ${brightness.name} mode', (tester) async {
        tester.view.physicalSize = Size(width, 1250);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'Inter'),
            home: Scaffold(
              body: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: brightness == Brightness.dark ? const Color(0xFF18181B) : const Color(0xFFFAFAFA),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: TeamBulkImportReviewTable(
                      rows: rows(),
                      previewRows: preview(),
                      isCapstoneAdmin: false,
                      pitLeadYear: '1st Year',
                      showIssuesOnly: false,
                      onRowChanged: (_) {},
                      onDeleteRow: (_) {},
                      onAddRow: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = tester.widget<Container>(
          find.byWidgetPredicate(
            (w) => w is Container && w.key is ValueKey && w.key.toString().contains('bulk_import_row_0'),
          ),
        );
        expect(((card.decoration as BoxDecoration).border as Border).top.color, const Color(0xFF10B981));
        if (Platform.environment['DEFENSYS_REVIEW_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('../.tmp/team-import-${width.toInt()}-${brightness.name}.png');
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('PIT import toolbar labels instructor filters and grouping', (tester) async {
    tester.view.physicalSize = const Size(1600, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentTeamsBulkImportView(
            state: const StudentTeamsState(),
            isCapstoneAdmin: false,
            pitLeadYear: '1st Year',
            parsedBulkRows: rows(),
            bulkCsvDraft: '',
            selectedBulkAdviserFilter: 'all',
            bulkPreview: {
              'rows': preview(),
              'summary': {'ready': 2},
            },
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
    );
    await tester.pumpAndSettle();
    expect(find.text('All Instructors'), findsOneWidget);
    expect(find.text('All Advisers'), findsNothing);
    final select = find.byWidgetPredicate((w) => w is ShadSelect<String> && w.initialValue == 'none');
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.text('Group: By Instructor'), findsOneWidget);
  });
}
