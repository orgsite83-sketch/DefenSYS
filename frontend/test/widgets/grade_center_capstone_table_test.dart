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
    expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(2));
    expect(find.text('Mark Complete'), findsNWidgets(2));

    // Tap more options on first card
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('View Details'), findsOneWidget);

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
}
