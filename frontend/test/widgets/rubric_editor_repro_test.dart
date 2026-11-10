import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_engine_screen.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return AuthState(
      user: {
        'id': 1,
        'username': 'admin',
        'role': 'admin',
        'is_superuser': true,
      },
      token: 'fake-token',
    );
  }
}

class FakeRubricNotifier extends RubricEngineNotifier {
  Map<String, dynamic>? savedPayload;

  @override
  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async {
    savedPayload = payload;
    return true;
  }

  @override
  RubricEngineState build() {
    return const RubricEngineState(
      isLoading: false,
      rubrics: [],
      scopes: [
        {'value': 'capstone', 'label': 'Capstone'},
        {'value': 'pit', 'label': 'PIT'},
      ],
      semesters: [
        {'id': 1, 'school_year': '2024-2025', 'semester': '1st Semester'},
      ],
      activeSemester: {
        'id': 1,
        'school_year': '2024-2025',
        'semester': '1st Semester',
      },
      scaleOptions: ['5-Point Scale', '10-Point Scale', '100-Point Scale'],
    );
  }

  @override
  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? successMessage,
  }) async {}
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      schoolYears: [
        {'id': 1, 'school_year': '2024-2025', 'is_active': true},
      ],
      activeSemester: {
        'id': 1,
        'school_year': '2024-2025',
        'semester': '1st Semester',
      },
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeAdminDashboardNotifier extends DashboardNotifier {
  FakeAdminDashboardNotifier() : super('admin');

  @override
  DashboardState build() {
    return DashboardState(data: {'active_semester': '2024-2025'});
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeFacultyDashboardNotifier extends DashboardNotifier {
  FakeFacultyDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(data: {'pit_lead_year': '3rd Year'});
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeNotificationsNotifier extends NotificationsNotifier {
  FakeNotificationsNotifier([super.workspace = 'admin']);
  @override
  NotificationsState build() =>
      const NotificationsState(notifications: [], unreadCount: 0);

  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

void main() {
  Future<ProviderContainer> pumpWeightEditor(
    WidgetTester tester,
    List<Object> weights, {
    bool readOnly = false,
    String scale = '10-Point Scale',
    List<String>? sections,
    List<int>? points,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier()),
        rubricEngineProvider.overrideWith(() => FakeRubricNotifier()),
        dashboardProvider(
          'faculty',
        ).overrideWith(() => FakeFacultyDashboardNotifier()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RubricFullPageEditor(
              rubric: {
                'id': 1,
                'name': 'Saved weights',
                'scope': 'capstone',
                'evaluation_type': 'panel',
                'semester_id': 1,
                'scale': scale,
                if (scale == 'Custom Scale') 'custom_max_score': 25,
                'criteria': [
                  for (var i = 0; i < weights.length; i++)
                    {
                      'name': 'Criterion $i',
                      'weight': weights[i],
                      'max_score': points?[i] ?? 10,
                      'scale': scale,
                      'section': sections?[i] ?? '',
                      'display_order': i,
                    },
                ],
              },
              readOnly: readOnly,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final scale in [
    '5-Point Scale',
    '10-Point Scale',
    '100-Point Scale',
    'Custom Scale',
  ]) {
    testWidgets('$scale distributes evenly to exactly 100 and saves', (
      tester,
    ) async {
      final container = await pumpWeightEditor(
        tester,
        List<Object>.filled(6, 1),
        scale: scale,
      );
      final distribute = find.text('Distribute evenly');
      await tester.ensureVisible(distribute);
      await tester.tap(distribute);
      await tester.pumpAndSettle();
      expect(find.text('100% of 100%'), findsOneWidget);
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      final weights =
          (notifier.savedPayload!['criteria'] as List)
              .map((c) => ((c['weight'] as num) * 100).round())
              .toList()
            ..sort();
      expect(weights.reduce((a, b) => a + b), 10000);
      expect(weights.last - weights.first, lessThanOrEqualTo(1));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  }

  testWidgets(
    'points distribution refreshes an already edited total and saves exact section shares',
    (tester) async {
      final container = await pumpWeightEditor(
        tester,
        [10, 20, 30],
        scale: 'Points-Based (Sections)',
        sections: ['Oral', 'Manuscript', 'Output'],
      );
      final sectionWeight = find.descendant(
        of: find
            .byWidgetPredicate(
              (w) =>
                  w is ShadInput &&
                  w.trailing is Text &&
                  (w.trailing as Text).data == '%',
            )
            .first,
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(sectionWeight);
      await tester.enterText(sectionWeight, '15');
      await tester.pumpAndSettle();
      expect(container.read(unsavedChangesProvider), isTrue);
      expect(find.text('65% of 100%'), findsOneWidget);
      final distribute = find.text('Distribute section weights evenly');
      await tester.ensureVisible(distribute);
      await tester.tap(distribute);
      await tester.pumpAndSettle();
      expect(find.text('100% of 100%'), findsOneWidget);
      expect(find.text('100% Balanced'), findsOneWidget);
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      final weights = (notifier.savedPayload!['criteria'] as List)
          .map((c) => c['weight'])
          .toList();
      expect(weights, [33.34, 33.33, 33.33]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  for (final sectioned in [true, false]) {
    testWidgets(
      '${sectioned ? 'points-based' : 'calculate from sections'} preserves rounded budgets inside each section',
      (tester) async {
        final container = await pumpWeightEditor(
          tester,
          List<Object>.filled(7, 1),
          scale: sectioned ? 'Points-Based (Sections)' : '10-Point Scale',
          sections: [
            'Oral',
            'Oral',
            'Oral',
            'Manuscript',
            'Manuscript',
            'Manuscript',
            'Output',
          ],
          points: [1, 1, 1, 1, 2, 4, 1],
        );
        final action = find.text(
          sectioned
              ? 'Distribute section weights evenly'
              : 'Calculate from sections',
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        if (!sectioned) {
          await tester.tap(find.text('Apply Weights'));
          await tester.pumpAndSettle();
        }
        expect(find.text('100% of 100%'), findsOneWidget);
        expect(
          await container.read(unsavedChangesSaveDraftProvider)!(),
          isTrue,
        );
        final notifier =
            container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
        final criteria = notifier.savedPayload!['criteria'] as List;
        final budgets = <String, int>{};
        for (final criterion in criteria) {
          final section = criterion['section'] as String;
          budgets[section] =
              (budgets[section] ?? 0) +
              ((criterion['weight'] as num) * 100).round();
        }
        expect(budgets, {'Oral': 3334, 'Manuscript': 3333, 'Output': 3333});
        expect(criteria.map((c) => c['weight']).toList(), [
          11.12,
          11.11,
          11.11,
          4.76,
          9.52,
          19.05,
          33.33,
        ]);
        expect(criteria.map((c) => c['max_score']).toList(), [
          1,
          1,
          1,
          1,
          2,
          4,
          1,
        ]);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  }

  testWidgets(
    'changing preset scales does not restore obsolete section weights',
    (tester) async {
      final container = await pumpWeightEditor(
        tester,
        [20, 80],
        scale: 'Points-Based (Sections)',
        sections: ['Oral', 'Output'],
      );
      for (final action in ['5-point', 'Distribute evenly', '10-point']) {
        final button = find.text(action).first;
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      expect(
        (notifier.savedPayload!['criteria'] as List)
            .map((c) => c['weight'])
            .toList(),
        [50, 50],
      );
      expect(notifier.savedPayload!['scale'], '10-Point Scale');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'incomplete totals block draft, publish and unsaved draft saves',
    (tester) async {
      final container = await pumpWeightEditor(tester, [1, 1, 1, 1]);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      for (final label in ['Save as Draft', 'Publish Rubric']) {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(notifier.savedPayload, isNull);
      }
      final saveDraft = container.read(unsavedChangesSaveDraftProvider)!;
      expect(await saveDraft(), isFalse);
      expect(notifier.savedPayload, isNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'one hundredth under 100 is visible and blocked until corrected',
    (tester) async {
      final container = await pumpWeightEditor(tester, [99.99]);
      expect(find.text('99.99% of 100%'), findsOneWidget);
      expect(find.text('0.01% Unallocated'), findsOneWidget);
      final saveDraft = container.read(unsavedChangesSaveDraftProvider)!;
      expect(await saveDraft(), isFalse);
      final weightField = find.descendant(
        of: find.byKey(const ValueKey('criterion-weight-0')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(weightField);
      await tester.enterText(weightField, '100');
      await tester.pumpAndSettle();
      expect(await saveDraft(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      expect(
        (notifier.savedPayload!['criteria'] as List).single['weight'],
        100,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets('decimal percentages loaded from the API survive saving', (
    tester,
  ) async {
    final container = await pumpWeightEditor(tester, [
      '33.33',
      '33.33',
      '33.34',
    ]);
    expect(find.text('100% of 100%'), findsOneWidget);
    expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
    final notifier =
        container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
    expect(
      (notifier.savedPayload!['criteria'] as List)
          .map((item) => item['weight'])
          .toList(),
      [33.33, 33.33, 33.34],
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets(
    'locked rubric displays all four saved percentages as 100 total',
    (tester) async {
      await pumpWeightEditor(tester, [25, 25, 25, 25], readOnly: true);
      expect(find.text('100% of 100%'), findsOneWidget);
      final weightFields = tester.widgetList<ShadInput>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ShadInput &&
              widget.key.toString().contains('criterion-weight-'),
        ),
      );
      expect(weightFields.map((widget) => widget.controller!.text).toList(), [
        '25',
        '25',
        '25',
        '25',
      ]);
      expect(weightFields.every((widget) => widget.enabled == false), isTrue);
    },
  );

  testWidgets('Clicking Create Standard Rubric opens editor without crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier()),
        rubricEngineProvider.overrideWith(() => FakeRubricNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        dashboardProvider(
          'admin',
        ).overrideWith(() => FakeAdminDashboardNotifier()),
        dashboardProvider(
          'faculty',
        ).overrideWith(() => FakeFacultyDashboardNotifier()),
        notificationsProvider.overrideWith2(
          (workspace) => FakeNotificationsNotifier(workspace),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    router.go('/admin/rubrics');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RubricEngineScreen), findsOneWidget);
    final createBtn = find.text('Create Standard Rubric').first;
    expect(createBtn, findsOneWidget);

    await tester.tap(createBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RubricFullPageEditor), findsOneWidget);
    final editorState = tester.state(find.byType(RubricFullPageEditor));
    await tester.tap(find.text('Academic Periods').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rubrics').first);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(RubricFullPageEditor)), same(editorState));

    await tester.enterText(
      find
          .descendant(
            of: find.byKey(const ValueKey('rubric-name')),
            matching: find.byType(EditableText),
          )
          .first,
      'Discarded rubric name',
    );
    await tester.pumpAndSettle();
    expect(container.read(unsavedChangesProvider), isTrue);
    await tester.tap(find.text('Academic Periods').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rubrics').first);
    await tester.pumpAndSettle();
    expect(find.byType(RubricFullPageEditor), findsNothing);
    expect(find.byType(RubricEngineScreen), findsOneWidget);
    expect(container.read(unsavedChangesProvider), isFalse);
  });
}
