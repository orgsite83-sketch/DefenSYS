import 'package:defensys/screens/web/admin/student_teams/components/student_teams_bulk_import.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  final rows = <Map<String, dynamic>>[
    {
      'team_name': 'Team AgriPulse',
      'project_title': 'Soil monitoring module',
      'section': 'BSIT-3A',
      'member_ids': ['Ana Cruz', 'Ben Santos'],
      'leader_id': 'Ana Cruz',
    },
  ];

  testWidgets(
    'PIT import exposes event context, blocks conflicts and links the original roster',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      int? reviewed;
      String? selectedEvent;
      const previewKey = ValueKey('pit-import-conflict-preview');
      final preview = <String, dynamic>{
        'summary': {'total': 1, 'ready': 0},
        'rows': [
          {
            'row': 1,
            'ready': false,
            'team_name': 'Team AgriPulse',
            'section': 'BSIT-3A',
            'program_label': '3rd Year PIT',
            'issues': [
              'Ana Cruz is already assigned to team "AgriPulse". Review its existing concept proposals.',
            ],
            'membership_conflicts': [
              {'id': 49, 'name': 'AgriPulse', 'event_name': 'Mini Capstone'},
            ],
          },
        ],
      };
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: previewKey,
          child: StudentTeamsBulkImportView(
            state: const StudentTeamsState(
              pitEvents: [
                {
                  'id': 4,
                  'event_name': 'Mini Capstone',
                  'year_level': '3rd Year',
                },
                {
                  'id': 5,
                  'event_name': 'Later showcase',
                  'year_level': '3rd Year',
                },
              ],
            ),
            isCapstoneAdmin: false,
            pitLeadYear: '3rd Year',
            parsedBulkRows: rows,
            bulkCsvDraft: '',
            selectedBulkAdviserFilter: 'all',
            bulkPreview: preview,
            showIssuesOnly: false,
            templateWarning: null,
            isBulkImportDirty: false,
            section: null,
            systemName: null,
            projectManager: null,
            onRequestClose: () async {},
            onDownloadTemplate: () {},
            onPickBulkCsvFile: () {},
            onImportBulkTeams: () =>
                fail('Conflicting row must not be importable'),
            onExportBulkCsv: () {},
            onScheduleRowPreview: (_) {},
            onDeleteBulkRow: (_) {},
            onAddBulkRow: () {},
            onAdviserFilterChanged: (_) {},
            onShowIssuesOnlyChanged: (_) {},
            onEventChanged: (value) => selectedEvent = value,
            onOpenExistingTeam: (id) => reviewed = id,
          ),
        ),
      );
      expect(find.text('Unassigned roster'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('top_import_ready_teams_btn')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Unassigned roster'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later showcase').last);
      await tester.pumpAndSettle();
      expect(selectedEvent, 'Later showcase');
      await tester.ensureVisible(find.text('Review AgriPulse'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byKey(previewKey),
        'pit-import-conflict-review',
      );
      await tester.tap(find.text('Review AgriPulse'));
      expect(reviewed, 49);
      expect(find.text('Ready'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'intentional multiple-team overlap keeps a visible warning in the row status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: TeamBulkImportReviewTable(
            rows: rows,
            previewRows: [
              {
                'row': 1,
                'ready': true,
                'section': 'BSIT-3A',
                'issues': [],
                'warnings': [
                  'The multiple-team policy permits an additional roster. Original records remain attached to AgriPulse.',
                ],
              },
            ],
            isCapstoneAdmin: false,
            pitLeadYear: '3rd Year',
            showIssuesOnly: false,
            onRowChanged: (_) {},
            onDeleteRow: (_) {},
            onAddRow: () {},
          ),
        ),
      );
      expect(find.text('Ready · 1 warning'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
