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

  test('middle-initial review suggestions explain conflicts', () {
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
      isTrue,
    );
    expect(
      teamImportPossibleName('GINBERT ALLAN FERNANDEZ', 'GINBERT FERNANDEZ'),
      isFalse,
    );
  });

  test(
    'client spelling and suffix differences are explained as review suggestions',
    () {
      expect(
        teamImportNameDifference('BONGCAC, Ryza Mae G.', 'RYZA MAY G. BONGCAC'),
        'Spelling differs: MAE versus MAY',
      );
      expect(
        teamImportNameDifference('TAC-AN, Edgar Jr. C.', 'EDGAR, JR C TAC-AN'),
        'Formatting match',
      );
      expect(
        teamImportNameDifference('Ginbert A Fernandez', 'Ginbert B Fernandez'),
        'Middle initial differs: A versus B',
      );
      expect(
        teamImportNameDifference('Dela Cruz, Juan', 'Juan Dela Crux'),
        isNull,
      );
      expect(
        teamImportNameDifference('Juan Cruz Jr.', 'Juan Cruz Sr.'),
        'Suffix differs: jr versus sr',
      );
    },
  );

  test(
    'one adviser selection updates equivalent references across Capstone sections',
    () {
      final rows = <Map<String, dynamic>>[
        {'section': 'BSIT-3A', 'adviser_name': 'GINBERT A. FERNANDEZ'},
        {'section': 'BSIT-4D', 'adviser_name': 'FERNANDEZ, Ginbert A'},
        {'section': 'BSIT-3B', 'adviser_name': 'GINBERT B FERNANDEZ'},
        {'level': '1st Year PIT', 'adviser_name': 'GINBERT A. FERNANDEZ'},
        {'instructor_name': 'GINBERT A. FERNANDEZ'},
        {'adviser_name': 'previously-selected-id'},
      ];
      expect(
        applyTeamImportAccount(
          rows: rows,
          index: 0,
          username: '207',
          resolution: {
            'field': 'adviser_name',
            'reference': 'GINBERT A. FERNANDEZ',
          },
        ),
        [0, 1],
      );
      expect(rows[1]['adviser_name'], '207');
      expect(rows[1]['adviser_id'], '207');
      expect(rows[2]['adviser_name'], 'GINBERT B FERNANDEZ');
      expect(rows[3]['adviser_name'], 'GINBERT A. FERNANDEZ');
      expect(rows[4]['instructor_name'], 'GINBERT A. FERNANDEZ');
      expect(rows[5]['adviser_name'], 'previously-selected-id');
    },
  );

  test(
    'batch correction uses server keys and never fills an unvalidated row',
    () {
      final rows = <Map<String, dynamic>>[
        {'adviser_name': 'Dr. Ginbert A. Fernandez'},
        {'adviser_name': 'FERNANDEZ, Ginbert A'},
        {'adviser_name': 'GINBERT A. FERNANDEZ'},
      ];
      const source = {
        'field': 'adviser_name',
        'reference': 'Dr. Ginbert A. Fernandez',
        'reference_key': 'ginbert a fernandez',
      };
      final changed = applyTeamImportAccount(
        rows: rows,
        index: 0,
        username: '207',
        resolution: source,
        allResolutions: [
          [source],
          [
            {
              'field': 'adviser_name',
              'reference': 'FERNANDEZ, Ginbert A',
              'reference_key': 'ginbert a fernandez',
            },
          ],
          [],
        ],
      );
      expect(changed, [0, 1]);
      expect(rows[2]['adviser_name'], 'GINBERT A. FERNANDEZ');
    },
  );

  test(
    'repeated student references stay within the same section year and event',
    () {
      final rows = <Map<String, dynamic>>[
        for (final scope in [
          {
            'section': 'BSIT-2A',
            'year_level': '2nd Year',
            'current_defense_stage': 'Design',
          },
          {
            'section': 'BSIT-2A',
            'year_level': '2nd Year',
            'current_defense_stage': 'Design',
          },
          {
            'section': 'BSIT-2A',
            'year_level': '2nd Year',
            'current_defense_stage': 'Final',
          },
          {
            'section': 'BSIT-2B',
            'year_level': '2nd Year',
            'current_defense_stage': 'Design',
          },
        ])
          {
            ...scope,
            'level': '2nd Year PIT',
            'member_ids': ['BONGCAC, Ryza Mae G.'],
            'leader_id': 'BONGCAC, Ryza Mae G.',
          },
      ];
      expect(
        applyTeamImportAccount(
          rows: rows,
          index: 0,
          username: 'ryza-id',
          resolution: {
            'field': 'member_ids',
            'reference': 'BONGCAC, Ryza Mae G.',
          },
        ),
        [0, 1],
      );
      expect(rows[1]['leader_id'], 'ryza-id');
      expect(rows[2]['member_ids'], ['BONGCAC, Ryza Mae G.']);
      expect(rows[3]['leader_id'], 'BONGCAC, Ryza Mae G.');
    },
  );

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
    'expanded middle names and encoding problems have specific explanations',
    () {
      expect(
        teamImportNameDifference('CATADA, Mernel A.', 'MERNEL ANTIO CATADA'),
        'Middle initial expanded',
      );
      expect(
        teamImportNameDifference('QUI\u00d1ON, Ray An', 'RAY AN QUI\ufffdON'),
        'Account name needs encoding repair',
      );
      expect(
        teamImportNameDifference('DOMINGUEZ, Noel R.', 'NOEL R DOMINGUEZ JR.'),
        contains('Suffix differs'),
      );
    },
  );

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
