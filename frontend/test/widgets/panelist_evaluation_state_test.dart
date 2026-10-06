import 'dart:async';
import 'dart:convert';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
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
  bool longNames = false,
  List<Map<String, dynamic>> drafts = const [],
  List<Map<String, dynamic>> materials = const [],
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
  scope: 'capstone',
  isCapstone: true,
  stageName: 'Concept Proposal',
  scheduledDate: date ?? TeamData.manilaToday,
  startTime: '23:30',
  room: 'Room 301',
  members: longNames
      ? const ['Adrian Christopher Valdez', 'Stephanie Alexandra Yap']
      : const ['Alice', 'Bob'],
  memberDetails: longNames
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
        ],
  criteria: [],
  isPosted: false,
  isChair: true,
  serverCanIssueVerdict: false,
  evaluationContext: 'context-$id-$target',
  draftSubmissions: drafts,
  defenseMaterials: materials,
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
      expect(find.textContaining('Students ·'), findsNothing);
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
      expect(find.text('1 of 1 scores entered'), findsOneWidget);
      expect(find.text('Score entered'), findsOneWidget);
      expect(team.draftSubmissions.single['criteria_scores'], [
        {'criterion_id': 1, 'score': 0.0},
      ]);
      expect(team.evaluationProgress.complete, isTrue);
      expect(find.text('PANEL RAW SCORE'), findsOneWidget);
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
          await _tapVisible(tester, find.textContaining('Students ·'));
        } else {
          expect(find.textContaining('Team ·'), findsNothing);
          expect(find.text('Team criteria'), findsNothing);
        }
        await _tapScore(tester, criterion, '7');
        expect(team.progressFor('1').complete, isTrue);
        expect(team.progressFor('2').entered, 0);
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('student-selector-2')),
        );
        expect(_value(tester, criterion), isNull);
        expect(find.text('Viewing'), findsOneWidget);
        expect(find.text('Complete · 1/1 scored'), findsOneWidget);
        await _tapScore(tester, criterion, '9');
        expect(
          find.text(
            '${target == 'both' ? 3 : 2} of ${target == 'both' ? 3 : 2} scores entered',
          ),
          findsOneWidget,
        );
        expect(team.evaluationProgress.complete, isTrue);
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('student-selector-1')),
        );
        expect(_value(tester, criterion), 7);
        if (target == 'both') {
          await _tapVisible(tester, find.textContaining('Team ·'));
          expect(_value(tester, 'Clarity'), 0);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      expect(find.text('Submitted · Locked'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );
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
      await _tapVisible(tester, find.textContaining('Students ·'));
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
      expect(find.text('Changes pending'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 850));
      expect(find.text('Saving draft…'), findsOneWidget);
      expect(find.text('Draft saved'), findsNothing);
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
      expect(find.text('Draft saved'), findsOneWidget);
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
      await _tapVisible(tester, find.textContaining('Students ·'));
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
      await _tapVisible(tester, find.textContaining('Students ·'));
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
