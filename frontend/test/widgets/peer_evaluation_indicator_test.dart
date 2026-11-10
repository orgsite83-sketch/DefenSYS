import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _Deliverables extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();

  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

void main() {
  const indicatorKey = ValueKey('peer-evaluation-pending-indicator');
  const members = [
    {'id': 1, 'name': 'Alex'},
    {'id': 2, 'name': 'Sam'},
  ];

  Map<String, dynamic> dashboard(List<Map<String, dynamic>> submissions) => {
    'student': {'id': 1},
    'team': {'id': 7, 'name': 'Team Seven', 'currentStage': 'Current event'},
    'current_stage': 'Current event',
    'stage_options': ['Earlier event', 'Current event'],
    'members': members,
    'peerEvalEnabled': false,
    'myPeerSubmissions': [
      {'evaluateeId': 1},
      {'evaluateeId': 2},
    ],
    'stages': [
      {
        'stage_label': 'Earlier event',
        'team_id': 8,
        'team': {'id': 8, 'name': 'Team Eight', 'members': members},
        'peer_eval_allowed': true,
        'my_peer_submissions': submissions,
      },
      {
        'stage_label': 'Current event',
        'team_id': 7,
        'peer_eval_allowed': false,
      },
    ],
  };

  testWidgets(
    'peer tab is red before any submission and until all ratings are done',
    (tester) async {
      for (final submissions in [
        <Map<String, dynamic>>[],
        <Map<String, dynamic>>[
          {'evaluateeId': 2, 'stage': 'Earlier event'},
        ],
        <Map<String, dynamic>>[
          {'evaluateeId': 1, 'stage': 'Earlier event'},
          {'evaluateeId': 2, 'stage': 'Earlier event'},
        ],
      ]) {
        await pumpDefensysWidget(
          tester,
          StudentEventsTab(
            isCapstone: false,
            studentData: dashboard(submissions),
            initialStage: 'Earlier event',
            isActive: false,
          ),
          overrides: [
            capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
          ],
        );
        final indicator = find.byKey(indicatorKey);
        expect(
          indicator,
          submissions.length < 2 ? findsOneWidget : findsNothing,
        );
        if (submissions.length < 2) {
          final dot = tester.widget<Container>(indicator);
          expect((dot.decoration as BoxDecoration).color, Colors.redAccent);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'closed selected event has no dot when another event needs ratings',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        StudentEventsTab(
          isCapstone: false,
          studentData: dashboard([]),
          isActive: false,
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
        ],
      );
      expect(find.text('Peer Eval'), findsOneWidget);
      expect(find.byKey(indicatorKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
