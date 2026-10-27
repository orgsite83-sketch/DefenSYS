import 'package:defensys/screens/web/admin/grade_center/grade_masterlist.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_center_event_teams_screen.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_center_team_detail_screen.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_peer_evidence.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/services/grading/grade_masterlist_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
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

class _Reader extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'faculty'});
}

class _StaleSessions extends GradeMasterlistSessions {
  @override
  Map<String, Map<String, String>> build() => {
    '1|pit|pit|Prototype showcase|7|1': {
      'scope': 'capstone',
      'coverage': 'semester',
      'semester_id': '99',
      'pit_event_config_id': '99',
      'stage_label': 'Different event',
      'year_level': '4th Year',
      'entity': 'teams',
      'detail_level': 'full',
    },
  };
}

class _CapstoneGrades extends GradeCenterNotifier {
  _CapstoneGrades(this.selectedYear);
  final String selectedYear;
  @override
  GradeCenterState build() => GradeCenterState(
    activeSemester: const {'id': 7},
    yearLevel: selectedYear,
    groupSettings: const {
      'capstone|Prototype showcase': {'defense_stage_id': 4},
    },
    grades: const [
      {
        'scope': 'capstone',
        'stage_label': 'Prototype showcase',
        'year_level': '4th Year',
      },
    ],
  );
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
    activeSemester: {'id': 7},
    groupSettings: {
      'pit|Prototype showcase': {
        'pit_event_config_id': 1,
        'year_level': '2nd Year',
        'grading_total_team_count': 16,
        'grading_ready_team_count': 0,
      },
    },
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

class _WorkflowGrades extends _Grades {
  _WorkflowGrades({this.ready = false, this.complete = false});
  final bool ready, complete;
  final writes = <Map<String, dynamic>>[];
  int checks = 0;

  @override
  GradeCenterState build() {
    final original = super.build();
    return original.copyWith(
      groupSettings: {
        ...original.groupSettings,
        'pit|Prototype showcase': {
          ...original.groupSettings['pit|Prototype showcase']!,
          'grading_total_team_count': 2,
          'grading_ready_team_count': ready ? 2 : 1,
          'is_officially_complete': complete,
          'peer_grading_enabled': false,
        },
      },
    );
  }

  @override
  Future<GradeGroupCompletionReadiness> checkGroupCompletion({
    required String scope,
    required String stageLabel,
  }) async {
    checks++;
    return GradeGroupCompletionReadiness(
      totalTeams: 2,
      readyTeams: ready ? 2 : 1,
      canComplete: ready,
      incompleteTeams: ready
          ? []
          : [
              {
                'team_name': 'Hidden team missing grades',
                'missing_components': ['panel'],
              },
            ],
    );
  }

  @override
  Future<bool> updateGroupSettings({
    required String scope,
    required String stageLabel,
    bool? isOfficiallyComplete,
    bool? peerGradingEnabled,
  }) async {
    writes.add({
      'scope': scope,
      'stage_label': stageLabel,
      'is_officially_complete': isOfficiallyComplete,
      'peer_grading_enabled': peerGradingEnabled,
    });
    final key = '$scope|$stageLabel';
    state = state.copyWith(
      groupSettings: {
        ...state.groupSettings,
        key: {
          ...state.groupSettings[key]!,
          if (isOfficiallyComplete != null)
            'is_officially_complete': isOfficiallyComplete,
          if (peerGradingEnabled != null)
            'peer_grading_enabled': peerGradingEnabled,
        },
      },
    );
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  List<String>? queries,
  bool staleSession = false,
  bool eventScreen = false,
  _WorkflowGrades? workflow,
  bool reader = false,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    eventScreen
        ? GradeCenterEventTeamsScreen(
            groupKey: 'pit|Prototype showcase',
            scope: 'pit',
            stageLabel: 'Prototype showcase',
            title: 'PIT · Prototype showcase',
            onBack: () {},
            onOpenTeamDetail: (_, _) {},
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GradeMasterlist(
              groupKey: 'pit|Prototype showcase',
              scope: 'pit',
              stageLabel: 'Prototype showcase',
              initialYear: '2nd Year',
              initialSemesterId: 7,
              initialAssessmentId: 1,
              readinessSummary: 'In progress · 0 of 16 teams ready',
              onBack: () {},
            ),
          ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      authProvider.overrideWith(reader ? _Reader.new : _Admin.new),
      gradeCenterProvider.overrideWith(() => workflow ?? _Grades()),
      if (staleSession)
        gradeMasterlistSessionsProvider.overrideWith(_StaleSessions.new),
      gradeMasterlistDataProvider.overrideWith((ref, query) async {
        queries?.add(query);
        return _payload(query);
      }),
    ],
  );
}

void main() {
  for (final selectedYear in ['', '3rd Year']) {
    testWidgets(
      'Capstone event uses the selected cohort rather than the first team year: $selectedYear',
      (tester) async {
        final queries = <String>[];
        await pumpDefensysWidget(
          tester,
          GradeCenterEventTeamsScreen(
            groupKey: 'capstone|Prototype showcase',
            scope: 'capstone',
            stageLabel: 'Prototype showcase',
            title: 'Prototype showcase',
            onBack: () {},
            onOpenTeamDetail: (_, _) {},
          ),
          overrides: [
            authProvider.overrideWith(_Admin.new),
            gradeCenterProvider.overrideWith(
              () => _CapstoneGrades(selectedYear),
            ),
            gradeMasterlistDataProvider.overrideWith((ref, query) async {
              queries.add(query);
              return _payload(query);
            }),
          ],
        );
        final query = Uri.splitQueryString(queries.last);
        expect(query['scope'], 'capstone');
        expect(query['defense_stage_id'], '4');
        expect(query['year_level'] ?? '', selectedYear);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'continuous student rows retain pending students and full mode has no disclosure action',
    (tester) async {
      final queries = <String>[];
      await _pump(tester, queries: queries, eventScreen: true);
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

  testWidgets('team table stays fixed to the opened assessment', (
    tester,
  ) async {
    final queries = <String>[];
    await _pump(tester, queries: queries);
    await tester.tap(find.text('Team Grades'));
    await tester.pumpAndSettle();
    expect(Uri.splitQueryString(queries.last)['entity'], 'teams');
    expect(find.text('Team AlgoNest'), findsOneWidget);
    final query = Uri.splitQueryString(queries.last);
    expect(query['coverage'], 'assessment');
    expect(query['semester_id'], '7');
    expect(query['pit_event_config_id'], '1');
    expect(find.text('Coverage'), findsNothing);
    expect(find.text('Academic period'), findsNothing);
    expect(find.text('PIT event'), findsNothing);
    expect(find.text('Final exhibit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opened event replaces stale saved scope while preserving table mode',
    (tester) async {
      final queries = <String>[];
      await _pump(tester, queries: queries, staleSession: true);
      final query = Uri.splitQueryString(queries.last);
      expect(query['scope'], 'pit');
      expect(query['year_level'], '2nd Year');
      expect(query['semester_id'], '7');
      expect(query['pit_event_config_id'], '1');
      expect(query['coverage'], 'assessment');
      expect(query['entity'], 'teams');
      expect(query['detail_level'], 'full');
      expect(query.containsKey('stage_label'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'table workspace owns views and filters; page header owns export',
    (tester) async {
      await _pump(tester, eventScreen: true);
      final workspace = find.byKey(const ValueKey('grade-table-workspace'));
      expect(
        find.descendant(of: workspace, matching: find.text('Student Grades')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: workspace, matching: find.text('Summary')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: workspace, matching: find.byType(ShadInput)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: workspace, matching: find.byType(ReportExportMenu)),
        findsNothing,
      );
      expect(find.text('Mark Complete'), findsOneWidget);
      expect(find.text('Peer grading open'), findsOneWidget);
      expect(
        find.descendant(of: workspace, matching: find.text('Mark Complete')),
        findsNothing,
      );
      expect(
        find.descendant(of: workspace, matching: find.byType(ShadSwitch)),
        findsNothing,
      );
      expect(find.text('In progress · 0 of 16 teams ready'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
      expect(find.text('Configure export'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(DefensysDataTable<GradeRow>)).dy,
        lessThan(370),
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Export Excel'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Configure export'), findsOneWidget);
      expect(find.text('Report Center'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear filters appears when needed and preserves the event context',
    (tester) async {
      final queries = <String>[];
      await _pump(tester, queries: queries);
      expect(find.text('Clear filters'), findsNothing);
      await tester.enterText(find.byType(EditableText).first, 'Karen');
      await tester.pump();
      // An export immediately after typing must carry the visible search text.
      expect(
        tester
            .widget<ReportExportMenu>(find.byType(ReportExportMenu))
            .params['search'],
        'Karen',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(Uri.splitQueryString(queries.last)['search'], 'Karen');
      expect(find.text('Clear filters'), findsOneWidget);
      final export = tester.widget<ReportExportMenu>(
        find.byType(ReportExportMenu),
      );
      expect(export.params['search'], 'Karen');
      expect(export.params['semester_id'], '7');
      expect(export.params['pit_event_config_id'], '1');
      expect(export.params['coverage'], 'assessment');
      expect(export.params.containsKey('page'), isFalse);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Clear filters'), findsNothing);
      expect(Uri.splitQueryString(queries.last)['pit_event_config_id'], '1');
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('header peer switch updates only the opened PIT event', (
    tester,
  ) async {
    final workflow = _WorkflowGrades();
    await _pump(tester, eventScreen: true, workflow: workflow);
    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();
    expect(workflow.writes.single, {
      'scope': 'pit',
      'stage_label': 'Prototype showcase',
      'is_officially_complete': null,
      'peer_grading_enabled': true,
    });
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header completion checks hidden teams before allowing a write', (
    tester,
  ) async {
    final workflow = _WorkflowGrades();
    await _pump(tester, eventScreen: true, workflow: workflow);
    await tester.enterText(find.byType(EditableText).first, 'Visible student');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShadButton, 'Mark Complete'));
    await tester.pumpAndSettle();
    expect(workflow.checks, 1);
    expect(find.text('Hidden team missing grades'), findsOneWidget);
    expect(workflow.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed completion closes peer grading and offers Reopen', (
    tester,
  ) async {
    final workflow = _WorkflowGrades(ready: true);
    await _pump(tester, eventScreen: true, workflow: workflow);
    await tester.tap(find.widgetWithText(ShadButton, 'Mark Complete'));
    await tester.pumpAndSettle();
    expect(workflow.checks, 1);
    expect(workflow.writes, isEmpty);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete').last);
    await tester.pumpAndSettle();
    expect(workflow.writes.single, {
      'scope': 'pit',
      'stage_label': 'Prototype showcase',
      'is_officially_complete': true,
      'peer_grading_enabled': false,
    });
    expect(find.text('Reopen Event'), findsOneWidget);
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary faculty do not receive header management actions', (
    tester,
  ) async {
    await _pump(tester, eventScreen: true, reader: true);
    expect(find.text('Mark Complete'), findsNothing);
    expect(find.byType(ShadSwitch), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an already completed event keeps peer access locked', (
    tester,
  ) async {
    await _pump(
      tester,
      eventScreen: true,
      workflow: _WorkflowGrades(ready: true, complete: true),
    );
    expect(find.text('Reopen Event'), findsOneWidget);
    expect(find.text('Mark Complete'), findsNothing);
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).enabled, isFalse);
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
          await _pump(tester, width: width, dark: dark, eventScreen: true);
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
