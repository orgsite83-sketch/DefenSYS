import 'dart:async';
import 'dart:convert';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/screens/app/panelist/widgets/team_grade_chooser.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _HttpClient extends Mock implements AuthenticatedHttpClient {}

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(user: {'id': 42, 'role': 'faculty'}, isRestoring: false);
}

http.Response _saved() => http.Response(
  json.encode({
    'draft': {'saved_at': '2026-10-20T08:00:00+08:00'},
  }),
  200,
);

TeamData _team({
  DateTime? date,
  String target = 'team',
  String id = '20',
  bool isCapstone = true,
  bool longNames = false,
  bool canIssue = false,
  List<TeamMember>? roster,
  List<Map<String, dynamic>> drafts = const [],
  List<Map<String, dynamic>> materials = const [],
  List<Map<String, dynamic>> concepts = const [],
}) => TeamData(
  name: longNames
      ? 'Team Smart Agriculture and Crop Monitoring'
      : id == '20'
      ? 'Team SkyLedger'
      : 'Team BioPulse',
  project: id == '20' ? 'Alumni Career Tracker' : 'Plant Health Monitoring',
  defenseDate: 'Concept Proposal',
  teamId: id,
  scheduleId: id,
  scope: isCapstone ? 'capstone' : 'pit',
  isCapstone: isCapstone,
  stageName: 'Concept Proposal',
  scheduledDate: date ?? TeamData.manilaToday,
  startTime: '23:30',
  room: 'Room 301',
  members:
      roster?.map((member) => member.name).toList() ??
      (longNames
          ? const ['Adrian Christopher Valdez', 'Stephanie Alexandra Yap']
          : const ['Alice', 'Bob']),
  memberDetails:
      roster ??
      (longNames
          ? const [
              TeamMember(
                id: '1',
                name: 'Adrian Christopher Valdez',
                isLeader: true,
              ),
              TeamMember(id: '2', name: 'Stephanie Alexandra Yap'),
            ]
          : const [
              TeamMember(id: '1', name: 'Alice', isLeader: true),
              TeamMember(id: '2', name: 'Bob'),
            ]),
  criteria: [],
  isPosted: false,
  isChair: true,
  serverCanIssueVerdict: canIssue,
  evaluationContext: 'context-$id-$target',
  draftSubmissions: drafts,
  defenseMaterials: materials,
  assessmentConcepts: concepts,
  draftSavedAt: drafts.isNotEmpty ? '2026-10-20T08:00:00+08:00' : null,
  panelRubric: {
    'id': 1,
    'name': 'Proposal rubric',
    'target_type': target,
    'criteria': [
      {'id': 1, 'name': 'Clarity', 'max_score': 10, 'target_type': 'team'},
      if (target == 'both')
        {
          'id': 2,
          'name': 'Contribution',
          'max_score': 10,
          'target_type': 'individual',
        },
    ],
  },
);
Finder _picker(String criterion) => find.byWidgetPredicate(
  (w) => w is EvaluationScorePicker && w.label == criterion,
);
Finder _targetTab(String label) => find.descendant(
  of: find.byKey(const ValueKey('evaluation-target-tabs')),
  matching: find.text(label),
);
double? _value(WidgetTester tester, String criterion) =>
    tester.widget<EvaluationScorePicker>(_picker(criterion)).value;
Future<void> _tapScore(
  WidgetTester tester,
  String criterion,
  String value,
) async {
  final button = find.descendant(
    of: _picker(criterion),
    matching: find.byKey(ValueKey('score-value-$value')),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseMember(WidgetTester tester, String id) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('choose-evaluation-member')),
  );
  await _tapVisible(tester, find.byKey(ValueKey('student-selector-$id')));
}

Future<_HttpClient> _showSheet(
  WidgetTester tester,
  List<TeamData> teams, {
  _HttpClient? client,
  GlobalKey<GradeSheetTabState>? sheetKey,
  bool start = true,
  double width = 390,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  client ??= _HttpClient();
  when(
    () => client!.post(any(), body: any(named: 'body')),
  ).thenAnswer((_) async => _saved());
  var selected = 0;
  await pumpDefensysWidget(
    tester,
    RepaintBoundary(
      key: const ValueKey('grading-preview'),
      child: ColoredBox(
        color: dark
            ? AppTheme.mistDarkTheme.scaffoldBackgroundColor
            : AppTheme.lightTheme.scaffoldBackgroundColor,
        child: StatefulBuilder(
          builder: (context, update) => GradeSheetTab(
            key: sheetKey,
            teams: teams,
            selectedTeamIndex: selected,
            onTeamChanged: (index) => update(() => selected = index),
          ),
        ),
      ),
    ),
    overrides: [
      authProvider.overrideWith(_Auth.new),
      authenticatedHttpClientProvider.overrideWithValue(client),
    ],
    theme: dark ? AppTheme.mistDarkTheme : null,
  );
  if (start && teams.first.gradingAvailable) {
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('start-team-evaluation')),
    );
  }
  return client;
}

void main() {
  testWidgets('configured re-defense confirmation requires fresh endorsement', (
    tester,
  ) async {
    final team = _team(canIssue: true)..isPosted = true;
    team.workflowGrade = {
      'workflow': {
        'assessment_policy': {'version': 1},
        'outcome_rule': {
          'outcome': 'for_redefense',
          'qualifying_score': 75,
          'allowed_verdicts': ['for_redefense'],
        },
      },
    };
    await _showSheet(tester, [team], start: false);
    final instructions = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.hintText ?? '').startsWith(
            'Enter reasons for re-defense',
          ),
    );
    await tester.ensureVisible(instructions);
    await tester.enterText(
      instructions,
      'Revise the panel materials and present again.',
    );
    await _tapVisible(tester, find.text('Submit Verdict'));
    expect(find.textContaining('a fresh endorsement'), findsOneWidget);
    expect(find.textContaining('No new adviser endorsement'), findsNothing);
    expect(
      find.text('Require adviser verification of corrections'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Concept assessments keep independent drafts, progress, and review',
    (tester) async {
      final team = _team(
        concepts: [
          {'key': 'c1', 'title': 'First concept'},
          {'key': 'c2', 'title': 'Second concept'},
          {'key': 'c3', 'title': 'Third concept'},
        ],
      );
      await _showSheet(tester, [team]);
      await _tapScore(tester, 'Clarity', '0');
      expect(team.evaluationProgress.entered, 1);
      expect(team.evaluationProgress.required, 3);
      expect(team.evaluationProgress.complete, isFalse);
      Future<void> select(String key, String title) async {
        final selector = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<String>,
        );
        await _tapVisible(tester, selector);
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
      }

      await select('c2', 'Second concept');
      expect(_value(tester, 'Clarity'), isNull);
      await _tapScore(tester, 'Clarity', '10');
      await select('c1', 'First concept');
      expect(_value(tester, 'Clarity'), 0);
      await select('c3', 'Third concept');
      await _tapScore(tester, 'Clarity', '7');
      expect(team.evaluationProgress.complete, isTrue);
      expect(team.draftSubmissions.map((s) => s['concept_key']).toSet(), {
        'c1',
        'c2',
        'c3',
      });
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('review-evaluation')),
      );
      expect(find.text('First concept'), findsOneWidget);
      expect(find.text('Second concept'), findsOneWidget);
      expect(find.text('Third concept'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    registerFallbackValue(Uri.parse('https://example.test'));
    await loadPreviewFonts();
  });
  test(
    'Unscored and intentional zero remain distinct; availability uses the day',
    () {
      final criterion = Criterion('Clarity', 10);
      expect(criterion.isScored, isFalse);
      criterion.score = 0;
      expect(criterion.isScored, isTrue);
      expect(_team().gradingAvailable, isTrue);
      expect(
        _team(
          date: TeamData.manilaToday.subtract(const Duration(days: 1)),
        ).gradingAvailable,
        isTrue,
      );
      expect(
        _team(
          date: TeamData.manilaToday.add(const Duration(days: 1)),
        ).gradingAvailable,
        isFalse,
      );
    },
  );
  testWidgets(
    'Opening a grade sheet requires identity verification before scoring',
    (tester) async {
      await _showSheet(tester, [_team()], start: false);
      expect(find.byType(EvaluationScorePicker), findsNothing);
      expect(find.text('Presenting members'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('start-team-evaluation')),
      );
      expect(_picker('Clarity'), findsOneWidget);
      expect(find.text('Currently grading'), findsOneWidget);
    },
  );
  testWidgets(
    'Upcoming defense is a preparation view with no scores or verdict controls',
    (tester) async {
      await _showSheet(tester, [
        _team(date: TeamData.manilaToday.add(const Duration(days: 1))),
      ]);
      expect(find.text('Upcoming defense'), findsOneWidget);
      expect(find.byType(EvaluationScorePicker), findsNothing);
      expect(find.text('Submit Verdict'), findsNothing);
      await _tapVisible(tester, find.text('Rubric preview'));
      expect(find.text('Clarity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Incomplete review cannot submit; intentional zero completes the team',
    (tester) async {
      final team = _team();
      final client = await _showSheet(tester, [team]);
      expect(find.text('0 of 1 scores entered'), findsOneWidget);
      expect(_targetTab('Individuals'), findsNothing);
      expect(find.text('PANEL RAW SCORE'), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('review-evaluation')),
      );
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('submit-reviewed-grades')),
            )
            .enabled,
        isFalse,
      );
      verifyNever(() => client.post(any(), body: any(named: 'body')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapScore(tester, 'Clarity', '0');
      expect(find.text('Your panel score 0.0%'), findsOneWidget);
      expect(find.text('Score entered'), findsOneWidget);
      expect(team.draftSubmissions.single['criteria_scores'], [
        {'criterion_id': 1, 'score': 0.0},
      ]);
      expect(team.evaluationProgress.complete, isTrue);
      expect(find.text('PANEL RAW SCORE'), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('review-evaluation')),
      );
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('submit-reviewed-grades')),
            )
            .enabled,
        isTrue,
      );
      expect(find.text('0 / 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final target in ['individual', 'both']) {
    testWidgets(
      '$target rubric keeps separate student answers and counts all required scores',
      (tester) async {
        final team = _team(target: target);
        await _showSheet(tester, [team]);
        final criterion = target == 'both' ? 'Contribution' : 'Clarity';
        if (target == 'both') {
          await _tapScore(tester, 'Clarity', '0');
          await _tapVisible(tester, _targetTab('Individuals'));
        } else {
          expect(_targetTab('Team'), findsNothing);
          expect(find.text('Team criteria'), findsNothing);
        }
        await _tapScore(tester, criterion, '7');
        expect(team.progressFor('1').complete, isTrue);
        expect(team.progressFor('2').entered, 0);
        await _chooseMember(tester, '2');
        expect(_value(tester, criterion), isNull);
        expect(find.text('Member 2 of 2'), findsOneWidget);
        expect(
          find.text(
            target == 'both' ? '1 of 2 members' : '1 of 2 members complete',
          ),
          findsOneWidget,
        );
        await _tapScore(tester, criterion, '9');
        expect(
          find.textContaining(
            '${target == 'both' ? 3 : 2}/${target == 'both' ? 3 : 2} scored',
          ),
          findsOneWidget,
        );
        expect(team.evaluationProgress.complete, isTrue);
        await _chooseMember(tester, '1');
        expect(_value(tester, criterion), 7);
        if (target == 'both') {
          await _tapVisible(tester, _targetTab('Team'));
          expect(_value(tester, 'Clarity'), 0);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'guided grading keeps four member drafts and reaches review without submitting',
    (tester) async {
      final team = _team(
        target: 'both',
        isCapstone: false,
        roster: const [
          TeamMember(id: '1', name: 'Alden VELASQUEZ', isLeader: true),
          TeamMember(id: '2', name: 'Karen EVANGELISTA'),
          TeamMember(id: '3', name: 'Ron VELASCO'),
          TeamMember(id: '4', name: 'Rona MORATALLA'),
        ],
      );
      team.panelRubric!['criteria'] = <Map<String, dynamic>>[
        ...(team.panelRubric!['criteria'] as List).cast<Map<String, dynamic>>(),
        {
          'id': 3,
          'name': 'System functionality',
          'max_score': 10,
          'target_type': 'team',
        },
        {
          'id': 4,
          'name': 'Technical understanding',
          'max_score': 10,
          'target_type': 'individual',
        },
      ];
      final client = await _showSheet(tester, [team]);
      await _tapScore(tester, 'Clarity', '0');
      await _tapScore(tester, 'System functionality', '9');
      expect(find.text('Member 1 of 4'), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      expect(find.text('Member 1 of 4'), findsOneWidget);
      expect(find.byKey(const ValueKey('student-selector-2')), findsNothing);
      await tester.ensureVisible(find.text('Proposal rubric'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byKey(const ValueKey('grading-preview')),
        'guided-grading-members-light',
      );
      await _tapScore(tester, 'Contribution', '0');
      await _tapScore(tester, 'Technical understanding', '7');
      expect(find.text('Scoring Alden VELASQUEZ'), findsOneWidget);
      await _tapVisible(tester, find.text('Optional feedback'));
      final feedback = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Feedback for Alden VELASQUEZ',
      );
      await tester.ensureVisible(feedback);
      await tester.enterText(feedback, 'Explain the implementation decisions.');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      expect(find.text('Scoring Karen EVANGELISTA'), findsOneWidget);
      expect(_value(tester, 'Contribution'), isNull);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('previous-evaluation-member')),
      );
      expect(_value(tester, 'Contribution'), 0);
      expect(_value(tester, 'Technical understanding'), 7);
      await _tapVisible(tester, find.text('Optional feedback'));
      expect(
        tester.widget<TextField>(feedback).controller!.text,
        'Explain the implementation decisions.',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      for (var member = 2; member <= 4; member++) {
        await _tapScore(tester, 'Contribution', '8');
        await _tapScore(tester, 'Technical understanding', '9');
        if (member < 4) {
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('next-evaluation-member')),
          );
        }
      }
      expect(team.evaluationProgress.required, 10);
      expect(team.evaluationProgress.complete, isTrue);
      expect(
        find.byKey(const ValueKey('next-evaluation-member')),
        findsNothing,
      );
      expect(
        team.draftSubmissions.firstWhere(
          (row) => row['student_id'] == 1,
        )['remarks'],
        'Explain the implementation decisions.',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('review-evaluation')),
      );
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('submit-reviewed-grades')),
            )
            .enabled,
        isTrue,
      );
      expect(team.isPosted, isFalse);
      final requests = verify(
        () => client.post(captureAny(), body: any(named: 'body')),
      ).captured.cast<Uri>();
      expect(
        requests.every((uri) => uri.path.endsWith('/grade-draft/')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed and pending draft saves keep the current target and member',
    (tester) async {
      final team = _team(target: 'both');
      final client = await _showSheet(tester, [team]);
      final pending = Completer<http.Response>();
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) => pending.future);
      await _tapScore(tester, 'Clarity', '0');
      await _tapVisible(tester, _targetTab('Individuals'));
      expect(_picker('Clarity'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('next-evaluation-member')),
            )
            .enabled,
        isFalse,
      );
      final tabs = tester.widget<ShadTabs<bool>>(
        find.descendant(
          of: find.byKey(const ValueKey('evaluation-target-tabs')),
          matching: find.byType(ShadTabs<bool>),
        ),
      );
      expect(tabs.value, isFalse);
      pending.complete(http.Response('{"detail":"Offline"}', 503));
      await tester.pumpAndSettle();
      expect(_value(tester, 'Clarity'), 0);
      expect(find.textContaining('Couldn’t save draft'), findsOneWidget);
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _saved());
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      expect(find.text('Scoring Alice'), findsOneWidget);
      await _tapScore(tester, 'Contribution', '7');
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => http.Response('{"detail":"Offline"}', 503));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      expect(find.text('Scoring Alice'), findsOneWidget);
      expect(_value(tester, 'Contribution'), 7);
      expect(team.hasUnsavedChanges, isTrue);
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _saved());
      await _chooseMember(tester, '2');
      expect(find.text('Scoring Bob'), findsOneWidget);
      expect(_value(tester, 'Contribution'), isNull);
      expect(team.isPosted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'next unscored preserves the previous concept and opens the next incomplete assessment',
    (tester) async {
      final team = _team(
        target: 'both',
        concepts: [
          {'key': 'c1', 'title': 'First concept'},
          {'key': 'c2', 'title': 'Second concept'},
        ],
      );
      await _showSheet(tester, [team]);
      await _tapScore(tester, 'Clarity', '0');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      await _tapScore(tester, 'Contribution', '7');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('next-evaluation-member')),
      );
      await _tapScore(tester, 'Contribution', '9');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('more-grading-actions')),
      );
      await _tapVisible(tester, find.text('Next unscored'));
      expect(
        find.byKey(const ValueKey('concept-assessment-c2')),
        findsOneWidget,
      );
      expect(_value(tester, 'Clarity'), isNull);
      expect(
        team.draftSubmissions
            .where((row) => row['concept_key'] == 'c1')
            .expand((row) => row['criteria_scores'] as List)
            .map((row) => row['score']),
        [0, 7, 9],
      );
      expect(team.evaluationProgress.entered, 3);
      expect(team.evaluationProgress.required, 6);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Only the named review confirmation submits and locks the exact scores',
    (tester) async {
      final team = _team();
      final client = await _showSheet(tester, [team]);
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (call) async =>
            (call.positionalArguments.first as Uri).path.contains(
              'submit-grades',
            )
            ? http.Response('{}', 201)
            : _saved(),
      );
      await _tapScore(tester, 'Clarity', '9');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('review-evaluation')),
      );
      expect(team.isPosted, isFalse);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('submit-reviewed-grades')),
      );
      final calls = verify(
        () => client.post(captureAny(), body: captureAny(named: 'body')),
      ).captured;
      final submitBody =
          json.decode(
                calls[calls.indexWhere(
                          (item) =>
                              item is Uri &&
                              item.path.contains('submit-grades'),
                        ) +
                        1]
                    as String,
              )
              as Map;
      expect(submitBody['schedule_id'], 20);
      expect(submitBody['evaluation_context'], 'context-20-team');
      expect(submitBody['submissions'][0]['criteria_scores'][0]['score'], 9);
      expect(team.isPosted, isTrue);
      expect(team.evaluationProgress.complete, isTrue);
      expect(find.byType(EvaluationScorePicker), findsNothing);
      expect(find.textContaining('Submitted · Locked'), findsNothing);
      expect(find.textContaining('Submitted'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Submitted team has a compact green chooser indicator', (
    tester,
  ) async {
    final team = _team()..isPosted = true;
    await pumpDefensysWidget(
      tester,
      TeamGradeChooser(
        teams: [team],
        current: team,
        onConfirm: (_) async => null,
      ),
    );
    final submittedBadge = find.byKey(const ValueKey('submitted-status-20-20'));
    expect(submittedBadge, findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.textContaining('Submitted · Locked'), findsNothing);
    expect(
      (tester.widget<Container>(submittedBadge).decoration as BoxDecoration)
          .color,
      DefensysTokens.successBg,
    );
  });
  testWidgets('Submitted PIT scores describe the numeric event result', (
    tester,
  ) async {
    final team = _team(isCapstone: false)..isPosted = true;
    await _showSheet(tester, [team], start: false);
    expect(
      find.textContaining('PIT event result follows the final numeric grade'),
      findsOneWidget,
    );
    expect(find.textContaining('official stage verdict'), findsNothing);
    expect(find.text('Panel Chair Official Verdict'), findsNothing);
  });
  testWidgets(
    'Draft hydration restores zero without filling unanswered scores',
    (tester) async {
      final team = _team(
        target: 'both',
        drafts: [
          {
            'student_id': null,
            'criteria_scores': [
              {'criterion_id': 1, 'score': 0},
            ],
            'remarks': 'Review prototype',
          },
        ],
      );
      await _showSheet(tester, [team]);
      expect(_value(tester, 'Clarity'), 0);
      expect(find.text('1 of 3 scores entered'), findsOneWidget);
      await _tapVisible(tester, _targetTab('Individuals'));
      expect(_value(tester, 'Contribution'), isNull);
      expect(find.text('Draft saved'), findsOneWidget);
    },
  );
  testWidgets(
    'Autosave uses the owning schedule and shows saved only after acknowledgement',
    (tester) async {
      final client = _HttpClient();
      final team = _team();
      await _showSheet(tester, [team], client: client);
      final response = Completer<http.Response>();
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) => response.future);
      await _tapScore(tester, 'Clarity', '0');
      expect(find.textContaining('Changes pending'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 850));
      expect(find.textContaining('Saving draft…'), findsOneWidget);
      expect(find.textContaining('Draft saved'), findsNothing);
      expect(team.hasUnsavedChanges, isTrue);
      response.complete(_saved());
      await tester.pumpAndSettle();
      final payload =
          json.decode(
                verify(
                      () => client.post(any(), body: captureAny(named: 'body')),
                    ).captured.single
                    as String,
              )
              as Map;
      expect(payload['evaluation_context'], 'context-20-team');
      expect(payload['schedule_id'], '20');
      expect(payload['submissions'][0]['criteria_scores'][0]['score'], 0);
      expect(team.hasUnsavedChanges, isFalse);
      expect(team.isPosted, isFalse);
      expect(find.textContaining('Draft saved'), findsOneWidget);
      expect(find.text('Draft saved. You can continue later.'), findsNothing);
    },
  );
  testWidgets(
    'Preview and cancel never change a team; failed save blocks a confirmed switch',
    (tester) async {
      final first = _team();
      final second = _team(id: '21', target: 'individual');
      final client = await _showSheet(tester, [first, second]);
      await _tapScore(tester, 'Clarity', '8');
      await tester.ensureVisible(find.text('Proposal rubric'));
      await tester.pumpAndSettle();
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => http.Response('{"detail":"Offline"}', 503));
      await _tapVisible(tester, find.text('Change team'));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('preview-team-21-21')),
      );
      expect(find.text('Team preview'), findsOneWidget);
      await capturePreview(
        tester,
        find
            .ancestor(
              of: find.text('Team preview'),
              matching: find.byType(RepaintBoundary),
            )
            .first,
        'panel-team-preview',
      );
      expect(first.hasUnsavedChanges, isTrue);
      await tester.tap(find.byTooltip('Keep current team'));
      await tester.pumpAndSettle();
      expect(_value(tester, 'Clarity'), 8);
      await _tapVisible(tester, find.text('Change team'));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('preview-team-21-21')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('confirm-team-selection')),
      );
      // The preview list builds this notice after the expanded team details.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('team-switch-error')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('team-switch-error')), findsOneWidget);
      expect(second.hasDraft, isFalse);
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _saved());
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('confirm-team-selection')),
      );
      expect(find.text('Individual evaluation'), findsOneWidget);
      expect(_value(tester, 'Clarity'), isNull);
      expect(first.hasUnsavedChanges, isFalse);
      await _tapVisible(tester, find.text('Change team'));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('preview-team-20-20')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('confirm-team-selection')),
      );
      expect(_value(tester, 'Clarity'), 8);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Edits during an in-flight save require a second acknowledgement before leaving',
    (tester) async {
      final key = GlobalKey<GradeSheetTabState>();
      final team = _team();
      final client = await _showSheet(tester, [team], sheetKey: key);
      final first = Completer<http.Response>();
      final second = Completer<http.Response>();
      var calls = 0;
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) => ++calls == 1 ? first.future : second.future);
      await _tapScore(tester, 'Clarity', '7');
      await tester.pump(const Duration(milliseconds: 850));
      await _tapScore(tester, 'Clarity', '9');
      bool? mayLeave;
      unawaited(
        key.currentState!.savePendingChanges().then(
          (value) => mayLeave = value,
        ),
      );
      first.complete(_saved());
      await tester.pumpAndSettle();
      expect(mayLeave, isNull);
      expect(team.hasUnsavedChanges, isTrue);
      second.complete(_saved());
      await tester.pumpAndSettle();
      expect(mayLeave, isTrue);
      expect(team.hasUnsavedChanges, isFalse);
      final bodies =
          verify(() => client.post(any(), body: captureAny(named: 'body')))
              .captured
              .cast<String>()
              .map((body) => json.decode(body) as Map)
              .toList();
      expect(
        bodies.map(
          (body) => body['submissions'][0]['criteria_scores'][0]['score'],
        ),
        [7, 9],
      );
    },
  );
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('Grading and team preview fit at $width', (tester) async {
      final team = _team(target: 'both');
      await _showSheet(tester, [team, _team(id: '21')], width: width);
      await _tapScore(tester, 'Clarity', '8');
      await capturePreview(
        tester,
        find.byKey(const ValueKey('grading-preview')),
        'grading-team-${width.toInt()}',
      );
      await _tapVisible(tester, _targetTab('Individuals'));
      await _tapScore(tester, 'Contribution', '7');
      await tester.ensureVisible(find.text('Proposal rubric'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byKey(const ValueKey('grading-preview')),
        'grading-student-${width.toInt()}',
      );
      await _tapVisible(tester, find.text('Change team'));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('preview-team-21-21')),
      );
      expect(
        find.byKey(const ValueKey('confirm-team-selection')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Dark grading, student selectors and preview wrap long names on a small phone',
    (tester) async {
      final team = _team(target: 'both', longNames: true);
      await _showSheet(tester, [team, _team(id: '21')], width: 320, dark: true);
      await _tapScore(tester, 'Clarity', '8');
      await _tapVisible(tester, _targetTab('Individuals'));
      await _tapScore(tester, 'Contribution', '7');
      await tester.ensureVisible(find.text('Proposal rubric'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byKey(const ValueKey('grading-preview')),
        'grading-dark-320',
      );
      await _tapVisible(tester, find.text('Change team'));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('preview-team-20-20')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Upcoming assignments remain accessible and filter separately from grading',
    (tester) async {
      int? opened;
      final upcoming = _team(
        date: TeamData.manilaToday.add(const Duration(days: 1)),
      );
      await pumpDefensysWidget(
        tester,
        AssignmentsTab(teams: [upcoming], onOpenGradeSheet: (i) => opened = i),
      );
      expect(find.text('View Defense'), findsOneWidget);
      expect(find.text('Grade Team'), findsNothing);
      await tester.tap(find.text('View Defense'));
      expect(opened, 0);
      await tester.tap(find.text('Needs Grading').first);
      await tester.pumpAndSettle();
      expect(find.text('Team SkyLedger'), findsNothing);
      await tester.tap(find.text('Upcoming').first);
      await tester.pumpAndSettle();
      expect(find.text('Team SkyLedger'), findsOneWidget);
    },
  );
  testWidgets(
    'Defense materials keep deliverable name and file details with view action',
    (tester) async {
      await _showSheet(tester, [
        _team(
          materials: [
            {
              'id': 'concept_paper',
              'label': 'Concept Paper',
              'file_name': 'SkyLedger_Concept_Paper.pdf',
              'file_url': '/media/deliverables/2026/10/concept_paper.pdf',
            },
          ],
        ),
      ]);
      expect(find.text('Defense materials'), findsOneWidget);
      expect(find.text('Concept Paper'), findsOneWidget);
      expect(find.text('SkyLedger_Concept_Paper.pdf'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    },
  );
}
