import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_defense_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defense/team_defense_records.dart';
import 'package:defensys/widgets/defense/concept_hearing_history.dart';
import 'package:defensys/widgets/defense/panel_recommendations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Defenses extends TeamDefenseNotifier {
  _Defenses(this.records, {this.error});
  final List<Map<String, dynamic>> records;
  final String? error;
  int refreshes = 0;
  @override
  TeamDefenseState build() =>
      TeamDefenseState(schedules: records, error: error);
  @override
  Future<void> fetch({String? workspace}) async {
    refreshes++;
  }
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  _Deliverables({this.teams = const []});
  final List<Map<String, dynamic>> teams;
  @override
  CapstoneDeliverablesState build() => CapstoneDeliverablesState(
    teams: teams,
    selectedStage: 'Project Proposal',
    stageOptions: ['Concept Proposal', 'Project Proposal'],
  );
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

const _continuedLabels = [
  'Concept Proposal',
  'Project Proposal',
  'Final Defense',
];
const _approvedTitle =
    'AgriSense: An Integrated Crop Health, Soil Monitoring, and Irrigation Management System for Smallholder Farmers';

final _continuedStages = <Map<String, dynamic>>[
  for (final label in _continuedLabels)
    {
      'stage_label': label,
      'semester_id': label == 'Final Defense' ? 9 : 3,
      'read_only': label != 'Final Defense',
      'stage_progress_status': label == 'Final Defense' ? 'locked' : 'passed',
      'deliverables_configured': true,
      'endorsed': label != 'Final Defense',
      'archive_complete': true,
      'post': <Map<String, dynamic>>[],
      'deliverables': [
        if (label != 'Final Defense')
          {
            'id': 'PRE',
            'label': '$label paper',
            'type': 'pre',
            'required': true,
            'uploaded': true,
            'can_upload': false,
            'submission': {
              'status': 'accepted',
              'file_name': 'original-$label.pdf',
            },
          },
      ],
      if (label != 'Final Defense')
        'grade': {
          'schedule_id': label == 'Project Proposal' ? 18 : 17,
          'status': 'published',
          'verdict': 'approved',
          'final_grade': 85,
        },
    },
];

class _ContinuedDeliverables extends CapstoneDeliverablesNotifier {
  CapstoneDeliverablesState _forStage(String selected) =>
      CapstoneDeliverablesState(
        selectedStage: selected,
        stageOptions: _continuedLabels,
        teams: [
          {
            'id': 7,
            'name': 'Team AgriSense',
            'project_version': 1,
            'semester_id': 9,
            'current_stage': 'Final Defense',
            'stages': _continuedStages,
            'selected_stage': _continuedStages.firstWhere(
              (stage) => stage['stage_label'] == selected,
            ),
          },
        ],
      );

  @override
  CapstoneDeliverablesState build() => _forStage('Final Defense');

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
  }) async {
    state = _forStage(selectedStage ?? state.selectedStage);
  }
}

Map<String, dynamic> _record(
  int id, {
  String status = 'scheduled',
  String? minutes,
  String verdict = '',
  String? progress,
  String? approvedTitle,
}) => {
  'id': id,
  'team_id': 7,
  'team_name': 'Team AgriSense',
  'scope': 'capstone',
  'stage_label': 'Project Proposal',
  'project_version': 1,
  'semester_id': 3,
  'project_title': 'Smart Agriculture Crop & Soil Monitoring',
  'scheduled_date': '2099-10-20',
  'start_time': '08:00:00',
  'slot_duration': 60,
  'room': 'Room 301',
  'status': status,
  'display_status': progress ?? status,
  'adviser_name': 'Ricardo Fontanilla',
  'documenter_name': 'Cecilia Magbanua',
  'minutes_required': true,
  'minutes_status': minutes,
  'panelists': [
    {'name': 'Florencia Dela Torre', 'is_chair': true},
    {'name': 'Teresita Buenaventura'},
  ],
  'external_evaluators': [
    {'name': 'Dr. Lina Santos', 'is_active': false},
  ],
  'assessment': {
    'verdict': verdict,
    'approved_title':
        approvedTitle ??
        (const {'approved', 'approved_with_revisions'}.contains(verdict)
            ? _approvedTitle
            : ''),
    'attempt_count': id == 18 ? 1 : 2,
    'is_completed': progress == 'completed',
  },
};

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> records, {
  bool adviser = false,
  bool dark = false,
  List<Map<String, dynamic>> grades = const [],
  String? error,
  List<Map<String, dynamic>> hearingHistory = const [],
}) => pumpDefensysWidget(
  tester,
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: TeamDefenseRecordsView(
        teamId: 7,
        selectedStage: 'Project Proposal',
        grades: grades,
        allowAdviserReview: adviser,
        hearingHistory: hearingHistory,
      ),
    ),
  ),
  theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
  overrides: [
    teamDefenseProvider.overrideWith(() => _Defenses(records, error: error)),
  ],
);

void main() {
  for (final isCapstone in [false, true]) {
    testWidgets(
      '${isCapstone ? 'Capstone' : 'PIT'} recommendations appear only in the Defense or Schedule tab',
      (tester) async {
        final stage = <String, dynamic>{
          'stage_label': 'Project Proposal',
          'endorsed': true,
          'deliverables_configured': true,
          'grade': {
            'schedule_id': 18,
            'verdict': 'for_redefense',
            'verdict_remarks':
                'Use the panel recommendations for the next hearing.',
          },
          'concept_workflow': {
            'enabled': true,
            'can_edit': true,
            'round': 2,
            'concepts': [
              {
                'key': 'c1',
                'title': 'Next system title',
                'requested_action': 'revise',
                'panel_feedback': 'Copied preparation feedback',
              },
            ],
            'history': [
              {
                'schedule_id': 18,
                'round': 1,
                'verdict': 'for_redefense',
                'concepts': [
                  {
                    'title': 'Presented system',
                    'remarks': 'Explain the sensor readings.',
                  },
                ],
              },
            ],
          },
          'deliverables': [
            {
              'id': 'PAPER',
              'label': 'Concept Paper',
              'type': 'pre',
              'required': true,
              'uploaded': true,
              'can_upload': false,
              'submission': {'status': 'accepted', 'file_name': 'concept.pdf'},
            },
          ],
        };
        final team = <String, dynamic>{
          'id': 7,
          'name': 'Team AgriSense',
          'currentStage': 'Project Proposal',
          'stages': [stage],
          'selected_stage': stage,
        };
        await pumpDefensysWidget(
          tester,
          StudentEventsTab(
            isCapstone: isCapstone,
            isActive: false,
            studentData: {
              'team': team,
              'current_stage': 'Project Proposal',
              'stage_options': ['Project Proposal'],
              'stages': [stage],
            },
          ),
          overrides: [
            capstoneDeliverablesProvider.overrideWith(
              () => _Deliverables(teams: [team]),
            ),
            teamDefenseProvider.overrideWith(
              () => _Defenses([
                _record(18, status: 'done', verdict: 'for_redefense'),
              ]),
            ),
          ],
        );
        expect(find.text('Panel recommendations'), findsOneWidget);
        expect(
          find.text('Use the panel recommendations for the next hearing.'),
          findsOneWidget,
        );
        expect(find.text('Presented system'), findsOneWidget);
        expect(find.text('Explain the sensor readings.'), findsOneWidget);
        expect(find.text('Copied preparation feedback'), findsNothing);

        await tester.ensureVisible(find.text('Deliverables'));
        await tester.tap(find.text('Deliverables'));
        await tester.pumpAndSettle();
        expect(find.text('Concept Paper'), findsOneWidget);
        expect(find.text('Panel recommendations'), findsNothing);
        expect(
          find.text('Use the panel recommendations for the next hearing.'),
          findsNothing,
        );
        expect(find.text('Explain the sensor readings.'), findsNothing);
        expect(find.text('Copied preparation feedback'), findsNothing);
        expect(find.textContaining('Revise ·'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'Defense shows hearing recommendations once and separate system notes $dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final record = _record(18, status: 'done', verdict: 'for_redefense');
        (record['assessment'] as Map)['verdict_remarks'] = 'We will meet again';
        await _pump(
          tester,
          [record],
          dark: dark,
          hearingHistory: [
            {
              'schedule_id': 18,
              'round': 1,
              'remarks': 'We will meet again',
              'concepts': [
                {
                  'key': 'c1',
                  'title': 'AquaWatch',
                  'remarks': 'We will meet again',
                },
                {
                  'key': 'c2',
                  'title': 'FoodRescue',
                  'remarks': 'Clarify food storage and pickup.',
                  'panel_score': 99.77,
                },
                {
                  'key': 'c3',
                  'title': 'SoundSense',
                  'remarks': 'Explain how noise is measured.',
                },
              ],
            },
            {
              'schedule_id': 17,
              'round': 1,
              'remarks': 'Unrelated hearing notes',
              'concepts': [],
            },
          ],
        );
        expect(find.text('Panel recommendations'), findsOneWidget);
        expect(find.text('We will meet again'), findsOneWidget);
        expect(find.text('AquaWatch'), findsNothing);
        expect(find.text('FoodRescue'), findsOneWidget);
        expect(find.text('Clarify food storage and pickup.'), findsOneWidget);
        expect(find.text('SoundSense'), findsOneWidget);
        expect(find.text('Explain how noise is measured.'), findsOneWidget);
        expect(find.text('Unrelated hearing notes'), findsNothing);
        expect(find.textContaining('99.77'), findsNothing);
        expect(find.textContaining('Revise ·'), findsNothing);
        await tester.ensureVisible(find.text('Panel recommendations'));
        await capturePreview(
          tester,
          find.byType(TeamDefenseRecordsView),
          'panel-recommendations-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an upcoming repeat does not inherit earlier hearing recommendations',
    (tester) async {
      await _pump(
        tester,
        [_record(19)],
        hearingHistory: [
          {
            'schedule_id': 18,
            'round': 1,
            'remarks': 'Earlier recommendation',
            'concepts': [
              {'title': 'Earlier system', 'remarks': 'Earlier system note'},
            ],
          },
        ],
      );
      expect(find.text('Panel recommendations'), findsNothing);
      expect(find.text('Earlier recommendation'), findsNothing);
      expect(find.text('Earlier system note'), findsNothing);
      expect(find.byTooltip('More history actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT stage recommendations use the matching hearing and omit preparation feedback',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        PanelRecommendations.fromStage({
          'grade': {'schedule_id': 18},
          'concept_workflow': {
            'concepts': [
              {'title': 'New title', 'panel_feedback': 'Preparation copy'},
            ],
            'history': [
              {
                'schedule_id': 18,
                'round': 1,
                'remarks': 'Recorded recommendation',
                'concepts': [
                  {
                    'title': 'Original title',
                    'remarks': 'System-specific feedback',
                  },
                ],
              },
              {'schedule_id': 19, 'round': 2, 'remarks': 'Other hearing'},
            ],
          },
        }),
      );
      expect(find.text('Recorded recommendation'), findsOneWidget);
      expect(find.text('Original title'), findsOneWidget);
      expect(find.text('System-specific feedback'), findsOneWidget);
      expect(find.text('Other hearing'), findsNothing);
      expect(find.text('Preparation copy'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT upcoming hearing does not show an older grade recommendation',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        PanelRecommendations.fromStage({
          'schedule': {'id': 19},
          'grade': {
            'schedule_id': 18,
            'verdict_remarks': 'Earlier recommendation',
          },
          'hearing_history': [
            {
              'schedule_id': 18,
              'round': 1,
              'remarks': 'Earlier recommendation',
            },
            {'schedule_id': 19, 'round': 2, 'remarks': ''},
          ],
        }),
      );
      expect(find.text('Panel recommendations'), findsNothing);
      expect(find.text('Earlier recommendation'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed legacy assessment has a public status without numeric grades',
    (tester) async {
      final record = _record(18, status: 'done', progress: 'completed');
      (record['assessment'] as Map)['grade_status'] = 'published';
      (record['assessment'] as Map)['published_result'] = 'passed';
      await _pump(
        tester,
        [record],
        grades: [
          {
            'schedule_id': 18,
            'status': 'published',
            'result': 'passed',
            'final_grade': 91,
          },
        ],
      );
      expect(find.text('Stage completed'), findsOneWidget);
      expect(find.text('Title pending'), findsNothing);
      expect(find.textContaining('91'), findsNothing);
      expect(find.textContaining('Team average'), findsNothing);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('concept outcome and history fit a narrow phone $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        [
          _record(
            18,
            status: 'done',
            verdict: 'approved',
            progress: 'pending_post_defense',
          ),
        ],
        dark: dark,
        hearingHistory: [
          {
            'schedule_id': 18,
            'round': 1,
            'verdict': 'approved',
            'decided_at': '2026-11-03T08:00:00Z',
            'concepts': [
              {
                'title': 'MakersMap: Artisan Profiles & Discovery Module',
                'decision': 'approved',
                'panel_score': 82.5,
              },
            ],
            'documents': [
              {
                'files': [
                  {'file_name': 'concept.pdf', 'revision': 1},
                ],
              },
            ],
          },
        ],
      );
      expect(find.text('Concept approved'), findsOneWidget);
      expect(find.text('More'), findsNothing);
      final menu = find.byTooltip('More history actions');
      await tester.ensureVisible(menu);
      await capturePreview(
        tester,
        find.byType(TeamDefenseRecordsView),
        'concept-outcome-${dark ? 'dark' : 'light'}',
        viewport: true,
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hearing history'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ConceptHistory),
          matching: find.text('Attempt 1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('82.5'), findsNothing);
      expect(find.text('Presented files'), findsNothing);
      await capturePreview(
        tester,
        find.byType(ConceptHistory),
        'concept-outcome-history-${dark ? 'dark' : 'light'}',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'hearing history opens from the outcome menu without scores or files',
    (tester) async {
      await _pump(
        tester,
        [_record(18, status: 'done', verdict: 'approved')],
        hearingHistory: [
          {
            'schedule_id': 18,
            'round': 1,
            'verdict': 'approved',
            'concepts': [
              {
                'title': 'Selected module',
                'decision': 'approved',
                'panel_score': 82.5,
                'next_action': 'omit',
              },
              {
                'title': 'Earlier module',
                'decision': 'not_selected',
                'panel_score': 80,
                'next_action': 'omit',
              },
            ],
            'documents': [
              {
                'files': [
                  {
                    'file_name': 'presented.pdf',
                    'revision': 1,
                    'status': 'accepted',
                  },
                ],
              },
            ],
          },
        ],
      );
      expect(find.text('Concept hearing'), findsNothing);
      expect(find.byType(ConceptHistory), findsNothing);
      expect(find.text('Concept approved'), findsOneWidget);
      final menu = find.byTooltip('More history actions');
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hearing history'));
      await tester.pumpAndSettle();
      final attempt = find.descendant(
        of: find.byType(ConceptHistory),
        matching: find.text('Attempt 1'),
      );
      await tester.ensureVisible(attempt);
      await tester.tap(attempt);
      await tester.pumpAndSettle();
      expect(find.text('Selected module'), findsOneWidget);
      expect(find.text('Not selected'), findsOneWidget);
      expect(find.text('Panel score: 82.5%'), findsNothing);
      expect(find.textContaining('Not requested'), findsNothing);
      expect(find.text('Presented files'), findsNothing);
      expect(find.text('presented.pdf'), findsNothing);
      expect(find.textContaining('82.5'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'migrated student can inspect earlier stages (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('continued-stages-preview'),
            child: StudentEventsTab(
              isCapstone: true,
              isActive: false,
              studentData: {
                'student': {'id': 1},
                'team': {
                  'id': 7,
                  'name': 'Team AgriSense',
                  'semester_id': 9,
                  'project_version': 1,
                  'currentStage': 'Final Defense',
                },
                'members': <Map<String, dynamic>>[],
                'current_stage': 'Final Defense',
                'stage_options': _continuedLabels,
                'stages': _continuedStages,
              },
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          overrides: [
            capstoneDeliverablesProvider.overrideWith(
              _ContinuedDeliverables.new,
            ),
            teamDefenseProvider.overrideWith(
              () => _Defenses([
                _record(
                  18,
                  status: 'done',
                  progress: 'completed',
                  verdict: 'approved',
                ),
              ]),
            ),
          ],
        );
        expect(find.text('Stage 3 of 3'), findsOneWidget);
        for (final label in _continuedLabels) {
          expect(find.text(label), findsWidgets);
        }
        expect(find.text('Passed'), findsNWidgets(2));
        await capturePreview(
          tester,
          find.byKey(const ValueKey('continued-stages-preview')),
          'continued-student-stages-${dark ? 'dark' : 'light'}',
        );

        await tester.tap(find.text('Project Proposal'));
        await tester.pumpAndSettle();
        final records = tester.widget<TeamDefenseRecordsView>(
          find.byType(TeamDefenseRecordsView),
        );
        expect(records.selectedStage, 'Project Proposal');
        expect(records.semesterId, 3);
        expect(find.byKey(const ValueKey('defense-record-18')), findsOneWidget);
        expect(find.text('Stage 3 of 3'), findsOneWidget);

        await tester.tap(find.text('Deliverables'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Project Proposal paper'));
        await tester.pumpAndSettle();
        expect(find.text('original-Project Proposal.pdf'), findsOneWidget);
        expect(find.text('Upload File'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'automatic closure failure displays the final outcome instead of a pending verdict',
    (tester) async {
      final record = _record(
        18,
        status: 'done',
        progress: 'failed',
        verdict: 'failed',
      );
      record['assessment'] = <String, dynamic>{
        ...Map<String, dynamic>.from(record['assessment'] as Map),
        'automatic_outcomes': true,
        'hearing_outcome': 'for_redefense',
        'grade_status': 'published',
        'published_result': 'failed',
      };
      await _pump(tester, [record]);
      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Awaiting verdict'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('approved outcome shows the selected title before completion', (
    tester,
  ) async {
    final record = _record(
      18,
      status: 'done',
      progress: 'pending_post_defense',
      verdict: 'approved',
    );
    (record['assessment'] as Map)['automatic_outcomes'] = true;
    await _pump(tester, [record]);
    final outcome = find.text('Approved');
    final title = find.text(_approvedTitle);
    final completion = find.text('Post-defense requirements pending');
    expect(outcome, findsOneWidget);
    expect(title, findsOneWidget);
    expect(
      tester.getTopLeft(outcome).dy,
      lessThan(tester.getTopLeft(title).dy),
    );
    expect(
      tester.getTopLeft(title).dy,
      lessThan(tester.getTopLeft(completion).dy),
    );
    expect(find.text('Smart Agriculture Crop & Soil Monitoring'), findsNothing);
    expect(find.text('Grade publication: Pending'), findsNothing);
  });

  testWidgets(
    'a pending or re-defense outcome cannot label a proposal as approved',
    (tester) async {
      for (final verdict in ['', 'for_redefense', 'failed']) {
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, [
          _record(18, verdict: verdict, approvedTitle: 'Unapproved proposal'),
        ]);
        expect(find.textContaining('Approved title:'), findsNothing);
      }
    },
  );

  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets('upcoming records show the full roster before minutes exist', (
    tester,
  ) async {
    await _pump(tester, [_record(18)]);
    expect(find.text('Hearing scheduled'), findsOneWidget);
    expect(find.text('Room 301'), findsOneWidget);
    expect(find.textContaining('Florencia Dela Torre · Chair'), findsOneWidget);
    expect(
      find.textContaining('Dr. Lina Santos · External panelist'),
      findsOneWidget,
    );
    expect(find.text('Cecilia Magbanua'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Awaiting verdict'), findsNothing);
    expect(find.text('View final minutes'), findsNothing);
  });

  testWidgets(
    'recorded verdict is visible before grades and minutes are finalized',
    (tester) async {
      await _pump(
        tester,
        [
          _record(
            18,
            status: 'done',
            verdict: 'approved_with_revisions',
            progress: 'revisions_pending',
          ),
        ],
        grades: [
          {
            'schedule_id': 18,
            'status': 'draft',
            'revision_deadline': '2099-10-25',
            'final_grade': 77.07,
          },
        ],
      );
      expect(find.text('Approved with revisions'), findsOneWidget);
      expect(find.text(_approvedTitle), findsOneWidget);
      expect(find.textContaining('Revision deadline:'), findsOneWidget);
      expect(find.text('Grade publication: Pending'), findsNothing);
      expect(find.textContaining('77.07'), findsNothing);
      expect(find.text('Not started'), findsOneWidget);
    },
  );

  testWidgets(
    'completed records keep schedule details and students only get the final PDF action',
    (tester) async {
      await _pump(
        tester,
        [
          _record(
            18,
            status: 'done',
            verdict: 'approved',
            progress: 'completed',
            minutes: 'completed',
          ),
        ],
        grades: [
          {
            'schedule_id': 18,
            'status': 'published',
            'result': 'passed',
            'final_grade': 77.07,
          },
        ],
      );
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.text('Stage completed'), findsOneWidget);
      expect(find.textContaining('77.07'), findsNothing);
      expect(find.text('View final minutes'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, [_record(18, minutes: 'submitted')]);
      expect(find.text('Awaiting adviser signature'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsNothing);
      expect(find.text('View signed minutes'), findsNothing);
    },
  );

  testWidgets(
    'history preserves cancelled and earlier attempts without leaking their verdict',
    (tester) async {
      await _pump(tester, [
        _record(18, status: 'done', verdict: 'for_redefense'),
        _record(19),
        _record(20, status: 'cancelled'),
        {..._record(21), 'team_id': 99, 'room': 'Private room'},
        {
          ..._record(22),
          'stage_label': 'Concept Proposal',
          'room': 'Concept room',
        },
      ]);
      expect(find.byKey(const ValueKey('defense-record-19')), findsOneWidget);
      expect(find.text('Re-defense required'), findsNothing);
      await tester.ensureVisible(find.byTooltip('More history actions'));
      await tester.tap(find.byTooltip('More history actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hearing history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous defenses (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Re-defense required'), findsOneWidget);
      expect(find.text('Hearing cancelled'), findsOneWidget);
      expect(find.text('Private room'), findsNothing);
      expect(find.text('Concept room'), findsNothing);
    },
  );

  testWidgets('empty and refresh errors are explicit', (tester) async {
    await _pump(tester, []);
    expect(find.text('No defense scheduled yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, [
      _record(18),
    ], error: 'Unable to refresh defense records.');
    expect(find.text('Unable to refresh defense records.'), findsOneWidget);
    expect(find.text('Room 301'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'student roadmap uses the Defense tab and loads schedules before minutes',
    (tester) async {
      final defenses = _Defenses([
        _record(18),
        {..._record(19), 'team_id': 99, 'room': 'Private room'},
        {
          ..._record(20, status: 'done'),
          'stage_label': 'Concept Proposal',
          'room': 'Concept room',
        },
        {
          ..._record(21, status: 'cancelled'),
          'stage_label': 'Concept Proposal',
          'room': 'Cancelled concept room',
        },
      ]);
      await pumpDefensysWidget(
        tester,
        const StudentEventsTab(
          isCapstone: true,
          initialStage: 'Project Proposal',
          studentData: {
            'team': {
              'id': 7,
              'project_version': 1,
              'semester_id': 3,
              'adviserName': 'Ricardo Fontanilla',
            },
            'stage_options': ['Concept Proposal', 'Project Proposal'],
            'current_stage': 'Project Proposal',
            'stages': [],
          },
        ),
        overrides: [
          teamDefenseProvider.overrideWith(() => defenses),
          capstoneDeliverablesProvider.overrideWith(
            () => _Deliverables(
              teams: [
                {
                  'id': 99,
                  'project_version': 1,
                  'semester_id': 3,
                  'stages': [],
                },
              ],
            ),
          ),
        ],
      );
      expect(defenses.refreshes, 1);
      expect(find.text('Defense'), findsOneWidget);
      expect(find.text('Schedule'), findsNothing);
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('Private room'), findsNothing);
      expect(find.text('Concept room'), findsNothing);
      expect(find.textContaining('Previous defenses ('), findsNothing);
      await tester.ensureVisible(find.text('Concept Proposal'));
      await tester.tap(find.text('Concept Proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.ensureVisible(find.byTooltip('More history actions'));
      await tester.tap(find.byTooltip('More history actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hearing history'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Previous defenses (1)'));
      await tester.tap(find.text('Previous defenses (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'adviser stage switching filters the current record and history',
    (tester) async {
      var selectedStage = 'Project Proposal';
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => selectedStage = 'Concept Proposal'),
                  child: const Text('View Concept Proposal'),
                ),
                AdviserDefenseTab(teamId: 7, selectedStage: selectedStage),
              ],
            ),
          ),
        ),
        overrides: [
          teamDefenseProvider.overrideWith(
            () => _Defenses([
              _record(18),
              {
                ..._record(19, status: 'done'),
                'stage_label': 'Concept Proposal',
                'room': 'Concept room',
              },
              {
                ..._record(20, status: 'cancelled'),
                'stage_label': 'Concept Proposal',
                'room': 'Cancelled concept room',
              },
            ]),
          ),
        ],
      );
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.textContaining('Previous defenses ('), findsNothing);
      await tester.tap(find.text('View Concept Proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.ensureVisible(find.byTooltip('More history actions'));
      await tester.tap(find.byTooltip('More history actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hearing history'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Previous defenses (1)'));
      await tester.tap(find.text('Previous defenses (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
    },
  );

  for (final variant in ['desktop', 'phone', 'dark']) {
    testWidgets('$variant defense record fits and renders in its theme', (
      tester,
    ) async {
      tester.view.physicalSize = variant == 'phone'
          ? const Size(390, 1050)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: ColoredBox(
            color: variant == 'dark'
                ? const Color(0xFF131720)
                : const Color(0xFFF8FAFC),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TeamDefenseRecordsView(
                  teamId: 7,
                  selectedStage: 'Project Proposal',
                  allowAdviserReview: variant != 'phone',
                  grades: const [
                    {
                      'schedule_id': 19,
                      'status': 'draft',
                      'revision_deadline': '2099-10-25',
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
        theme: variant == 'dark' ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        overrides: [
          teamDefenseProvider.overrideWith(
            () => _Defenses([
              _record(
                19,
                status: 'done',
                progress: 'revisions_pending',
                verdict: 'approved_with_revisions',
                minutes: 'submitted',
              ),
              _record(
                18,
                status: 'done',
                progress: 'completed',
                verdict: 'approved',
                minutes: 'completed',
              ),
            ]),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_approvedTitle), findsOneWidget);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('preview')),
        'defense_records/$variant',
      );
    });
  }
}
