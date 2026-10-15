import 'package:defensys/screens/web/admin/grade_center/grade_center_shared.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_group_completion_summary.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  for (final status in ['pending', 'published']) {
    testWidgets('PIT $status keeps the Failed score indicator', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        gradeCenterHeroSummaryCard(
          grade: {
            'scope': 'pit',
            'team_name': 'Team ApexCode',
            'stage_label': 'System Concept Pitching',
            'final_grade': '73.23',
            'panel_score': '73.00',
            'peer_score': '74.16',
            'weights': {'panel': 80, 'peer': 20},
            'result': 'failed',
            'status': status,
          },
        ),
      );
      expect(find.text('73.23'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('Passing Mark: 75.00%'), findsOneWidget);
      expect(find.text('Event score indicator only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final isPit in [true, false]) {
    testWidgets(
      'completion explains ${isPit ? 'PIT indicators' : 'Capstone restrictions'}',
      (tester) async {
        await pumpDefensysWidget(
          tester,
          GradeGroupCompletionSummary(
            isPit: isPit,
            readiness: const GradeGroupCompletionReadiness(
              totalTeams: 1,
              readyTeams: 1,
              canComplete: true,
              failingTeams: [
                {'team_id': 1, 'team_name': 'Team ApexCode'},
              ],
            ),
          ),
        );
        expect(find.text('1 team has failing grades.'), findsOneWidget);
        expect(
          find.text('These teams will not qualify for project archiving.'),
          isPit ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('can still finalize this event'),
          isPit ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
