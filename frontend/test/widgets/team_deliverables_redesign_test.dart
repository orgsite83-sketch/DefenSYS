import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_filter_bar.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';

import '../helpers/pump_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    testWidgets('renders triage chips and view toggle when showViewToggle is true', (tester) async {
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

      // Verify triage chips exist
      expect(find.textContaining('All (3)'), findsOneWidget);
      expect(find.textContaining('Needs Review (1)'), findsOneWidget);
      expect(find.textContaining('Ready for Defense (1)'), findsOneWidget);
      expect(find.textContaining('Missing / Overdue (1)'), findsOneWidget);

      // Verify segmented view toggle exists
      expect(find.text('Cohort Matrix'), findsOneWidget);
      expect(find.text('Team Dossier'), findsOneWidget);

      // Tap Needs Review triage chip
      await tester.tap(find.textContaining('Needs Review (1)'));
      await tester.pumpAndSettle();
      expect(selectedFilter, equals(TeamTriageFilter.needsReview));

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
      expect(find.text('Teams (1)'), findsOneWidget);
      expect(find.text('Team Beta'), findsWidgets);
      expect(find.text('Team Alpha'), findsNothing);

      // Verify consolidated header details for Team Beta (found in left card and detail header)
      expect(find.text('Automated Grading Assistance'), findsNWidgets(2));
      expect(find.textContaining('Adv: Dr. Ada Lovelace'), findsOneWidget);
      expect(find.text('1 Member'), findsOneWidget);
    });
  });
}
