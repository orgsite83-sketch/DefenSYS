import 'dart:io';
import 'dart:ui' as ui;

import 'package:defensys/screens/web/admin/defense_board/components/schedule_operations_dialog.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_group_actions.dart';
import 'package:defensys/screens/web/admin/grade_center/grade_correction_dialog.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_action_menu.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _schedule = <String, dynamic>{
  'id': 1,
  'team_name': 'Team SkyLedger',
  'stage_label': 'Concept Proposal',
  'scope': 'capstone',
  'scheduled_date': '2026-10-04',
  'start_time': '08:00:00',
  'room': 'Room 301',
  'status': 'scheduled',
  'panelist_ids': [101, 102],
  'panelists': [
    {'id': 101, 'is_chair': true},
    {'id': 102, 'is_chair': false},
  ],
};

class _Board extends DefenseBoardNotifier {
  _Board({this.entries});
  final List<Map<String, dynamic>>? entries;
  final List<Map<String, dynamic>> calls = [];
  @override
  DefenseBoardState build() => const DefenseBoardState();
  @override
  Future<Map<String, dynamic>> operation(Map<String, dynamic> payload) async {
    calls.add(payload);
    if (payload['action'] != 'preview_delete') {
      return {'deleted': 1, 'updated': 1};
    }
    final preview = <String, dynamic>{
      'total': 2,
      'empty': 1,
      'protected': 1,
      'expected_revisions': {'1': 1, '2': 3},
      'entries': [
        {
          'id': 1,
          'team_name': 'Team SkyLedger',
          'date': '2026-10-04',
          'start_time': '08:00',
          'status': 'scheduled',
          'can_delete': true,
          'blockers': [],
        },
        {
          'id': 2,
          'team_name': 'Team BioPulse',
          'date': '2026-10-04',
          'start_time': '09:00',
          'status': 'scheduled',
          'can_delete': false,
          'blockers': ['Panel evaluations have been submitted.'],
        },
      ],
    };
    if (entries != null) {
      preview['entries'] = entries;
      preview['expected_revisions'] = {
        for (final entry in entries!)
          '${entry['id']}': entry['id'] == 2 ? 3 : 1,
      };
    }
    if (payload['target'] == 'schedule') {
      preview['entries'] = (preview['entries'] as List).take(1).toList();
      preview['expected_revisions'] = {'1': 1};
      preview['total'] = 1;
      preview['protected'] = 0;
    }
    return preview;
  }

  @override
  Future<Map<String, dynamic>> operationOptions() async => {
    'panelists': [
      {'id': 101, 'name': 'Jonathan Beltran'},
      {'id': 102, 'name': 'Maricel Suarez'},
      {'id': 103, 'name': 'Renato Villanueva'},
    ],
    'faculty': [],
    'external_evaluators': [],
  };

  @override
  Future<Map<String, dynamic>> managementContext() async {
    final preview = await operation({
      'action': 'preview_delete',
      'target': 'session',
    });
    return {
      ...await operationOptions(),
      ...preview,
      'entries': [
        for (final entry in (preview['entries'] as List))
          {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'defense_stage_id': 1,
            'session_id': 'session',
            'revision': 1,
            'panelist_ids': [101, 102],
            'year_level': '4th Year',
            'section': 'A',
            ...(entry as Map),
          },
      ],
    };
  }
}

Map<String, dynamic> _before() => {
  'team_name': 'Team SkyLedger',
  'stage_label': 'Concept Proposal',
  'panel_score': '55.00',
  'adviser_score': '95.00',
  'peer_score': '95.00',
  'final_grade': '75.00',
  'scope': 'capstone',
  'adviser_grading_enabled': true,
  'panel_score_is_override': false,
  'individual_grading': false,
  'criteria': [
    {
      'id': 1,
      'submission_id': 1,
      'evaluator': 'Jonathan Beltran',
      'student_name': 'Team',
      'criterion': 'Research methods',
      'score': '2.00',
      'max_score': '10.00',
    },
  ],
  'submissions': [
    {'id': 1, 'is_void': false},
  ],
  'students': [],
};
Map<String, dynamic> _after() => {
  ..._before(),
  'panel_score': '90.00',
  'final_grade': '92.50',
  'criteria': [
    {
      ...(_before()['criteria'] as List).first as Map<String, dynamic>,
      'score': '9.00',
    },
  ],
};

class _Grades extends GradeCenterNotifier {
  _Grades({this.pending = false, this.empty = false, this.individual = false});
  final bool pending, empty, individual;
  final List<Map<String, dynamic>> calls = [];
  @override
  GradeCenterState build() => const GradeCenterState();
  @override
  Future<Map<String, dynamic>> correctionDetails(int id) async => {
    'updated_at': '2026-10-04T05:00:00+00:00',
    'requires_approval': pending,
    'grade': {
      ..._before(),
      if (empty) ...{
        'panel_score': null,
        'adviser_score': null,
        'peer_score': null,
        'final_grade': null,
      },
      'individual_grading': individual,
    },
    'completion': {'submitted': empty ? 0 : 2, 'required': 2},
    'scores': empty
        ? []
        : [
            {
              'id': 1,
              'submission_id': 1,
              'evaluator': 'Jonathan Beltran',
              'evaluator_key': 'faculty:101',
              'evaluator_reference': 'jonathan.beltran',
              'student_id': individual ? 10 : null,
              'student': individual ? 'Ana Cruz' : 'Team',
              'criterion': 'Research methods',
              'score': '2.00',
              'max_score': '10.00',
              'is_void': false,
            },
            if (individual) ...[
              {
                'id': 2,
                'submission_id': 2,
                'evaluator': 'Jonathan Beltran',
                'evaluator_key': 'faculty:101',
                'evaluator_reference': 'jonathan.beltran',
                'student_id': 11,
                'student': 'Ben Santos',
                'criterion': 'Research methods',
                'score': '3.00',
                'max_score': '10.00',
                'is_void': false,
              },
              {
                'id': 3,
                'submission_id': 3,
                'evaluator': 'Jonathan Beltran',
                'evaluator_key': 'faculty:102',
                'evaluator_reference': 'j.beltran',
                'student_id': 10,
                'student': 'Ana Cruz',
                'criterion': 'Research methods',
                'score': '4.00',
                'max_score': '10.00',
                'is_void': false,
              },
            ],
          ],
    'history': pending
        ? [
            {
              'id': 8,
              'status': 'pending',
              'requested_by_name': 'Admin Reyes',
              'created_at': '2026-10-04 1:00 PM',
              'reason': 'Score confirmed against the signed grading sheet',
              'before': _before(),
              'after': _after(),
            },
          ]
        : [],
  };
  @override
  Future<Map<String, dynamic>> correctGrade(
    int id,
    Map<String, dynamic> payload,
  ) async {
    calls.add(payload);
    return {
      'before': _before(),
      'after': _after(),
      'requires_approval': pending,
      'status': pending ? 'pending' : 'applied',
    };
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget dialog, {
  _Board? board,
  _Grades? grades,
  bool dark = false,
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 1050);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (board != null) defenseBoardProvider.overrideWith(() => board),
        if (grades != null) gradeCenterProvider.overrideWith(() => grades),
      ],
      child: RepaintBoundary(
        key: const ValueKey('operations-preview'),
        child: MaterialApp(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => dialog),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _input(WidgetTester tester, String key, String text) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(EditableText),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('operations-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../.tmp/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _select(WidgetTester tester, String label, String choice) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is WorkflowSelect && widget.label == label,
  );
  final select = find.descendant(
    of: field,
    matching: find.byType(ShadSelect<String>),
  );
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ShadOption<String>, choice).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter');
    loader.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });
  testWidgets('mixed session deletion requires an explicit empty-only choice', (
    tester,
  ) async {
    final board = _Board();
    await _pump(
      tester,
      const ScheduleOperationsDialog(
        schedule: _schedule,
        target: 'session',
        tab: 'delete',
      ),
      board: board,
    );
    final button = tester.widget<ShadButton>(
      find.ancestor(
        of: find.text('Review changes'),
        matching: find.byType(ShadButton),
      ),
    );
    expect(button.onPressed, isNull);
    await _tap(
      tester,
      'Delete only empty schedules and keep recorded defenses',
    );
    await _input(
      tester,
      'schedule-change-reason',
      'Duplicate empty session created during import',
    );
    await _tap(tester, 'Review changes');
    expect(
      find.text('Delete 1 empty schedule and keep 1 protected record?'),
      findsOneWidget,
    );
    expect(find.textContaining('Team BioPulse · 09:00 · Keep'), findsOneWidget);
    await _capture(tester, 'schedule-delete-review');
    await _tap(tester, 'Delete schedules');
    expect(board.calls.last['target'], 'session');
    expect(board.calls.last['empty_only'], true);
    expect(board.calls.last['expected_revisions'], {'1': 1, '2': 3});
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected deletion counts only the selected defenses', (
    tester,
  ) async {
    final board = _Board();
    await _pump(
      tester,
      const ScheduleOperationsDialog(
        schedule: _schedule,
        target: 'selected',
        tab: 'delete',
      ),
      board: board,
      dark: true,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(ShadCheckbox),
        matching: find.text('Team BioPulse · 09:00'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 empty schedule can be deleted.'), findsOneWidget);
    await _input(
      tester,
      'schedule-change-reason',
      'Remove only the accidentally duplicated slot',
    );
    await _tap(tester, 'Review changes');
    await _capture(tester, 'schedule-delete-review-dark');
    await _tap(tester, 'Delete schedules');
    expect(board.calls.last['schedule_ids'], [1]);
    expect(board.calls.last['expected_revisions'], {'1': 1});
    expect(board.calls.last['empty_only'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assignment review identifies people and retains the selected scope',
    (tester) async {
      final board = _Board();
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'schedule',
          tab: 'assignments',
        ),
        board: board,
      );
      expect(find.text('Action'), findsNothing);
      expect(find.text('Affected schedules'), findsNothing);
      await _capture(tester, 'edit-panel-friendly');
      await _select(tester, 'Add panelist', 'Renato Villanueva');
      await _input(
        tester,
        'schedule-change-reason',
        'An omitted panelist was confirmed for this defense',
      );
      await _tap(tester, 'Review changes');
      expect(
        find.text('Jonathan Beltran, Maricel Suarez, Renato Villanueva'),
        findsOneWidget,
      );
      expect(find.text('Panel chair'), findsOneWidget);
      await _tap(tester, 'Save changes');
      expect(board.calls.last['changes']['panelist_ids'], [101, 102, 103]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'criterion correction requires a reason and a separate preview confirmation',
    (tester) async {
      final grades = _Grades();
      await _pump(
        tester,
        const GradeCorrectionDialog(gradeId: 1),
        grades: grades,
      );
      await _capture(tester, 'grade-correction-friendly');
      await _tap(tester, 'Review correction');
      expect(grades.calls, isEmpty);
      await _input(tester, 'grade-correction-score', '9');
      await _input(
        tester,
        'grade-correction-reason',
        'Panelist confirmed 9 on the signed grading sheet',
      );
      await _tap(tester, 'Review correction');
      expect(grades.calls.single['preview'], true);
      expect(find.text('9.00 / 10.00'), findsOneWidget);
      expect(find.text('75.00'), findsOneWidget);
      expect(find.text('92.50'), findsOneWidget);
      await _capture(tester, 'grade-correction-preview');
      await _tap(tester, 'Save correction');
      expect(grades.calls.last['preview'], false);
      expect(grades.calls.last['changes']['criterion'], {
        'id': 1,
        'score': '9',
      });
      expect(
        find.text(
          'Correction saved. The original score and reason are kept in history.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'published amendment approval requires a reason and acknowledgement',
    (tester) async {
      final grades = _Grades(pending: true);
      await _pump(
        tester,
        const GradeCorrectionDialog(gradeId: 1),
        grades: grades,
        dark: true,
        width: 560,
      );
      await _tap(tester, 'History (1 pending)');
      await _tap(tester, 'Review request');
      await _tap(tester, 'Approve correction');
      expect(grades.calls, isEmpty);
      await _input(
        tester,
        'grade-review-reason',
        'Reviewed and confirmed against the signed grading sheet',
      );
      await _tap(
        tester,
        'I reviewed the evidence and authorize this grade change.',
      );
      await _tap(tester, 'Approve correction');
      expect(grades.calls.single['action'], 'approve');
      expect(grades.calls.single['acknowledge_published_change'], true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty correction has no unnecessary form or save button', (
    tester,
  ) async {
    await _pump(
      tester,
      const GradeCorrectionDialog(gradeId: 1),
      grades: _Grades(empty: true),
      width: 390,
    );
    expect(find.text('No scores to correct yet'), findsOneWidget);
    expect(find.byType(ShadInput), findsNothing);
    expect(find.text('Review correction'), findsNothing);
    await _capture(tester, 'grade-correction-empty-mobile');
    await _tap(tester, 'History');
    expect(find.text('No corrections recorded'), findsOneWidget);
    expect(find.byType(ShadInput), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'student is selected before a criterion and changing panelist clears the score',
    (tester) async {
      final grades = _Grades(individual: true);
      await _pump(
        tester,
        const GradeCorrectionDialog(gradeId: 1),
        grades: grades,
      );
      expect(
        find.byKey(const ValueKey('grade-correction-score')),
        findsNothing,
      );
      await _select(tester, 'Panelist', 'Jonathan Beltran · j.beltran');
      // The two panelists have the same name; distinct identity remains intact.
      expect(find.text('4.00 / 10.00'), findsOneWidget);
      await _input(tester, 'grade-correction-score', '9');
      final panel = find.byWidgetPredicate(
        (widget) => widget is WorkflowSelect && widget.label == 'Panelist',
      );
      await tester.tap(
        find.descendant(of: panel, matching: find.byType(ShadSelect<String>)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ShadOption<String>,
          'Jonathan Beltran · jonathan.beltran',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('grade-correction-score')),
        findsNothing,
      );
      await _select(tester, 'Student', 'Ben Santos');
      expect(find.text('3.00 / 10.00'), findsOneWidget);
      await _input(tester, 'grade-correction-score', '8');
      await _input(
        tester,
        'grade-correction-reason',
        'Confirmed the correct student and score on the signed sheet',
      );
      await _tap(tester, 'Review correction');
      expect(grades.calls.single['changes']['criterion']['id'], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('out of range score is caught before requesting a preview', (
    tester,
  ) async {
    final grades = _Grades();
    await _pump(
      tester,
      const GradeCorrectionDialog(gradeId: 1),
      grades: grades,
    );
    await _input(tester, 'grade-correction-score', '99');
    await _input(
      tester,
      'grade-correction-reason',
      'Verified against the signed grading sheet',
    );
    await _tap(tester, 'Review correction');
    expect(grades.calls, isEmpty);
    expect(find.text('Enter a score between 0 and 10.'), findsOneWidget);
  });

  testWidgets(
    'room editing shows just the room and reason and works at mobile width',
    (tester) async {
      final board = _Board();
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'schedule',
          tab: 'room',
        ),
        board: board,
        width: 390,
      );
      expect(find.text('Change room'), findsOneWidget);
      expect(find.text('Action'), findsNothing);
      expect(find.byType(ShadCheckbox), findsNothing);
      await _input(tester, 'schedule-room', 'Room 401');
      await _input(
        tester,
        'schedule-change-reason',
        'The original room is unavailable today',
      );
      await _tap(tester, 'Review changes');
      await _capture(tester, 'schedule-room-mobile');
      await _tap(tester, 'Save changes');
      expect(board.calls.last['changes'], {'room': 'Room 401'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('more menu contains actions and closes after selecting one', (
    tester,
  ) async {
    var selected = false;
    await _pump(
      tester,
      DefensysShadcnScope(
        child: ShadDialog(
          title: const Text('Defense row'),
          child: DefensysActionMenu(
            label: 'More actions for Team SkyLedger',
            items: [
              DefensysMenuItem(
                label: 'View details',
                icon: LucideIcons.info,
                onPressed: () => selected = true,
              ),
              DefensysMenuItem(
                label: 'Edit panel',
                icon: LucideIcons.users,
                onPressed: () {},
              ),
              const DefensysMenuItem(
                label: 'Delete empty schedule',
                icon: LucideIcons.trash2,
                destructive: true,
                hint: 'Scores have been submitted.',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('View details'), findsNothing);
    expect(find.byIcon(LucideIcons.info), findsNothing);
    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);
    expect(find.text('Edit panel'), findsOneWidget);
    final trigger = tester.getRect(find.byIcon(LucideIcons.ellipsis));
    final item = tester.getRect(
      find.widgetWithText(ShadContextMenuItem, 'View details'),
    );
    expect(item.top, greaterThan(trigger.bottom));
    expect(item.right, lessThanOrEqualTo(trigger.right + 16));
    final deletion = tester.widget<ShadContextMenuItem>(
      find.widgetWithText(ShadContextMenuItem, 'Delete empty schedule'),
    );
    expect(deletion.enabled, false);
    await _capture(tester, 'defense-more-menu');
    await _tap(tester, 'View details');
    expect(selected, true);
    expect(find.text('View details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session editing excludes completed defenses and keeps submitted panelists',
    (tester) async {
      final board = _Board(
        entries: [
          {
            'id': 1,
            'team_name': 'Team SkyLedger',
            'date': '2026-10-04',
            'start_time': '08:00',
            'status': 'scheduled',
            'can_edit': true,
            'submitted_panelist_ids': [101],
            'panelist_names': ['Jonathan Beltran', 'Maricel Suarez'],
          },
          {
            'id': 2,
            'team_name': 'Team BioPulse',
            'date': '2026-10-04',
            'start_time': '09:00',
            'status': 'done',
            'can_edit': false,
            'submitted_panelist_ids': [103],
          },
        ],
      );
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'session',
          tab: 'panel',
        ),
        board: board,
      );
      expect(
        find.text('1 defense in this session will be updated.'),
        findsOneWidget,
      );
      expect(
        find.text('Evaluation submitted · assignment kept'),
        findsOneWidget,
      );
      final remove = tester.widget<ShadButton>(
        find
            .descendant(
              of: find.byType(Tooltip),
              matching: find.byWidgetPredicate(
                (widget) => widget is ShadButton && !widget.enabled,
              ),
            )
            .first,
      );
      expect(remove.onPressed, isNull);
      await _select(tester, 'Add panelist', 'Renato Villanueva');
      await _input(
        tester,
        'schedule-change-reason',
        'Add the missing panelist to the unfinished defense',
      );
      await _tap(tester, 'Review changes');
      await _tap(tester, 'Save changes');
      expect(board.calls.last['target'], 'selected');
      expect(board.calls.last['schedule_ids'], [1]);
      expect(board.calls.last['expected_revisions'], {'1': 1});
      expect(board.calls.last['changes']['panelist_ids'], contains(101));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resume session includes cancelled schedules', (tester) async {
    final board = _Board(
      entries: [
        {
          'id': 1,
          'team_name': 'Team SkyLedger',
          'start_time': '08:00',
          'status': 'scheduled',
          'can_edit': true,
        },
        {
          'id': 2,
          'team_name': 'Team BioPulse',
          'start_time': '09:00',
          'status': 'cancelled',
          'can_edit': true,
        },
      ],
    );
    await _pump(
      tester,
      const ScheduleOperationsDialog(
        schedule: _schedule,
        target: 'session',
        tab: 'normal',
      ),
      board: board,
    );
    expect(
      find.text('2 defenses in this session will be updated.'),
      findsOneWidget,
    );
    await _input(
      tester,
      'schedule-change-reason',
      'The emergency is resolved and both defenses can proceed',
    );
    await _tap(tester, 'Review changes');
    await _tap(tester, 'Save changes');
    expect(board.calls.last['schedule_ids'], [1, 2]);
    expect(board.calls.last['changes'], {
      'operation_state': 'normal',
      'status': 'scheduled',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recorded evaluations explain why room and time cannot be edited',
    (tester) async {
      final board = _Board(
        entries: [
          {
            'id': 1,
            'team_name': 'Team SkyLedger',
            'start_time': '08:00',
            'status': 'scheduled',
            'can_edit': true,
            'can_reschedule': false,
          },
        ],
      );
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'schedule',
          tab: 'room',
        ),
        board: board,
      );
      expect(find.text('No eligible defenses'), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-room')), findsNothing);
      final save = tester.widget<ShadButton>(
        find.widgetWithText(ShadButton, 'Review changes'),
      );
      expect(save.enabled, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing session status updates eligibility for cancelled defenses',
    (tester) async {
      final board = _Board(
        entries: [
          {
            'id': 1,
            'team_name': 'Team SkyLedger',
            'start_time': '08:00',
            'status': 'scheduled',
            'can_edit': true,
          },
          {
            'id': 2,
            'team_name': 'Team BioPulse',
            'start_time': '09:00',
            'status': 'cancelled',
            'can_edit': true,
          },
        ],
      );
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'session',
          tab: 'status',
        ),
        board: board,
      );
      await _select(tester, 'New status', 'Paused');
      expect(
        find.text('1 defense in this session will be updated.'),
        findsOneWidget,
      );
      await _select(tester, 'New status', 'Resume');
      expect(
        find.text('2 defenses in this session will be updated.'),
        findsOneWidget,
      );
      await _select(tester, 'New status', 'Paused');
      await _input(
        tester,
        'schedule-change-reason',
        'Pause the active defense while the replacement panelist arrives',
      );
      await _tap(tester, 'Review changes');
      await _tap(tester, 'Save changes');
      expect(board.calls.last['schedule_ids'], [1]);
      expect(board.calls.last['changes'], {'operation_state': 'paused'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('session menu has three actions and opens the tabbed editor', (
    tester,
  ) async {
    final board = _Board();
    await _pump(
      tester,
      const DefensysShadcnScope(
        child: ShadDialog(
          title: Text('Session'),
          child: ScheduleGroupActions(schedule: _schedule),
        ),
      ),
      board: board,
    );
    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.byType(ShadContextMenuItem), findsNWidgets(3));
    expect(find.text('Edit session'), findsOneWidget);
    expect(find.text('Change status'), findsOneWidget);
    expect(find.text('Delete schedules'), findsOneWidget);
    expect(find.text('Delete empty stage schedules'), findsNothing);
    await _capture(tester, 'session-three-actions');
    await _tap(tester, 'Edit session');
    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('Documenter'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    await _capture(tester, 'session-tabbed-editor');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stage editing spans eligible sessions and saves only the current tab',
    (tester) async {
      final board = _Board(
        entries: [
          {
            'id': 1,
            'team_name': 'Team SkyLedger',
            'date': '2026-10-04',
            'start_time': '08:00',
            'session_id': 'first',
            'status': 'scheduled',
            'can_edit': true,
            'room': 'Room 301',
          },
          {
            'id': 2,
            'team_name': 'Team BioPulse',
            'date': '2026-10-05',
            'start_time': '09:00',
            'session_id': 'second',
            'status': 'scheduled',
            'can_edit': true,
            'room': 'Room 302',
          },
          {
            'id': 3,
            'team_name': 'Team Complete',
            'date': '2026-10-04',
            'start_time': '10:00',
            'session_id': 'third',
            'status': 'done',
            'can_edit': false,
          },
        ],
      );
      await _pump(
        tester,
        const ScheduleOperationsDialog(
          schedule: _schedule,
          target: 'stage',
          tab: 'edit',
        ),
        board: board,
      );
      expect(find.text('Edit stage schedules'), findsOneWidget);
      expect(find.text('2 sessions affected'), findsOneWidget);
      expect(board.calls.first['target'], 'stage');
      await _select(tester, 'Add panelist', 'Renato Villanueva');
      await _tap(tester, 'Room');
      await _input(tester, 'schedule-room', 'Room 401');
      await _input(
        tester,
        'schedule-change-reason',
        'Use the replacement room for the remaining stage defenses',
      );
      await _tap(tester, 'Review changes');
      expect(
        find.text('Team SkyLedger: Room 301\nTeam BioPulse: Room 302'),
        findsOneWidget,
      );
      await _capture(tester, 'stage-change-review');
      await _tap(tester, 'Save changes');
      expect(board.calls.last['target'], 'stage_selected');
      expect(board.calls.last['schedule_ids'], [1, 2]);
      expect(board.calls.last['expected_revisions'], {'1': 1, '2': 3});
      expect(board.calls.last['changes'], {'room': 'Room 401'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stage tabs recalculate eligibility for recorded evaluations', (
    tester,
  ) async {
    final board = _Board(
      entries: [
        {
          'id': 1,
          'team_name': 'Team SkyLedger',
          'date': '2026-10-04',
          'start_time': '08:00',
          'session_id': 'first',
          'status': 'scheduled',
          'can_edit': true,
          'can_reschedule': true,
        },
        {
          'id': 2,
          'team_name': 'Team BioPulse',
          'date': '2026-10-05',
          'start_time': '09:00',
          'session_id': 'second',
          'status': 'scheduled',
          'can_edit': true,
          'can_reschedule': false,
        },
      ],
    );
    await _pump(
      tester,
      const ScheduleOperationsDialog(
        schedule: _schedule,
        target: 'stage',
        tab: 'edit',
      ),
      board: board,
      width: 390,
      dark: true,
    );
    expect(
      find.text('2 defenses in this stage will be updated.'),
      findsOneWidget,
    );
    await _tap(tester, 'Time');
    expect(
      find.text('1 defense in this stage will be updated.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-shift-minutes')),
      findsOneWidget,
    );
    await _capture(tester, 'stage-tabs-mobile-dark');
    await _tap(tester, 'Panel');
    expect(
      find.text('2 defenses in this stage will be updated.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage header groups sessions without repeated stage actions', (
    tester,
  ) async {
    final board = _Board();
    await _pump(
      tester,
      const DefensysShadcnScope(
        child: ShadDialog(
          title: Text('Defense schedules'),
          child: StageScheduleHeader(
            schedule: _schedule,
            sessionCount: 2,
            canManage: true,
          ),
        ),
      ),
      board: board,
      width: 390,
    );
    expect(find.text('Concept Proposal'), findsOneWidget);
    expect(find.text('Capstone stage · 2 sessions shown'), findsOneWidget);
    expect(find.text('Stage actions'), findsNothing);
    expect(find.byIcon(LucideIcons.ellipsis), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT session editor omits the documenter tab', (tester) async {
    await _pump(
      tester,
      ScheduleOperationsDialog(
        schedule: {..._schedule, 'scope': 'pit'},
        target: 'session',
        tab: 'edit',
      ),
      board: _Board(),
      width: 390,
    );
    expect(find.text('Documenter'), findsNothing);
    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
