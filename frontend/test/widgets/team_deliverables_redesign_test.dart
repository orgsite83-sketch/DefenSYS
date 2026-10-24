import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_filter_bar.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadPreviewFonts(force: true));

  final mockTeams = [
    {
      'id': 101,
      'name': 'Team Alpha',
      'project_title': 'Campus Navigation & Indoor Mapping',
      'adviser_name': 'Dr. Alan Turing',
      'current_stage': 'Concept Proposal',
      'stages': [
        {
          'stage_label': 'Concept Proposal',
          'status': 'ready',
          'endorsed': true,
          'deliverables': [
            {'id': 1, 'name': 'Project Charter', 'status': 'approved'},
            {'id': 2, 'name': 'Literature Review', 'status': 'approved'},
          ],
        },
      ],
      'members': [
        {'id': 1, 'name': 'Alice Smith', 'role': 'leader'},
        {'id': 2, 'name': 'Bob Jones', 'role': 'member'},
      ],
    },
    {
      'id': 102,
      'name': 'Team Beta',
      'project_title': 'Automated Grading Assistance',
      'adviser_name': 'Dr. Ada Lovelace',
      'current_stage': 'Concept Proposal',
      'stages': [
        {
          'stage_label': 'Concept Proposal',
          'status': 'pending',
          'endorsed': false,
          'deliverables': [
            {'id': 3, 'name': 'Proposal Deck', 'status': 'pending'},
            {'id': 4, 'name': 'Problem Statement', 'status': 'submitted'},
          ],
        },
      ],
      'members': [
        {'id': 3, 'name': 'Charlie Day', 'role': 'leader'},
      ],
    },
    {
      'id': 103,
      'name': 'Team Gamma',
      'project_title': 'IoT Environmental Monitoring',
      'adviser_name': 'Dr. Grace Hopper',
      'current_stage': 'Concept Proposal',
      'stages': [
        {
          'stage_label': 'Concept Proposal',
          'status': 'missing',
          'endorsed': false,
          'deliverables': [
            {'id': 5, 'name': 'Hardware Specs', 'status': 'missing'},
          ],
        },
      ],
      'members': [
        {'id': 4, 'name': 'Dave Miller', 'role': 'member'},
      ],
    },
  ];

  group('DeliverablesTriageHelper Unit Tests', () {
    test('review-first is stable and leaves provider order unchanged', () {
      final ordered = DeliverablesTriageHelper.reviewFirst(mockTeams);
      expect(ordered.map((t) => t['id']), [102, 101, 103]);
      expect(mockTeams.map((t) => t['id']), [101, 102, 103]);
      expect(DeliverablesTriageHelper.pendingReviewCount(mockTeams[1]), 2);
    });

    test('uploaded is not accepted or ready; upload locks do not hide reviews', () {
      final team = <String, dynamic>{'selected_stage': {
        'required_complete': true, 'deliverables_configured': true,
        'pre': [
          {'uploaded': true, 'submission': {'status': 'pending'}},
          {'uploaded': true, 'submission': {'status': 'accepted'}},
          {'uploaded': true, 'submission': {'status': 'rejected'}},
          {'uploaded': true, 'is_waived': true},
          {'uploaded': true, 'locked': true},
        ],
      }};
      expect(DeliverablesTriageHelper.pendingReviewCount(team), 2);
      expect(DeliverablesTriageHelper.isReadyForDefense(team), isFalse);
      (team['selected_stage'] as Map)['pre'] = [];
      expect(DeliverablesTriageHelper.hasPendingReview(team), isFalse);
    });

    test('matchesFilter accurately classifies teams into triage categories', () {
      // Team Alpha is endorsed and ready
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[0], TeamTriageFilter.all), isTrue);
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[0], TeamTriageFilter.readyForDefense), isTrue);
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[0], TeamTriageFilter.needsReview), isFalse);

      // Team Beta has pending submissions needing review
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[1], TeamTriageFilter.all), isTrue);
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[1], TeamTriageFilter.needsReview), isTrue);
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[1], TeamTriageFilter.readyForDefense), isFalse);

      // Team Gamma has missing deliverables
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[2], TeamTriageFilter.all), isTrue);
      expect(DeliverablesTriageHelper.matchesFilter(mockTeams[2], TeamTriageFilter.overdue), isTrue);
    });

    test('computeCounts generates correct bucket distribution', () {
      final counts = DeliverablesTriageHelper.computeCounts(mockTeams);
      expect(counts[TeamTriageFilter.all], equals(3));
      expect(counts[TeamTriageFilter.readyForDefense], equals(1));
      expect(counts[TeamTriageFilter.needsReview], equals(1));
      expect(counts[TeamTriageFilter.overdue], equals(1));
    });
  });

  group('DeliverablesFilterBar Widget Tests', () {
    testWidgets('filters through the status picker and retains the optional view toggle', (tester) async {
      TeamTriageFilter selectedFilter = TeamTriageFilter.all;
      DeliverablesViewMode selectedMode = DeliverablesViewMode.dossier;

      final dummyState = CapstoneDeliverablesState(
        teams: mockTeams,
        stageOptions: ['Concept Proposal'],
        selectedStage: 'Concept Proposal',
      );

      final searchCtrl = TextEditingController();

      await pumpDefensysWidget(
        tester,
        DeliverablesFilterBar(
          state: dummyState,
          searchController: searchCtrl,
          isAdviser: false,
          showViewToggle: true,
          viewMode: selectedMode,
          activeTriageFilter: selectedFilter,
          onTriageFilterChanged: (filter) => selectedFilter = filter,
          onViewModeChanged: (mode) => selectedMode = mode,
        ),
      );

      expect(find.text('All teams (3)'), findsOneWidget);
      expect(find.text('Needs review (1)'), findsNothing);

      // Verify segmented view toggle exists
      expect(find.text('Cohort Matrix'), findsOneWidget);
      expect(find.text('Team Dossier'), findsOneWidget);

      await tester.tap(find.byType(ShadSelect<TeamTriageFilter>));
      await tester.pumpAndSettle();
      expect(find.text('Requirements'), findsNothing);
      await tester.tap(find.text('For review (1)'));
      await tester.pumpAndSettle();
      expect(selectedFilter, equals(TeamTriageFilter.forReview));

      // Tap Cohort Matrix toggle
      await tester.tap(find.text('Cohort Matrix'));
      await tester.pumpAndSettle();
      expect(selectedMode, equals(DeliverablesViewMode.matrix));
    });
  });

  group('CohortSubmissionsMatrix Widget Tests', () {
    testWidgets('renders teams in table and triggers onSelectTeam on Review tap', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int? selectedTeamId;

      final dummyState = CapstoneDeliverablesState(
        teams: mockTeams,
        stageOptions: ['Concept Proposal'],
        selectedStage: 'Concept Proposal',
      );

      await pumpDefensysWidget(
        tester,
        CohortSubmissionsMatrix(
          teams: mockTeams,
          state: dummyState,
          isAdviser: false,
          onSelectTeam: (id) => selectedTeamId = id,
        ),
      );

      expect(find.text('Team Alpha'), findsOneWidget);
      expect(find.text('Campus Navigation & Indoor Mapping'), findsOneWidget);
      expect(find.text('Team Beta'), findsOneWidget);
      expect(find.text('Automated Grading Assistance'), findsOneWidget);
      expect(find.text('Dr. Alan Turing'), findsOneWidget);

      // Find Review button for Team Alpha and tap it
      final reviewButtons = find.text('Review');
      expect(reviewButtons, findsWidgets);

      await tester.tap(reviewButtons.first);
      await tester.pumpAndSettle();

      expect(selectedTeamId, equals(101));
    });

    testWidgets('expands accordion inline on tap, showing deliverables and collapsing on Hide tap', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummyState = CapstoneDeliverablesState(
        teams: mockTeams,
        stageOptions: ['Concept Proposal'],
        selectedStage: 'Concept Proposal',
      );

      await pumpDefensysWidget(
        tester,
        CohortSubmissionsMatrix(
          teams: mockTeams,
          state: dummyState,
          isAdviser: false,
        ),
      );

      // Initially, deliverables checklist is not visible
      expect(find.text('Project Charter'), findsNothing);
      expect(find.text('Literature Review'), findsNothing);

      // Tap Team Alpha's Review button to expand inline accordion
      await tester.tap(find.text('Review').first);
      await tester.pumpAndSettle();

      // Team Alpha's accordion is now expanded
      expect(find.text('Team Alpha · Concept Proposal Deliverables'), findsOneWidget);
      expect(find.text('Project Charter'), findsOneWidget);
      expect(find.text('Literature Review'), findsOneWidget);
      expect(find.text('Hide'), findsWidgets);

      // Tap Hide button to collapse accordion
      await tester.tap(find.text('Hide').first);
      await tester.pumpAndSettle();

      // Checklist is hidden again
      expect(find.text('Project Charter'), findsNothing);
    });

    testWidgets('supports initialExpandedTeamId to render accordion pre-expanded', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummyState = CapstoneDeliverablesState(
        teams: mockTeams,
        stageOptions: ['Concept Proposal'],
        selectedStage: 'Concept Proposal',
      );

      await pumpDefensysWidget(
        tester,
        CohortSubmissionsMatrix(
          teams: mockTeams,
          state: dummyState,
          isAdviser: false,
          initialExpandedTeamId: 102, // Team Beta
        ),
      );

      // Team Beta's deliverables start pre-expanded
      expect(find.text('Team Beta · Concept Proposal Deliverables'), findsOneWidget);
      expect(find.text('Proposal Deck'), findsOneWidget);
      expect(find.text('Problem Statement'), findsOneWidget);
    });
  });

  group('DeliverablesTablePane Consolidated Header & Filter Tests', () {
    testWidgets('renders consolidated header and filters team list', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummyState = CapstoneDeliverablesState(
        teams: mockTeams,
        stageOptions: ['Concept Proposal'],
        selectedStage: 'Concept Proposal',
      );

      await pumpDefensysWidget(
        tester,
        DeliverablesTablePane(
          state: dummyState,
          isAdviser: false,
          activeTriageFilter: TeamTriageFilter.needsReview,
        ),
      );

      // Since activeTriageFilter is needsReview, only Team Beta matches
      expect(find.text('Teams (1) - Review first'), findsOneWidget);
      expect(find.text('Team Beta'), findsWidgets);
      expect(find.text('Team Alpha'), findsNothing);

      // Project details belong in the dossier; the compact list shows team names.
      expect(find.text('Automated Grading Assistance'), findsOneWidget);
      expect(find.textContaining('Adv: Dr. Ada Lovelace'), findsOneWidget);
      expect(find.text('1 Member'), findsOneWidget);
    });
  });
}
