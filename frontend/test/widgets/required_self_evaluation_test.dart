import 'package:defensys/screens/app/student/peer_eval_tab.dart';
import 'package:defensys/services/defense/capstone_deliverables_provider.dart';
import 'package:defensys/widgets/buttons/save_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

const _members = [
  {'id': 1, 'name': 'Alex'},
  {'id': 2, 'name': 'Sam'},
];
const _teammateSubmission = {
  'evaluateeId': 2,
  'breakdown': [
    {'criteriaName': 'Contribution', 'score': 4, 'max': 5},
  ],
};
const _selfSubmission = {
  'evaluateeId': 1,
  'breakdown': [
    {'criteriaName': 'Contribution', 'score': 3, 'max': 5},
  ],
};

PeerEvalTab _form({
  List<Map<String, dynamic>> submissions = const [],
  String stage = 'Proposal',
}) => PeerEvalTab(
  isCapstone: true,
  peerEvalAllowed: true,
  members: _members,
  peerCriteria: const [
    {'name': 'Contribution', 'maxScore': 5},
  ],
  studentId: '1',
  teamId: '7',
  stage: stage,
  myPeerSubmissions: submissions,
);

void main() {
  setUpAll(() => loadPreviewFonts());
  for (final width in [390, 1200]) {
    testWidgets(
      'self-evaluation remains required after teammate submission at $width px',
      (tester) async {
        tester.view.physicalSize = Size(width.toDouble(), 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          _form(submissions: [_teammateSubmission]),
        );
        expect(find.text('Alex (You)'), findsOneWidget);
        expect(find.text('1 / 2 Complete'), findsOneWidget);
        expect(
          find.text(
            'All peer and self-evaluations submitted and locked for this event.',
          ),
          findsNothing,
        );
        expect(find.byType(DefensysSaveButton), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(tester, find.byType(PeerEvalTab), 'peer-self-evaluation-$width', viewport: true);
      },
    );
  }

  testWidgets(
    'self submission is restored and locked with all other evaluations',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        _form(submissions: [_selfSubmission, _teammateSubmission]),
      );
      expect(find.text('2 / 2 Complete'), findsOneWidget);
      expect(
        find.text('Self-evaluation submitted and locked.'),
        findsOneWidget,
      );
      expect(find.byType(DefensysSaveButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing stage resets self and teammate submission state', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      _form(submissions: [_selfSubmission, _teammateSubmission]),
    );
    expect(find.text('2 / 2 Complete'), findsOneWidget);
    await pumpDefensysWidget(tester, _form(stage: 'Final'));
    expect(find.text('0 / 2 Complete'), findsOneWidget);
    expect(find.byType(DefensysSaveButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('task badge stays pending until self-evaluation is submitted', () {
    final data = <String, dynamic>{
      'peerEvalEnabled': true,
      'student': {'id': 1},
      'members': _members,
      'myPeerSubmissions': [_teammateSubmission],
    };
    expect(StudentTaskBadgeHelper.hasPendingPeerEval(data), isTrue);
    data['myPeerSubmissions'] = [_selfSubmission, _teammateSubmission];
    expect(StudentTaskBadgeHelper.hasPendingPeerEval(data), isFalse);
  });

  test(
    'a teammate with the same name cannot satisfy the self-evaluation task',
    () {
      expect(
        StudentTaskBadgeHelper.hasPendingPeerEval({
          'peerEvalEnabled': true,
          'student': {'id': 1},
          'members': [
            {'id': 1, 'name': 'Alex'},
            {'id': 2, 'name': 'Alex'},
          ],
          'myPeerSubmissions': [
            {'evaluateeId': 2, 'evaluateeName': 'Alex'},
          ],
        }),
        isTrue,
      );
    },
  );
}
