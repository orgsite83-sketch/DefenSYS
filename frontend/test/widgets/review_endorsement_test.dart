import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _stage({bool ready = true, bool accepted = false}) => {
  'stage_label': 'Concept Proposal',
  'deliverables_configured': true,
  'required_complete': accepted,
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
      'is_defense_material': true,
      'uploaded': ready,
      'can_faculty_review': true,
      if (ready)
        'submission': {
          'status': accepted ? 'accepted' : 'pending',
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
  List<Object>? endorsed;
  List<Object>? combinedReview;
  Map<String, String>? correction;
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();
  @override
  Future<bool> reviewAndEndorseTeam(
    int teamId,
    String stageLabel,
    String reviewToken,
  ) async {
    combinedReview = [teamId, stageLabel, reviewToken];
    return true;
  }

  @override
  Future<bool> endorseTeam(int teamId, String stageLabel) async {
    endorsed = [teamId, stageLabel];
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
    int? fileId,
  }) async {
    correction = {
      'id': deliverableId,
      'status': status,
      'feedback': feedback ?? '',
    };
    return true;
  }
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required Map<String, dynamic> stage,
  required _ReviewNotifier notifier,
  bool pit = false,
  ThemeData? theme,
}) async {
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
            teams: [
              {
                'id': 7,
                'name': 'Team FreshStartAdvising',
                'current_stage': 'Concept Proposal',
                'stages': [stage],
              },
            ],
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
    theme: theme,
  );
}

Finder _endorseButton() => find.ancestor(
  of: find.text('Endorse team'),
  matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
);

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final pit in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${pit ? 'PIT' : 'Capstone'} shares badge labels and colors in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          tester.view.physicalSize = const Size(1500, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          final notifier = _ReviewNotifier();
          final scenarios =
              <(Map<String, dynamic>, String, WorkflowStatusTone)>[
                (
                  _stage(ready: false),
                  'Awaiting files',
                  WorkflowStatusTone.neutral,
                ),
                (_stage(), 'Needs review', WorkflowStatusTone.attention),
                (
                  _stage(accepted: true),
                  'Awaiting endorsement',
                  WorkflowStatusTone.attention,
                ),
                (
                  {
                    ..._stage(),
                    'assessment_progress': {
                      'display_status': 'scheduled',
                      'is_completed': false,
                    },
                  },
                  'Scheduled',
                  WorkflowStatusTone.active,
                ),
                (
                  {
                    ..._stage(),
                    'assessment_progress': {
                      'display_status': 'failed',
                      'is_completed': false,
                    },
                  },
                  'Failed',
                  WorkflowStatusTone.destructive,
                ),
                (
                  {
                    ..._stage(),
                    'assessment_progress': {
                      'display_status': 'completed',
                      'is_completed': true,
                    },
                    'archive_complete': true,
                    'documentation_complete': true,
                  },
                  'Completed',
                  WorkflowStatusTone.success,
                ),
              ];
          Size? cardSize;
          for (final (stage, label, tone) in scenarios) {
            await _pumpWorkspace(
              tester,
              stage: stage,
              notifier: notifier,
              pit: pit,
              theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            );
            final labels = find.text(label);
            expect(
              labels,
              findsNWidgets(2),
              reason: 'Team card and dossier must agree',
            );
            final style = WorkflowStatusStyle.of(
              tester.element(labels.first),
              tone,
            );
            for (final text in tester.widgetList<Text>(labels)) {
              expect(text.style?.color, style.foreground);
            }
            final card = find
                .ancestor(
                  of: find.text('Team FreshStartAdvising').first,
                  matching: find.byType(InkWell),
                )
                .first;
            cardSize ??= tester.getSize(card);
            expect(
              tester.getSize(card),
              cardSize,
              reason: 'Status changes preserve the team card layout',
            );
            expect(tester.takeException(), isNull);
            if (label == 'Scheduled') {
              await capturePreview(
                tester,
                find.byKey(const Key('review-preview')),
                'workflow-${pit ? 'pit' : 'capstone'}-${dark ? 'dark' : 'light'}',
              );
            }
          }
        },
      );
    }
  }

  for (final pit in [false, true]) {
    testWidgets(
      '${pit ? 'PIT' : 'Capstone'} accepts scheduling files before separate endorsement; deck needs no approval',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final notifier = _ReviewNotifier();
        final stage = _stage();
        await _pumpWorkspace(
          tester,
          stage: stage,
          notifier: notifier,
          pit: pit,
        );
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        expect(find.text('Uploaded'), findsOneWidget);
        expect(find.text('Request corrections'), findsOneWidget);
        expect(find.text('Review & endorse'), findsNothing);
        expect(
          tester.widget<ElevatedButton>(_endorseButton()).onPressed,
          isNull,
        );
        await capturePreview(
          tester,
          find.byKey(const Key('review-preview')),
          'review-endorsement-${pit ? 'pit' : 'capstone'}',
        );
        await tester.tap(find.text('Accept'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accept Requirement'));
        await tester.pumpAndSettle();
        expect(notifier.correction, {
          'id': 'PAPER',
          'status': 'accepted',
          'feedback': '',
        });
        expect(notifier.endorsed, isNull);
        expect(notifier.combinedReview, isNull);

        await _pumpWorkspace(
          tester,
          stage: _stage(accepted: true),
          notifier: notifier,
          pit: pit,
        );
        expect(find.text('Accepted'), findsOneWidget);
        expect(find.text('Awaiting endorsement'), findsWidgets);
        expect(
          tester.widget<ElevatedButton>(_endorseButton()).onPressed,
          isNotNull,
        );
        await tester.tap(_endorseButton());
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'All required before-endorsement files have been accepted.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Endorse'));
        await tester.pumpAndSettle();
        expect(notifier.endorsed, [7, 'Concept Proposal']);
        expect(notifier.combinedReview, isNull);

        await tester.tap(find.text('Request corrections'));
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

    testWidgets(
      '${pit ? 'PIT' : 'Capstone'} rejects a before-endorsement file with feedback',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final notifier = _ReviewNotifier();
        final stage = _stage();
        // Explicit scheduling timing must behave like the compatible default.
        (stage['pre'] as List).first['requirement_timing'] = 'scheduling';
        await _pumpWorkspace(
          tester,
          stage: stage,
          notifier: notifier,
          pit: pit,
        );
        await tester.tap(find.text('Reject'));
        await tester.pumpAndSettle();
        expect(find.text('Reject: Concept paper'), findsOneWidget);
        final dialog = find.byType(AlertDialog);
        final reject = find.descendant(
          of: dialog,
          matching: find.byType(ElevatedButton),
        );
        expect(tester.widget<ElevatedButton>(reject).onPressed, isNull);
        await tester.enterText(
          find.descendant(of: dialog, matching: find.byType(TextField)),
          'Explain the system architecture',
        );
        await tester.pump();
        await tester.tap(reject);
        await tester.pumpAndSettle();
        expect(notifier.correction, {
          'id': 'PAPER',
          'status': 'rejected',
          'feedback': 'Explain the system architecture',
        });
        expect(notifier.endorsed, isNull);
        expect(notifier.combinedReview, isNull);
        expect(
          tester.widget<ElevatedButton>(_endorseButton()).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'missing scheduling files disable endorsement even when the deck is uploaded',
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
      expect(tester.widget<ElevatedButton>(_endorseButton()).onPressed, isNull);
      expect(
        find.text(
          'The team needs to upload the required before-endorsement files.',
        ),
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
