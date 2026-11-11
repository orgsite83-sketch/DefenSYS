import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:defensys/screens/web/admin/rubric_engine/rubric_criterion_fields.dart';

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
  Map<int, Map<String, String>> rejectedCriteria = {};

  @override
  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async {
    if (rejectedCriteria.isNotEmpty) {
      state = state.copyWith(
        error: 'Check the criterion name.',
        criterionErrors: rejectedCriteria,
      );
      return false;
    }
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
    List<String>? descriptions,
    bool expandSections = true,
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
                      'description': descriptions?[i] ?? '',
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
    if (expandSections && scale == 'Points-Based (Sections)') {
      for (var index = 1; index < sections!.toSet().length; index++) {
        final toggle = find.byKey(ValueKey('section-toggle-$index'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
    }
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
      final distribute = find.text('Distribute evenly');
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
      '${sectioned ? 'weighted sections' : 'switching to weighted sections'} preserves rounded budgets inside each section',
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
        expect(find.text('Calculate from sections'), findsNothing);
        if (!sectioned) {
          final setup = find.text('Weighted sections');
          await tester.ensureVisible(setup);
          await tester.tap(setup);
          await tester.pumpAndSettle();
        }
        final action = find.text('Distribute evenly');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
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
      for (final action in [
        'Standard criteria',
        '5-point',
        'Distribute evenly',
        '10-point',
      ]) {
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
    'inline criteria preserve names and legacy guidelines through reordering',
    (tester) async {
      final container = await pumpWeightEditor(
        tester,
        [60, 40],
        descriptions: ['Explain the implementation choices.', ''],
      );
      expect(
        find.byKey(const ValueKey('criterion-description-0')),
        findsNothing,
      );
      final name = find.descendant(
        of: find.byKey(const ValueKey('criterion-name-0')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Implementation quality');
      final actions = find.byKey(const ValueKey('criterion-actions-0'));
      await tester.ensureVisible(actions);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('criterion-0-Move down')));
      await tester.pumpAndSettle();
      final movedName = find.descendant(
        of: find.byKey(const ValueKey('criterion-name-1')),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(movedName).controller.text,
        'Implementation quality',
      );
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      final criteria = notifier.savedPayload!['criteria'] as List;
      expect(criteria.map((c) => c['name']), [
        'Criterion 1',
        'Implementation quality',
      ]);
      expect(
        criteria.last['description'],
        'Explain the implementation choices.',
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets('save focuses the missing name in an inline criterion', (
    tester,
  ) async {
    final container = await pumpWeightEditor(tester, [60, 40]);
    final name = find.descendant(
      of: find.byKey(const ValueKey('criterion-name-0')),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(name);
    await tester.enterText(name, '');
    await tester.pumpAndSettle();
    expect(name, findsOneWidget);
    final save = container.read(unsavedChangesSaveDraftProvider)!;
    expect(await save(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Enter a criterion name.'), findsOneWidget);
    expect(tester.widget<EditableText>(name).focusNode.hasFocus, isTrue);
    expect(tester.getRect(name).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(name).bottom, lessThanOrEqualTo(1100));
    await tester.enterText(name, 'Implementation');
    await tester.pumpAndSettle();
    expect(await save(), isTrue);
    final notifier =
        container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
    expect(
      (notifier.savedPayload!['criteria'] as List).first['description'],
      '',
    );
    expect(find.textContaining('Optional'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets(
    'weighted sections derive percentages from edited criterion points',
    (tester) async {
      final container = await pumpWeightEditor(
        tester,
        [20, 40, 40],
        scale: 'Points-Based (Sections)',
        sections: ['Oral', 'Oral', 'Output'],
        points: [10, 20, 20],
      );
      expect(find.text('Weighted sections'), findsOneWidget);
      expect(find.text('5-point'), findsNothing);
      final firstCriterion = find.byType(RubricCriterionFields).first;
      final points = find.descendant(
        of: firstCriterion,
        matching: find.byKey(const ValueKey('criterion-max-score-0')),
      );
      final input = find.descendant(
        of: points,
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, '20');
      await tester.pumpAndSettle();
      expect(find.text('30% of rubric'), findsNWidgets(2));
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      expect(notifier.savedPayload!['scale'], 'Points-Based (Sections)');
      expect(
        (notifier.savedPayload!['criteria'] as List).map((c) => c['weight']),
        [30, 30, 40],
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'new sections require user-entered names and keep separate unnamed drafts',
    (tester) async {
      final container = await pumpWeightEditor(tester, [100]);
      Future<void> chooseSetup(String label) async {
        final choice = find.text(label);
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
      }

      Finder input(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      );
      await chooseSetup('Weighted sections');
      expect(
        tester.widget<EditableText>(input('section-name-0')).controller.text,
        '',
      );
      final save = container.read(unsavedChangesSaveDraftProvider)!;
      expect(await save(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Enter a section name.'), findsOneWidget);
      expect(
        tester.widget<EditableText>(input('section-name-0')).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(input('section-name-0'), 'Oral presentation');
      await tester.pumpAndSettle();
      expect(await save(), isTrue);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      notifier.savedPayload = null;
      final add = find.text('Add Section');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(input('section-name-1')).controller.text,
        '',
      );
      expect(
        tester.widget<EditableText>(input('section-name-1')).focusNode.hasFocus,
        isTrue,
      );
      final newCriterion = find.byType(RubricCriterionFields).last;
      final newName = find.descendant(
        of: newCriterion,
        matching: find.byKey(const ValueKey('criterion-name-0')),
      );
      final newInput = find.descendant(
        of: newName,
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(newInput);
      await tester.enterText(newInput, 'Technical quality');
      final distribute = find.text('Distribute evenly');
      await tester.ensureVisible(distribute);
      await tester.tap(distribute);
      await tester.pumpAndSettle();
      await chooseSetup('Standard criteria');
      await chooseSetup('Weighted sections');
      expect(
        tester.widget<EditableText>(input('section-name-0')).controller.text,
        'Oral presentation',
      );
      expect(
        tester.widget<EditableText>(input('section-name-1')).controller.text,
        '',
      );
      expect(await save(), isFalse);
      await tester.pumpAndSettle();
      expect(notifier.savedPayload, isNull);
      expect(
        tester.widget<EditableText>(input('section-name-1')).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(input('section-name-1'), 'Manuscript');
      await tester.pumpAndSettle();
      expect(await save(), isTrue);
      expect(
        (notifier.savedPayload!['criteria'] as List).map((c) => c['section']),
        ['Oral presentation', 'Manuscript'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'criterion action menu opens with the keyboard and preserves the moved row',
    (tester) async {
      await pumpWeightEditor(tester, [60, 40]);
      final first = find.byType(RubricCriterionFields).first;
      final state = tester.state(first);
      final menu = find.byKey(const ValueKey('criterion-actions-0'));
      await tester.ensureVisible(menu);
      tester.widget<ShadButton>(menu).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Move down'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('criterion-0-Move down')));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(RubricCriterionFields).last),
        same(state),
      );
      final movedInput = find
          .descendant(
            of: find.byType(RubricCriterionFields).last,
            matching: find.byType(EditableText),
          )
          .first;
      expect(
        tester.widget<EditableText>(movedInput).controller.text,
        'Criterion 0',
      );
      expect(find.byKey(const ValueKey('criterion-name-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locked rubric displays all four saved percentages as 100 total',
    (tester) async {
      await pumpWeightEditor(tester, [25, 25, 25, 25], readOnly: true);
      expect(find.text('100% of 100%'), findsOneWidget);
      expect(find.byKey(const ValueKey('criterion-actions-0')), findsNothing);
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

  for (final scale in ['10-Point Scale', 'Points-Based (Sections)']) {
    testWidgets(
      '$scale saves long names and focuses an over-limit name without truncating it',
      (tester) async {
        final container = await pumpWeightEditor(
          tester,
          [100],
          scale: scale,
          sections: ['Oral'],
        );
        final name = find.descendant(
          of: find.byKey(const ValueKey('criterion-name-0')),
          matching: find.byType(EditableText),
        );
        await tester.ensureVisible(name);
        final longName = 'Criterion ${'X' * 990}';
        await tester.enterText(name, longName);
        await tester.pumpAndSettle();
        final save = container.read(unsavedChangesSaveDraftProvider)!;
        expect(await save(), isTrue);
        final notifier =
            container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
        expect(
          (notifier.savedPayload!['criteria'] as List).single['name'],
          longName,
        );
        await tester.enterText(name, '${longName}X');
        await tester.pumpAndSettle();
        expect(await save(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Use 1000 characters or fewer.'), findsOneWidget);
        expect(tester.widget<EditableText>(name).controller.text.length, 1001);
        expect(tester.widget<EditableText>(name).focusNode.hasFocus, isTrue);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  }

  testWidgets(
    'save reveals a server-rejected criterion in a collapsed section',
    (tester) async {
      final container = await pumpWeightEditor(
        tester,
        [60, 40],
        scale: 'Points-Based (Sections)',
        sections: ['Oral', 'Manuscript'],
        expandSections: false,
      );
      expect(find.byType(RubricCriterionFields), findsOneWidget);
      final notifier =
          container.read(rubricEngineProvider.notifier) as FakeRubricNotifier;
      notifier.rejectedCriteria = {
        1: {'name': 'This criterion name is unavailable.'},
      };
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('This criterion name is unavailable.'), findsOneWidget);
      final input = find
          .descendant(
            of: find.byType(RubricCriterionFields).last,
            matching: find.byType(EditableText),
          )
          .first;
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      await tester.enterText(input, 'Revised manuscript');
      await tester.pumpAndSettle();
      expect(find.text('This criterion name is unavailable.'), findsNothing);
      notifier.rejectedCriteria = {};
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'new criteria focus their name and can be deleted through the row menu',
    (tester) async {
      await pumpWeightEditor(tester, [100]);
      final add = find.text('Add criterion');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final name = find.descendant(
        of: find.byKey(const ValueKey('criterion-name-1')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(name).focusNode.hasFocus, isTrue);
      await tester.tap(find.byKey(const ValueKey('criterion-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete criterion'));
      await tester.pumpAndSettle();
      expect(find.byType(RubricCriterionFields), findsOneWidget);
      expect(tester.takeException(), isNull);
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
