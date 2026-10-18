import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    user: {
      'id': 1,
      'role': 'faculty',
      'is_pit_lead': true,
      'pit_lead_year': '2nd Year',
    },
  );
}

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('faculty');
  @override
  DashboardState build() => DashboardState(data: {'pit_lead_year': '2nd Year'});
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Rubrics extends RubricEngineNotifier {
  Map<String, dynamic>? savedPayload;
  @override
  RubricEngineState build() => const RubricEngineState(
    activeSemester: {'id': 1, 'school_year': '2097-2098'},
    semesters: [
      {'id': 1, 'school_year': '2097-2098', 'display_name': 'First Semester'},
      {'id': 2, 'school_year': '2097-2098', 'display_name': 'Second Semester'},
    ],
    pitEvents: [
      {
        'id': 11,
        'semester_id': 1,
        'event_name': 'Prototype Showcase',
        'panel_rubric_id': 91,
      },
      {
        'id': 12,
        'semester_id': 1,
        'event_name': 'Completed Pitch',
        'is_locked': true,
      },
      {'id': 13, 'semester_id': 2, 'event_name': 'Next Term Event'},
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
  }) async {}
  @override
  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async {
    savedPayload = payload;
    return true;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String type = 'panel',
  int? eventId,
  bool readOnly = false,
  String scope = 'pit',
}) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_Auth.new),
      rubricEngineProvider.overrideWith(_Rubrics.new),
      dashboardProvider('faculty').overrideWith(_Dashboard.new),
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
              'name': 'Test rubric',
              'scope': scope,
              'semester_id': 1,
              'evaluation_type': type,
              'pit_event_id': eventId,
              'event_name': eventId == 11 ? 'Prototype Showcase' : '',
              'criteria': [
                {'name': 'Quality', 'weight': 100, 'max_score': 10},
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

void main() {
  testWidgets(
    'assigns an existing event, warns on replacement and sends its ID',
    (tester) async {
      final container = await _pump(tester);
      final picker = find.byKey(const ValueKey('pit-event-1-null'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Next Term Event'), findsNothing);
      final locked = tester.widget<DropdownMenuItem<int?>>(
        find
            .ancestor(
              of: find.text('Completed Pitch (Locked)').last,
              matching: find.byType(DropdownMenuItem<int?>),
            )
            .last,
      );
      expect(locked.enabled, isFalse);
      await tester.tap(find.text('Prototype Showcase').last);
      await tester.pumpAndSettle();
      expect(container.read(unsavedChangesProvider), isTrue);
      expect(
        find.text(
          "Saving will replace the selected event's current panel rubric.",
        ),
        findsOneWidget,
      );
      final save = container.read(unsavedChangesSaveDraftProvider)!;
      expect(await save(), isTrue);
      expect(
        (container.read(rubricEngineProvider.notifier) as _Rubrics)
            .savedPayload?['pit_event_id'],
        11,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'semester change clears assignment and offers the correct events',
    (tester) async {
      await _pump(tester, eventId: 11);
      expect(find.text('Prototype Showcase'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sem-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second Semester').last);
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('pit-event-2-null'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Next Term Event'), findsWidgets);
      expect(find.text('Prototype Showcase'), findsNothing);
      await tester.tap(find.text('Next Term Event').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('peer target stays disabled and red help popup explains why', (
    tester,
  ) async {
    await _pump(tester, type: 'peer');
    final target = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('target-individual')),
    );
    expect(target.onChanged, isNull);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('target-individual'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('scale-10-Point Scale'))).dy,
      );
    expect(
      find.text('Peer evaluations always grade each student individually.'),
      findsOneWidget,
    );
    final help = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.message?.startsWith(
                'Each student evaluates their teammates',
              ) ==
              true,
    );
    final tooltip = tester.widget<Tooltip>(help);
    expect((tooltip.decoration as BoxDecoration).color, isNot(Colors.black));
    await tester.tap(
      find.descendant(of: help, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text(tooltip.message!), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 9));
  });

  testWidgets(
    'read-only assignment cannot change and Capstone keeps stage selector',
    (tester) async {
      await _pump(tester, eventId: 11, readOnly: true);
      final picker = tester.widget<DropdownButtonFormField<int?>>(
        find.byKey(const ValueKey('pit-event-1-11')),
      );
      expect(picker.onChanged, isNull);
      expect(find.text('Prototype Showcase'), findsOneWidget);
      await _pump(tester, scope: 'capstone');
      expect(find.text('ASSIGN TO PIT EVENT (OPTIONAL)'), findsNothing);
      expect(find.text('ASSIGN TO DEFENSE STAGE (OPTIONAL)'), findsOneWidget);
    },
  );
}
