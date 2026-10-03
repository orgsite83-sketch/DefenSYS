import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parsed = ParsedScheduleImport(
    rows: const [
      ParsedScheduleImportRow(
        sheetRow: 2,
        time: '08:00 - 09:00',
        startTime: '08:00',
        endTime: '09:00',
        teamName: 'Team Aurora',
        projectTitle: 'Prototype',
        adviser: '',
        members: [],
        chair: 'Lina Santos',
        panelMembers: [],
        documenter: '',
        room: 'Lab 1',
        date: '2026-10-20',
        stage: 'PIT 1',
        slotDuration: 60,
      ),
    ],
  );
  const state = DefenseSchedulerState(
    faculty: [
      {
        'id': 12,
        'name': 'Lina Santos',
        'username': 'FAC-12',
        'is_panelist': false,
      },
    ],
    teams: [
      {
        'id': 99,
        'name': 'Team Aurora',
        'project_title': 'Prototype',
        'level': '1st Year PIT',
        'year_level': '1st Year',
      },
    ],
  );
  ScheduleImportPreviewRow preview(DefenseSchedulerState value) =>
      buildScheduleImportPreviewRows(
        parsed,
        value,
        scope: 'pit',
        stageId: null,
        eventName: 'PIT 1',
        date: '2026-10-20',
        room: 'Lab 1',
        fallbackDuration: 60,
        panelRubricId: 10,
        adviserRubricId: null,
        peerRubricId: 20,
        panelWeight: 80,
        peerWeight: 20,
      ).single;

  test('admin import approves known faculty when confirmed', () {
    final admin = state.copyWith(canApprovePanelists: true);
    final row = preview(admin);
    expect(row.panelistIds, [12]);
    expect(
      row.warnings.any((w) => w.contains('reusable panelist eligibility')),
      isTrue,
    );
    expect(
      row.slotIssues.any((i) => i.contains('panelist eligibility')),
      isFalse,
    );
    expect(admin.isEligiblePanelist(12), isFalse);
    expect(admin.selectablePanelists.length, 1);
  });
  test(
    'PIT import retains faculty match but blocks unapproved assignments',
    () {
      final lead = state.copyWith(requiresPanelistApproval: true);
      final row = preview(lead);
      expect(row.panelistIds, [12]);
      expect(
        row.slotIssues.any((i) => i.contains('Request admin approval')),
        isTrue,
      );
      expect(row.ready, isFalse);
      expect(lead.selectablePanelists, isEmpty);
    },
  );
  test(
    'later approval removes the import blocker without changing the file',
    () {
      final lead = state.copyWith(
        requiresPanelistApproval: true,
        panelists: [
          {'id': 12, 'name': 'Lina Santos', 'is_panelist': true},
        ],
      );
      final row = preview(lead);
      expect(row.panelistIds, [12]);
      expect(
        row.slotIssues.any((i) => i.contains('panelist eligibility')),
        isFalse,
      );
      expect(lead.selectablePanelists.length, 1);
    },
  );
}
