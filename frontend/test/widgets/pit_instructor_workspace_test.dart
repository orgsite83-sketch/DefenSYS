import 'package:defensys/screens/web/faculty/pit_instructor/pit_instructor_dashboard_content.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _pitStage = {
  'stage_label': 'System Concept Pitching',
  'deliverables_configured': true,
  'required_complete': true,
  'endorsement_required': false,
  'stage_status_detail': 'scheduling_eligible',
  'endorsed': false,
  'required_total': 0,
  'required_uploaded': 0,
  'materials_readiness': {'required_total': 2, 'submitted_total': 0},
  'pre': [
    {
      'id': 'PAPER',
      'label': 'Concept Paper',
      'type': 'pre',
      'required': true,
      'requirement_timing': 'defense',
      'uploaded': false,
    },
    {
      'id': 'DECK',
      'label': 'Pitch Deck',
      'type': 'pre',
      'required': true,
      'requirement_timing': 'defense',
      'uploaded': false,
    },
  ],
  'post': <Map<String, dynamic>>[],
};

const _pitTeam = {
  'id': 7,
  'name': 'Team AlphaWave',
  'project_title': 'Library tracker',
  'current_stage': 'System Concept Pitching',
  'stages': [_pitStage],
};

class _PitDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    scope: 'pit',
    selectedStage: 'System Concept Pitching',
    stageOptions: ['System Concept Pitching'],
    teams: [_pitTeam],
  );

  @override
  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

class _PitGradesNotifier extends AdviserGradingNotifier {
  @override
  Future<void> fetchAll() async {}
}

void main() {
  testWidgets(
    'instructor dashboard uses adviser layout for assigned PIT teams',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      int? openedTeam;
      int? openedGradeTeam;

      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: PitInstructorDashboardContent(
            data: const {
              'active_semester': '1st Semester, A.Y. 2026-2027',
              'pit_teams': [
                {
                  'id': 7,
                  'name': 'Team AlphaWave',
                  'projectTitle': 'Library tracker',
                  'yearLevel': '1st Year',
                  'section': 'BSIT-1A',
                  'semester': '1st Semester',
                  'schoolYear': '2026-2027',
                },
                {
                  'id': 8,
                  'name': 'Other section',
                  'yearLevel': '1st Year',
                  'section': 'BSIT-1B',
                },
              ],
            },
            facultyName: 'Eduardo Padilla',
            yearLevel: '1st Year',
            section: 'BSIT-1A',
            onOpenDeliverables: (id) => openedTeam = id,
            onOpenGrading: (id) => openedGradeTeam = id,
          ),
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            _PitDeliverablesNotifier.new,
          ),
        ],
      );

      expect(find.text('My actions'), findsOneWidget);
      expect(find.text('Defense materials'), findsOneWidget);
      expect(find.text('My teams'), findsOneWidget);
      expect(find.text('Ready to schedule'), findsOneWidget);
      expect(
        find.text('No submissions need review right now.'),
        findsOneWidget,
      );
      expect(find.text('Other section'), findsNothing);
      await tester.tap(find.text('Team AlphaWave').first);
      expect(openedTeam, 7);
      await tester.ensureVisible(find.text('View PIT grades'));
      await tester.tap(find.text('View PIT grades'));
      expect(openedGradeTeam, 7);
    },
  );

  testWidgets('PIT files due after scheduling need no endorsement', (
    tester,
  ) async {
    expect(
      DeliverablesTriageHelper.isOverdueOrMissing(
        Map<String, dynamic>.from(_pitTeam),
      ),
      isTrue,
    );
    expect(
      DeliverablesTriageHelper.isReadyForDefense(
        Map<String, dynamic>.from(_pitTeam),
      ),
      isTrue,
    );
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: ['System Concept Pitching'],
            teams: [_pitTeam],
          ),
          isAdviser: false,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );

    expect(find.text('Ready to Schedule'), findsWidgets);
    expect(find.text('Ready for Endorsement'), findsNothing);
    expect(find.text('No scheduling uploads required'), findsOneWidget);
    expect(
      find.textContaining(
        'No endorsement needed. This team can be scheduled now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Endorse Team'), findsNothing);
  });

  testWidgets('required PIT scheduling files still allow manual endorsement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final stage = <String, dynamic>{
      ..._pitStage,
      'endorsement_required': true,
      'stage_status_detail': 'awaiting_endorsement',
      'required_total': 1,
      'required_uploaded': 1,
      'materials_readiness': {'required_total': 0, 'submitted_total': 0},
      'pre': [
        {
          'id': 'PAPER',
          'label': 'Concept Paper',
          'type': 'pre',
          'required': true,
          'uploaded': true,
          'submission': {'status': 'accepted'},
        },
      ],
    };
    final team = <String, dynamic>{
      ..._pitTeam,
      'stages': [stage],
    };
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: const ['System Concept Pitching'],
            teams: [team],
          ),
          isAdviser: false,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );

    expect(find.text('Ready for Endorsement'), findsWidgets);
    final endorseButton = find.ancestor(
      of: find.text('Endorse Team'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(endorseButton).onPressed, isNotNull);
  });
}
