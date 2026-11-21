import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_engine_screen.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(user: {'id': 1, 'role': 'admin'});
}

class _PitAuth extends _Auth {
  @override
  AuthState build() => AuthState(
    user: {
      'id': 2,
      'role': 'faculty',
      'is_pit_lead': true,
      'pit_lead_year': '2nd Year',
    },
  );
}

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('faculty');
  @override
  DashboardState build() => DashboardState(data: {});
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

Map<String, dynamic> _rubric(
  int id,
  String name, {
  int? stage = 1,
  String role = 'panel',
  bool locked = false,
}) => {
  'id': id,
  'name': name,
  'scope': 'capstone',
  'semester_id': 10,
  'evaluation_type': role,
  'defense_stage_id': stage,
  'status': 'published',
  'scale': '10-Point Scale',
  'target_type': role == 'peer' ? 'individual' : 'team',
  'is_locked': locked,
  'criteria': [
    {
      'name': name == 'Outdated rubric' ? 'Old criterion' : 'Technical quality',
      'weight': 100,
      'max_score': 10,
      'scale': '10-Point Scale',
      'target_type': role == 'peer' ? 'individual' : 'team',
    },
  ],
};

Map<String, dynamic> _stage(int id, String label, {bool concept = false}) => {
  'id': id,
  'label': label,
  'concept_config': {'enabled': concept},
  'rubric_slots': {
    for (final role in ['panel', 'adviser', 'peer'])
      role: {
        'required': role == 'panel' || !concept,
        'rubric_id': id == 1 && role == 'panel' ? 101 : null,
        'status': id == 1 && role == 'panel' ? 'published' : null,
      },
  },
};

class _Rubrics extends RubricEngineNotifier {
  Map<String, dynamic>? savedPayload;
  bool rejectSave = false;
  int requests = 0;
  @override
  RubricEngineState build() => RubricEngineState(
    // The old rubric deliberately comes first; assignment must use the slot ID.
    rubrics: [
      _rubric(102, 'Outdated rubric'),
      _rubric(101, 'Proposal Defense — Panel Rubric'),
    ],
    activeSemester: {'id': 10, 'display_name': '1st Semester, A.Y. 2026–2027'},
    semesters: [
      {'id': 10, 'display_name': '1st Semester, A.Y. 2026–2027'},
    ],
    defenseStages: [
      _stage(1, 'Proposal Defense'),
      _stage(2, 'Final Defense'),
      _stage(3, 'Concept selection', concept: true),
    ],
  );
  @override
  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? successMessage,
  }) async {
    requests++;
  }

  @override
  Future<List<Map<String, dynamic>>> checkExistingRubrics({
    String? scope,
  }) async => [
    {
      ..._rubric(400, 'Project — Peer Rubric', stage: null, role: 'peer'),
      'display_semester': '2nd Semester, A.Y. 2025–2026',
      'criteria': [
        {
          'name': 'Contribution',
          'weight': 100,
          'max_score': 10,
          'scale': '10-Point Scale',
          'target_type': 'individual',
        },
      ],
    },
    {
      ..._rubric(401, 'Previous panel rubric', stage: null),
      'display_semester': '2nd Semester, A.Y. 2025–2026',
    },
  ];
  @override
  Future<bool> addRubric(Map<String, dynamic> payload) async =>
      _save(500, payload);
  @override
  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async =>
      _save(rubricId, payload);
  bool _save(int rubricId, Map<String, dynamic> payload) {
    if (rejectSave) return false;
    savedPayload = payload;
    final saved = {...payload, 'id': rubricId};
    final stages = state.defenseStages.map((stage) {
      if (stage['id'] != payload['defense_stage_id']) return stage;
      final slots = Map<String, dynamic>.from(stage['rubric_slots']);
      slots[payload['evaluation_type']] = {
        'required': true,
        'rubric_id': rubricId,
        'status': payload['status'],
      };
      return {...stage, 'rubric_slots': slots};
    }).toList();
    state = state.copyWith(
      rubrics: [saved, ...state.rubrics.where((r) => r['id'] != rubricId)],
      defenseStages: stages,
      pitEvents: state.pitEvents
          .map(
            (event) => event['id'] == payload['pit_event_id']
                ? {
                    ...event,
                    'rubric_slots': {
                      ...Map<String, dynamic>.from(event['rubric_slots']),
                      payload['evaluation_type']: {
                        'required': true,
                        'rubric_id': rubricId,
                        'status': payload['status'],
                      },
                    },
                  }
                : event,
          )
          .toList(),
    );
    return true;
  }

  void lockPanel() {
    state = state.copyWith(
      rubrics: state.rubrics
          .map(
            (rubric) => rubric['id'] == 101
                ? {
                    ...rubric,
                    'is_locked': true,
                    'lock_reason': 'Recorded evaluations protect this rubric.',
                  }
                : rubric,
          )
          .toList(),
    );
  }
}

class _PitRubrics extends _Rubrics {
  @override
  RubricEngineState build() => super.build().copyWith(
    scope: 'pit',
    rubrics: [],
    defenseStages: [],
    pitEvents: [
      {
        'id': 11,
        'semester_id': 10,
        'event_name': 'Prototype Showcase',
        'rubric_slots': {
          'panel': {'required': true, 'rubric_id': null},
          'peer': {'required': true, 'rubric_id': null},
        },
      },
      {'id': 12, 'semester_id': 20, 'event_name': 'Other semester event'},
    ],
  );
  @override
  Future<List<Map<String, dynamic>>> checkExistingRubrics({
    String? scope,
  }) async => (await super.checkExistingRubrics(
    scope: scope,
  )).map((source) => {...source, 'scope': 'pit'}).toList();
}

class _SetupRubrics extends _Rubrics {
  _SetupRubrics(this.initialState, {this.recoverOnRetry = false});
  final RubricEngineState initialState;
  final bool recoverOnRetry;

  @override
  RubricEngineState build() => initialState;

  @override
  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? successMessage,
  }) async {
    requests++;
    if (recoverOnRetry && requests > 1) {
      state = const RubricEngineState(
        activeSemester: {
          'id': 10,
          'display_name': '1st Semester, A.Y. 2026–2027',
        },
      );
    }
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  bool pit = false,
  double textScale = 1,
  RubricEngineNotifier Function()? rubrics,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => pit ? _PitAuth() : _Auth()),
      rubricEngineProvider.overrideWith(
        rubrics ?? () => pit ? _PitRubrics() : _Rubrics(),
      ),
      dashboardProvider('faculty').overrideWith(_Dashboard.new),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: pit ? '/faculty/rubrics' : '/admin/rubrics',
    routes: [
      GoRoute(
        path: pit ? '/faculty/rubrics' : '/admin/rubrics',
        builder: (_, route) => Scaffold(
          body: RubricEngineScreen(
            initialStageId: int.tryParse(
              route.uri.queryParameters['stage'] ?? '',
            ),
            initialEvaluationType: route.uri.queryParameters['evaluation'],
          ),
        ),
      ),
      for (final path in [
        '/admin/academic-periods',
        '/admin/defense-stages',
        '/faculty/pit-events',
      ])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('Destination: $path')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: DefensysTokens.fontFamilyInter,
          scaffoldBackgroundColor: dark
              ? DefensysTokens.mistBackground
              : DefensysTokens.background,
        ),
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
  return container;
}

Finder get _name => find.descendant(
  of: find.byKey(const ValueKey('rubric-name')),
  matching: find.byType(EditableText),
);
String _nameValue(WidgetTester tester) =>
    tester.widget<EditableText>(_name).controller.text;
Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  testWidgets('missing academic period leads to Academic Periods', (
    tester,
  ) async {
    await _pump(
      tester,
      rubrics: () => _SetupRubrics(const RubricEngineState()),
    );
    expect(find.byType(DefensysEmptyState), findsOneWidget);
    expect(find.text('No active academic period'), findsOneWidget);
    expect(find.text('Set up stages'), findsNothing);
    expect(find.text('Create reusable template'), findsNothing);
    await tester.tap(find.text('Academic Periods'));
    await tester.pumpAndSettle();
    expect(find.text('Destination: /admin/academic-periods'), findsOneWidget);
  });
  testWidgets('active period with no stages leads to stage setup', (
    tester,
  ) async {
    await _pump(
      tester,
      rubrics: () =>
          _SetupRubrics(const RubricEngineState(activeSemester: {'id': 10})),
    );
    expect(find.text('No defense stages available'), findsOneWidget);
    expect(find.text('Create reusable template'), findsNothing);
    await tester.tap(find.text('Set up stages'));
    await tester.pumpAndSettle();
    expect(find.text('Destination: /admin/defense-stages'), findsOneWidget);
  });
  testWidgets('PIT lead without events opens PIT event setup', (tester) async {
    await _pump(
      tester,
      pit: true,
      rubrics: () =>
          _SetupRubrics(const RubricEngineState(activeSemester: {'id': 10})),
    );
    expect(find.text('No PIT events configured'), findsOneWidget);
    await tester.tap(find.text('Set up PIT events'));
    await tester.pumpAndSettle();
    expect(find.text('Destination: /faculty/pit-events'), findsOneWidget);
  });
  testWidgets('PIT lead without an active period sees administrator guidance', (
    tester,
  ) async {
    await _pump(
      tester,
      pit: true,
      rubrics: () => _SetupRubrics(const RubricEngineState()),
    );
    expect(
      find.text(
        'Ask an administrator to activate an academic period, then set up your PIT events.',
      ),
      findsOneWidget,
    );
    expect(find.text('Academic Periods'), findsNothing);
    expect(find.text('Set up PIT events'), findsNothing);
    expect(find.text('Create reusable template'), findsNothing);
  });
  testWidgets('setup load failure retries before showing prerequisites', (
    tester,
  ) async {
    final notifier = _SetupRubrics(
      const RubricEngineState(error: 'Connection failed'),
      recoverOnRetry: true,
    );
    await _pump(tester, rubrics: () => notifier);
    expect(find.text('Could not load rubric setup'), findsOneWidget);
    expect(find.text('No active academic period'), findsNothing);
    expect(find.text('Create reusable template'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(notifier.requests, 2);
    expect(find.text('No defense stages available'), findsOneWidget);
  });
  testWidgets('loading rubric setup does not offer template creation', (
    tester,
  ) async {
    await _pump(
      tester,
      rubrics: () => _SetupRubrics(const RubricEngineState(isLoading: true)),
    );
    expect(find.byType(DefensysEmptyState), findsNothing);
    expect(find.text('Create reusable template'), findsNothing);
    expect(find.text('Academic Periods'), findsNothing);
  });
  for (final hasPeriod in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'setup empty state fits $width pixels, period=$hasPeriod, dark=$dark',
          (tester) async {
            await _pump(
              tester,
              width: width,
              dark: dark,
              textScale: width == 320 ? 1.3 : 1,
              rubrics: () => _SetupRubrics(
                RubricEngineState(
                  activeSemester: hasPeriod ? {'id': 10} : null,
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final action = find.text(
              hasPeriod ? 'Set up stages' : 'Academic Periods',
            );
            expect(action.hitTestable(), findsOneWidget);
            await capturePreview(
              tester,
              find.byType(RubricEngineScreen),
              'rubric-empty-${hasPeriod ? 'stages' : 'period'}-${dark ? 'dark' : 'light'}-${width.toInt()}',
              viewport: true,
            );
          },
        );
      }
    }
  }
  testWidgets('Export follows the displayed stage and evaluation type', (
    tester,
  ) async {
    await _pump(tester);
    ReportExportMenu export() => tester.widget<ReportExportMenu>(
      find.byWidgetPredicate(
        (widget) => widget is ReportExportMenu && widget.reportId == 'rubrics',
      ),
    );
    expect(export().params['stage_id'], '1');
    expect(export().params['evaluation_type'], 'panel');
    await _tap(tester, const ValueKey('rubric-destination-2'));
    await _tap(tester, const ValueKey('rubric-evaluation-peer'));
    expect(export().params['stage_id'], '2');
    expect(export().params['evaluation_type'], 'peer');
    expect(export().params['semester_id'], '10');
    expect(export().params['assignment_scope'], 'configured');
    expect(export().params['search'], isEmpty);
    expect(export().configureBeforeDownload, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'PIT export follows the selected event instead of a same-named rubric',
    (tester) async {
      await _pump(tester, pit: true);
      await _tap(tester, const ValueKey('rubric-evaluation-peer'));
      final export = tester.widget<ReportExportMenu>(
        find.byType(ReportExportMenu),
      );
      expect(export.params['pit_event_config_id'], '11');
      expect(export.params.containsKey('stage_id'), isFalse);
      expect(export.params['scope'], 'pit');
      expect(export.params['evaluation_type'], 'peer');
    },
  );
  testWidgets(
    'main workspace opens the exact assigned rubric and protects switches',
    (tester) async {
      final container = await _pump(tester);
      expect(find.byType(RubricFullPageEditor), findsOneWidget);
      expect(find.text('Technical quality'), findsWidgets);
      expect(find.text('Old criterion'), findsNothing);
      expect(find.text('Back to rubrics'), findsNothing);
      expect(
        (container.read(rubricEngineProvider.notifier) as _Rubrics).requests,
        1,
      );
      await tester.enterText(_name, 'Custom proposal rubric');
      await _tap(tester, const ValueKey('rubric-destination-2'));
      expect(find.text('Unsaved rubric changes'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(_nameValue(tester), 'Custom proposal rubric');
      await _tap(tester, const ValueKey('rubric-destination-2'));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(_nameValue(tester), 'Final Defense — Panel Rubric');
      expect(container.read(unsavedChangesProvider), isFalse);
    },
  );
  testWidgets(
    'copy retains destination, automatic name, evaluation and semester',
    (tester) async {
      final container = await _pump(tester);
      await _tap(tester, const ValueKey('rubric-destination-2'));
      await _tap(tester, const ValueKey('rubric-evaluation-peer'));
      expect(_nameValue(tester), 'Final Defense — Peer Rubric');
      await tester.ensureVisible(find.text('Copy from rubric'));
      await tester.tap(find.text('Copy from rubric'));
      await tester.pumpAndSettle();
      expect(find.text('Previous panel rubric'), findsNothing);
      await tester.tap(find.text('Project — Peer Rubric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy rubric'));
      await tester.pumpAndSettle();
      expect(_nameValue(tester), 'Final Defense — Peer Rubric');
      expect(find.text('Use suggested name'), findsNothing);
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      await tester.pumpAndSettle();
      final payload =
          (container.read(rubricEngineProvider.notifier) as _Rubrics)
              .savedPayload!;
      expect(payload['defense_stage_id'], 2);
      expect(payload['evaluation_type'], 'peer');
      expect(payload['semester_id'], 10);
      expect(payload['target_type'], 'individual');
      expect(payload['name'], 'Final Defense — Peer Rubric');
      expect(find.byType(RubricFullPageEditor), findsOneWidget);
      expect(find.text('Contribution'), findsWidgets);
      expect(container.read(unsavedChangesSaveDraftProvider), isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
  testWidgets('save draft before switching saves the original rubric', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.enterText(_name, 'Reviewed proposal rubric');
    await _tap(tester, const ValueKey('rubric-destination-2'));
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    final payload = (container.read(rubricEngineProvider.notifier) as _Rubrics)
        .savedPayload!;
    expect(payload['defense_stage_id'], 1);
    expect(payload['name'], 'Reviewed proposal rubric');
    expect(_nameValue(tester), 'Final Defense — Panel Rubric');
    expect(container.read(unsavedChangesProvider), isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 8));
  });
  testWidgets(
    'copy preserves a deliberate name and can reuse another evaluation type',
    (tester) async {
      final container = await _pump(tester);
      await _tap(tester, const ValueKey('rubric-destination-2'));
      await _tap(tester, const ValueKey('rubric-evaluation-peer'));
      await tester.enterText(_name, 'Contribution and teamwork');
      await tester.tap(find.text('Copy from rubric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peer rubrics only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous panel rubric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy rubric'));
      await tester.pumpAndSettle();
      expect(_nameValue(tester), 'Contribution and teamwork');
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      await tester.pumpAndSettle();
      final payload =
          (container.read(rubricEngineProvider.notifier) as _Rubrics)
              .savedPayload!;
      expect(payload['evaluation_type'], 'peer');
      expect(payload['defense_stage_id'], 2);
      expect((payload['criteria'] as List).single['target_type'], 'individual');
      await tester.pumpAndSettle(const Duration(seconds: 8));
    },
  );
  testWidgets('expanded scoring exposes invalid custom points before saving', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    final points = find.descendant(
      of: find.byKey(const ValueKey('custom-scale-points')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(points, '0');
    expect(await container.read(unsavedChangesSaveDraftProvider)!(), isFalse);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(points).focusNode.hasFocus, isTrue);
    expect(
      (container.read(rubricEngineProvider.notifier) as _Rubrics).savedPayload,
      isNull,
    );
    await tester.pumpAndSettle(const Duration(seconds: 8));
  });
  testWidgets('PIT workspace retains event and peer policy when copying', (
    tester,
  ) async {
    final container = await _pump(tester, pit: true);
    expect(find.text('Event rubrics'), findsOneWidget);
    expect(find.text('Other semester event'), findsNothing);
    expect(
      find.byKey(const ValueKey('rubric-evaluation-adviser')),
      findsNothing,
    );
    await _tap(tester, const ValueKey('rubric-evaluation-peer'));
    await tester.tap(find.text('Copy from rubric'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project — Peer Rubric'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy rubric'));
    await tester.pumpAndSettle();
    expect(_nameValue(tester), 'Prototype Showcase — Peer Rubric');
    expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
    await tester.pumpAndSettle();
    final payload = (container.read(rubricEngineProvider.notifier) as _Rubrics)
        .savedPayload!;
    expect(payload['pit_event_id'], 11);
    expect(payload['defense_stage_id'], isNull);
    expect(payload['target_type'], 'individual');
    await tester.pumpAndSettle(const Duration(seconds: 8));
  });
  testWidgets('stage links update an already mounted workspace', (
    tester,
  ) async {
    await _pump(tester);
    final element = tester.element(find.byType(RubricEngineScreen));
    GoRouter.of(element).go('/admin/rubrics?stage=2&evaluation=peer');
    await tester.pumpAndSettle();
    expect(_nameValue(tester), 'Final Defense — Peer Rubric');
  });
  testWidgets('failed draft save keeps the current unsaved rubric', (
    tester,
  ) async {
    final container = await _pump(tester);
    (container.read(rubricEngineProvider.notifier) as _Rubrics).rejectSave =
        true;
    await tester.enterText(_name, 'Keep my work');
    await _tap(tester, const ValueKey('rubric-evaluation-peer'));
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(_nameValue(tester), 'Keep my work');
    expect(container.read(unsavedChangesProvider), isTrue);
    await tester.pumpAndSettle(const Duration(seconds: 8));
  });
  testWidgets(
    'concept stage shows only required evaluation and locked rubrics remain read only',
    (tester) async {
      final container = await _pump(tester);
      (container.read(rubricEngineProvider.notifier) as _Rubrics).lockPanel();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadInput>(find.byKey(const ValueKey('rubric-name')))
            .enabled,
        isFalse,
      );
      await _tap(tester, const ValueKey('rubric-destination-3'));
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('rubric-evaluation-peer')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('rubric-evaluation-adviser')),
            )
            .enabled,
        isFalse,
      );
      expect(_nameValue(tester), 'Concept selection — Panel Rubric');
    },
  );
  testWidgets(
    'templates and historical rubrics open inside the same workspace',
    (tester) async {
      await _pump(tester);
      await _tap(tester, const ValueKey('rubric-workspace-library'));
      final create = find.text('Create reusable template').first;
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.byType(RubricFullPageEditor), findsOneWidget);
      expect(find.text('Back to rubrics'), findsNothing);
      expect(
        GoRouterState.of(
          tester.element(find.byType(RubricEngineScreen)),
        ).uri.path,
        '/admin/rubrics',
      );
      await _tap(tester, const ValueKey('rubric-workspace-stages'));
      expect(_nameValue(tester), 'Proposal Defense — Panel Rubric');
    },
  );
  for (final width in [320.0, 390.0, 420.0, 768.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('workspace fits $width pixels, dark=$dark', (tester) async {
        await _pump(tester, width: width, dark: dark);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(RubricEngineScreen),
          'rubric-workspace-${dark ? 'dark' : 'light'}-${width.toInt()}',
          viewport: true,
        );
        final bar = find.byKey(const ValueKey('rubric-editor-actions'));
        final before = tester.getRect(bar);
        expect(find.text('Save as Draft').hitTestable(), findsOneWidget);
        final scroll = find.ancestor(
          of: find.byKey(const ValueKey('rubric-editor-content')),
          matching: find.byType(SingleChildScrollView),
        ).first;
        await tester.drag(scroll, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getRect(bar), before);
        expect(find.text('Save as Draft').hitTestable(), findsOneWidget);
        expect(find.text('Review & publish').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
