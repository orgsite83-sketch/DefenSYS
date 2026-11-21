import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/admin_overview_workspace.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/fake_planner_client.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  testWidgets('Initial load shows responsive skeletons; failure offers retry', (
    tester,
  ) async {
    await loadPreviewFonts(force: true);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget workspace({String? error}) => AdminOverviewWorkspace(
      data: null,
      error: error,
      loading: error == null,
      refreshing: false,
      onRefresh: () {},
      onAction: (_) {},
    );
    for (final width in [320.0, 800.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1200);
      for (final theme in [AppTheme.theme, AppTheme.mistDarkTheme]) {
        await pumpDefensysWidget(tester, workspace(), theme: theme);
        expect(
          find.byKey(const ValueKey('overview-loading-skeleton')),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Summary unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('PIT'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('overview-skeleton-card-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview-skeleton-schedule')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        // Reset the provider scope before checking the next viewport/theme.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    await pumpDefensysWidget(tester, workspace(error: 'Unavailable'));
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('overview-loading-skeleton')),
      findsNothing,
    );
  });

  testWidgets(
    'Workflow leads; readiness and attention stay beside a growing calendar',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      await loadPreviewFonts();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? selected;
      var actionCalls = 0;
      await pumpDefensysWidget(
        tester,
        AdminOverviewWorkspace(
          data: {
            'overview': {
              'missing_advisers': 1,
              'totals': {
                'capstone': {'teams': 12, 'ready': 3, 'scheduled_teams': 4},
              },
              'action_items': [
                {
                  'id': 'enrollment:1',
                  'title': 'Enrollment required',
                  'description':
                      'No students are enrolled in 1st Year this semester.',
                  'category_label': 'ENROLLMENT',
                  'button_label': 'Start enrollment',
                  'target_route':
                      '/admin/users?tab=students&view=enrollment&semester_id=1',
                },
                {
                  'id': 'team_assignment:1:capstone:3rd Year',
                  'kind': 'team_assignment',
                  'scope': 'capstone',
                  'year_level': '3rd Year',
                  'affected_count': 64,
                  'title': '3rd Year students without a team',
                  'button_label': 'Assign teams',
                  'target_route':
                      '/admin/student-teams/creation?attention=team_assignment&year_level=3rd+Year',
                },
              ],
            },
          },
          error: null,
          loading: false,
          refreshing: false,
          onRefresh: () {},
          onAction: (item) {
            selected = item;
            actionCalls++;
          },
        ),
        overrides: [
          authenticatedHttpClientProvider.overrideWithValue(
            FakePlannerClient(),
          ),
        ],
      );
      final readiness = find.byKey(const ValueKey('overview-team-readiness'));
      final schedule = find.byKey(const ValueKey('overview-defense-schedule'));
      final attention = find.byKey(const ValueKey('overview-attention'));
      final leading = find.byKey(
        const ValueKey('overview-readiness-attention'),
      );
      expect(find.text('Semester at a glance'), findsNothing);
      expect(
        tester.getRect(find.text('Semester workflow')).bottom,
        lessThan(tester.getRect(readiness).top),
      );
      expect(
        tester.getRect(readiness).bottom,
        lessThan(tester.getRect(attention).top),
      );
      expect(
        tester.getRect(attention).right,
        lessThan(tester.getRect(schedule).left),
      );
      expect(find.text('Enrollment to review'), findsOneWidget);
      expect(find.text('64 students without a team'), findsOneWidget);
      expect(find.text('3rd Year · Capstone'), findsOneWidget);
      expect(find.text('ENROLLMENT'), findsNothing);
      expect(
        tester.getSize(leading).height,
        closeTo(tester.getSize(schedule).height, 0.1),
      );
      final readinessHeight = tester.getSize(readiness).height;
      final weekHeight = tester.getSize(schedule).height;
      await capturePreview(
        tester,
        find.byType(AdminOverviewWorkspace),
        'admin-overview-aligned-week',
        viewport: true,
      );
      await tester.ensureVisible(find.text('Month'));
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(tester.getSize(schedule).height, greaterThan(weekHeight));
      expect(tester.getSize(readiness).height, closeTo(readinessHeight, 0.1));
      await tester.ensureVisible(schedule);
      await capturePreview(
        tester,
        find.byType(AdminOverviewWorkspace),
        'admin-overview-aligned-month',
        viewport: true,
      );
      await tester.ensureVisible(find.text('Week'));
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(tester.getSize(schedule).height, closeTo(weekHeight, 0.1));
      expect(tester.getSize(readiness).height, closeTo(readinessHeight, 0.1));
      final toggle = find.byKey(const ValueKey('overview-attention-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('64 students without a team'), findsNothing);
      expect(find.text('Needs your attention'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      Focus.of(tester.element(find.text('Show'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('64 students without a team'), findsOneWidget);
      for (final id in [
        'enrollment:1',
        'team_assignment:1:capstone:3rd Year',
      ]) {
        final row = find.byKey(ValueKey('overview-attention-item-$id'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final rect = tester.getRect(row);
        for (final point in [
          rect.topLeft + const Offset(4, 4),
          rect.centerRight - const Offset(4, 0),
          rect.bottomRight - const Offset(4, 4),
        ]) {
          final previousCalls = actionCalls;
          selected = null;
          await tester.tapAt(point);
          expect(selected?['id'], id);
          expect(actionCalls, previousCalls + 1);
        }
      }
      final assign = find.text('Assign teams');
      await tester.ensureVisible(assign);
      await tester.tap(assign);
      expect(selected?['target_route'], contains('year_level=3rd+Year'));
      Focus.of(tester.element(assign)).requestFocus();
      await tester.pump();
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        selected = null;
        await tester.sendKeyEvent(key);
        expect(selected?['id'], 'team_assignment:1:capstone:3rd Year');
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Unknown release counts do not show an all-clear', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      AdminOverviewWorkspace(
        data: {
          'overview': {'partial': true},
        },
        error: null,
        loading: false,
        refreshing: false,
        onRefresh: () {},
        onAction: (_) {},
      ),
      overrides: [
        authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
      ],
    );
    expect(find.text('No admin actions pending'), findsNothing);
    expect(
      find.textContaining('Some release counts are unavailable'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Workflow card padding opens each module and actions expand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? selected;
    await pumpDefensysWidget(
      tester,
      AdminOverviewWorkspace(
        data: {
          'overview': {
            'action_items': [
              for (var i = 0; i < 6; i++)
                {
                  'id': 'task$i',
                  'title': 'Issue $i',
                  'button_label': 'Fix $i',
                  'target_section': 'defenseStages',
                  'scope': 'capstone',
                },
            ],
          },
        },
        error: null,
        loading: false,
        refreshing: false,
        onRefresh: () {},
        onAction: (item) => selected = item,
      ),
      overrides: [
        authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
      ],
    );
    expect(find.text('All programs'), findsNothing);
    expect(find.text('Issue 3'), findsNothing);
    await tester.ensureVisible(find.text('View all 6 actions'));
    await tester.tap(find.text('View all 6 actions'));
    await tester.pumpAndSettle();
    expect(find.text('Issue 5'), findsOneWidget);
    for (final section in [
      'userManagement',
      'defenseStages',
      'studentTeams',
      'defenseBoardSchedules',
      'gradeCenter',
    ]) {
      final card = find.byKey(ValueKey('overview-workflow-$section'));
      await tester.ensureVisible(card);
      final rect = tester.getRect(card);
      await tester.tapAt(rect.bottomRight - const Offset(9, 9));
      expect(selected?['target_section'], section);
      Focus.of(
        tester.element(
          find.descendant(of: card, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await tester.pump();
      selected = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected?['target_section'], section);
      selected = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(selected?['target_section'], section);
    }
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 800.0, 1280.0, 1920.0]) {
    for (final dark in [false, true]) {
      testWidgets('Overview actions and scope at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (width == 390 && dark) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await loadPreviewFonts();
        Map<String, dynamic>? selected;
        final data = <String, dynamic>{
          'active_semester': '1st Semester, A.Y. 2026-2027',
          'stats': {'total_faculty': 11, 'published_grades': 99},
          'overview': {
            'semester_id': 1,
            'stage_count': 1,
            'workflow': [
              for (final card in [
                (
                  'Users',
                  '64',
                  'Enrolled students',
                  'All years · Active semester',
                  'Manage enrollment',
                  'userManagement',
                ),
                (
                  'Stage setup',
                  '0 / 1',
                  'Stages configured',
                  '1 stage missing rubrics',
                  'Needs setup',
                  'defenseStages',
                ),
                (
                  'Teams',
                  '1',
                  'Active teams',
                  'Advisers: 1 assigned',
                  'Advisers assigned',
                  'studentTeams',
                ),
                (
                  'Scheduling',
                  '0',
                  'Teams scheduled',
                  '0 ready to schedule',
                  'Waiting for teams',
                  'defenseBoardSchedules',
                ),
                (
                  'Results',
                  '0',
                  'Ready for release',
                  '0 assessments need review',
                  'No release action',
                  'gradeCenter',
                ),
              ])
                {
                  'title': card.$1,
                  'value': card.$2,
                  'label': card.$3,
                  'detail': card.$4,
                  'status': card.$5,
                  'section': card.$6,
                  'action': card.$1 == 'Stage setup',
                },
            ],
            'students': 64,
            'pit_cohorts': [
              {
                'year': '1st Year',
                'leads': ['Ricardo Fontanilla'],
                'teams': 8,
                'event_count': 2,
                'events': [
                  {
                    'event_name': 'Concept presentation',
                    'is_officially_complete': true,
                  },
                  {
                    'event_name': 'Project demonstration',
                    'is_officially_complete': false,
                  },
                ],
                'next_defense': '2026-12-03',
              },
              {
                'year': '2nd Year',
                'leads': [],
                'teams': 0,
                'event_count': 0,
                'events': [],
                'next_defense': null,
              },
              {
                'year': '3rd Year',
                'leads': [],
                'teams': null,
                'event_count': null,
                'events': null,
                'next_defense': null,
              },
            ],
            'totals': {
              'all': {'teams': 1, 'scheduled': 0, 'ready': 0},
              'capstone': {'teams': 1, 'scheduled': 0, 'ready': 0},
              'pit': {'teams': 0, 'scheduled': 0, 'ready': null},
            },
            'action_items': [
              {
                'id': 'stage_setup:7',
                'scope': 'capstone',
                'title': 'Proposal defense needs setup',
                'description': 'Attach a panel evaluation rubric.',
                'target_section': 'defenseStages',
                'target_route':
                    '/admin/defense-stages/7/edit?tab=1&semester_id=1&fromOverview=1',
                'button_label': 'Create rubrics',
              },
            ],
          },
        };
        await pumpDefensysWidget(
          tester,
          AdminOverviewWorkspace(
            data: data,
            error: null,
            loading: false,
            refreshing: false,
            onRefresh: () {},
            onAction: (item) => selected = item,
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          overrides: [
            authenticatedHttpClientProvider.overrideWithValue(
              FakePlannerClient(),
            ),
          ],
        );
        expect(find.text('0 ready to schedule'), findsNothing);
        expect(find.text('All years · Active semester'), findsNothing);
        expect(find.text('1 stage missing rubrics'), findsNothing);
        expect(find.text('Enrolled students'), findsOneWidget);
        expect(find.textContaining('Complete'), findsNothing);
        await tester.ensureVisible(find.text('Create rubrics'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create rubrics'));
        expect(selected?['target_route'], contains('/7/edit?tab=1'));
        await capturePreview(
          tester,
          find.byType(AdminOverviewWorkspace),
          'admin-overview-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.ensureVisible(find.text('PIT').first);
        await tester.tap(find.text('PIT').first);
        await tester.pumpAndSettle();
        expect(find.text('Proposal defense needs setup'), findsNothing);
        expect(
          find.text('Read-only oversight · Managed by PIT Leads'),
          findsOneWidget,
        );
        expect(find.text('Dec 3, 2026'), findsOneWidget);
        expect(find.text('Unassigned'), findsNWidgets(2));
        expect(find.text('Unavailable'), findsNWidgets(2));
        expect(find.text('View details'), findsNWidgets(3));
        final firstCard = find.byKey(const ValueKey('pit-cohort-1st Year'));
        final secondCard = find.byKey(const ValueKey('pit-cohort-2nd Year'));
        final thirdCard = find.byKey(const ValueKey('pit-cohort-3rd Year'));
        final first = tester.getRect(firstCard);
        final second = tester.getRect(secondCard);
        final third = tester.getRect(thirdCard);
        if (width >= 1280) {
          expect(first.top, second.top);
          expect(second.top, third.top);
          expect(first.right, lessThan(second.left));
          expect(second.right, lessThan(third.left));
        } else if (width == 800) {
          expect(first.top, second.top);
          expect(first.right, lessThan(second.left));
          expect(third.top, greaterThan(first.bottom));
        } else {
          expect(first.left, second.left);
          expect(second.top, greaterThan(first.bottom));
          expect(third.top, greaterThan(second.bottom));
        }
        selected = null;
        expect(find.text('Concept presentation'), findsNothing);
        final details = find.byKey(const ValueKey('pit-details-1st Year'));
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text('Concept presentation'), findsOneWidget);
        expect(find.text('Officially complete'), findsOneWidget);
        expect(find.text('Open'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(AdminOverviewWorkspace),
          'admin-pit-details-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        Focus.of(tester.element(find.text('Hide details'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Concept presentation'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('Concept presentation'), findsOneWidget);
        await tester.tap(details);
        await tester.pumpAndSettle();
        final emptyDetails = find.byKey(const ValueKey('pit-details-2nd Year'));
        await tester.ensureVisible(emptyDetails);
        await tester.tap(emptyDetails);
        await tester.pumpAndSettle();
        expect(find.text('No events configured.'), findsOneWidget);
        expect(find.text('Event details unavailable.'), findsNothing);
        await tester.tap(emptyDetails);
        await tester.pumpAndSettle();
        final unavailableDetails = find.byKey(
          const ValueKey('pit-details-3rd Year'),
        );
        await tester.ensureVisible(unavailableDetails);
        await tester.tap(unavailableDetails);
        await tester.pumpAndSettle();
        expect(find.text('Event details unavailable.'), findsOneWidget);
        expect(find.text('No events configured.'), findsNothing);
        await tester.tap(unavailableDetails);
        await tester.pumpAndSettle();
        expect(selected, isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.ensureVisible(find.text('PIT overview'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(AdminOverviewWorkspace),
          'admin-pit-overview-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Recent activity shows readable labels and opens the audit trail',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? selected;
      await pumpDefensysWidget(
        tester,
        AdminOverviewWorkspace(
          data: {
            'active_semester': '1st Semester, A.Y. 2026-2027',
            'recent_activity': [
              {
                'action': 'capstone.stage_created',
                'action_label': 'Defense stage created',
                'actor_name': 'Admin User',
                'timestamp': '2026-11-17T09:30:00+08:00',
              },
              {'action': 'rubric.create'},
            ],
          },
          error: null,
          loading: false,
          refreshing: false,
          onRefresh: () {},
          onAction: (item) => selected = item,
        ),
        overrides: [
          authenticatedHttpClientProvider.overrideWithValue(
            FakePlannerClient(),
          ),
        ],
      );
      expect(find.text('Defense stage created').hitTestable(), findsNothing);
      await tester.ensureVisible(find.text('Recent activity'));
      await tester.tap(find.text('Recent activity'));
      await tester.pumpAndSettle();
      expect(find.text('Defense stage created'), findsOneWidget);
      expect(find.text('Rubric created'), findsOneWidget);
      expect(find.textContaining('Admin User · Nov 17, 2026'), findsOneWidget);
      expect(find.text('capstone.stage_created'), findsNothing);
      expect(find.text('rubric.create'), findsNothing);
      await tester.ensureVisible(find.text('View audit trail'));
      await tester.tap(find.text('View audit trail'));
      expect(selected?['target_route'], AdminRoutes.auditCompliance);
      expect(tester.takeException(), isNull);
    },
  );
}
