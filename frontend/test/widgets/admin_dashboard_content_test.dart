import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/admin_dashboard_content.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';

import '../helpers/fake_planner_client.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class FakeAdminInbox extends NotificationsNotifier {
  FakeAdminInbox() : super('admin');

  @override
  NotificationsState build() => const NotificationsState();

  void receiveRequest() => state = state.copyWith(
    totalCount: 1,
    unreadCount: 1,
    notifications: [
      {
        'action_payload': {'action_kind': 'panelist_request', 'request_id': 42},
        'action': {'status': 'pending'},
      },
    ],
  );

  void readRequest() => state = state.copyWith(unreadCount: 0);

  void completeRequest() => state = state.copyWith(
    notifications: [
      {
        'action_payload': {'action_kind': 'panelist_request', 'request_id': 42},
        'action': {'status': 'completed'},
      },
    ],
  );
}

class FakeAdminDashboardNotifier extends DashboardNotifier {
  FakeAdminDashboardNotifier(super.role, {Map<String, dynamic>? initialData})
      : _mockData = initialData;

  Map<String, dynamic>? _mockData;
  int fetchCallCount = 0;

  @override
  DashboardState build() {
    return DashboardState(
      isLoading: false,
      data: _mockData,
    );
  }

  void updateMockData(Map<String, dynamic> data) {
    _mockData = data;
    state = state.copyWith(data: data);
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {
    fetchCallCount++;
    if (_mockData != null) {
      state = state.copyWith(data: _mockData, isRefreshing: false);
    }
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  FakeAcademicPeriodNotifier({Map<String, dynamic>? initialActiveSemester})
      : _initialActiveSemester = initialActiveSemester;

  final Map<String, dynamic>? _initialActiveSemester;
  int fetchCallCount = 0;

  @override
  AcademicPeriodState build() {
    return AcademicPeriodState(
      isLoading: false,
      activeSemester: _initialActiveSemester,
      schoolYears: [],
    );
  }

  void setActiveSemester(Map<String, dynamic>? semester) {
    state = state.copyWith(activeSemester: semester);
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {
    fetchCallCount++;
  }
}

void main() {
  for (final tapButton in [true, false]) {
    testWidgets(
      'Panelist approval ${tapButton ? 'button' : 'row'} opens the exact request',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        const requestRoute =
            '/admin/users?tab=faculty&view=panelists&section=requests&request=42';
        const title = '1 Panelist Request Awaiting Approval';
        final dashboard = FakeAdminDashboardNotifier('admin', initialData: {
          'active_semester': '1st Semester, A.Y. 2024-2025',
          'stats': <String, dynamic>{},
          'action_items': [
            {
              'id': 'pending_panelist_requests',
              'title': title,
              'description': 'Review faculty nominations for the approved panelist pool.',
              'category_label': 'PANELIST APPROVAL',
              'severity': 'action',
              'target_section': 'userManagement',
              'target_route': requestRoute,
              'button_label': 'Review Request',
            },
          ],
        });
        final inbox = FakeAdminInbox();
        final router = GoRouter(
          initialLocation: '/admin/overview',
          routes: [
            GoRoute(
              path: '/admin/overview',
              builder: (_, _) => Scaffold(
                body: AdminDashboardContent(
                  onNavigate: (_) => fail('The request must open its own URL.'),
                ),
              ),
            ),
            GoRoute(
              path: '/admin/users',
              builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            dashboardProvider('admin').overrideWith(() => dashboard),
            academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
            notificationsProvider('admin').overrideWith(() => inbox),
            authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
          ],
          child: MaterialApp.router(
            theme: tapButton ? AppTheme.lightTheme : AppTheme.mistDarkTheme,
            routerConfig: router,
          ),
        ));
        await tester.pumpAndSettle();

        final initialFetches = dashboard.fetchCallCount;
        inbox.receiveRequest();
        await tester.pumpAndSettle();
        expect(dashboard.fetchCallCount, greaterThan(initialFetches));
        final pendingFetches = dashboard.fetchCallCount;
        inbox.readRequest();
        await tester.pumpAndSettle();
        expect(dashboard.fetchCallCount, pendingFetches);
        inbox.completeRequest();
        await tester.pumpAndSettle();
        expect(dashboard.fetchCallCount, greaterThan(pendingFetches));
        expect(find.text(title), findsOneWidget);
        expect(find.text('PANELIST APPROVAL'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(AdminDashboardContent),
          'admin_panelist_approval_${tapButton ? 'light' : 'dark'}',
          viewport: true,
        );
        final target = find.text(tapButton ? 'Review Request' : title);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.text(requestRoute), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('AdminDashboardContent shows action item when no period is active', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockInitialData = {
      'active_semester': 'Not configured',
      'stats': {
        'total_students': 0,
        'total_faculty': 1,
        'total_teams': 0,
        'upcoming_defenses': 0,
      },
      'team_pipeline': {},
      'action_items': [
        {
          'id': 'no_active_period',
          'title': 'No Active Academic Period',
          'description': 'Activate an academic period in Academic Periods.',
          'severity': 'danger',
          'target_section': 'academicPeriods',
          'button_label': 'Configure',
        },
      ],
      'upcoming_defenses_list': [],
      'recent_activity': [],
    };

    final dashNotifier = FakeAdminDashboardNotifier('admin', initialData: mockInitialData);
    final acadNotifier = FakeAcademicPeriodNotifier();

    await pumpDefensysWidget(
      tester,
      AdminDashboardContent(
        onNavigate: (_) {},
      ),
      overrides: [
        dashboardProvider('admin').overrideWith(() => dashNotifier),
        academicPeriodProvider.overrideWith(() => acadNotifier),
        authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
      ],
    );

    // Should show Period: Not configured and No Active Academic Period
    expect(find.text('Period: Not configured'), findsOneWidget);
    expect(find.text('No Active Academic Period'), findsOneWidget);
    expect(find.text('Configure'), findsOneWidget);
  });

  testWidgets(
    'AdminDashboardContent clears action item when active semester is configured without needing full page reload',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockInitialData = {
        'active_semester': 'Not configured',
        'stats': {
          'total_students': 0,
          'total_faculty': 1,
          'total_teams': 0,
          'upcoming_defenses': 0,
        },
        'team_pipeline': {},
        'action_items': [
          {
            'id': 'no_active_period',
            'title': 'No Active Academic Period',
            'description': 'Activate an academic period in Academic Periods.',
            'severity': 'danger',
            'target_section': 'academicPeriods',
            'button_label': 'Configure',
          },
        ],
        'upcoming_defenses_list': [],
        'recent_activity': [],
      };

      final dashNotifier = FakeAdminDashboardNotifier('admin', initialData: mockInitialData);
      final acadNotifier = FakeAcademicPeriodNotifier();

      await pumpDefensysWidget(
        tester,
        AdminDashboardContent(
          onNavigate: (_) {},
        ),
        overrides: [
          dashboardProvider('admin').overrideWith(() => dashNotifier),
          academicPeriodProvider.overrideWith(() => acadNotifier),
          authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
        ],
      );

      expect(find.text('No Active Academic Period'), findsOneWidget);

      // Simulate the user configuring the semester in Academic Periods:
      acadNotifier.setActiveSemester({
        'id': 1,
        'label': '1st Semester',
        'school_year': '2024-2025',
      });
      await tester.pumpAndSettle();

      // The action item should now be immediately cleared and All Clear displayed!
      expect(find.text('No Active Academic Period'), findsNothing);
      expect(find.text('All Clear — No Pending Actions'), findsOneWidget);
      expect(find.text('Period: 1st Semester, A.Y. 2024-2025'), findsOneWidget);
    },
  );

  testWidgets('AdminDashboardContent has manual Refresh button that re-fetches dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockData = {
      'active_semester': '1st Semester, A.Y. 2024-2025',
      'stats': {
        'total_students': 10,
        'total_faculty': 2,
        'total_teams': 3,
        'upcoming_defenses': 1,
      },
      'team_pipeline': {},
      'action_items': [],
      'upcoming_defenses_list': [],
      'recent_activity': [],
    };

    final dashNotifier = FakeAdminDashboardNotifier('admin', initialData: mockData);
    final acadNotifier = FakeAcademicPeriodNotifier();

    await pumpDefensysWidget(
      tester,
      AdminDashboardContent(
        onNavigate: (_) {},
      ),
      overrides: [
        dashboardProvider('admin').overrideWith(() => dashNotifier),
        academicPeriodProvider.overrideWith(() => acadNotifier),
        authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
      ],
    );

    expect(find.text('All Clear — No Pending Actions'), findsOneWidget);

    final refreshButtons = find.text('Refresh');
    expect(refreshButtons, findsWidgets);

    final initialCalls = dashNotifier.fetchCallCount;
    await tester.tap(refreshButtons.first);
    await tester.pumpAndSettle();

    expect(dashNotifier.fetchCallCount, greaterThan(initialCalls));
  });

  testWidgets(
    'AdminDashboardContent displays expanded action items and navigates correctly',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      DefensysAdminSection? navigatedSection;

      final mockData = {
        'active_semester': '1st Semester, A.Y. 2026-2027',
        'stats': {
          'total_students': 10,
          'total_faculty': 2,
          'total_teams': 3,
          'upcoming_defenses': 0,
        },
        'team_pipeline': {},
        'action_items': [
          {
            'id': 'stages_without_rubrics',
            'title': 'Proposal Defense Stage Needs a Scoring Rubric',
            'description': 'Assign and publish scoring rubrics in Defense Stages.',
            'category_label': 'RUBRIC SETUP',
            'severity': 'danger',
            'target_section': 'defenseStages',
            'button_label': 'Configure',
          },
          {
            'id': 'stages_without_deliverables',
            'title': 'Final Defense Stage Missing Deliverables',
            'description': 'Configure pre-defense submission requirements.',
            'category_label': 'STAGE SETUP',
            'severity': 'warning',
            'target_section': 'defenseStages',
            'button_label': 'Configure',
          },
          {
            'id': 'draft_rubrics',
            'title': '2 Draft Rubrics need Publication',
            'description': 'Draft rubrics cannot be used for defense grading.',
            'category_label': 'DRAFT RUBRICS',
            'severity': 'warning',
            'target_section': 'rubrics',
            'button_label': 'Review Drafts',
          },
        ],
        'upcoming_defenses_list': [],
        'recent_activity': [],
      };

      final dashNotifier = FakeAdminDashboardNotifier('admin', initialData: mockData);
      final acadNotifier = FakeAcademicPeriodNotifier();

      await pumpDefensysWidget(
        tester,
        AdminDashboardContent(
          onNavigate: (section) {
            navigatedSection = section;
          },
        ),
        overrides: [
          dashboardProvider('admin').overrideWith(() => dashNotifier),
          academicPeriodProvider.overrideWith(() => acadNotifier),
          authenticatedHttpClientProvider.overrideWithValue(FakePlannerClient()),
        ],
      );

      expect(find.text('Proposal Defense Stage Needs a Scoring Rubric'), findsOneWidget);
      expect(find.text('RUBRIC SETUP'), findsOneWidget);
      expect(find.text('Final Defense Stage Missing Deliverables'), findsOneWidget);
      expect(find.text('STAGE SETUP'), findsOneWidget);
      expect(find.text('2 Draft Rubrics need Publication'), findsOneWidget);
      expect(find.text('DRAFT RUBRICS'), findsOneWidget);

      final reviewDraftsBtn = find.text('Review Drafts');
      expect(reviewDraftsBtn, findsOneWidget);
      await tester.tap(reviewDraftsBtn);
      await tester.pumpAndSettle();

      expect(navigatedSection, equals(DefensysAdminSection.rubrics));
    },
  );

}
