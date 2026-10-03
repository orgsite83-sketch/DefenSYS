import 'package:defensys/screens/web/admin/user_management/external_evaluators/external_evaluator_views.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

const _evaluators = [
  {
    'id': 11,
    'name': 'Dr. Lina Santos',
    'institution': 'Partner University',
    'status': 'approved',
    'is_active': true,
  },
  {
    'id': 12,
    'name': 'Dr. Alex Reyes',
    'institution': 'Research Institute',
    'status': 'approved',
    'is_active': true,
  },
  {
    'id': 13,
    'name': 'Pending Expert',
    'institution': '',
    'status': 'pending',
    'is_active': true,
  },
];

Map<String, dynamic> _schedule(
  int id,
  String title,
  String team, {
  String scope = 'capstone',
  int stage = 7,
  int period = 1,
  String year = '4th Year',
  int day = 30,
  String time = '08:00:00',
}) => {
  'id': id,
  'team_name': team,
  'stage_label': title,
  'scope': scope,
  'defense_stage_id': scope == 'capstone' ? stage : null,
  'event_name': scope == 'pit' ? title : '',
  'semester_id': period,
  'display_semester': period == 1
      ? '1st Semester, A.Y. 2026-2027'
      : '2nd Semester, A.Y. 2025-2026',
  'year_level': year,
  'room': 'Room 301',
  'date': DateTime.now()
      .add(Duration(days: day))
      .toIso8601String()
      .split('T')
      .first,
  'start_time': time,
  'slot_duration': 60,
};

class _Assignments extends ExternalEvaluatorNotifier {
  _Assignments({
    this.pitOnly = false,
    this.assigned = false,
    this.fail = false,
  });
  final bool pitOnly, assigned, fail;
  int calls = 0;
  List<int>? evaluatorIds, scheduleIds;
  DateTime? expiry;

  @override
  ExternalEvaluatorState build() => ExternalEvaluatorState(
    canApprove: !pitOnly,
    activeSemesterId: 1,
    evaluators: _evaluators,
    schedules: [
      if (!pitOnly) ...[
        _schedule(101, 'Concept Proposal', 'Team SkyLedger'),
        _schedule(102, 'Concept Proposal', 'Team BioPulse', time: '09:00:00'),
        _schedule(103, 'Final Defense', 'Team SkyLedger', stage: 8, day: 60),
        _schedule(
          104,
          'Historical Proposal',
          'Archived cohort',
          period: 2,
          stage: 9,
        ),
      ],
      _schedule(
        201,
        'Concept Pitch',
        'Team Prototype',
        scope: 'pit',
        year: '1st Year',
      ),
      _schedule(
        202,
        'Prototype Demo',
        'Team Prototype',
        scope: 'pit',
        year: '1st Year',
        day: 70,
      ),
    ],
    invitations: assigned
        ? const [
            {
              'id': 1,
              'evaluator_id': 11,
              'schedule_ids': [101],
              'status': 'Active',
            },
          ]
        : const [],
  );

  @override
  Future<bool> fetch() async => true;

  @override
  Future<bool> invite(
    List<int> evaluators,
    List<int> schedules,
    DateTime expiresAt,
  ) async {
    calls++;
    evaluatorIds = evaluators;
    scheduleIds = schedules;
    expiry = expiresAt;
    if (fail) {
      state = state.copyWith(
        error: 'Selected defenses overlap. Choose different times.',
      );
      return false;
    }
    final old = state;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in old.schedules.where((s) => schedules.contains(s['id']))) {
      groups.putIfAbsent(s['stage_label'].toString(), () => []).add(s);
    }
    var number = 0;
    state = ExternalEvaluatorState(
      evaluators: old.evaluators,
      invitations: old.invitations,
      schedules: old.schedules,
      canApprove: old.canApprove,
      activeSemesterId: old.activeSemesterId,
      createdInvitations: [
        for (final evaluator in evaluators)
          for (final group in groups.values)
            {
              'id': ++number,
              'code': 'DEF-ACCESS-$number',
              'evaluator_id': evaluator,
              'guest_name': old.approved.firstWhere(
                (p) => p['id'] == evaluator,
              )['name'],
              'schedule_ids': group.map((s) => s['id']).toList(),
              'schedules': group,
              'expires_at': expiresAt.toIso8601String(),
            },
      ],
    );
    return true;
  }
}

void main() {
  setUpAll(loadPreviewFonts);
  Future<void> open(
    WidgetTester tester,
    _Assignments assignments, {
    double width = 1280,
    bool dark = false,
    int? evaluator = 11,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [externalEvaluatorProvider.overrideWith(() => assignments)],
        child: RepaintBoundary(
          key: const ValueKey('assignment-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ExternalInvitationCreateDialog.show(
                    context,
                    evaluatorId: evaluator,
                  ),
                  child: const Text('Open assignments'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open assignments'));
    await tester.pumpAndSettle();
  }

  Future<void> selectAll(WidgetTester tester) async {
    final all = find.byKey(const ValueKey('select-all-sessions'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'assigns all capstone stages from the active period and shows separate access links',
    (tester) async {
      final assignments = _Assignments();
      await open(tester, assignments);
      expect(find.text('Dr. Lina Santos'), findsOneWidget);
      expect(find.text('Historical Proposal'), findsNothing);
      await selectAll(tester);
      expect(find.text('1 evaluator · 3 defenses · 2 stages'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('confirm-external-assignments')),
      );
      await tester.pumpAndSettle();
      expect(assignments.evaluatorIds, [11]);
      expect(assignments.scheduleIds, [101, 102, 103]);
      expect(
        assignments.expiry!.isAfter(
          DateTime.parse(
            _schedule(103, '', '', day: 60)['date'],
          ).add(const Duration(hours: 9)),
        ),
        isTrue,
      );
      expect(find.text('Evaluator invitations'), findsOneWidget);
      expect(find.text('Copy invitation'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('assignment-preview')),
        'external-assignment-access-links',
      );
    },
  );

  testWidgets('PIT lead assigns every visible event in one request', (
    tester,
  ) async {
    final assignments = _Assignments(pitOnly: true);
    await open(tester, assignments);
    await selectAll(tester);
    expect(find.text('1 evaluator · 2 defenses · 2 events'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-external-assignments')),
    );
    await tester.pumpAndSettle();
    expect(assignments.scheduleIds, [201, 202]);
    expect(find.text('Copy invitation'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expanded stages allow specific teams and preserve selections while searching',
    (tester) async {
      final assignments = _Assignments();
      await open(tester, assignments);
      await tester.tap(
        find.byKey(const ValueKey('expand-capstone:4th Year:7')),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const ValueKey('search-capstone:4th Year:7')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'BioPulse');
      await tester.pumpAndSettle();
      expect(find.text('Team SkyLedger'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('defense-102')));
      await tester.tap(find.byKey(const ValueKey('defense-102')));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'Sky');
      await tester.pumpAndSettle();
      expect(find.text('1 evaluator · 1 defense · 1 stage'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('confirm-external-assignments')),
      );
      await tester.pumpAndSettle();
      expect(assignments.scheduleIds, [102]);
    },
  );

  testWidgets(
    'already assigned defenses are identified and excluded from new assignments',
    (tester) async {
      final assignments = _Assignments(assigned: true);
      await open(tester, assignments);
      await selectAll(tester);
      await tester.tap(
        find.byKey(const ValueKey('expand-capstone:4th Year:7')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Already assigned · manage their access in Invitations'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ShadCheckbox>(find.byKey(const ValueKey('defense-101')))
            .enabled,
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-external-assignments')),
      );
      await tester.pumpAndSettle();
      expect(assignments.scheduleIds, [102, 103]);
    },
  );

  testWidgets(
    'assignment error keeps selections so the coordinator can correct them',
    (tester) async {
      final assignments = _Assignments(fail: true);
      await open(tester, assignments);
      await selectAll(tester);
      await tester.tap(
        find.byKey(const ValueKey('confirm-external-assignments')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Selected defenses overlap. Choose different times.'),
        findsOneWidget,
      );
      expect(find.text('1 evaluator · 3 defenses · 2 stages'), findsOneWidget);
      expect(find.text('Assign external evaluators'), findsOneWidget);
      expect(assignments.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only approved evaluators can be selected and context changes clear defenses',
    (tester) async {
      final assignments = _Assignments();
      await open(tester, assignments, evaluator: null);
      await tester.tap(find.byType(ShadSelect<int>).first);
      await tester.pumpAndSettle();
      expect(find.text('Pending Expert'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(ShadOption<int>),
          matching: find.text('Dr. Alex Reyes'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await selectAll(tester);
      await tester.tap(find.text('PIT'));
      await tester.pumpAndSettle();
      expect(find.text('1 evaluator · 0 defenses · 0 events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'assignment dialog fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          await open(tester, _Assignments(), width: width, dark: dark);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('assignment-preview')),
            'external-assignment-start-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          await selectAll(tester);
          expect(
            find.text('1 evaluator · 3 defenses · 2 stages'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('assignment-preview')),
            'external-assignment-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
        },
      );
    }
  }
}
