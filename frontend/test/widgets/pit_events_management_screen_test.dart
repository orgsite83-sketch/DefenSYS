import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/faculty/events/pit_events_management_screen.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/theme/app_theme.dart';

class _FakeScheduler extends DefenseSchedulerNotifier {
  _FakeScheduler({this.configs = const []});
  final List<Map<String, dynamic>> configs;

  @override
  DefenseSchedulerState build() => const DefenseSchedulerState(
        activeSemester: {'id': 1, 'display_name': '1st Semester, A.Y. 2026-2027'},
        isLoading: false,
      );

  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchPitEventConfigs({int? semesterId}) async => configs;
}

class _FakeAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        user: {'id': 1, 'role': 'faculty', 'username': 'pit_lead'},
        token: 'test',
        isRestoring: false,
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final sampleConfig = <String, dynamic>{
    'id': 1,
    'event_name': 'System Concept Pitching',
    'event_code': 'system-concept-pitching',
    'panel_weight': 80,
    'peer_weight': 20,
    'is_locked': false,
    'peer_grading_enabled': true,
    'panel_rubric_id': 10,
    'peer_rubric_id': 20,
    'deliverables': [
      {'label': 'Concept Paper', 'deliverable_type': 'pre', 'required': true},
      {'label': 'Pitch Deck', 'deliverable_type': 'pre', 'required': false},
      {'label': 'Post Reflection', 'deliverable_type': 'post', 'required': true},
    ],
  };

  testWidgets('PitEventsManagementScreen renders empty state with ShadCard', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          defenseSchedulerProvider.overrideWith(() => _FakeScheduler(configs: const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: PitEventsManagementScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PIT Event Operations & Setup'), findsOneWidget);
    expect(find.text('No PIT Events Configured'), findsOneWidget);
    expect(find.byType(ShadCard), findsWidgets);
  });

  testWidgets('PitEventsManagementScreen renders Shadcn cards, metrics, and event showcase', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          defenseSchedulerProvider.overrideWith(() => _FakeScheduler(configs: [sampleConfig])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: PitEventsManagementScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Executive Header & Buttons
    expect(find.text('PIT Event Operations & Setup'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Add Event'), findsOneWidget);

    // Consolidated KPI Stat metrics
    expect(find.text('Configured Events'), findsOneWidget);
    expect(find.text('Weight Split'), findsOneWidget);
    expect(find.text('Active Rubrics'), findsOneWidget);
    expect(find.text('Archive Templates'), findsOneWidget);

    // Lifecycle Legend Banner
    expect(find.text('PIT Event Lifecycle'), findsOneWidget);
    expect(find.text('Event & Weights'), findsOneWidget);
    expect(find.text('Rubrics & Checklists'), findsOneWidget);
    expect(find.text('Audit Lock'), findsOneWidget);

    // View Switcher Tabs
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Matrix'), findsOneWidget);

    // Event Showcase Card details
    expect(find.text('System Concept Pitching'), findsOneWidget);
    expect(find.text('system-concept-pitching'), findsOneWidget);
    expect(find.text('Active Showcase'), findsOneWidget);
    expect(find.text('Peer Open'), findsOneWidget);
    expect(find.text('Panel: 80%'), findsOneWidget);
    expect(find.text('Peer: 20%'), findsOneWidget);
    expect(find.text('Panel Rubric'), findsOneWidget);
    expect(find.text('Peer Rubric'), findsOneWidget);
    expect(find.text('Deliverable Checklist (2 Pre, 1 Post)'), findsOneWidget);

    // Switch to Event Matrix
    await tester.tap(find.text('Matrix'));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('80% / 20%'), findsNWidgets(2));
  });
}
