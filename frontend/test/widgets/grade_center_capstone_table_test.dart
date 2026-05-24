import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/screens/web/admin/grade_center_capstone_table.dart';
import 'package:user/screens/web/admin/grade_center_shared.dart';
import 'package:user/services/grade_center_provider.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('CapstoneStagesUnifiedCard shows stage rows with bounded table height', (
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
    expect(find.text('View Details'), findsNWidgets(2));

    final horizontalScroll = find.descendant(
      of: find.byType(CapstoneStagesUnifiedCard),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(horizontalScroll, findsOneWidget);
    final tableBox = tester.renderObject<RenderBox>(horizontalScroll);
    expect(tableBox.size.height, greaterThan(0));
    expect(capstoneStagesTableBodyHeight(2), greaterThan(0));

    searchController.dispose();
  });
}
