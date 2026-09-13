import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/grade_center_capstone_table.dart';
import 'package:defensys/screens/web/admin/grade_center_shared.dart';
import 'package:defensys/services/grade_center_provider.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('CapstoneStagesUnifiedCard renders stage milestone cards with actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team Alpha',
        },
      ],
      activeSemester: {
        'display_name': '2026-2027 · 2nd Semester',
        'capstone_peer_evaluation_enabled': true,
        'capstone_adviser_grading_enabled': true,
      },
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': false,
          'peer_grading_enabled': false,
        },
      },
    );

    final stages = [
      {
        'label': 'Concept Proposal',
        'display_order': 1,
        'description': 'Concept stage',
        'is_active': true,
      },
      {
        'label': 'Final Defense',
        'display_order': 3,
        'description': 'Final stage',
        'is_active': true,
      },
    ];

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            state: state,
            stages: stages,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, __) {},
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Concept Proposal'), findsOneWidget);
    expect(find.text('Final Defense'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    expect(find.text('Mark Complete'), findsNWidgets(2));

    searchController.dispose();
  });

  testWidgets('CapstoneStagesUnifiedCard renders Officially Complete badge when complete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team Alpha',
        },
      ],
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': true,
          'peer_grading_enabled': false,
        },
      },
    );

    final stages = [
      {
        'label': 'Concept Proposal',
        'display_order': 1,
        'description': 'Concept stage',
        'is_active': true,
      },
    ];

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            state: state,
            stages: stages,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, __) {},
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('OFFICIALLY COMPLETE'), findsOneWidget);
    expect(find.text('Reopen Stage'), findsOneWidget);
    searchController.dispose();
  });

  testWidgets('Tapping Reopen opens confirm dialog and invokes callback with false', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool? updatedValue;
    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team Alpha',
        },
      ],
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': true,
          'peer_grading_enabled': false,
        },
      },
    );

    final stages = [
      {
        'label': 'Concept Proposal',
        'display_order': 1,
        'description': 'Concept stage',
        'is_active': true,
      },
    ];

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            state: state,
            stages: stages,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, val) {
              updatedValue = val;
            },
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Reopen Stage'), findsOneWidget);

    // Tap Reopen Stage
    await tester.tap(find.text('Reopen Stage'));
    await tester.pumpAndSettle();

    // Confirm dialog should be visible
    expect(find.text('Reopen Concept Proposal?'), findsOneWidget);

    // Tap Confirm button in dialog
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen Stage'));
    await tester.pumpAndSettle();

    expect(updatedValue, isFalse);

    searchController.dispose();
  });

  testWidgets('Tapping Mark Complete opens confirm dialog and invokes callback on confirm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool? updatedValue;
    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team Alpha',
        },
      ],
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': false,
        },
      },
    );

    final stages = [
      {
        'label': 'Concept Proposal',
        'display_order': 1,
        'description': 'Concept stage',
        'is_active': true,
      },
    ];

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            state: state,
            stages: stages,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, val) {
              updatedValue = val;
            },
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Mark Complete'), findsOneWidget);

    // Tap Mark Complete
    await tester.tap(find.text('Mark Complete'));
    await tester.pumpAndSettle();

    // Confirm dialog should be visible
    expect(find.text('Mark Concept Proposal Complete?'), findsOneWidget);

    // Tap Confirm button in dialog
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete'));
    await tester.pumpAndSettle();

    expect(updatedValue, isTrue);

    searchController.dispose();
  });

  testWidgets('CapstoneStagesUnifiedCard renders PIT stage milestone cards with peer toggle and snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const state = GradeCenterState(
      grades: [
        {
          'id': 101,
          'scope': 'pit',
          'stage_label': '1st Year Concept Pitch',
          'team_name': 'PIT Team Alpha',
          'grading_ready': true,
        },
      ],
      activeSemester: {
        'display_name': '2026-2027 · 1st Semester',
      },
      pitEvents: [
        {
          'event_name': '1st Year Concept Pitch',
          'display_order': 1,
          'panel_weight': 80,
          'peer_weight': 20,
          'is_officially_complete': false,
          'peer_grading_enabled': true,
        },
      ],
      groupSettings: {
        'pit|1st Year Concept Pitch': {
          'scope': 'pit',
          'stage_label': '1st Year Concept Pitch',
          'is_officially_complete': false,
          'peer_grading_enabled': true,
        },
      },
    );

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            scope: 'pit',
            state: state,
            stages: state.pitEvents,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, __) {},
            onPeerGradingChanged: (_, __) {},
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('PIT Expos & Event Stages'), findsOneWidget);
    expect(find.text('1st Year Concept Pitch'), findsOneWidget);
    expect(find.text('Peer grading open'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('Mark Complete'), findsOneWidget);
    expect(find.text('ENROLLED TEAMS'), findsOneWidget);
    expect(find.text('EVALUATION READINESS'), findsOneWidget);
    expect(find.text('EVALUATION COMPONENTS'), findsOneWidget);

    searchController.dispose();
  });

  testWidgets('CapstoneStagesUnifiedCard renders All Scopes with Capstone and PIT milestone cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team Alpha',
          'grading_ready': true,
        },
        {
          'id': 101,
          'scope': 'pit',
          'stage_label': '1st Year Concept Pitch',
          'team_name': 'PIT Team Alpha',
          'grading_ready': true,
        },
      ],
      activeSemester: {
        'display_name': '2026-2027 · 1st Semester',
        'capstone_peer_evaluation_enabled': true,
        'capstone_adviser_grading_enabled': true,
      },
      pitEvents: [
        {
          'event_name': '1st Year Concept Pitch',
          'display_order': 1,
          'panel_weight': 80,
          'peer_weight': 20,
          'is_officially_complete': false,
          'peer_grading_enabled': true,
        },
      ],
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': false,
          'peer_grading_enabled': false,
        },
        'pit|1st Year Concept Pitch': {
          'scope': 'pit',
          'stage_label': '1st Year Concept Pitch',
          'is_officially_complete': false,
          'peer_grading_enabled': true,
        },
      },
    );

    final stages = [
      {
        'label': 'Concept Proposal',
        'display_order': 1,
        'description': 'Concept stage',
        'is_active': true,
      },
    ];

    final searchController = TextEditingController();

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1400,
        child: SingleChildScrollView(
          child: CapstoneStagesUnifiedCard(
            scope: 'all',
            state: state,
            stages: stages,
            stagesLoading: false,
            isAdmin: true,
            searchController: searchController,
            scopeFilter: const SizedBox(height: 40),
            yearLevelFilter: const SizedBox(height: 40),
            statusFilter: const SizedBox(height: 40),
            onOpenStage: (_) {},
            onOfficiallyCompleteChanged: (_, __) {},
            onPeerGradingChanged: (_, __) {},
            onSearchChanged: (_) {},
            onSearchSubmitted: (_) {},
            onSearchFocusChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('All Grade Groups'), findsOneWidget);
    expect(find.text('Capstone · Concept Proposal'), findsOneWidget);
    expect(find.text('PIT · 1st Year Concept Pitch'), findsOneWidget);
    expect(find.text('Peer grading open'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    expect(find.text('Mark Complete'), findsNWidgets(2));

    searchController.dispose();
  });

  testWidgets('gradeCenterKpiStatCard renders scoped title and metrics properly', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      gradeCenterKpiStatCard(
        title: 'Total Capstone teams',
        value: '0',
        icon: Icons.groups_rounded,
        accent: const Color(0xFF2563EB),
        iconBg: const Color(0xFFEFF6FF),
        progress: 0,
      ),
    );

    expect(find.text('Total Capstone teams'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
  });
}
