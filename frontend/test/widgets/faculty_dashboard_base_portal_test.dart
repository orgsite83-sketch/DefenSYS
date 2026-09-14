import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/screens/web/faculty/faculty_dashboard.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/repository_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/l10n/app_localizations.dart';

class _FakeBaseFacultyDashboardNotifier extends DashboardNotifier {
  _FakeBaseFacultyDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(
      data: {
        'faculty': {'name': 'Prof. Jonathan Beltran'},
        'roles': {
          'panelist': false,
          'pit_lead': false,
          'adviser': false,
          'pit_instructor': false,
          'documenter': false,
          'uploader': false,
        },
        'active_semester': '1st Semester, A.Y. 2025-2026',
      },
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _FakePublicRepositoryNotifier extends RepositoryNotifier {
  @override
  RepositoryState build() {
    return const RepositoryState(
      isLoading: false,
      entries: [
        {
          'id': '1',
          'file_name': 'Automated_Aquaponics_Monitoring_System.pdf',
          'team_name': 'Team AquaTech',
          'uploaded_by': 'John Doe',
          'academic_year': '2025-2026',
          'status': 'Approved',
          'uploaded_at': '2026-03-01',
          'year_level': '4th Year',
          'stage': 'Final Defense',
          'type': 'capstone',
          'summary': 'IoT-enabled aquaponics system for real-time water quality monitoring.',
          'category': 'Internet of Things',
          'average_rating': 4.8,
          'ratings_count': 12,
          'reviews_count': 5,
        },
      ],
    );
  }

  @override
  Future<void> fetchForStudent({String? search}) async {}

  @override
  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? stage,
    String? academicYear,
    bool includeTeamDocuments = false,
  }) async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      user: {
        'username': 'jbeltran',
        'name': 'Prof. Jonathan Beltran',
        'role': 'faculty',
      },
    );
  }
}

class _FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(notifications: [], unreadCount: 0);

  @override
  Future<void> fetchNotifications() async {}
}

void main() {
  testWidgets('Faculty Portal base role displays public Research Repository instead of admin audit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        dashboardProvider('faculty').overrideWith(_FakeBaseFacultyDashboardNotifier.new),
        repositoryProvider.overrideWith(_FakePublicRepositoryNotifier.new),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        notificationsProvider.overrideWith(_FakeNotificationsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    final router = GoRouter(
      initialLocation: '/faculty/project-archive',
      routes: [
        GoRoute(
          path: '/faculty/project-archive',
          builder: (context, state) => PrimaryScrollController(
            controller: scrollController,
            child: const FacultyDashboard(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Brand
    expect(find.text('DefenSYS'), findsWidgets);

    // Verify Base Faculty Portal sidebar has Repository -> Research Repository
    expect(find.text('REPOSITORY'), findsOneWidget);
    expect(find.text('Research Repository'), findsOneWidget);

    // Verify public e-library repository content is rendered
    expect(find.text('USTP Research Library'), findsOneWidget);
    expect(find.text('Digital Manuscripts & Defense Archives'), findsOneWidget);
    expect(
      find.text('Institutional Research Library · Read manuscripts, view peer remarks & leave reviews.'),
      findsOneWidget,
    );

    // Verify book from public repository is visible
    expect(find.text('Team AquaTech'), findsWidgets);

    // Verify admin audit tools and controls are NOT present
    expect(find.text('Program Stage Access'), findsNothing);
    expect(find.text('Export Archive Records'), findsNothing);
    expect(find.text('Repository audit is available to admins and PIT leads.'), findsNothing);
    expect(find.text('Defense Board'), findsNothing);
    expect(find.text('Rubrics'), findsNothing);
    expect(find.text('Audit Trail'), findsNothing);

    // Verify User profile card
    expect(find.text('Prof. Jonathan Beltran'), findsOneWidget);
    expect(find.text('Faculty Portal'), findsOneWidget);
  });

  testWidgets('Faculty with other assigned roles excludes base Faculty Portal from switcher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        dashboardProvider('faculty').overrideWith(
          () => _FakeMultiRoleFacultyDashboardNotifier(),
        ),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        notificationsProvider.overrideWith(_FakeNotificationsNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    final router = GoRouter(
      initialLocation: '/faculty/dashboard',
      routes: [
        GoRoute(
          path: '/faculty/dashboard',
          builder: (context, state) => PrimaryScrollController(
            controller: scrollController,
            child: const FacultyDashboard(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Dropdown is shown with multiple assigned roles
    expect(find.byType(DropdownButton<WorkspaceOption>), findsOneWidget);

    // Verify Project Adviser and PIT Instructor exist in options
    expect(find.text('Project Adviser'), findsWidgets);

    // Open dropdown
    await tester.tap(find.byType(DropdownButton<WorkspaceOption>));
    await tester.pumpAndSettle();

    // Verify that "Faculty Portal" is NOT in the dropdown items
    expect(find.text('Faculty Portal'), findsNothing);
  });
}

class _FakeMultiRoleFacultyDashboardNotifier extends DashboardNotifier {
  _FakeMultiRoleFacultyDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(
      data: {
        'faculty': {'name': 'Prof. Jonathan Beltran'},
        'roles': {
          'panelist': false,
          'pit_lead': false,
          'adviser': true,
          'pit_instructor': true,
          'pit_instructor_sections': [
            {'year_level': '2nd Year', 'section': 'BSIT-2A'},
          ],
          'documenter': false,
          'uploader': false,
        },
        'active_semester': '1st Semester, A.Y. 2025-2026',
      },
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

