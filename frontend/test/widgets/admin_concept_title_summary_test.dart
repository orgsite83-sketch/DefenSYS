import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_grid.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/widgets/repository/proposal_title_summary.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';

Map<String, dynamic> workflow({bool blank = false, int count = 3}) => {
  'enabled': true,
  'status': 'concepts_needed',
  'required_count': count,
  'shared_import_pending': true,
  'concepts': [
    for (var i = 1; i <= count; i++)
      {
        'key': 'c$i',
        'title': i == 1 && !blank ? 'Imported soil sensor module' : '',
      },
  ],
  'system_concepts': [
    for (var i = 1; i <= count; i++)
      {
        'key': 'c$i',
        'title': i == 1 && !blank ? 'Imported shared agriculture platform' : '',
      },
  ],
};

Map<String, dynamic> team({bool blank = false, int count = 3}) => {
  'id': 5,
  'name': 'Team AgriPulse',
  'section': 'BSIT-3A',
  'level': '3rd Year Capstone',
  'project_title': blank ? '' : 'Imported soil sensor module',
  // Old imports can have this false; workflow slots remain authoritative.
  'project_pending': false,
  'adviser_name': 'Eduardo Padilla',
  'leader_name': 'Gabriel Navarro',
  'project_manager_name': 'Gabriel Navarro',
  'defense_context': {
    'current_stage': 'Concept Proposal',
    'concept_workflow': workflow(blank: blank, count: count),
  },
};

Future<void> _size(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1550, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Admin Teams keeps compact rows and shows larger shared titles with a status badge $dark',
      (tester) async {
        await _size(tester);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: GroupedSectionView(
              state: StudentTeamsState(teams: [team()]),
              isPit: false,
              searchQuery: 'AgriPulse',
              onOpenTeamDetail: (_) {},
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        expect(find.text('1 of 3 titles provided'), findsOneWidget);
        expect(
          find.text('Concept selection · 1 of 3 titles provided'),
          findsOneWidget,
        );
        expect(
          find.text('Imported shared agriculture platform'),
          findsOneWidget,
        );
        expect(find.text('Imported soil sensor module'), findsNothing);
        expect(find.text('System B'), findsOneWidget);
        expect(find.text('System C'), findsOneWidget);
        expect(find.text('Concept 2'), findsNothing);
        expect(find.text('Concept 3'), findsNothing);
        expect(find.text('Pending proposal'), findsNWidgets(2));
        expect(find.byType(ProposalTitleProgressBadge), findsOneWidget);
        expect(
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text('Team AgriPulse'),
                      matching: find.byType(Column),
                    )
                    .first,
              )
              .height,
          lessThan(90),
        );
        expect(find.byType(EditableText), findsNothing);
        await capturePreview(
          tester,
          find.byType(GroupedSectionView),
          'admin-imported-concepts-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Cohort dropdown lists imported and pending concepts beside the existing three paper slots $dark',
      (tester) async {
        await _size(tester);
        final item = team();
        final stage = <String, dynamic>{
          'stage_label': 'Concept Proposal',
          'deliverables_configured': true,
          'required_total': 3,
          'concept_workflow': workflow(),
          'pre': [
            {
              'id': 'PAPER',
              'label': 'Concept Papers',
              'type': 'pre',
              'required': true,
              'file_policy': {'mode': 'concepts'},
              'can_upload': false,
              'document_slots': [
                for (var i = 1; i <= 3; i++)
                  {
                    'key': 'c$i:paper',
                    'label': 'Concept $i · Concept paper',
                    'required': true,
                    'formats': ['pdf'],
                  },
              ],
            },
          ],
        };
        item['selected_stage'] = stage;
        item['stages'] = [stage];
        item['current_stage'] = 'Concept Proposal';
        final state = CapstoneDeliverablesState(
          teams: [item],
          selectedStage: 'Concept Proposal',
          stageOptions: const ['Concept Proposal'],
        );
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: CohortSubmissionsMatrix(
              teams: [item],
              state: state,
              isAdviser: false,
              initialExpandedTeamId: 5,
            ),
          ),
          overrides: authTestOverrides(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        expect(
          find.text('Concept proposals · 1 of 3 titles provided'),
          findsOneWidget,
        );
        await tester.tap(
          find.text('Concept proposals · 1 of 3 titles provided'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Imported soil sensor module'), findsOneWidget);
        expect(find.text('Pending proposal'), findsNWidgets(2));
        expect(find.text('Concept 3 · Concept paper'), findsOneWidget);
        expect(
          find.text('Concept selection · 3 required proposals'),
          findsOneWidget,
        );
        await capturePreview(
          tester,
          find.byType(CohortSubmissionsMatrix),
          'cohort-imported-concepts-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'blank and custom-count proposals keep every configured slot; approved titles use the normal summary',
    (tester) async {
      await _size(tester);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: GroupedSectionView(
            state: StudentTeamsState(teams: [team(blank: true, count: 4)]),
            isPit: false,
            searchQuery: 'AgriPulse',
            onOpenTeamDetail: (_) {},
          ),
        ),
      );
      expect(
        find.text('Concept selection · 0 of 4 titles provided'),
        findsOneWidget,
      );
      expect(find.text('Concept 4'), findsNothing);
      expect(find.text('System D'), findsOneWidget);
      expect(
        hasOpenConceptProposals({...workflow(), 'status': 'approved'}),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
