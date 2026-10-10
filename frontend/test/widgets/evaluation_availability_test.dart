import 'package:defensys/screens/app/student/peer_eval_tab.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_grading_screen.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/widgets/buttons/save_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _LockedAdviserGrades extends AdviserGradingNotifier {
  @override
  AdviserGradingState build() => const AdviserGradingState(grades: [
    {
      'id': 7,
      'team_name': 'Unscheduled Team',
      'stage_label': 'Project Proposal',
      'adviser_grading_available': false,
      'adviser_grading_unavailable_reason': 'This team must be endorsed and scheduled before grading opens.',
      'assigned_adviser_rubric_id': 1,
      'assigned_adviser_rubric_target_type': 'team',
      'assigned_adviser_criteria': [
        {'id': 1, 'name': 'Contribution', 'max_score': 10},
      ],
    },
  ]);

  @override
  Future<void> fetchAll() async {}
}

void main() {
  testWidgets('locked peer form explains the panel completion requirement', (tester) async {
    await pumpDefensysWidget(tester, const PeerEvalTab(
      isCapstone: true, peerEvalAllowed: false,
      peerEvalUnavailableReason: 'Waiting for all assigned panelists to finish grading.',
      teammates: [{'id': 2, 'name': 'Member Two'}],
      peerCriteria: [{'name': 'Contribution', 'maxScore': 5}], studentId: '1', teamId: '7',
    ));
    expect(find.text('Waiting for all assigned panelists to finish grading.'), findsOneWidget);
    expect(find.text('Submit Evaluation'), findsNothing);
  });

  testWidgets('closed peer form keeps pending submissions disabled alongside history', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, const PeerEvalTab(
      isCapstone: true, peerEvalAllowed: false,
      teammates: [{'id': 2, 'name': 'Member Two'}, {'id': 3, 'name': 'Member Three'}],
      peerCriteria: [{'name': 'Contribution', 'maxScore': 5}], studentId: '1', teamId: '7',
      myPeerSubmissions: [{'evaluateeId': 2, 'breakdown': [{'criteriaName': 'Contribution', 'score': 4, 'max': 5}]}],
    ));
    final buttons = tester.widgetList<DefensysSaveButton>(find.byType(DefensysSaveButton));
    expect(buttons, isNotEmpty);
    expect(buttons.every((button) => button.onPressed == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unscheduled adviser grade displays its reason and locks scoring', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, const AdviserGradingScreen(), overrides: [
      adviserGradingProvider.overrideWith(_LockedAdviserGrades.new),
    ]);
    await tester.tap(find.text('Unscheduled Team'));
    await tester.pumpAndSettle();
    expect(find.text('This team must be endorsed and scheduled before grading opens.'), findsOneWidget);
    expect(find.text('Grading Locked'), findsOneWidget);
    expect(find.text('Submit Grade'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
