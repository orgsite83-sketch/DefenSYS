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
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:defensys/widgets/repository/shared_deliverables_editor.dart';
import 'package:defensys/widgets/setup/setup_requirement_panels.dart';
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
      {'label': 'Concept Paper', 'deliverable_type': 'pre', 'required': true,
        'file_format': 'pdf', 'is_defense_material': true},
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
    bool dark = false,
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
      child: MaterialApp(theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
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
      await tester.ensureVisible(find.text('Allow peer evaluation'));
      await tester.pumpAndSettle();
    }
    return scheduler;
  }

  for (final size in [const Size(1440, 1200), const Size(360, 1100)]) {
    for (final dark in [false, true]) {
      testWidgets('shared requirements belong inside their pre/post section at ${size.width} dark=$dark', (tester) async {
        final scheduler = await openPeerSetup(tester, tab: 2, size: size, dark: dark, config: {
          ...sampleConfig,
          'shared_deliverables': [
            {'deliverable_id': 'SHARED_PRE', 'label': 'Shared proposal', 'deliverable_type': 'pre',
              'required': true, 'file_format': 'pdf', 'file_policy': {'mode': 'single'}},
            {'deliverable_id': 'SHARED_POST', 'label': 'Shared final report', 'deliverable_type': 'post',
              'required': true, 'file_format': 'pdf', 'file_policy': {'mode': 'single'}},
          ],
        });
        final pre = find.byKey(const ValueKey('pre-defense-deliverables-section'));
        final post = find.byKey(const ValueKey('post-defense-deliverables-section'));
        final preShared = find.descendant(of: pre, matching: find.byType(SharedDeliverablesEditor));
        final postShared = find.descendant(of: post, matching: find.byType(SharedDeliverablesEditor));
        expect(preShared, findsOneWidget);
        expect(postShared, findsOneWidget);
        for (final section in [pre, post]) {
          expect((tester.widget<Container>(section).decoration as BoxDecoration).color,
            dark ? DefensysTokens.mistSurface : DefensysTokens.surface);
        }
        expect(tester.widget<SharedDeliverablesEditor>(preShared).deliverableType, 'pre');
        expect(tester.widget<SharedDeliverablesEditor>(postShared).deliverableType, 'post');
        expect(find.text('Pre-defense: 3'), findsOneWidget);
        expect(find.text('Post-defense: 2'), findsOneWidget);

        final expand = find.descendant(of: preShared, matching: find.text('Shared system deliverables'));
        await tester.ensureVisible(expand);
        await tester.tap(expand);
        await tester.pumpAndSettle();
        final summary = find.descendant(of: preShared, matching: find.text('Shared proposal'));
        await tester.ensureVisible(summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('shared-name-SHARED_PRE'));
        await tester.ensureVisible(name);
        final nameInput = find.descendant(of: name, matching: find.byType(TextField));
        expect(tester.widget<TextField>(nameInput).decoration?.labelText, 'Pre-Defense Requirement Name *');
        final options = find.descendant(of: preShared, matching: find.text('More options'));
        if (size.width >= 1000) {
          expect((tester.getRect(name).center.dy - tester.getRect(options).center.dy).abs(), lessThan(2));
        } else {
          expect(tester.getRect(options).top, greaterThan(tester.getRect(name).bottom));
        }
        await capturePreview(tester, find.byType(Dialog),
          'shared-setup-nested-${size.width.toInt()}-${dark ? 'dark' : 'light'}', viewport: true);
        expect(tester.takeException(), isNull);

        if (size.width >= 1000 && !dark) {
          await tester.enterText(name, 'Section proposal');
          final done = find.descendant(of: preShared, matching: find.text('Done editing'));
          await tester.ensureVisible(done);
          await tester.tap(done);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('shared-name-SHARED_PRE')), findsNothing);
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();
          final shared = (scheduler.saved?['shared_deliverables'] as List).cast<Map>();
          expect(shared.first['label'], 'Section proposal');
          expect(shared.last['deliverable_type'], 'post');
          expect((scheduler.saved?['deliverables'] as List).cast<Map>().first['label'], 'Concept Paper');
        }
      });
    }
  }

  for (final dark in [false, true]) {
    testWidgets('PIT grading uses shared controls and saves balanced weights dark=$dark', (tester) async {
      Map<String, dynamic> rubric(String role, int id) => {
        'id': id, 'name': 'PIT $role rubric', 'scope': 'pit',
        'evaluation_type': role, 'status': 'published', 'semester_id': 1,
      };
      final scheduler = await openPeerSetup(tester, config: sampleConfig, dark: dark,
        size: const Size(1100, 1000), rubrics: [rubric('panel', 10)], peerRubrics: [rubric('peer', 20)]);
      await capturePreview(tester, find.byType(Dialog), 'grading-pit-dialog-${dark ? 'dark' : 'light'}', viewport: true);
      await tester.enterText(find.byKey(const ValueKey('panel-weight')), '70');
      await tester.pumpAndSettle();
      expect(tester.widget<ShadInput>(find.byKey(const ValueKey('peer-weight'))).controller!.text, '30');
      expect(find.text('Total 100%'), findsOneWidget);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(scheduler.saved?['panel_weight'], 70);
      expect(scheduler.saved?['peer_weight'], 30);
      expect(scheduler.saved?['panel_rubric_id'], 10);
      expect(scheduler.saved?['peer_rubric_id'], 20);
      expect(tester.takeException(), isNull);
    });
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

  testWidgets('assigned draft names remain visible outside published choices', (tester) async {
    await openPeerSetup(tester, config: {
      ...sampleConfig,
      'panel_rubric_name': '2nd Year PIT — Panel Rubric',
      'peer_rubric_name': 'PIT — Peer Rubric',
    });
    expect(find.text('2nd Year PIT — Panel Rubric'), findsOneWidget);
    expect(find.text('PIT — Peer Rubric'), findsOneWidget);
    // Assigned drafts are displayed without adding them to selectable options.
    for (final select in tester.widgetList<ShadSelect<int>>(find.byType(ShadSelect<int>))) {
      expect(select.options!.whereType<ShadOption<int>>().map((option) => option.value), [0]);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pit-event-requirements-1')));
    await tester.pumpAndSettle();
    expect(find.text('2nd Year PIT — Panel Rubric'), findsOneWidget);
    expect(find.text('PIT — Peer Rubric'), findsOneWidget);
    expect(find.text('Unknown Rubric'), findsNothing);
    expect(find.text('Selected rubric (unavailable)'), findsNothing);
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
    final dropdowns = tester.widgetList<ShadSelect<int>>(
      find.byType(ShadSelect<int>),
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
      final pickers = find.byType(ShadSelect<int>);
      final fields = tester.widgetList<ShadSelect<int>>(pickers).toList();
      expect(fields[0].options!.whereType<ShadOption<int>>().map((item) => item.value), [0, if (!creating) 10, 12]);
      expect(fields[1].options!.whereType<ShadOption<int>>().map((item) => item.value), [0, if (!creating) 20, 22]);
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
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(find.text('Open by Default'), findsNothing);
    expect(find.text('Opens after all panelists submit evaluations.'), findsOneWidget);
    expect(find.text('Select a peer rubric.'), findsOneWidget);
    expect(find.text('Evaluation Guide'), findsNothing);
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

  testWidgets('peer access toggles without redundant badges or guide', (tester) async {
    await openPeerSetup(tester, config: {...sampleConfig, 'peer_grading_enabled': false});
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
    expect(find.text('Opens after all panelists submit evaluations.'), findsNothing);
    expect(find.text('Evaluation Guide'), findsNothing);
    await tester.tap(find.byType(ShadSwitch));
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(find.text('Opens after all panelists submit evaluations.'), findsOneWidget);
    expect(find.text('Enabled'), findsNothing);
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
      await tester.tap(find.text('1. Event Details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Concept selection'));
      await tester.tap(find.text('Concept selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      expect(find.text('Concept Papers'), findsNothing);
      expect(find.text('Approved Concept Paper'), findsNothing);
      expect(find.text('Pitch Deck'), findsWidgets);
      expect(find.text('Post Reflection'), findsWidgets);
      await tester.tap(find.text('1. Event Details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Concept selection'));
      await tester.tap(find.text('Concept selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(scheduler.saved?['year_level'], '1st Year');
      expect(scheduler.saved?['concept_config'], {'required_count': 3, 'enabled': true, 'review_policy': 'always'});
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

  testWidgets('PIT overview preserves zero-weight peer configuration', (tester) async {
    await openPeerSetup(tester, config: {
      ...sampleConfig, 'panel_weight': 100, 'peer_weight': 0,
      'peer_rubric_id': null, 'peer_grading_enabled': true,
    }, tab: 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final metadata = find.byKey(const ValueKey('pit-event-metadata-1'));
    expect(tester.widgetList<Text>(find.descendant(of: metadata, matching: find.byType(Text)))
      .map((text) => text.data), ['1 rubric attached', '2 pre-defense · 1 post-defense']);
    expect(find.text('Peer Open'), findsNothing);
    expect(find.text('Peer Closed'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pit-event-requirements-1')));
    await tester.pumpAndSettle();
    final peer = tester.widgetList<SetupRubricCard>(find.byType(SetupRubricCard))
      .singleWhere((card) => card.role == 'peer');
    expect(peer.isRequired, isFalse);
    expect(find.text('Not required for current grading settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 640.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('PIT event requirements fit $width wide dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() => loadPreviewFonts(force: true));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(_FakeAuth.new),
              dashboardProvider('faculty').overrideWith(_FakeDashboard.new),
              defenseSchedulerProvider.overrideWith(
                () => _FakeScheduler(
                  rubrics: [
                    {'id': 10, 'name': 'Pitch evaluation'},
                  ],
                  peerRubrics: [
                    {'id': 20, 'name': 'Team collaboration'},
                  ],
                  configs: [
                    {
                      ...sampleConfig,
                      'event_name':
                          'System Concept Pitching and Academic Innovation Showcase',
                      'deliverables': [
                        ...sampleConfig['deliverables'] as List,
                        {
                          'label': 'Archived event portfolio',
                          'deliverable_type': 'vault',
                          'required': true,
                        },
                      ],
                    },
                    {
                      ...sampleConfig,
                      'id': 2,
                      'event_name': 'Prototype Exhibit',
                      'is_locked': true,
                      'lock_reason': 'This PIT event has recorded evaluations.',
                      'peer_grading_enabled': false,
                      'panel_rubric_id': null,
                      'peer_rubric_id': null,
                      'deliverables': [],
                    },
                  ],
                ),
              ),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
              home: const Scaffold(body: PitEventsManagementScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('01'), findsOneWidget);
        expect(find.text('02'), findsOneWidget);
        expect(find.text('Active Showcase'), findsNothing);
        expect(find.text('2 pre-defense · 2 post-defense'), findsOneWidget);
        expect(find.text('Peer Closed'), findsOneWidget);
        expect(find.byKey(const ValueKey('pit-event-menu-2')), findsNothing);
        expect(find.text('View'), findsOneWidget);
        expect(
          find.text('This PIT event has recorded evaluations.'),
          findsOneWidget,
        );
        expect(find.text('Panel: 80%'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'pit-event-directory-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );

        final requirements = find.byKey(
          const ValueKey('pit-event-requirements-1'),
        );
        await tester.ensureVisible(requirements);
        await tester.tap(requirements);
        await tester.pumpAndSettle();
        expect(find.text('Concept Paper'), findsOneWidget);
        expect(find.text('Archived event portfolio'), findsOneWidget);
        expect(find.text('Panel evaluation'), findsOneWidget);
        expect(find.text('Pitch evaluation'), findsOneWidget);
        expect(find.text('Team collaboration'), findsOneWidget);
        expect(find.text('PDF · Visible to panelists'), findsOneWidget);
        expect(
          tester
              .widgetList<SetupRubricCard>(find.byType(SetupRubricCard))
              .map((card) => card.role),
          ['panel', 'peer'],
        );
        expect(find.byType(SetupRequirementGroup), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('pit-event-card-1')),
        );
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'pit-event-directory-expanded-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );

        await tester.ensureVisible(requirements);
        await tester.tap(requirements);
        await tester.pumpAndSettle();
        expect(find.text('Concept Paper'), findsNothing);
        final lockedRequirements = find.byKey(
          const ValueKey('pit-event-requirements-2'),
        );
        await tester.ensureVisible(lockedRequirements);
        await tester.tap(lockedRequirements);
        await tester.pumpAndSettle();
        expect(find.text('Rubric required'), findsNWidgets(2));
        expect(find.text('No requirements configured'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('pit-event-card-2')));
        await tester.pumpAndSettle();
        await capturePreview(tester, find.byType(Scaffold),
          'pit-event-directory-missing-${width.toInt()}-${dark ? 'dark' : 'light'}', viewport: true);
        expect(find.text('Table'), findsNothing);
        expect(find.text('Events'), findsNothing);
        expect(find.byType(ShadTabs<String>), findsNothing);
        expect(find.byType(DataTable), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'PIT events use independent cards without view tabs or a table',
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

      expect(find.text('Events'), findsNothing);
      expect(find.text('Table'), findsNothing);
      expect(find.byType(ShadTabs<String>), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('Prototype Exhibit'), findsOneWidget);

      // Event Showcase Card details
      expect(find.text('System Concept Pitching'), findsOneWidget);
      expect(find.text('system-concept-pitching'), findsNWidgets(2));
      expect(find.text('Active Showcase'), findsNothing);
      expect(find.text('Peer Open'), findsNWidgets(2));
      expect(find.text('Panel: 80%'), findsNothing);
      expect(find.text('Peer: 20%'), findsNothing);
      expect(find.text('Panel Rubric'), findsNothing);
      expect(find.text('Peer Rubric'), findsNothing);
      expect(find.text('2 rubrics attached'), findsOneWidget);
      expect(find.text('1 rubric attached'), findsOneWidget);
      expect(find.text('2 pre-defense · 1 post-defense'), findsNWidgets(2));
      expect(find.text('View requirements'), findsNWidgets(2));
      final firstMetadata = find.byKey(const ValueKey('pit-event-metadata-1'));
      final tiles = find.descendant(of: firstMetadata, matching: find.byType(Text));
      expect(tester.widgetList<Text>(tiles).map((text) => text.data), [
        '2 rubrics attached', '2 pre-defense · 1 post-defense', 'Peer Open',
      ]);
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
        'pit-event-setup-cards',
      );
      await tester.tap(find.text('Rubrics missing'));
      await tester.pumpAndSettle();
      expect(find.text('Attach panel evaluation rubric.'), findsOneWidget);
      await tester.tap(find.text('Prototype Exhibit'));
      await tester.pumpAndSettle();

      final requirements = find.byKey(const ValueKey('pit-event-requirements-1'));
      await tester.tap(requirements);
      await tester.pumpAndSettle();
      expect(find.text('Panel evaluation'), findsOneWidget);
      expect(find.text('Peer evaluation'), findsOneWidget);
      expect(find.text('Concept Paper'), findsOneWidget);
      expect(find.text('Pitch Deck'), findsOneWidget);
      expect(find.text('Post Reflection'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Optional'), findsOneWidget);
      await capturePreview(tester, find.byKey(const ValueKey('pit-event-setup-preview')),
        'pit-event-setup-expanded');
      await tester.tap(requirements);
      await tester.pumpAndSettle();
      expect(find.text('Concept Paper'), findsNothing);

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

    },
  );
}
