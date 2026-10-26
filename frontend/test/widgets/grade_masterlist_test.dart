import 'package:defensys/screens/web/admin/grade_center/grade_masterlist.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_center_team_detail_screen.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_peer_evidence.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/services/grading/grade_masterlist_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Admin extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
}

const _names = ['Alden VELASQUEZ', 'Karen EVANGELISTA', 'Alex MENDOZA'];

GradeRow _payload(String query) {
  final params = Uri.splitQueryString(query);
  final teams = params['entity'] == 'teams';
  final semester = params['coverage'] == 'semester';
  GradeRow cell(int index, int event) => {
    'assessment_key': 'pit:$event',
    'assessment_id': event,
    'grade_id': index < 2 && event == 1 ? 51 : null,
    'team': index < 2
        ? {
            'id': 10,
            'name': 'Team AlgoNest',
            'project_title': 'Academic exchange portal',
          }
        : null,
    'components': index < 2 && event == 1
        ? {
            'panel': {
              'score': 82.75,
              'weight': 80,
              'weighted': 66.20,
              'enabled': true,
            },
            'peer': {
              'score': 90,
              'weight': 20,
              'weighted': 18,
              'enabled': true,
            },
          }
        : {},
    'final_grade': index < 2 && event == 1 ? 84.20 : null,
    'status': index < 2 ? 'published' : 'no_team',
    'status_label': index < 2 ? 'Published' : 'No team',
    'is_locked': true,
    'missing_components': [],
    'outcome': '',
    'panel_required': index < 2 && event == 1 ? 2 : 0,
    'panel_submitted': index < 2 && event == 1 ? 2 : 0,
    'evaluators': index < 2 && event == 1
        ? [
            {'key': 'panel-1', 'name': 'Jonathan Beltran', 'score': 81.50},
            {'key': 'panel-2', 'name': 'Analiza Corpuz', 'score': 84.0},
          ]
        : [],
  };
  final rows = List.generate(
    teams ? 1 : 3,
    (index) => {
      'id': teams ? 10 : index + 1,
      'student_id': teams ? null : index + 1,
      'name': teams ? 'Team AlgoNest' : _names[index],
      'student_number': '2025-00${index + 1}',
      'section': 'BSIT-2A',
      'team_name': index < 2 ? 'Team AlgoNest' : 'Unassigned',
      'assessments': [cell(index, 1), if (semester) cell(index, 2)],
    },
  );
  return {
    'rows': rows,
    'total': rows.length,
    'page': 1,
    'page_size': 25,
    'context': {
      'semester_id': 7,
      'academic_period': '2025–2026 · 2nd Semester',
      'year_level': '2nd Year',
      'assessment_id': 1,
    },
    'assessments': [
      {'key': 'pit:1', 'id': 1, 'label': 'Prototype showcase'},
      if (semester) {'key': 'pit:2', 'id': 2, 'label': 'Final exhibit'},
    ],
    'options': {
      'semesters': [
        {'id': 7, 'label': '2025–2026 · 2nd Semester'},
      ],
      'assessments': [
        {
          'key': 'pit:1',
          'id': 1,
          'label': 'Prototype showcase',
          'year_level': '2nd Year',
        },
        {
          'key': 'pit:2',
          'id': 2,
          'label': 'Final exhibit',
          'year_level': '2nd Year',
        },
      ],
      'sections': ['BSIT-2A'],
      'statuses': [
        {'value': 'published', 'label': 'Published'},
      ],
    },
  };
}

class _Grades extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState(
    grades: [
      {
        'id': 51,
        'team_id': 10,
        'team_name': 'Team AlgoNest',
        'project_title': 'Academic exchange portal',
        'scope': 'pit',
        'stage_label': 'Prototype showcase',
        'status': 'published',
        'weights': {'panel': 80, 'peer': 20, 'adviser': 0},
        'panel_score': 82.75,
        'peer_score': 90,
        'final_grade': 84.2,
        'members': [
          {'student_id': 1, 'name': 'Alden VELASQUEZ', 'is_leader': true},
          {'student_id': 2, 'name': 'Karen EVANGELISTA'},
        ],
        'peer_per_student': [
          {
            'student_id': 1,
            'student_name': 'Alden VELASQUEZ',
            'panel_score': 82.75,
            'peer_score': 90,
            'final_grade': 84.2,
          },
          {
            'student_id': 2,
            'student_name': 'Karen EVANGELISTA',
            'panel_score': 85,
            'peer_score': 88,
            'final_grade': 85.6,
          },
        ],
        'breakdowns': [],
        'panelists': [],
        'panel_evaluation_scores': [],
      },
    ],
  );

  @override
  Future<bool> refreshGrade(int id) async => true;
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  List<String>? queries,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GradeMasterlist(
        groupKey: 'pit|Prototype showcase',
        scope: 'pit',
        stageLabel: 'Prototype showcase',
        initialYear: '2nd Year',
        initialSemesterId: 7,
        onBack: () {},
      ),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      authProvider.overrideWith(_Admin.new),
      gradeCenterProvider.overrideWith(_Grades.new),
      gradeMasterlistDataProvider.overrideWith((ref, query) async {
        queries?.add(query);
        return _payload(query);
      }),
    ],
  );
}

void main() {
  testWidgets(
    'continuous student rows retain pending students and full mode has no disclosure action',
    (tester) async {
      final queries = <String>[];
      await _pump(tester, queries: queries);
      expect(find.text('Alden VELASQUEZ'), findsOneWidget);
      expect(find.text('Alex MENDOZA'), findsOneWidget);
      expect(find.text('View breakdown'), findsNothing);
      await tester.tap(find.text('Full breakdown'));
      await tester.pumpAndSettle();
      expect(find.text('Panel 1'), findsOneWidget);
      expect(find.text('Panel 2'), findsOneWidget);
      expect(find.text('View breakdown'), findsNothing);
      expect(Uri.splitQueryString(queries.last)['detail_level'], 'full');
      expect(find.byType(DefensysDataTable<GradeRow>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(GradeMasterlist),
        'visualizations/grade-masterlist-implemented-full',
        viewport: true,
      );
    },
  );

  testWidgets(
    'student name opens the selected student and Back retains table mode',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Full breakdown'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Karen EVANGELISTA'));
      await tester.tap(find.text('Karen EVANGELISTA'));
      await tester.pumpAndSettle();
      final screen = tester.widget<GradeCenterTeamDetailScreen>(
        find.byType(GradeCenterTeamDetailScreen),
      );
      expect(screen.initialStudentId, 2);
      expect(screen.gradeId, 51);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(GradeCenterTeamDetailScreen));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(find.text('Panel 1'), findsOneWidget);
    },
  );

  testWidgets('unassigned student opens a read-only contextual empty state', (
    tester,
  ) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Alex MENDOZA'));
    await tester.tap(find.text('Alex MENDOZA'));
    await tester.pumpAndSettle();
    expect(find.byType(GradePendingDetails), findsOneWidget);
    expect(
      find.text(
        'This student has no team assigned for the selected assessment.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('team table and semester coverage request the selected dataset', (
    tester,
  ) async {
    final queries = <String>[];
    await _pump(tester, queries: queries);
    await tester.tap(find.text('Team Grades'));
    await tester.pumpAndSettle();
    expect(Uri.splitQueryString(queries.last)['entity'], 'teams');
    expect(find.text('Team AlgoNest'), findsOneWidget);
    final select = find.byWidgetPredicate(
      (widget) =>
          widget is ShadSelect<String> && widget.initialValue == 'assessment',
    );
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole semester').last);
    await tester.pumpAndSettle();
    expect(Uri.splitQueryString(queries.last)['coverage'], 'semester');
    expect(find.text('Final exhibit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team full mode opens the recorded team view', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Team Grades'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full breakdown'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Team AlgoNest'));
    await tester.tap(find.text('Team AlgoNest'));
    await tester.pumpAndSettle();
    final screen = tester.widget<GradeCenterTeamDetailScreen>(
      find.byType(GradeCenterTeamDetailScreen),
    );
    expect(screen.initialStudentId, isNull);
    expect(screen.gradeId, 51);
    expect(tester.takeException(), isNull);
  });

  testWidgets('received peer evidence stays scoped to the selected student', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const GradePeerEvidence(
        studentId: 1,
        evidence: [
          {
            'student_id': 1,
            'student_name': 'Alden',
            'evaluator_name': 'Karen',
            'is_self': false,
            'rating': 80,
            'criteria': [
              {'criteriaName': 'Contribution', 'score': 4, 'max': 5},
            ],
          },
          {
            'student_id': 2,
            'student_name': 'Karen',
            'evaluator_name': 'Other recipient evaluator',
            'rating': 60,
            'criteria': [],
          },
        ],
      ),
    );
    expect(find.text('Karen'), findsOneWidget);
    expect(find.text('Other recipient evaluator'), findsNothing);
    expect(find.text('4.00 / 5.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'masterlist fits $width pixels dark=$dark using neutral controls',
        (tester) async {
          await _pump(tester, width: width, dark: dark);
          expect(find.text('Student Grades'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(GradeMasterlist),
            'visualizations/grade-masterlist-implemented-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        },
      );
    }
  }
}
