import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/grade_center_event_teams_screen.dart';
import 'package:defensys/screens/web/admin/grade_center_team_detail_screen.dart';
import 'package:defensys/screens/web/admin/grade_center_shared.dart';
import 'package:defensys/services/grade_center_provider.dart';

import '../helpers/pump_app.dart';

class _Grades extends GradeCenterNotifier {
  _Grades(this.initial);
  final GradeCenterState initial;

  @override
  GradeCenterState build() => initial;

  @override
  Future<bool> refreshGrade(int gradeId) async => true;
}

void main() {
  Map<String, dynamic> grade({bool submitted = false}) => {
    'id': 1,
    'scope': 'pit',
    'stage_label': 'PIT Showcase',
    'team_name': 'Team Example',
    'project_title': 'Prototype',
    'grading_ready': false,
    'panel_score': submitted ? '90.00' : '80.00',
    'members': [
      {'student_id': 11, 'name': 'Student Example', 'is_leader': true},
    ],
    'weights': {'panel': 80, 'peer': 20},
    'panelists': [
      {'username': 'faculty', 'name': 'Faculty Example'},
      {
        'username': '',
        'panelist_key': 'guest:3',
        'name': 'External Expert',
        'is_external': true,
      },
    ],
    'panel_evaluation_scores': [
      {'panelist_key': 'faculty', 'student_id': null, 'percentage': '80.00'},
      if (submitted)
        {'panelist_key': 'guest:3', 'student_id': null, 'percentage': '100.00'},
    ],
    'breakdowns': [
      if (submitted)
        {
          'evaluation_type': 'panel',
          'criterion_name': 'Prototype',
          'student_id': 11,
          'remarks': 'Guest panelist: Old name (OLD-CODE)',
          'score': '10',
          'max_score': '10',
        },
    ],
  };

  test('assigned externals have a column before their first score', () {
    expect(gradePanelistColumns(grade()), [
      {'key': 'faculty', 'name': 'Faculty Example'},
      {'key': 'guest:3', 'name': 'External Expert'},
    ]);
  });

  test(
    'renewed access and old snapshot labels do not duplicate external columns',
    () {
      final columns = gradePanelistColumns(grade(submitted: true));
      expect(columns.length, 2);
      expect(columns.last, {'key': 'guest:3', 'name': 'External Expert'});
    },
  );

  test('legacy responses retain external scores from breakdowns', () {
    final legacy = grade(submitted: true)..remove('panel_evaluation_scores');
    legacy['panelists'] = [];
    expect(gradePanelistColumns(legacy), [
      {'key': 'Old name (OLD-CODE)', 'name': 'Old name'},
    ]);
  });

  test('access credentials are removed from old display labels and comments', () {
    expect(publicEvaluationText('James Bond (DEF-123ABC456DEF)'), 'James Bond');
    expect(publicEvaluationText('Access DEF-123ABC456DEF'), 'Access [redacted]');
  });

  for (final submitted in [false, true]) {
    testWidgets(
      'PIT master sheet shows external evaluator with submitted=$submitted',
      (tester) async {
        tester.view.physicalSize = const Size(2400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = GradeCenterState(grades: [grade(submitted: submitted)]);
        await pumpDefensysWidget(
          tester,
          GradeCenterEventTeamsScreen(
            groupKey: 'pit|PIT Showcase',
            scope: 'pit',
            stageLabel: 'PIT Showcase',
            title: 'PIT Showcase',
            onBack: () {},
            onOpenTeamDetail: (_, __) {},
          ),
          overrides: [gradeCenterProvider.overrideWith(() => _Grades(state))],
        );
        expect(find.text('External Expert'), findsOneWidget);
        expect(find.textContaining('OLD-CODE'), findsNothing);
        expect(find.text(submitted ? '90.00%' : '80.00%'), findsOneWidget);
        expect(find.text('100.0%'), submitted ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('team detail shows external grades without a code in either tab', (tester) async {
    tester.view.physicalSize = const Size(2400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = grade(submitted: true);
    payload['breakdowns'] = [{
      'evaluation_type': 'panel', 'criterion_name': 'Prototype',
      'student_id': 11, 'panelist_key': 'guest:3', 'evaluator_name': 'External Expert',
      'remarks': 'Strong prototype', 'score': '10', 'max_score': '10',
    }];
    final state = GradeCenterState(grades: [payload]);
    await pumpDefensysWidget(tester, GradeCenterTeamDetailScreen(
      gradeId: 1, isLocked: false, onBack: () {},
    ), overrides: [gradeCenterProvider.overrideWith(() => _Grades(state))]);
    expect(find.text('External Expert'), findsWidgets);
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('90.00%'), findsOneWidget);
    await tester.tap(find.text('Individual Rubric Breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('External Expert'), findsWidgets);
    expect(find.textContaining('Strong prototype'), findsWidgets);
    expect(find.textContaining('DEF-'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
