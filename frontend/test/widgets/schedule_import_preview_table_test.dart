import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
  testWidgets('Schedule import preview table displays multiple issues without overflow', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const stageId = 10;
    const stageLabel = 'Project Proposal';

    final testState = DefenseSchedulerState(
      defenseStages: const [
        {'id': stageId, 'label': stageLabel},
      ],
      faculty: const [
        {'id': 101, 'name': 'Jonathan Beltran', 'username': 'jbeltran'},
      ],
      teams: const [], // Team not registered -> team issue
    );

    final parsed = ParsedScheduleImport(
      rows: const [
        ParsedScheduleImportRow(
          sheetRow: 1,
          time: '9:00 AM - 9:30 AM',
          teamName: 'Team SkyLedger',
          projectTitle: 'Alumni Career Tracker',
          adviser: 'Ricardo Fontanilla',
          members: [],
          chair: 'Jonathan Beltran',
          panelMembers: [],
          documenter: 'Cecilia Magbanua',
          room: 'Room 301',
          date: '2026-06-18',
          stage: stageLabel,
          startTime: '09:00',
          endTime: '09:30',
          slotDuration: 30,
        ),
      ],
    );

    final rows = buildScheduleImportPreviewRows(
      parsed,
      testState,
      scope: 'capstone',
      stageId: stageId,
      eventName: '',
      date: '2026-06-18',
      room: 'Room 301',
      fallbackDuration: 30,
      panelRubricId: null, // rubric missing -> stage issue
      adviserRubricId: 2,
      peerRubricId: 3,
      panelWeight: 50,
      peerWeight: 20,
    );

    expect(rows, hasLength(1));
    expect(rows[0].stageIssues, isNotEmpty);
    expect(rows[0].teamIssues, isNotEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: double.infinity,
                    columns: const [
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Validation Issues')),
                    ],
                    rows: [
                      DataRow(
                        cells: [
                          const DataCell(Text('Status')),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      child: Text('Stage: ${rows[0].stageIssues.first}'),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      child: Text('Team: ${rows[0].teamIssues.first}'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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

    expect(find.textContaining('Stage:'), findsOneWidget);
    expect(find.textContaining('Team:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
