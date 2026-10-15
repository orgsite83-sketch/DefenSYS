import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _stage({bool ready = true}) => {
  'stage_label': 'Concept Proposal',
  'deliverables_configured': true,
  'required_complete': false,
  'required_total': 1,
  'required_uploaded': ready ? 1 : 0,
  'endorsement_required': true,
  'endorsed': false,
  'endorsement_review': {
    'can_review_and_endorse': ready,
    'review_token': ready ? 'snapshot-123' : '',
    'reason': ready
        ? ''
        : 'Upload all required before-endorsement files first.',
    'files': [
      {
        'id': 'PAPER',
        'label': 'Concept paper',
        'file_name': 'reviewed-paper.pdf',
      },
    ],
  },
  'pre': [
    {
      'id': 'PAPER',
      'label': 'Concept paper',
      'type': 'pre',
      'required': true,
      'uploaded': ready,
      'can_faculty_review': true,
      if (ready)
        'submission': {
          'status': 'pending',
          'file_name': 'reviewed-paper.pdf',
          'files': [],
        },
    },
    {
      'id': 'DECK',
      'label': 'Pitch deck',
      'type': 'pre',
      'required': true,
      'requirement_timing': 'defense',
      'uploaded': true,
      'can_upload': true,
      'can_faculty_review': true,
      'materials_submitted': true,
      'submission': {
        'status': 'pending',
        'file_name': 'pitch.pptx',
        'files': [],
      },
    },
  ],
  'post': [],
};

class _Grades extends AdviserGradingNotifier {
  @override
  AdviserGradingState build() => const AdviserGradingState();
  @override
  Future<void> fetchAll() async {}
}

class _ReviewNotifier extends CapstoneDeliverablesNotifier {
  List<Object>? reviewed;
  Map<String, String>? correction;
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();
  @override
  Future<bool> reviewAndEndorseTeam(
    int teamId,
    String stageLabel,
    String reviewToken,
  ) async {
    reviewed = [teamId, stageLabel, reviewToken];
    return true;
  }

  @override
  Future<bool> reviewDeliverable({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String status,
    String? feedback,
    bool clearDefenseRevisions = false,
  }) async {
    correction = {
      'id': deliverableId,
      'status': status,
      'feedback': feedback ?? '',
    };
    return true;
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final pit in [false, true]) {
    testWidgets(
      '${pit ? 'PIT' : 'Capstone'} reviews the displayed files in one action; deck needs no approval',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final notifier = _ReviewNotifier();
        final stage = _stage();
        final team = <String, dynamic>{
          'id': 7,
          'name': 'Team FreshStartAdvising',
          'current_stage': 'Concept Proposal',
          'stages': [stage],
        };
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const Key('review-preview'),
            child: SingleChildScrollView(
              child: DeliverablesTablePane(
                state: CapstoneDeliverablesState(
                  scope: pit ? 'pit' : 'capstone',
                  selectedStage: 'Concept Proposal',
                  stageOptions: const ['Concept Proposal'],
                  teams: [team],
                ),
                isAdviser: !pit,
                isPitInstructor: pit,
                initialTeamId: 7,
              ),
            ),
          ),
          overrides: [
            ...authTestOverrides(),
            adviserGradingProvider.overrideWith(_Grades.new),
            capstoneDeliverablesProvider.overrideWith(() => notifier),
          ],
        );
        expect(find.text('Accept'), findsNothing);
        expect(find.text('Reject'), findsNothing);
        expect(find.text('Uploaded'), findsOneWidget);
        expect(find.text('Awaiting review'), findsOneWidget);
        expect(find.text('Request corrections'), findsNWidgets(2));
        expect(DeliverablesTriageHelper.pendingReviewCount(team), 1);
        await capturePreview(
          tester,
          find.byKey(const Key('review-preview')),
          'review-endorsement-${pit ? 'pit' : 'capstone'}',
        );
        await tester.tap(find.text('Review & endorse'));
        await tester.pumpAndSettle();
        expect(find.text('reviewed-paper.pdf'), findsWidgets);
        expect(
          find.textContaining('approves these files and endorses'),
          findsOneWidget,
        );
        await tester.tap(find.text('Approve & endorse'));
        await tester.pumpAndSettle();
        expect(notifier.reviewed, [7, 'Concept Proposal', 'snapshot-123']);
        await tester.tap(find.text('Request corrections').last);
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final send = find.descendant(
          of: dialog,
          matching: find.byWidgetPredicate(
            (widget) => widget is ElevatedButton,
          ),
        );
        expect(tester.widget<ElevatedButton>(send).onPressed, isNull);
        await tester.enterText(
          find.descendant(of: dialog, matching: find.byType(TextField)),
          'Add the demo flow',
        );
        await tester.pump();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(notifier.correction, {
          'id': 'DECK',
          'status': 'rejected',
          'feedback': 'Add the demo flow',
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'missing scheduling files disable combined review even when the deck is uploaded',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DeliverablesTablePane(
            state: CapstoneDeliverablesState(
              selectedStage: 'Concept Proposal',
              stageOptions: const ['Concept Proposal'],
              teams: [
                {
                  'id': 7,
                  'name': 'Team Review',
                  'current_stage': 'Concept Proposal',
                  'stages': [_stage(ready: false)],
                },
              ],
            ),
            isAdviser: true,
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          adviserGradingProvider.overrideWith(_Grades.new),
        ],
      );
      final button = find.ancestor(
        of: find.text('Review & endorse'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(
        find.text('Upload all required before-endorsement files first.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'pending decks do not count as faculty reviews or block endorsed scheduling readiness',
    () {
      final stage = _stage();
      stage['endorsed'] = true;
      (stage['pre'] as List).removeAt(0);
      final team = <String, dynamic>{'selected_stage': stage};
      expect(DeliverablesTriageHelper.pendingReviewCount(team), 0);
      expect(DeliverablesTriageHelper.isReadyForDefense(team), true);
    },
  );

  testWidgets(
    'matrix treats an uploaded deck as uploaded and keeps scheduling clearance separate',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final stage = _stage();
      stage['endorsed'] = true;
      stage['required_complete'] = true;
      final pre = stage['pre'] as List;
      pre.first['submission']['status'] = 'accepted';
      final team = <String, dynamic>{
        'id': 7,
        'name': 'Team Review',
        'current_stage': 'Concept Proposal',
        'stages': [stage],
      };
      final state = CapstoneDeliverablesState(
        teams: [team],
        selectedStage: 'Concept Proposal',
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: CohortSubmissionsMatrix(
            teams: [team],
            state: state,
            isAdviser: true,
            initialExpandedTeamId: 7,
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.textContaining('Pending Review'), findsNothing);
      expect(find.text('1 / 1 Cleared'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
