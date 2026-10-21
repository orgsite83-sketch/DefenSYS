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
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import '../helpers/capture_preview.dart';

class _FakeScheduler extends DefenseSchedulerNotifier {
  _FakeScheduler({this.configs = const [], this.rubrics = const [], this.peerRubrics = const []});
  final List<Map<String, dynamic>> configs;
  final List<Map<String, dynamic>> rubrics;
  final List<Map<String, dynamic>> peerRubrics;
  Map<String, dynamic>? saved;

  @override
  Future<bool> savePitEventConfig(Map<String, dynamic> payload) async {
    saved = payload;
    return true;
  }

  @override
  DefenseSchedulerState build() => DefenseSchedulerState(
    activeSemester: {'id': 1, 'display_name': '1st Semester, A.Y. 2026-2027'},
    rubrics: rubrics,
    peerRubrics: peerRubrics,
    isLoading: false,
  );

  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {
    state = state.copyWith(pitEvents: configs);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPitEventConfigs({
    int? semesterId,
  }) async => configs;
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
      {
        'label': 'Post Reflection',
        'deliverable_type': 'post',
        'required': true,
      },
    ],
  };

  Future<_FakeScheduler> openPeerSetup(WidgetTester tester, {
    Map<String, dynamic>? config,
    int tab = 1,
    Size size = const Size(1400, 1200),
    List<Map<String, dynamic>> additionalConfigs = const [],
    List<Map<String, dynamic>> rubrics = const [],
    List<Map<String, dynamic>> peerRubrics = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => loadPreviewFonts());
    final scheduler = _FakeScheduler(
      configs: [if (config != null) config, ...additionalConfigs],
      rubrics: rubrics, peerRubrics: peerRubrics,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
        defenseSchedulerProvider.overrideWith(() => scheduler),
      ],
      child: MaterialApp(theme: AppTheme.theme,
        home: const Scaffold(body: PitEventsManagementScreen())),
    ));
    await tester.pumpAndSettle();
    if (config == null) {
      await tester.tap(find.text('Add Event'));
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate((widget) => widget is TextFormField &&
        widget.controller?.text == '');
      await tester.enterText(name.first, 'New peer grading event');
    } else {
      await tester.tap(find.byKey(const ValueKey('pit-event-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit event'));
    }
    await tester.pumpAndSettle();
    if (tab > 0) {
      await tester.tap(find.text(tab == 1 ? '2. Grading & Rubrics' : '3. Deliverables'));
      await tester.pumpAndSettle();
    }
    if (tab == 1) {
      await tester.ensureVisible(find.text('Peer Evaluation Access'));
      await tester.pumpAndSettle();
    }
    return scheduler;
  }

  for (final tab in [0, 1, 2]) {
    testWidgets('PIT rename saves original event ID from step ${tab + 1}', (tester) async {
      final scheduler = await openPeerSetup(tester, config: sampleConfig, tab: 0,
        size: const Size(1100, 900));
      await tester.enterText(find.widgetWithText(TextFormField, 'System Concept Pitching'),
        'IT Innovation Poster Showcase');
      if (tab > 0) {
        await tester.tap(find.text(tab == 1 ? '2. Grading & Rubrics' : '3. Deliverables'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Save Changes'), findsOneWidget);
      await capturePreview(tester, find.byType(Dialog), 'pit-edit-save-step-${tab + 1}', viewport: true);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(scheduler.saved?['config_id'], 1);
      expect(scheduler.saved?['event_name'], 'IT Innovation Poster Showcase');
      expect(scheduler.saved?['panel_rubric_id'], 10);
      expect(scheduler.saved?['peer_rubric_id'], 20);
      expect(scheduler.saved?['deliverables'], hasLength(3));
      expect(find.text('Edit PIT Event'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saving from event details still validates other steps', (tester) async {
    final scheduler = await openPeerSetup(tester, config: {
      ...sampleConfig,
      'deliverables': [{'label': '', 'deliverable_type': 'pre', 'required': true}],
    }, tab: 0);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(scheduler.saved, isNull);
    expect(find.text('Edit PIT Event'), findsOneWidget);
    expect(find.text('Add Pre-Defense'), findsOneWidget);
    expect(find.text('Deliverable name cannot be empty (item 1).'), findsOneWidget);
    dismissFeedbackToasts();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rubric assignments refresh with scheduler before editing an event', (tester) async {
    final scheduler = await openPeerSetup(tester, config: {
      ...sampleConfig,
      'panel_rubric_id': null,
      'peer_rubric_id': null,
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The retained setup page receives the same refresh as a return from Rubrics.
    scheduler.configs[0] = {...sampleConfig};
    await scheduler.fetchSchedules();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pit-event-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Grading & Rubrics'));
    await tester.pumpAndSettle();
    final dropdowns = tester.widgetList<DropdownButtonFormField<int?>>(
      find.byType(DropdownButtonFormField<int?>),
    ).toList();
    expect(dropdowns.map((field) => field.initialValue), [10, 20]);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(scheduler.saved?['panel_rubric_id'], 10);
    expect(scheduler.saved?['peer_rubric_id'], 20);
    expect(tester.takeException(), isNull);
  });

  for (final creating in [false, true]) {
    testWidgets('PIT ${creating ? 'creation' : 'editing'} excludes old and unavailable rubric choices', (tester) async {
      List<Map<String, dynamic>> choices(String role, int currentId) {
        final rubric = {
          'id': currentId, 'name': '1st Year PIT — $role Rubric', 'scope': 'pit',
          'evaluation_type': role, 'status': 'published', 'semester_id': 1,
          'pit_event_id': 1, 'is_locked': true,
        };
        return [
          rubric,
          {...rubric, 'id': currentId + 1, 'pit_event_id': 2},
          {...rubric, 'id': currentId + 2, 'pit_event_id': null, 'is_locked': false,
            'name': 'Available $role'},
          {...rubric, 'id': currentId + 3, 'pit_event_id': null, 'semester_id': 2},
          {...rubric, 'id': currentId + 4, 'pit_event_id': null, 'status': 'draft'},
          {...rubric, 'id': currentId + 5, 'pit_event_id': null},
          {...rubric, 'id': currentId + 6, 'pit_event_id': 99, 'is_locked': false},
          {...rubric, 'id': currentId + 7, 'pit_event_id': null, 'is_locked': false},
        ];
      }
      final scheduler = await openPeerSetup(tester,
        config: creating ? null : sampleConfig,
        additionalConfigs: [
          if (creating) sampleConfig,
          {'id': 2, 'event_name': 'Completed event', 'is_locked': true,
            'panel_rubric_id': 11, 'peer_rubric_id': 21},
          {'id': 3, 'event_name': 'Another event',
            'panel_rubric_id': 17, 'peer_rubric_id': 27},
        ],
        rubrics: choices('panel', 10), peerRubrics: choices('peer', 20),
      );
      final pickers = find.byType(DropdownButtonFormField<int?>);
      final fields = tester.widgetList<DropdownButton<int?>>(
        find.descendant(of: pickers, matching: find.byType(DropdownButton<int?>)),
      ).toList();
      expect(fields[0].items!.map((item) => item.value), [null, if (!creating) 10, 12]);
      expect(fields[1].items!.map((item) => item.value), [null, if (!creating) 20, 22]);
      for (final entry in [(pickers.first, 'panel'), (pickers.last, 'peer')]) {
        await tester.ensureVisible(entry.$1);
        await tester.tap(entry.$1);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Available ${entry.$2}').last);
        await tester.pumpAndSettle();
      }
      if (creating) {
        await tester.tap(find.text('3. Deliverables'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(creating ? 'Save Configuration' : 'Save Changes'));
      await tester.pumpAndSettle();
      expect(scheduler.saved?['panel_rubric_id'], 12);
      expect(scheduler.saved?['peer_rubric_id'], 22);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('project choices belong to the roster rather than event setup', (tester) async {
    final scheduler = await openPeerSetup(tester, config: {
      ...sampleConfig, 'project_setup_policy': 'new',
    }, tab: 0);
    expect(find.text('Project requirement'), findsNothing);
    expect(find.text('Existing projects allowed'), findsNothing);
    expect(find.text('New projects required'), findsNothing);
    expect(find.byType(ConceptSettings), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(scheduler.saved, isNotNull);
    expect(scheduler.saved!.containsKey('project_setup_policy'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new event keeps access enabled before rubrics are attached', (tester) async {
    final scheduler = await openPeerSetup(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Open by Default'), findsNothing);
    expect(find.text('Enabled — students can grade their teammates after their scheduled defense finishes.'), findsOneWidget);
    expect(find.textContaining('submit peer rubrics'), findsNothing);
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Configuration'));
    await tester.pumpAndSettle();
    expect(scheduler.saved?['peer_grading_enabled'], isTrue);
    expect(scheduler.saved?['peer_rubric_id'], isNull);
    expect(scheduler.saved!.containsKey('config_id'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed event badge and evaluation guide explain the actual policy', (tester) async {
    await openPeerSetup(tester, config: {...sampleConfig, 'peer_grading_enabled': false});
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Closed'), findsWidgets);
    expect(find.text('Open by Default'), findsNothing);
    expect(find.text('Closed — students cannot grade their teammates for this event.'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsOneWidget);
    await tester.ensureVisible(find.text('Evaluation Guide'));
    await tester.tap(find.text('Evaluation Guide'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scheduling alone does not unlock peer grading.'), findsOneWidget);
    expect(find.textContaining('peer rubric is attached later'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PIT Lead saves concept selection and concept papers in the assigned year',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scheduler = _FakeScheduler(configs: [sampleConfig]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
            defenseSchedulerProvider.overrideWith(() => scheduler),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: PitEventsManagementScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pit-event-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit event'));
      await tester.pumpAndSettle();
      final conceptToggle = find.descendant(
        of: find.byType(ConceptSettings),
        matching: find.byType(ShadCheckbox),
      );
      await Scrollable.ensureVisible(tester.element(conceptToggle), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concept selection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Instructor clearance before re-defense'),
        findsOneWidget,
      );
      expect(find.text('Peer scores on repeat attempts'), findsOneWidget);
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concept Papers').last);
      await tester.pumpAndSettle();
      final policy = find.byType(DocumentPolicyEditor);
      expect(policy, findsOneWidget);
      expect(
        find.text('These document slots repeat for each required concept.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(scheduler.saved?['year_level'], '1st Year');
      expect(scheduler.saved?['concept_config'], {'required_count': 3, 'enabled': true});
      expect(
        (scheduler.saved?['deliverables'] as List).where((d) => d['file_policy']['mode'] == 'concepts'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PitEventsManagementScreen renders empty state with ShadCard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
          defenseSchedulerProvider.overrideWith(
            () => _FakeScheduler(configs: const []),
          ),
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

  testWidgets(
    'PIT events use independent numbered rows and retain the table view',
    (tester) async {
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
            defenseSchedulerProvider.overrideWith(
              () => _FakeScheduler(
                configs: [
                  sampleConfig,
                  {
                    ...sampleConfig,
                    'id': 2,
                    'event_name': 'Prototype Exhibit',
                    'panel_rubric_id': null,
                  },
                ],
              ),
            ),
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
      expect(find.text('Rubrics linked'), findsNWidgets(2));
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
      expect(
        find.text('Deliverable Checklist (2 Pre, 1 Post)'),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pit-event-rubric-status-1')),
          matching: find.text('Rubrics linked'),
        ),
        findsOneWidget,
      );
      expect(find.text('Rubrics missing'), findsOneWidget);
      expect(find.text('Attach panel evaluation rubric.'), findsNothing);
      expect(find.byTooltip('Attach panel evaluation rubric.'), findsOneWidget);
      expect(find.byIcon(LucideIcons.trash2), findsNothing);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('pit-event-setup-preview')),
        'pit-event-setup-numbered',
      );
      await tester.tap(find.text('Rubrics missing'));
      await tester.pumpAndSettle();
      expect(find.text('Attach panel evaluation rubric.'), findsOneWidget);
      await tester.tap(find.text('Prototype Exhibit'));
      await tester.pumpAndSettle();

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
    },
  );
}
