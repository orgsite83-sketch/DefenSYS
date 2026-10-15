import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/faculty/events/pit_events_management_screen.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/capture_preview.dart';

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

class _FakeDashboard extends DashboardNotifier {
  _FakeDashboard() : super('faculty');

  @override
  DashboardState build() => DashboardState(data: {'pit_lead_year': '1st Year'});
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final sampleConfig = <String, dynamic>{
    'id': 1,
    'year_level': '1st Year',
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
          dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
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

  testWidgets('PIT events use independent numbered rows and retain the table view', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loadPreviewFonts();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
          defenseSchedulerProvider.overrideWith(() => _FakeScheduler(configs: [
                sampleConfig,
                {...sampleConfig, 'id': 2, 'event_name': 'Prototype Exhibit', 'panel_rubric_id': null},
              ])),
        ],
        child: RepaintBoundary(
          key: const ValueKey('pit-event-setup-preview'),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: PitEventsManagementScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Executive Header & Buttons
    expect(find.text('PIT Event Operations & Setup'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Add Event'), findsOneWidget);

    // Consolidated KPI Stat metrics
    expect(find.text('Total events'), findsOneWidget);
    expect(find.text('Rubrics linked'), findsOneWidget);
    expect(find.text('Checklist items'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('PIT Event Lifecycle'), findsNothing);

    // View Switcher Tabs
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('Prototype Exhibit'), findsOneWidget);

    // Event Showcase Card details
    expect(find.text('System Concept Pitching'), findsOneWidget);
    expect(find.text('system-concept-pitching'), findsNWidgets(2));
    expect(find.text('Active Showcase'), findsNWidgets(2));
    expect(find.text('Peer Open'), findsNWidgets(2));
    expect(find.text('Panel: 80%'), findsNWidgets(2));
    expect(find.text('Peer: 20%'), findsNWidgets(2));
    expect(find.text('Panel Rubric'), findsNWidgets(2));
    expect(find.text('Peer Rubric'), findsNWidgets(2));
    expect(find.text('Deliverable Checklist (2 Pre, 1 Post)'), findsNWidgets(2));
    expect(find.text('Attach panel evaluation rubric.'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('pit-event-setup-preview')),
      'pit-event-setup-numbered',
    );

    final firstEventMenu = find.byKey(const ValueKey('pit-event-menu-1'));
    await tester.tap(firstEventMenu);
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Delete event'), findsOneWidget);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('pit-event-setup-preview')),
      'pit-event-actions-menu',
    );
    await tester.tap(find.text('Delete event'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Event Configuration'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(firstEventMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit event'));
    await tester.pumpAndSettle();
    expect(find.text('Edit PIT Event'), findsOneWidget);
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    expect(find.text('Copy from Event'), findsOneWidget);
    expect(find.text('Copy from Stage'), findsNothing);
    await tester.tap(find.text('Load Preset'));
    await tester.pumpAndSettle();
    expect(find.text('Concept Proposal / Title Hearing'), findsNothing);
    expect(find.textContaining('No saved presets for'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy from Event'));
    await tester.pumpAndSettle();
    expect(find.text('Prototype Exhibit (3 files)'), findsOneWidget);
    expect(find.text('System Concept Pitching (3 files)'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // Switch to Event Matrix
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('80% / 20%'), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    await tester.ensureVisible(firstEventMenu);
    await tester.pumpAndSettle();
    await tester.tap(firstEventMenu);
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Delete event'), findsOneWidget);
  });
}
