import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/import/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_references.dart';
import 'package:defensys/utils/import/schedule_import_workspace.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
  final source = parseScheduleImportMatrix([
    ['Time', 'Team Name', 'Chair', 'Panel Member 1'],
    ['08:00-08:30', 'Alpha', 'Person A', 'Person A'],
    ['08:30-09:00', 'Beta', 'Person A', 'Person B'],
  ]);
  final rows = attachScheduleImportSource(
    source,
    'file',
    'schedule.csv',
  ).parsed.rows;
  final resolutions = {
    for (final r in scheduleReferenceRequests(rows, isPit: true))
      '${r['reference_id']}': {
        ...r,
        'reference_key': '${r['text']}'.toLowerCase(),
        'review_state': 'needs_confirmation',
      },
  };

  test(
    'registered ID corrections preserve source and duty boundaries through JSON',
    () {
      final corrected = selectScheduleAccount(
        rows: rows,
        referenceId: scheduleReferenceId(rows.first, 'chair'),
        duty: 'chair',
        accountId: 42,
        resolutions: resolutions,
        applyEquivalent: true,
      );
      expect(corrected.map((r) => r.selectedAccountIds['chair']), [42, 42]);
      expect(
        corrected.first.selectedAccountIds.containsKey('panel_0'),
        isFalse,
      );
      expect(corrected.first.chair, 'Person A');
      expect(
        ParsedScheduleImportRow.fromJson(
          corrected.first.toJson(),
        ).selectedAccountIds['chair'],
        42,
      );
      final single = selectScheduleAccount(
        rows: rows,
        referenceId: scheduleReferenceId(rows.first, 'chair'),
        duty: 'chair',
        accountId: 42,
        resolutions: resolutions,
      );
      expect(single.last.selectedAccountIds, isEmpty);
    },
  );

  test(
    'equivalent correction preserves a prior selection and ignores unvalidated rows',
    () {
      final existing = [
        rows.first,
        rows.last.copyWith(selectedAccountIds: {'chair': 7}),
      ];
      final corrected = selectScheduleAccount(
        rows: existing,
        referenceId: scheduleReferenceId(rows.first, 'chair'),
        duty: 'chair',
        accountId: 42,
        resolutions: resolutions,
        applyEquivalent: true,
      );
      expect(corrected.last.selectedAccountIds['chair'], 7);
      final unvalidated = selectScheduleAccount(
        rows: rows,
        referenceId: scheduleReferenceId(rows.first, 'chair'),
        duty: 'chair',
        accountId: 42,
        resolutions: {
          scheduleReferenceId(rows.first, 'chair'): resolutions.values.first,
        },
        applyEquivalent: true,
      );
      expect(unvalidated.last.selectedAccountIds, isEmpty);
    },
  );

  test(
    'authoritative reference results block fallback and carry selected IDs to payloads',
    () {
      ScheduleImportPreviewRow preview(
        Map<String, Map<String, dynamic>> references,
      ) => buildScheduleImportPreviewRows(
        ParsedScheduleImport(rows: [rows.first]),
        const DefenseSchedulerState(),
        scope: 'pit',
        stageId: null,
        eventName: 'Pitching',
        date: '2026-11-12',
        room: 'Room 1',
        fallbackDuration: 30,
        panelRubricId: 1,
        adviserRubricId: null,
        peerRubricId: 3,
        panelWeight: 80,
        peerWeight: 20,
        facultyReferences: references,
      ).single;
      expect(preview({}).hasUnresolvedFaculty, isTrue);
      final verified = preview({
        scheduleReferenceId(rows.first, 'chair'): {
          'account': {'id': 42},
        },
        scheduleReferenceId(rows.first, 'panel_0'): {
          'account': {'id': 43},
        },
      });
      expect(verified.chairPanelistId, 42);
      expect(verified.toPayload()['panelist_ids'], [42, 43]);
    },
  );

  test('impossible dates are not normalized to another calendar day', () {
    expect(normalizeImportDate('2026-02-30'), '2026-02-30');
    expect(normalizeImportDate('February 30, 2026'), 'February 30, 2026');
    expect(normalizeImportDate('2/30/2026'), '2/30/2026');
  });
}
