import 'package:defensys/screens/web/admin/defense_board/components/schedule_manager_dialog.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_group_actions.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> entry(
  int id, {
  bool protected = false,
  bool recorded = false,
  String scope = 'capstone',
}) => {
  'id': id,
  'scope': scope,
  'team_name': id == 1 ? 'Team SkyLedger' : 'Team BioPulse',
  'stage_label': 'Concept Proposal',
  'defense_stage_id': 1,
  'session_id': id == 1 ? 'morning' : 'afternoon',
  'section': id == 1 ? 'A' : 'B',
  'year_level': '4th Year',
  'date': '2026-10-20',
  'start_time': id == 1 ? '08:00:00' : '09:00:00',
  'room': 'Room 301',
  'status': 'scheduled',
  'can_edit': true,
  'can_reschedule': !recorded,
  'revision': id,
  'can_delete': !protected,
  'blockers': protected ? ['Panel evaluations submitted.'] : [],
  'panelist_ids': id == 1 ? [101, 102] : [101],
  'panelist_names': id == 1
      ? ['Maricel Suarez', 'Jonathan Beltran']
      : ['Maricel Suarez'],
  'chair_panelist_id': 101,
  'external_evaluator_ids': [],
  'submitted_panelist_ids': recorded ? [101] : [],
};

class Board extends DefenseBoardNotifier {
  Board({this.recorded = false, this.failSave = false});
  final bool recorded, failSave;
  final List<Map<String, dynamic>> calls = [];
  @override
  DefenseBoardState build() => const DefenseBoardState();
  @override
  Future<Map<String, dynamic>> managementContext() async => {
    'entries': [entry(1), entry(2, protected: true, recorded: recorded)],
    'expected_revisions': {'1': 1, '2': 2},
    'active_semester': {'display_name': '1st Semester, A.Y. 2026–2027'},
    'panelists': people,
    'faculty': people,
    'external_evaluators': [],
  };
  static const people = [
    {'id': 101, 'name': 'Maricel Suarez'},
    {'id': 102, 'name': 'Jonathan Beltran'},
    {'id': 103, 'name': 'Elena Reyes'},
  ];
  @override
  Future<Map<String, dynamic>> operation(Map<String, dynamic> data) async {
    calls.add(data);
    if (data['action'] == 'preview_update') {
      return {
        'updated': (data['schedule_ids'] as List).length,
        'unchanged': 0,
        'entries': [
          for (final id in data['schedule_ids'])
            {
              'id': id,
              'team_name': id == 1 ? 'Team SkyLedger' : 'Team BioPulse',
              'will_change': true,
              'changes': [
                {
                  'label': 'Faculty panel',
                  'before': 'Maricel Suarez',
                  'after': 'Maricel Suarez, Elena Reyes',
                },
                if ((data['changes'] as Map).containsKey('room'))
                  {
                    'label': 'Room',
                    'before': 'Room 301',
                    'after': data['changes']['room'],
                  },
              ],
            },
        ],
      };
    }
    if (failSave) {
      throw Exception(
        'These records changed. Refresh and review the selection before saving.',
      );
    }
    return {
      'updated': (data['schedule_ids'] as List).length,
      'unchanged': 0,
      'deleted': 1,
      'protected': 1,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> scheduleHistory(
    int id, {
    bool session = false,
  }) async => [
    {
      'team_name': 'Team SkyLedger',
      'summary': 'Faculty panel updated',
      'actor': 'Admin Reyes',
      'created_at': '2026-10-04T13:00:00+08:00',
      'reason': 'Emergency replacement confirmed',
      'changes': [
        {
          'label': 'Faculty panel',
          'before': 'Maricel Suarez',
          'after': 'Maricel Suarez, Elena Reyes',
        },
      ],
    },
  ];
}

Future<void> pump(
  WidgetTester tester,
  Widget dialog,
  Board board, {
  double width = 1100,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1050);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [defenseBoardProvider.overrideWith(() => board)],
      child: RepaintBoundary(
        key: const ValueKey('manager-preview'),
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

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> input(WidgetTester t, String key, String value) async {
  final f = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(EditableText),
  );
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> select(WidgetTester t, String label, String option) async {
  final field = find.byWidgetPredicate(
    (w) => w is WorkflowSelect && w.label == label,
  );
  final f = find.descendant(
    of: field,
    matching: find.byType(ShadSelect<String>),
  );
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(ShadOption<String>, option).last);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'stage status uses the central workflow and can return to edit tabs',
    (t) async {
      final b = Board();
      await pump(
        t,
        const ScheduleManagerDialog(
          initialScope: 'stage',
          initialAction: 'status',
          initialTab: 'status',
        ),
        b,
      );
      await select(t, 'New status', 'Postponed');
      await tap(t, 'Edit schedules');
      expect(
        find.byWidgetPredicate(
          (w) => w is WorkflowSelect && w.label == 'Add panelist',
        ),
        findsOneWidget,
      );
      await tap(t, 'Change status');
      await input(
        t,
        'manager-reason',
        'The stage is postponed because the campus is closed.',
      );
      await tap(t, 'Review changes');
      expect(b.calls.single['schedule_ids'], [1, 2]);
      expect(b.calls.single['changes'], {'operation_state': 'postponed'});
    },
  );
  testWidgets(
    'central manager preserves panel drafts across tabs and reviews all changes',
    (t) async {
      final b = Board();
      await pump(t, const ScheduleManagerDialog(), b);
      expect(find.text('Manage schedules'), findsOneWidget);
      await select(t, 'Add panelist', 'Elena Reyes');
      expect(find.text('Added'), findsOneWidget);
      await tap(t, 'Room');
      await input(t, 'manager-room', 'Room 302');
      await tap(t, 'Panel');
      expect(find.text('Elena Reyes'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      await input(
        t,
        'manager-reason',
        'Additional panelist and replacement room confirmed.',
      );
      await capturePreview(
        t,
        find.byKey(const ValueKey('manager-preview')),
        'manager-pending-desktop',
      );
      await tap(t, 'Review changes');
      expect(b.calls.single['action'], 'preview_update');
      final changes = b.calls.single['changes'] as Map;
      expect(changes['panel_change'], {
        'action': 'add',
        'panelist_ids': [103],
      });
      expect(changes['room'], 'Room 302');
      expect(b.calls.single['target'], 'management_selected');
      expect(b.calls.single['expected_revisions'], {'1': 1, '2': 2});
      expect(find.text('Room 302'), findsNWidgets(2));
      await capturePreview(
        t,
        find.byKey(const ValueKey('manager-preview')),
        'manager-review-desktop',
      );
      await tap(t, 'Save changes');
      expect(b.calls.last['action'], 'update');
      expect(find.text('Changes saved'), findsOneWidget);
    },
  );
  testWidgets('section scope selects only that year and section', (t) async {
    final b = Board();
    await pump(t, const ScheduleManagerDialog(), b);
    await select(t, 'Apply to', 'An academic section');
    await select(t, 'Section', '4th Year · B');
    await select(t, 'Add panelist', 'Elena Reyes');
    await input(t, 'manager-reason', 'Panelist added for this section.');
    await tap(t, 'Review changes');
    expect(b.calls.single['schedule_ids'], [2]);
    expect(b.calls.single['expected_revisions'], {'2': 2});
  });
  testWidgets(
    'room changes require explicit exclusion and do not drop other tab drafts',
    (t) async {
      final b = Board(recorded: true);
      await pump(t, const ScheduleManagerDialog(), b);
      await select(t, 'Add panelist', 'Elena Reyes');
      await tap(t, 'Room');
      await input(t, 'manager-room', 'Room 302');
      await input(
        t,
        'manager-reason',
        'Additional room and panelist confirmed.',
      );
      expect(
        t
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Review changes'),
            )
            .enabled,
        false,
      );
      await tap(t, 'Exclude defenses with recorded evaluations');
      await tap(t, 'Review changes');
      expect(b.calls.single['schedule_ids'], [1]);
      expect(
        (b.calls.single['changes'] as Map).keys,
        containsAll(['panel_change', 'room']),
      );
    },
  );
  testWidgets(
    'removal has an undo indicator and protects submitted evaluators',
    (t) async {
      final b = Board(recorded: true);
      await pump(t, const ScheduleManagerDialog(), b);
      await select(t, 'Panel change', 'Remove panelist');
      await select(t, 'Panelist to remove', 'Jonathan Beltran');
      expect(find.text('Will be removed'), findsOneWidget);
      await tap(t, 'Undo');
      expect(find.text('Will be removed'), findsNothing);
      expect(
        find.textContaining('Submitted evaluators stay assigned'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'deletion explains recorded activity and requires eligible-only acknowledgement',
    (t) async {
      final b = Board();
      await pump(t, const ScheduleManagerDialog(), b);
      await tap(t, 'Delete schedules');
      expect(find.text('1 can be deleted'), findsOneWidget);
      expect(find.text('1 will be kept'), findsOneWidget);
      await tap(t, 'What counts as recorded activity?');
      expect(find.textContaining('Scores (including 0)'), findsOneWidget);
      await input(
        t,
        'manager-reason',
        'Duplicate schedule created during import.',
      );
      expect(
        t
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Review deletion'),
            )
            .enabled,
        false,
      );
      await tap(
        t,
        'Delete eligible schedules only. Keep 1 protected schedules.',
      );
      await tap(t, 'Review deletion');
      expect(find.text('Delete 1 schedule'), findsOneWidget);
      await tap(t, 'Delete 1 schedule');
      expect(b.calls.single['empty_only'], true);
      expect(b.calls.single['schedule_ids'], [1, 2]);
    },
  );
  testWidgets('stale save preserves drafts and provides refresh', (t) async {
    final b = Board(failSave: true);
    await pump(t, const ScheduleManagerDialog(), b);
    await select(t, 'Add panelist', 'Elena Reyes');
    await input(t, 'manager-reason', 'An additional panelist is needed.');
    await tap(t, 'Review changes');
    await tap(t, 'Save changes');
    expect(find.text('Refresh records'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    await tap(t, 'Refresh records');
    expect(find.text('Added'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'session shortcut opens the same manager with a session preselected',
    (t) async {
      final b = Board();
      await pump(
        t,
        ScheduleGroupActions(
          schedule: {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
          },
        ),
        b,
      );
      await t.tap(find.byIcon(LucideIcons.ellipsis));
      await t.pumpAndSettle();
      await tap(t, 'Edit session');
      expect(find.text('Manage schedules'), findsOneWidget);
      expect(find.text('A session'), findsOneWidget);
      await select(t, 'Add panelist', 'Elena Reyes');
      await input(
        t,
        'manager-reason',
        'Additional panelist for the morning session.',
      );
      await tap(t, 'Review changes');
      expect(b.calls.single['schedule_ids'], [1]);
    },
  );
  testWidgets('history includes author time reason and before-after values', (
    t,
  ) async {
    await pump(
      t,
      const ScheduleHistoryDialog(scheduleId: 1, session: true),
      Board(),
    );
    expect(
      find.text('Reason: Emergency replacement confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('Admin Reyes'), findsOneWidget);
    expect(find.text('Maricel Suarez, Elena Reyes'), findsOneWidget);
  });
  testWidgets('dark narrow manager fits and PIT omits documenter', (t) async {
    final b = Board();
    await pump(t, const ScheduleManagerDialog(), b, width: 390, dark: true);
    await select(t, 'Add panelist', 'Elena Reyes');
    await capturePreview(
      t,
      find.byKey(const ValueKey('manager-preview')),
      'manager-pending-mobile-dark',
    );
    expect(t.takeException(), isNull);
    await select(t, 'Defense type', 'PIT');
    expect(find.text('Documenter'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
