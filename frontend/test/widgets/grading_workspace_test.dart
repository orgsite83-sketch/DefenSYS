import 'dart:convert';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(user: {'id': 42, 'role': 'faculty'}, isRestoring: false);
}

class _Guest extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(user: {'role': 'guest_panelist'}, isRestoring: false);
}

Map<String, dynamic> _file(String key, String scope) => {
  'candidate_key': key,
  'material_scope': scope,
  'label': '$scope $key paper',
  'file_name': '$scope-$key.pdf',
  'file_url': '/protected/$scope-$key/',
};

TeamData _team({
  bool concepts = true,
  bool shared = false,
  bool chair = true,
  bool capstone = true,
  bool posted = false,
  bool complete = false,
  String target = 'team',
  List<String> keys = const ['c1', 'c2', 'c3'],
  String teamId = '20',
}) => TeamData(
  name: 'Team AgriPulse',
  project: 'Agriculture',
  defenseDate: 'Concept Proposal',
  stageName: 'Concept Proposal',
  startTime: '08:00',
  room: '302',
  teamId: teamId,
  scheduleId: teamId,
  scope: capstone ? 'capstone' : 'pit',
  isCapstone: capstone,
  scheduledDate: TeamData.manilaToday,
  serverGradingAvailable: true,
  evaluationContext: 'hearing-context',
  isPosted: posted,
  isChair: chair,
  adviserName: 'Dr. Rivera',
  section: 'BSIT 4A',
  level: '4th Year',
  members: const ['Alice', 'Bob'],
  memberDetails: const [
    TeamMember(id: '1', name: 'Alice', isLeader: true),
    TeamMember(id: '2', name: 'Bob'),
  ],
  criteria: [],
  assessmentConcepts: concepts
      ? [
          for (final key in keys)
            {
              'key': key,
              'title':
                  'Autonomous Soil Sensor and Dynamic Drip Irrigation Module $key',
              if (shared)
                'system_title':
                    'Smart Agro-Industrial IoT and Sustainable Supply Platform $key',
            },
        ]
      : [],
  panelRubric: {
    'target_type': target,
    'name': 'Concept proposal rubric',
    'criteria': [
      {
        'id': 1,
        'name': 'Research topic',
        'max_score': 10,
        'target_type': 'team',
      },
      if (target == 'both')
        {
          'id': 2,
          'name': 'Presentation',
          'max_score': 10,
          'target_type': 'individual',
        },
    ],
  },
  gradingWorkspace: {
    'team_materials': [
      for (final key in keys) _file(key, 'team'),
      _file('', 'team'),
    ],
    'shared_materials_configured': shared,
    'shared_materials': shared
        ? [for (final key in keys) _file(key, 'shared')]
        : [],
    if (shared)
      'shared_review': {
        'id': 8,
        'round_id': 12,
        'review_token': 'captured-section-token',
        'section': 'BSIT 4A',
        'can_decide': chair,
        'verdict': '',
        'selected_key': '',
        'remarks': '',
        'decision_unavailable_reason': chair
            ? ''
            : 'The common panel chair records the shared system decision.',
        'teams': [
          {'id': 20, 'name': 'Team AgriPulse'},
          {'id': 21, 'name': 'Team BioPulse'},
        ],
        'systems': [
          for (final key in keys)
            {
              'key': key,
              'title':
                  'Smart Agro-Industrial IoT and Sustainable Supply Platform $key',
              'decision': '',
            },
        ],
      },
  },
  workflowGrade: {
    'id': 7,
    'status': 'draft',
    'workflow': {
      'can_save_recommendations': chair,
      'assessment_progress': {
        'panel_evaluators_submitted': complete ? 3 : 1,
        'panel_evaluators_required': 3,
      },
      'concept_workflow': {
        'enabled': concepts,
        if (shared) 'section_project_id': 8,
        'concepts': [
          for (final key in keys)
            {'key': key, 'title': 'Module $key', 'decision': ''},
        ],
      },
      'outcome_rule': {
        'automatic': true,
        'per_concept': concepts,
        'panel_complete': complete,
        'qualifying_score': 75,
        'outcome': shared ? 'pending' : 'approved',
        'review_token': 'outcome-token',
        'assessments': [
          for (final key in keys)
            {
              'key': key,
              'title':
                  'Autonomous Soil Sensor and Dynamic Drip Irrigation Module $key',
              'score': 80,
              'qualifies': true,
            },
        ],
      },
    },
  },
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _sectionNotes() => find.descendant(
  of: _key('shared-section-notes'),
  matching: find.byType(EditableText),
);
Future<_Client> _show(
  WidgetTester tester,
  TeamData team, {
  double width = 390,
  double height = 900,
  bool dark = false,
  bool guest = false,
  double scale = 1,
  bool start = true,
  Future<void> Function()? onRefresh,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = _Client();
  when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
    (_) async => http.Response(
      jsonEncode({
        'draft': {'saved_at': '2026-10-28T12:00:00Z'},
      }),
      200,
    ),
  );
  await pumpDefensysWidget(
    tester,
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(scale),
      ),
      child: GradeSheetTab(
        teams: [team],
        selectedTeamIndex: 0,
        onTeamChanged: (_) {},
        onRefresh: onRefresh,
      ),
    ),
    overrides: [
      authProvider.overrideWith(guest ? _Guest.new : _Auth.new),
      authenticatedHttpClientProvider.overrideWithValue(client),
    ],
    theme: dark ? AppTheme.mistDarkTheme : null,
  );
  if (start && !team.isPosted) {
    await _tap(tester, _key('start-team-evaluation'));
  }
  return client;
}

Future<void> _score(WidgetTester tester, String score) async {
  final picker = find.byType(EvaluationScorePicker);
  await _tap(
    tester,
    find.descendant(of: picker, matching: _key('score-value-$score')),
  );
}

Future<void> _select(WidgetTester tester, String key) async {
  final row = _key('assessment-candidate-$key');
  if (row.evaluate().isEmpty) {
    await _tap(tester, _key('assessment-selector'));
  }
  await _tap(tester, row);
}

void main() {
  setUpAll(() async {
    registerFallbackValue(Uri.parse('https://example.test'));
    await loadPreviewFonts(force: true);
  });

  test(
    'assignment title uses captured proposals until an official choice exists',
    () {
      final team = _team(shared: true, keys: ['c3']);
      expect(
        team.assignmentProjectTitle,
        'Module proposal under assessment · 1 proposal',
      );
      expect(team.evaluationStatus, 'Ready to evaluate');
      team.gradingWorkspace['shared_review']['selected_key'] = 'c3';
      expect(
        team.assignmentProjectTitle,
        team.assessmentConcepts.single['title'],
      );
      final independent = _team(keys: ['c2', 'c4']);
      expect(
        independent.assignmentProjectTitle,
        'Concepts under assessment · 2 proposals',
      );
      expect(_team(concepts: false).assignmentProjectTitle, 'Agriculture');
      independent.workflowGrade!['verdict'] = 'approved';
      (independent.workflowGrade!['workflow']['concept_workflow']['concepts']
              as List)[1]['decision'] =
          'approved';
      expect(independent.assignmentProjectTitle, 'Module c4');
    },
  );

  testWidgets(
    'assignment card keeps existing status and action with the pending title',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        AssignmentsTab(teams: [_team(shared: true)], onOpenGradeSheet: (_) {}),
      );
      expect(
        find.text('Module proposals under assessment · 3 proposals'),
        findsOneWidget,
      );
      expect(find.text('Ready to evaluate'), findsOneWidget);
      expect(find.text('Grade Team'), findsOneWidget);
      expect(find.text('Agriculture'), findsNothing);
    },
  );

  testWidgets('generic shared files do not enable a shared selection tab', (
    tester,
  ) async {
    final team = _team(concepts: false);
    team.gradingWorkspace['shared_materials_configured'] = true;
    team.gradingWorkspace['shared_materials'] = [_file('', 'shared')];
    await _show(tester, team);
    expect(_key('grading-shared-tab'), findsNothing);
    expect(find.text('shared-.pdf'), findsOneWidget);
    final independent = _team();
    await _show(tester, independent, start: false);
    expect(_key('grading-shared-tab'), findsNothing);
    expect(_key('grading-outcome-tab'), findsOneWidget);
  });

  testWidgets(
    'team details remain available and expanded across concept changes',
    (tester) async {
      final team = _team();
      await _show(tester, team);
      final summary = _key('team-defense-brief');
      final scroll = tester
          .widget<SingleChildScrollView>(_key('evaluation-scroll'))
          .controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Team details & presenting members'));
      expect(find.text('Dr. Rivera'), findsOneWidget);
      expect(find.text('BSIT 4A'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      await _select(tester, 'c2');
      expect(
        find.descendant(
          of: summary,
          matching: find.text(team.assessmentConcepts[1]['title']),
        ),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(GradeSheetTab),
        'grading-workspace-final/team-details-expanded',
        viewport: true,
      );
      await tester.ensureVisible(find.byType(EvaluationScorePicker));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await tester.ensureVisible(
        find.text('Team details & presenting members'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dr. Rivera'), findsOneWidget);
      expect(team.project, 'Agriculture');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, dark) in [(320.0, true), (390.0, false)]) {
    testWidgets(
      'independent concept summary and outcome fit $width dark=$dark',
      (tester) async {
        await _show(
          tester,
          _team(),
          width: width,
          dark: dark,
          scale: width == 320 ? 1.35 : 1,
        );
        tester
            .widget<SingleChildScrollView>(_key('evaluation-scroll'))
            .controller!
            .jumpTo(0);
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(GradeSheetTab),
          'grading-workspace-final/independent-evaluation-$width-$dark',
          viewport: true,
        );
        await _tap(tester, _key('grading-outcome-tab'));
        expect(_key('concept-assessment-c1'), findsOneWidget);
        expect(_key('concept-assessment-c2'), findsOneWidget);
        expect(_key('concept-assessment-c3'), findsOneWidget);
        expect(find.text('Provisional'), findsNWidgets(3));
        await capturePreview(
          tester,
          find.byType(GradeSheetTab),
          'grading-workspace-final/independent-outcome-$width-$dark',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('assessment navigation stays visible while the rubric scrolls', (
    tester,
  ) async {
    await _show(tester, _team(shared: true), height: 640);
    final before = tester.getTopLeft(_key('pinned-assessment-selector'));
    await tester.drag(_key('evaluation-scroll'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_key('pinned-assessment-selector')), before);
    await _select(tester, 'c2');
    expect(find.text('Module 2 of 3'), findsOneWidget);
    expect(find.byType(Radio<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short phone with large text keeps scoring and shared actions reachable',
    (tester) async {
      await _show(
        tester,
        _team(shared: true),
        width: 320,
        height: 520,
        scale: 1.5,
      );
      await _score(tester, '0');
      await _tap(tester, _key('grading-shared-tab'));
      await _tap(tester, find.text('Section instructions'));
      await tester.ensureVisible(_sectionNotes());
      await tester.enterText(_sectionNotes(), 'Shared revision notes');
      await tester.ensureVisible(find.text('Request another shared hearing'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared draft survives another team in the same section and resets for another round',
    (tester) async {
      await _show(tester, _team(shared: true));
      await _tap(tester, _key('grading-shared-tab'));
      await _tap(
        tester,
        find.descendant(
          of: _key('shared-system-option-c2'),
          matching: find.byType(Radio<String>),
        ),
      );
      await _tap(tester, find.text('Section instructions'));
      await tester.ensureVisible(_sectionNotes());
      await tester.enterText(_sectionNotes(), 'Keep shared evidence');
      await _tap(tester, _key('grading-evaluation-tab'));
      await _select(tester, 'c3');
      await _tap(tester, _key('grading-shared-tab'));
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'c2',
      );
      await _show(tester, _team(shared: true, teamId: '21'), start: false);
      await _tap(tester, _key('grading-shared-tab'));
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'c2',
      );
      expect(
        tester.widget<EditableText>(_sectionNotes()).controller.text,
        'Keep shared evidence',
      );
      final nextRound = _team(shared: true, teamId: '22');
      nextRound.gradingWorkspace['shared_review']['round_id'] = 99;
      await _show(tester, nextRound, start: false);
      await _tap(tester, _key('grading-shared-tab'));
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull,
      );
      await _tap(tester, find.text('Section instructions'));
      expect(
        tester.widget<EditableText>(_sectionNotes()).controller.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authorized shared files remain readable without decision context',
    (tester) async {
      final team = _team(shared: true);
      team.gradingWorkspace.remove('shared_review');
      await _show(tester, team);
      await _tap(tester, _key('grading-shared-tab'));
      expect(
        find.text('Shared system review is unavailable for this hearing.'),
        findsOneWidget,
      );
      expect(find.text('shared-c1.pdf'), findsOneWidget);
      expect(find.text('team-c1.pdf'), findsNothing);
      expect(_key('confirm-inline-shared-system'), findsNothing);
    },
  );

  testWidgets(
    'recorded shared choice shows only the linked module with alternatives disclosed',
    (tester) async {
      final team = _team(shared: true, complete: true);
      team.gradingWorkspace['shared_review']['selected_key'] = 'c2';
      team.gradingWorkspace['shared_review']['verdict'] = 'approved';
      team.workflowGrade!['verdict'] = 'approved';
      team.workflowGrade!['workflow']['outcome_rule']['outcome'] = 'approved';
      await _show(tester, team);
      await _tap(tester, _key('grading-outcome-tab'));
      expect(find.text('Selected shared system'), findsOneWidget);
      expect(find.text(team.assessmentConcepts[1]['title']), findsOneWidget);
      expect(find.text('Module panel score: 80%'), findsOneWidget);
      expect(find.text('Alternative module assessments'), findsOneWidget);
      expect(find.text('Confirm concept selection'), findsNothing);
      expect(_key('confirm-inline-shared-system'), findsNothing);
      expect(find.byType(Radio<String>), findsNothing);
      await _tap(tester, find.text('Alternative module assessments'));
      expect(find.text('Module panel score: 80%'), findsNWidgets(3));
      await _tap(tester, _key('grading-shared-tab'));
      expect(find.text('Other proposals'), findsOneWidget);
      expect(find.text('shared-c2.pdf'), findsOneWidget);
      expect(find.text('shared-c1.pdf'), findsNothing);
      expect(find.text('team-c2.pdf'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final capstone in [true, false]) {
    testWidgets('normal stage is evaluation only capstone=$capstone', (
      tester,
    ) async {
      final team = _team(concepts: false, capstone: capstone);
      // The configured workflow flag is false even though an outcome summary exists.
      await _show(tester, team);
      expect(_key('grading-evaluation-tab'), findsNothing);
      expect(_key('grading-outcome-tab'), findsNothing);
      expect(_key('automatic-assessment-panel'), findsNothing);
      expect(find.text('Submit Verdict'), findsNothing);
      expect(find.byType(EvaluationScorePicker), findsOneWidget);
      team.isPosted = true;
      expect(team.panelWorkFinished, isTrue);
      expect(team.canIssueVerdict, isFalse);
    });
  }
  testWidgets(
    'tabs preserve a zero, remarks, and paired files across assessments',
    (tester) async {
      final team = _team(shared: true);
      final client = await _show(tester, team);
      expect(find.text('shared-c1.pdf'), findsNothing);
      expect(find.text('team-c1.pdf'), findsOneWidget);
      expect(find.text('shared-c2.pdf'), findsNothing);
      await _score(tester, '0');
      await _tap(tester, find.text('Optional feedback'));
      final remarks = find.byType(TextField).first;
      await tester.ensureVisible(remarks);
      await tester.enterText(remarks, 'Retain evidence');
      await tester.pump();
      await _tap(tester, _key('grading-outcome-tab'));
      expect(_key('evaluation-footer'), findsNothing);
      expect(find.text('1 of 3 panelists submitted'), findsWidgets);
      expect(find.text('Waiting for shared-system selection'), findsOneWidget);
      expect(find.byType(Radio<String>), findsNothing);
      expect(find.text('Open section systems'), findsNothing);
      await _tap(tester, _key('grading-shared-tab'));
      expect(find.text('shared-c1.pdf'), findsOneWidget);
      expect(find.text('team-c1.pdf'), findsNothing);
      expect(find.text('Module panel score: 80%'), findsNothing);
      await _tap(tester, _key('grading-evaluation-tab'));
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        0,
      );
      await _select(tester, 'c2');
      expect(find.text('shared-c2.pdf'), findsNothing);
      expect(find.text('team-c2.pdf'), findsOneWidget);
      expect(find.text('shared-c1.pdf'), findsNothing);
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        isNull,
      );
      await _select(tester, 'c1');
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        0,
      );
      expect(
        team.draftSubmissions.firstWhere(
          (s) => s['concept_key'] == 'c1',
        )['remarks'],
        'Retain evidence',
      );
      final bodies = verify(
        () => client.post(any(), body: captureAny(named: 'body')),
      ).captured;
      expect(
        bodies.every(
          (body) => !jsonDecode(body as String).containsKey('action'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed draft save keeps the current candidate and all entered values',
    (tester) async {
      final team = _team();
      final client = await _show(tester, team);
      await _score(tester, '0');
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => http.Response('{}', 503));
      await _select(tester, 'c2');
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        0,
      );
      expect(find.text('team-c1.pdf'), findsOneWidget);
      expect(team.hasUnsavedChanges, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'common chair confirms once with captured section identity and refreshes assignments',
    (tester) async {
      var refreshed = 0;
      final team = _team(shared: true, posted: true);
      final client = await _show(
        tester,
        team,
        onRefresh: () async {
          refreshed++;
        },
      );
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            ...team.sharedReview!,
            'verdict': 'approved',
            'selected_key': 'c2',
          }),
          200,
        ),
      );
      await _tap(tester, _key('grading-shared-tab'));
      await _tap(
        tester,
        find.descendant(
          of: _key('shared-system-option-c2'),
          matching: find.byType(Radio<String>),
        ),
      );
      await _tap(tester, _key('confirm-inline-shared-system'));
      expect(find.text('Team BioPulse'), findsOneWidget);
      expect(find.textContaining('2 participating teams'), findsWidgets);
      await _tap(tester, find.text('Confirm shared direction'));
      final calls = verify(
        () => client.post(captureAny(), body: captureAny(named: 'body')),
      ).captured;
      expect((calls[0] as Uri).path, endsWith('/section-concepts/8/'));
      final body = jsonDecode(calls[1] as String);
      expect(body['round_id'], 12);
      expect(body['review_token'], 'captured-section-token');
      expect(body['concepts'][1]['decision'], 'approved');
      expect(body['concepts'][0]['decision'], 'not_selected');
      expect(refreshed, 1);
      expect(_key('confirm-inline-shared-system'), findsNothing);
      final stale = _team(shared: true, posted: true);
      stale.gradingWorkspace['shared_review']['remarks'] =
          'Older assignment refresh';
      await _show(tester, stale, start: false);
      expect(_key('confirm-inline-shared-system'), findsNothing);
      expect(find.text('Shared decision recorded'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'external panel reads shared review without common chair controls',
    (tester) async {
      await _show(tester, _team(shared: true, chair: false), guest: true);
      await _tap(tester, _key('grading-shared-tab'));
      expect(find.text('Decision pending'), findsOneWidget);
      expect(_key('confirm-inline-shared-system'), findsNothing);
      expect(find.byType(Radio<String>), findsNothing);
      expect(find.textContaining('common panel chair'), findsOneWidget);
    },
  );
  testWidgets('a repeat with only c3 retains its stable key and files', (
    tester,
  ) async {
    await _show(tester, _team(shared: true, keys: ['c3']));
    expect(find.text('Module 1 of 1'), findsOneWidget);
    expect(find.text('team-c3.pdf'), findsOneWidget);
    await _score(tester, '0');
    expect(_key('next-assessment'), findsNothing);
    await _tap(tester, _key('grading-shared-tab'));
    expect(find.text('shared-c3.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'refresh preserves the outcome tab, member position, and entered scores',
    (tester) async {
      final team = _team(shared: true, target: 'both');
      await _show(tester, team);
      await _score(tester, '7');
      await _tap(tester, _key('next-evaluation-member'));
      await _score(tester, '8');
      await _tap(tester, _key('next-evaluation-member'));
      await _score(tester, '0');
      await _tap(tester, _key('grading-outcome-tab'));
      final refreshed = _team(shared: true, target: 'both')
        ..draftSubmissions = List<Map<String, dynamic>>.from(
          team.draftSubmissions,
        );
      await _show(tester, refreshed, start: false);
      expect(_key('outcome-footer'), findsOneWidget);
      await _tap(tester, _key('grading-evaluation-tab'));
      expect(find.text('Scoring Bob'), findsOneWidget);
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        0,
      );
      expect(refreshed.evaluationProgress.entered, 3);
    },
  );
  testWidgets('configured counts and missing materials remain explicit', (
    tester,
  ) async {
    final team = _team(shared: true, keys: ['c1', 'c2', 'c3', 'c4']);
    (team.gradingWorkspace['shared_materials'] as List)[0] = {
      'candidate_key': 'c1',
      'label': 'System presentation',
      'missing': true,
    };
    await _show(tester, team);
    expect(find.text('Module 1 of 4'), findsOneWidget);
    await _tap(tester, _key('grading-shared-tab'));
    expect(find.text('Not uploaded'), findsOneWidget);
    expect(find.text('0 files'), findsOneWidget);
    await _tap(tester, _key('grading-evaluation-tab'));
    await _select(tester, 'c4');
    expect(find.text('Module 4 of 4'), findsOneWidget);
    expect(find.text('team-c4.pdf'), findsOneWidget);
    expect(team.evaluationProgress.required, 4);
  });
  testWidgets('shared files are distinguished from an unconfigured checklist', (
    tester,
  ) async {
    final team = _team(shared: true);
    team.gradingWorkspace['shared_materials_configured'] = false;
    team.gradingWorkspace['shared_materials'] = [];
    await _show(tester, team);
    await _tap(tester, _key('grading-shared-tab'));
    expect(
      find.text('No shared defense materials configured.'),
      findsNWidgets(3),
    );
    expect(find.text('No shared files uploaded yet.'), findsNothing);
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('workspace fits $width dark=$dark with long titles', (
        tester,
      ) async {
        final previewTeam = _team(shared: true);
        previewTeam.gradingWorkspace['team_materials'][0]['file_name'] =
            'Team_SoilSense_Soil_NPK_Nutrient_Analysis_And_Fertilizer_Dispensing_Module.pdf';
        previewTeam.gradingWorkspace['shared_materials'][0]['file_name'] =
            'Concept_1_Shared_System_Concept_Paper.pdf';
        await _show(
          tester,
          previewTeam,
          width: width,
          dark: dark,
          scale: width == 320 ? 1.35 : 1,
        );
        final scroll = tester.widget<SingleChildScrollView>(
          _key('evaluation-scroll'),
        );
        scroll.controller!.jumpTo(0);
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(GradeSheetTab),
          'grading-workspace-final/evaluation-$width-$dark',
          viewport: true,
        );
        await _tap(tester, _key('grading-outcome-tab'));
        await capturePreview(
          tester,
          find.byType(GradeSheetTab),
          'grading-workspace-final/outcome-$width-$dark',
          viewport: true,
        );
        await _tap(tester, _key('grading-shared-tab'));
        await capturePreview(
          tester,
          find.byType(GradeSheetTab),
          'grading-workspace-final/shared-$width-$dark',
          viewport: true,
        );
        await _tap(tester, find.text('Section instructions'));
        await tester.ensureVisible(find.text('Request another shared hearing'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
