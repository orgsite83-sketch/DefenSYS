import 'dart:convert';

import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/widgets/tactile_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import '../helpers/pump_app.dart';

class _HttpClient extends Mock implements AuthenticatedHttpClient {}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(user: {'id': 42, 'role': 'faculty'}, isRestoring: false);
}

TeamData _team({DateTime? date, String target = 'team', List<Map<String, dynamic>> drafts = const []}) => TeamData(
  name: 'Team SkyLedger', project: 'Alumni Career Tracker', defenseDate: 'Concept Proposal',
  teamId: '10', scheduleId: '20', scope: 'capstone', isCapstone: true,
  stageName: 'Concept Proposal', scheduledDate: date ?? TeamData.manilaToday,
  startTime: '23:30', room: 'Room 301',
  members: const ['Alice', 'Bob'],
  memberDetails: const [TeamMember(id: '1', name: 'Alice'), TeamMember(id: '2', name: 'Bob')],
  criteria: [], isPosted: false, isChair: true, serverCanIssueVerdict: false,
  evaluationContext: 'context-a', draftSubmissions: drafts,
  draftSavedAt: drafts.isNotEmpty ? '2026-10-20T08:00:00+08:00' : null,
  panelRubric: {
    'id': 1, 'name': 'Proposal rubric', 'target_type': target,
    'criteria': [
      {'id': 1, 'name': 'Clarity', 'max_score': 10, 'target_type': 'team'},
      if (target == 'both')
        {'id': 2, 'name': 'Contribution', 'max_score': 10, 'target_type': 'individual'},
    ],
  },
);

void main() {
  test('Unscored and intentional zero remain distinct; availability uses the day', () {
    final criterion = Criterion('Clarity', 10);
    expect(criterion.score, isNull);
    expect(criterion.isScored, isFalse);
    criterion.score = 0;
    expect(criterion.isScored, isTrue);
    expect(_team().gradingAvailable, isTrue);
    expect(_team(date: TeamData.manilaToday.subtract(const Duration(days: 1))).gradingAvailable, isTrue);
    expect(_team(date: TeamData.manilaToday.add(const Duration(days: 1))).gradingAvailable, isFalse);
  });

  Future<void> showSheet(WidgetTester tester, TeamData team, {AuthenticatedHttpClient? client}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, GradeSheetTab(
      teams: [team], selectedTeamIndex: 0, onTeamChanged: (_) {},
    ), overrides: [
      authProvider.overrideWith(_Auth.new),
      if (client != null) authenticatedHttpClientProvider.overrideWithValue(client),
    ]);
  }

  Finder score(String criterion) => find.widgetWithText(TextFormField, 'Score for $criterion');
  TactileButton submitButton(WidgetTester tester) => tester.widget<TactileButton>(
    find.ancestor(of: find.text('Review & Submit'), matching: find.byWidgetPredicate((w) => w is TactileButton)),
  );

  testWidgets('Upcoming defense is a preparation view with no scores or verdict controls', (tester) async {
    await showSheet(tester, _team(date: TeamData.manilaToday.add(const Duration(days: 1))));
    expect(find.text('Upcoming defense'), findsOneWidget);
    expect(find.text('Rubric preview'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('PANEL RAW SCORE'), findsNothing);
    expect(find.text('Submit Official Verdict'), findsNothing);
    await tester.ensureVisible(find.text('Rubric preview'));
    await tester.tap(find.text('Rubric preview'));
    await tester.pumpAndSettle();
    expect(find.text('Clarity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Blank scores block submission; intentional zero completes a criterion', (tester) async {
    final team = _team();
    await showSheet(tester, team);
    expect(find.text('Ready to evaluate'), findsWidgets);
    expect(find.text('0 of 1 scores entered'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    expect(find.text('PANEL RAW SCORE'), findsNothing);
    await tester.ensureVisible(score('Clarity'));
    await tester.enterText(score('Clarity'), '0');
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 scores entered'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(submitButton(tester).onPressed, isNotNull);
    expect(team.draftSubmissions.single['criteria_scores'], [{'criterion_id': 1, 'score': 0.0}]);
    expect(find.text('PANEL RAW SCORE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('All individual scores are required and team score survives member switching', (tester) async {
    await showSheet(tester, _team(target: 'both'));
    await tester.ensureVisible(score('Clarity'));
    await tester.enterText(score('Clarity'), '0');
    await tester.ensureVisible(score('Contribution'));
    await tester.enterText(score('Contribution'), '7');
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 scores entered'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bob'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bob'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(score('Contribution')).initialValue, '');
    await tester.ensureVisible(score('Contribution'));
    await tester.enterText(score('Contribution'), '9');
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 scores entered'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNotNull);
    expect(tester.widget<TextFormField>(score('Clarity')).initialValue, '0.0');
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Alice (Leader)'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Alice (Leader)'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(score('Contribution')).initialValue, '7.0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Draft hydration restores zero without filling unanswered scores', (tester) async {
    await showSheet(tester, _team(target: 'both', drafts: [{
      'student_id': null, 'criteria_scores': [{'criterion_id': 1, 'score': 0}],
      'remarks': 'Review prototype',
    }]));
    expect(tester.widget<TextFormField>(score('Clarity')).initialValue, '0.0');
    expect(tester.widget<TextFormField>(score('Contribution')).initialValue, '');
    expect(find.text('1 of 3 scores entered'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('Save Draft sends entered scores to backend and confirms only successful persistence', (tester) async {
    final client = _HttpClient();
    registerFallbackValue(Uri.parse('https://example.test'));
    when(() => client.post(any(), body: any(named: 'body'))).thenAnswer((_) async =>
      http.Response(json.encode({'draft': {'saved_at': '2026-10-20T08:00:00+08:00'}}), 200));
    final team = _team();
    await showSheet(tester, team, client: client);
    await tester.ensureVisible(score('Clarity'));
    await tester.enterText(score('Clarity'), '0');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Draft'));
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();
    final captured = verify(() => client.post(any(), body: captureAny(named: 'body'))).captured.single as String;
    final payload = json.decode(captured) as Map;
    expect(payload['evaluation_context'], 'context-a');
    expect(payload['submissions'][0]['criteria_scores'][0]['score'], 0);
    expect(team.hasUnsavedChanges, isFalse);
    expect(team.isPosted, isFalse);
    expect(team.draftSavedAt, isNotNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Upcoming assignments remain accessible and filter separately from grading', (tester) async {
    int? opened;
    final upcoming = _team(date: TeamData.manilaToday.add(const Duration(days: 1)));
    await pumpDefensysWidget(tester, AssignmentsTab(teams: [upcoming], onOpenGradeSheet: (i) => opened = i));
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
  });
}
