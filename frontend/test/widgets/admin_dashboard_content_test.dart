import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/admin_dashboard_content.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';

import '../helpers/pump_app.dart';

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
}
