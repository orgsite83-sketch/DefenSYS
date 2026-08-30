import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';

void main() {
  group('buildScheduleImportPreviewRows', () {
    const stageId = 10;
    const stageLabel = 'Project Proposal';

    final testState = DefenseSchedulerState(
      defenseStages: const [
        {'id': stageId, 'label': stageLabel},
      ],
      faculty: const [
        {'id': 101, 'name': 'Jonathan Beltran', 'username': 'jbeltran'},
        {'id': 102, 'name': 'Cecilia Magbanua', 'username': 'cmagbanua'},
        {'id': 103, 'name': 'Ricardo Fontanilla', 'username': 'rfontanilla'},
      ],
      teams: const [
        // 1. Initial ready team (endorsed)
        {
          'id': 1,
          'name': 'Team Alpha',
          'project_title': 'Project Alpha',
          'level': 'Capstone 1',
          'ready_for_stage': stageLabel,
          'completed_stages': <String>[],
          'scheduled_stages': <String>[],
          'redefense_stages': <String>[],
        },
        // 2. Re-defense ready team (verdict for_redefense)
        {
          'id': 2,
          'name': 'Team SkyLedger',
          'project_title': 'Alumni Career Tracker',
          'level': 'Capstone 1',
          'ready_for_stage': null,
          'completed_stages': <String>[],
          'scheduled_stages': <String>[],
          'redefense_stages': [stageLabel],
        },
        // 3. Already passed team
        {
          'id': 3,
          'name': 'Team Nexus',
          'project_title': 'Smart Campus IoT',
          'level': 'Capstone 1',
          'ready_for_stage': null,
          'completed_stages': [stageLabel],
          'scheduled_stages': <String>[],
          'redefense_stages': <String>[],
        },
        // 4. Not endorsed team
        {
          'id': 4,
          'name': 'Team Beta',
          'project_title': 'Project Beta',
          'level': 'Capstone 1',
          'ready_for_stage': null,
          'completed_stages': <String>[],
          'scheduled_stages': <String>[],
          'redefense_stages': <String>[],
        },
      ],
    );

    test('classifies rows into correct lifecycle status: initial, redefense, passed, and unendorsed', () {
      final parsed = ParsedScheduleImport(
        stage: stageLabel,
        date: '2026-06-18',
        room: 'Room 301',
        rows: const [
          ParsedScheduleImportRow(
            sheetRow: 1,
            time: '09:00 - 09:30',
            teamName: 'Team Alpha',
            projectTitle: 'Project Alpha',
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
          ParsedScheduleImportRow(
            sheetRow: 2,
            time: '09:30 - 10:00',
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
            startTime: '09:30',
            endTime: '10:00',
            slotDuration: 30,
          ),
          ParsedScheduleImportRow(
            sheetRow: 3,
            time: '10:00 - 10:30',
            teamName: 'Team Nexus',
            projectTitle: 'Smart Campus IoT',
            adviser: 'Ricardo Fontanilla',
            members: [],
            chair: 'Jonathan Beltran',
            panelMembers: [],
            documenter: 'Cecilia Magbanua',
            room: 'Room 301',
            date: '2026-06-18',
            stage: stageLabel,
            startTime: '10:00',
            endTime: '10:30',
            slotDuration: 30,
          ),
          ParsedScheduleImportRow(
            sheetRow: 4,
            time: '10:30 - 11:00',
            teamName: 'Team Beta',
            projectTitle: 'Project Beta',
            adviser: 'Ricardo Fontanilla',
            members: [],
            chair: 'Jonathan Beltran',
            panelMembers: [],
            documenter: 'Cecilia Magbanua',
            room: 'Room 301',
            date: '2026-06-18',
            stage: stageLabel,
            startTime: '10:30',
            endTime: '11:00',
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
        panelRubricId: 1,
        adviserRubricId: 2,
        peerRubricId: 3,
        panelWeight: 50,
        peerWeight: 20,
      );

      expect(rows, hasLength(4));

      // Row 1: Initial Ready
      expect(rows[0].rowType, equals(ScheduleImportRowType.initialReady));
      expect(rows[0].ready, isTrue);
      expect(rows[0].isRedefense, isFalse);
      expect(rows[0].issues, isEmpty);

      // Row 2: Re-defense Ready
      expect(rows[1].rowType, equals(ScheduleImportRowType.redefenseReady));
      expect(rows[1].ready, isTrue);
      expect(rows[1].isRedefense, isTrue);
      expect(rows[1].issues, isEmpty);

      // Row 3: Already Passed (Protected / Skipped)
      expect(rows[2].rowType, equals(ScheduleImportRowType.alreadyPassed));
      expect(rows[2].ready, isFalse);
      expect(rows[2].isAlreadyPassed, isTrue);
      expect(rows[2].issues.first, contains('already completed and passed'));

      // Row 4: Not Endorsed
      expect(rows[3].rowType, equals(ScheduleImportRowType.notEndorsed));
      expect(rows[3].ready, isFalse);
      expect(rows[3].isNotEndorsed, isTrue);
      expect(rows[3].issues.first, contains('not endorsed'));
    });

    test('correctly identifies stage rubrics missing as stage issues and marks rows as not ready', () {
      final parsed = ParsedScheduleImport(
        stage: stageLabel,
        date: '2026-06-18',
        room: 'Room 301',
        rows: const [
          ParsedScheduleImportRow(
            sheetRow: 1,
            time: '09:00 - 09:30',
            teamName: 'Team Alpha',
            projectTitle: 'Project Alpha',
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
        panelRubricId: null, // Missing rubric!
        adviserRubricId: 2,
        peerRubricId: 3,
        panelWeight: 50,
        peerWeight: 20,
      );

      expect(rows, hasLength(1));
      expect(rows[0].ready, isFalse);
      expect(rows[0].hasStageIssue, isTrue);
      expect(rows[0].stageIssues.first, contains('rubrics are incomplete'));
      expect(rows[0].teamIssues, isEmpty);
    });
  });
}

