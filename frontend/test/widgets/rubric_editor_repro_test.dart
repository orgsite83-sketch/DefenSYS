import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      activeSemester: {'id': 1, 'school_year': '2024-2025', 'semester': '1st Semester'},
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeAdminDashboardNotifier extends DashboardNotifier {
  FakeAdminDashboardNotifier() : super('admin');

  @override
  DashboardState build() {
    return DashboardState(
      data: {'active_semester': '2024-2025'},
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeFacultyDashboardNotifier extends DashboardNotifier {
  FakeFacultyDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(
      data: {'pit_lead_year': '3rd Year'},
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeNotificationsNotifier extends NotificationsNotifier {
  FakeNotificationsNotifier([super.workspace = 'admin']);
  @override
  NotificationsState build() => const NotificationsState(notifications: [], unreadCount: 0);

  @override
  Future<void> fetchNotifications({bool? unreadOnly, bool loadMore = false}) async {}
}

void main() {
  Future<ProviderContainer> pumpWeightEditor(
    WidgetTester tester,
    List<Object> weights, {
    bool readOnly = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => FakeAuthNotifier()),
      rubricEngineProvider.overrideWith(() => FakeRubricNotifier()),
      dashboardProvider('faculty').overrideWith(() => FakeFacultyDashboardNotifier()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: RubricFullPageEditor(
        rubric: {
          'id': 1, 'name': 'Saved weights', 'scope': 'capstone',
          'evaluation_type': 'panel', 'semester_id': 1,
          'criteria': [for (var i = 0; i < weights.length; i++) {
            'name': 'Criterion $i', 'weight': weights[i], 'max_score': 10,
            'display_order': i,
          }],
        },
        readOnly: readOnly,
        onBack: () {},
      ))),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('incomplete totals block draft, publish and unsaved draft saves', (tester) async {
    final container = await pumpWeightEditor(tester, [1, 1, 1, 1]);
    final notifier = container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
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
  });

  testWidgets('one hundredth under 100 is visible and blocked until corrected', (tester) async {
    final container = await pumpWeightEditor(tester, [99.99]);
    expect(find.text('99.99% of 100%'), findsOneWidget);
    expect(find.text('0.01% Unallocated'), findsOneWidget);
    final saveDraft = container.read(unsavedChangesSaveDraftProvider)!;
    expect(await saveDraft(), isFalse);
    final weightField = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'WEIGHT');
    await tester.ensureVisible(weightField);
    await tester.enterText(weightField, '100');
    await tester.pumpAndSettle();
    expect(await saveDraft(), isTrue);
    final notifier = container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
    expect((notifier.savedPayload!['criteria'] as List).single['weight'], 100);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('decimal percentages loaded from the API survive saving', (tester) async {
    final container = await pumpWeightEditor(tester, ['33.33', '33.33', '33.34']);
    expect(find.text('100% of 100%'), findsOneWidget);
    expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
    final notifier = container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
    expect((notifier.savedPayload!['criteria'] as List).map((item) => item['weight']).toList(), [33.33, 33.33, 33.34]);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('locked rubric displays all four saved percentages as 100 total', (tester) async {
    await pumpWeightEditor(tester, [25, 25, 25, 25], readOnly: true);
    expect(find.text('100% of 100%'), findsOneWidget);
    final weightFields = tester.widgetList<TextField>(find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'WEIGHT'));
    expect(weightFields.map((widget) => widget.controller!.text).toList(), ['25', '25', '25', '25']);
    expect(weightFields.every((widget) => widget.enabled == false), isTrue);
  });

  testWidgets('Clicking Create Standard Rubric opens editor without crash', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier()),
        rubricEngineProvider.overrideWith(() => FakeRubricNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        dashboardProvider('admin').overrideWith(() => FakeAdminDashboardNotifier()),
        dashboardProvider('faculty').overrideWith(() => FakeFacultyDashboardNotifier()),
        notificationsProvider.overrideWith2((workspace) => FakeNotificationsNotifier(workspace)),
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

    await tester.enterText(find.descendant(
      of: find.byType(RubricFullPageEditor), matching: find.byType(TextField),
    ).first, 'Discarded rubric name');
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
