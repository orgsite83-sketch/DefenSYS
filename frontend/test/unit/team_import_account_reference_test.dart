import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/team_import_reference_corrections.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_draft.dart';

void main() {
  test('registered usernames remain distinct for duplicate display names', () {
    final accounts = teamImportAccounts([
      {'id': 901, 'username': '207', 'name': 'GINBERT FERNANDEZ'},
      {'id': 902, 'username': '208', 'name': 'GINBERT FERNANDEZ'},
    ]);
    expect(accounts.map(teamImportAccountId), ['207', '208']);
    expect(teamImportAccountId({'id': 901, 'name': 'Unidentified'}), isEmpty);
    expect(teamImportAccountId({'student_id': 'student-1'}), 'student-1');
  });

  test('middle-initial suggestions do not equate conflicting initials', () {
    expect(
      teamImportPossibleName('GINBERT A. FERNANDEZ', 'GINBERT FERNANDEZ'),
      isTrue,
    );
    expect(
      teamImportPossibleName('MATABALAN, Johnley L.', 'JOHNLEY L MATABALAN'),
      isTrue,
    );
    expect(
      teamImportPossibleName('GINBERT A. FERNANDEZ', 'GINBERT B FERNANDEZ'),
      isFalse,
    );
    expect(
      teamImportPossibleName('GINBERT ALLAN FERNANDEZ', 'GINBERT FERNANDEZ'),
      isFalse,
    );
  });

  test(
    'replacing a member updates the leader and deduplicates resolved identity',
    () {
      final rows = <Map<String, dynamic>>[
        {
          'team_name': 'CodeCrafters',
          'member_ids': [
            'MATABALAN, Johnley L.',
            'Johnley L Matabalan',
            'other',
          ],
          'leader_id': 'MATABALAN, Johnley L.',
        },
      ];
      applyTeamImportAccount(
        rows: rows,
        index: 0,
        username: '2023304712',
        resolution: {
          'field': 'member_ids',
          'reference': 'MATABALAN, Johnley L.',
        },
        resolutions: [
          {
            'field': 'member_ids',
            'reference': 'Johnley L Matabalan',
            'status': 'matched',
            'username': '2023304712',
          },
        ],
      );
      expect(rows.single['member_ids'], ['2023304712', 'other']);
      expect(rows.single['leader_id'], '2023304712');
    },
  );

  test(
    'faculty selection replaces both legacy fields with the registered ID',
    () {
      final rows = <Map<String, dynamic>>[
        {'adviser_name': 'GINBERT A. FERNANDEZ', 'adviser_id': 901},
      ];
      applyTeamImportAccount(
        rows: rows,
        index: 0,
        username: '207',
        resolution: {
          'field': 'adviser_name',
          'reference': 'GINBERT A. FERNANDEZ',
        },
      );
      expect(rows.single['adviser_name'], '207');
      expect(rows.single['adviser_id'], '207');
    },
  );

  test('shared manager replacement applies within the affected section', () {
    final rows = <Map<String, dynamic>>[
      {'section': 'BSIT-3A', 'project_manager': 'First M. Last'},
      {'section': 'BSIT-3A', 'project_manager': 'First M. Last'},
      {'section': 'BSIT-3B', 'project_manager': 'First M. Last'},
    ];
    expect(
      applyTeamImportAccount(
        rows: rows,
        index: 0,
        username: 'pm-id',
        resolution: {'field': 'project_manager', 'reference': 'First M. Last'},
      ),
      [0, 1],
    );
    expect(rows[1]['project_manager'], 'pm-id');
    expect(rows[2]['project_manager'], 'First M. Last');
  });

  test(
    'selected IDs and a non-first leader survive draft and CSV round trips',
    () {
      final row = <String, dynamic>{
        'team_name': 'CodeCrafters',
        'section': 'BSIT-3D',
        'member_ids': ['member-2', '2023304712'],
        'leader_id': '2023304712',
        'adviser_name': '207',
      };
      final draft = TeamBulkImportDraft(
        rows: [row],
        adviserFilter: 'all',
        savedAt: DateTime(2026),
      );
      expect(TeamBulkImportDraft.fromJson(draft.toJson()).rows.single, row);
      final csv = rowsToTeamCsv([row], isCapstoneAdmin: true);
      final restored = parseTeamBulkCsv(csv);
      expect(restored.rows.single['member_ids'], ['member-2', '2023304712']);
      expect(restored.rows.single['leader_id'], '2023304712');
      expect(restored.rows.single['adviser_name'], '207');
    },
  );
}
