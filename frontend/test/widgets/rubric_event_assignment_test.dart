import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_publish_review.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

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
  void setSaving(bool saving) => state = state.copyWith(isSaving: saving);
  @override
  RubricEngineState build() => const RubricEngineState(
    rubrics: [
      {
        'id': 91,
        'name': 'Prototype panel template',
        'scope': 'pit',
        'evaluation_type': 'panel',
        'target_type': 'both',
        'scale': 'Custom Scale',
        'custom_max_score': 25,
        'display_semester': 'First Semester',
        'criteria': [
          {
            'name': 'Implementation',
            'weight': 50,
            'max_score': 25,
            'scale': 'Custom Scale',
            'target_type': 'team',
          },
          {
            'name': 'Presentation',
            'weight': 50,
            'max_score': 25,
            'scale': 'Custom Scale',
            'target_type': 'individual',
          },
        ],
      },
    ],
    activeSemester: {'id': 1, 'school_year': '2097-2098'},
    semesters: [
      {'id': 1, 'school_year': '2097-2098', 'display_name': 'First Semester'},
      {'id': 2, 'school_year': '2097-2098', 'display_name': 'Second Semester'},
    ],
    defenseStages: [
      {'id': 21, 'label': 'Final Defense'},
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
  int? stageId,
  String target = 'team',
  List<Map<String, dynamic>>? criteria,
  bool readOnly = false,
  String scope = 'pit',
  int semesterId = 1,
  String name = 'Test rubric',
  String scale = '10-Point Scale',
  int? customMaxScore,
  double width = 1400,
  double height = 1100,
  bool dark = false,
  bool creating = false,
}) async {
  tester.view.physicalSize = Size(width, height);
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
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: 'Inter',
        ),
        home: Scaffold(
          body: RubricFullPageEditor(
            initialScope: scope,
            initialEvaluationType: type,
            rubric: creating
                ? null
                : {
                    'id': 1,
                    'name': name,
                    'scope': scope,
                    'semester_id': semesterId,
                    'scale': scale,
                    'custom_max_score': customMaxScore,
                    'evaluation_type': type,
                    'pit_event_id': eventId,
                    'defense_stage_id': stageId,
                    'target_type': target,
                    'event_name': eventId == 11 ? 'Prototype Showcase' : '',
                    'criteria':
                        criteria ??
                        [
                          {
                            'name': 'Quality',
                            'weight': 100,
                            'max_score': customMaxScore ?? 10,
                            'scale': scale,
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

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  testWidgets(
    'saving disables controls without changing selections or marking dirty',
    (tester) async {
      final container = await _pump(tester);
      final notifier =
          container.read(rubricEngineProvider.notifier) as _Rubrics;
      expect(container.read(unsavedChangesProvider), isFalse);
      notifier.setSaving(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container.read(unsavedChangesProvider), isFalse);
      expect(
        tester
            .widget<ShadInput>(find.byKey(const ValueKey('rubric-name')))
            .enabled,
        isFalse,
      );
      notifier.setSaving(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container.read(unsavedChangesProvider), isFalse);
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      expect(notifier.savedPayload?['evaluation_type'], 'panel');
      expect(notifier.savedPayload?['target_type'], 'team');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
  testWidgets('shadcn save confirmation cancels or saves the existing rubric', (
    tester,
  ) async {
    final container = await _pump(tester);
    final notifier = container.read(rubricEngineProvider.notifier) as _Rubrics;
    await tester.ensureVisible(find.text('Save as Draft'));
    await tester.tap(find.text('Save as Draft'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ShadDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(notifier.savedPayload, isNull);
    await tester.tap(find.text('Save as Draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();
    expect(notifier.savedPayload?['status'], 'draft');
    expect(find.byType(ShadDialog), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  for (final (scope, type) in [
    ('pit', 'panel'),
    ('pit', 'peer'),
    ('capstone', 'panel'),
    ('capstone', 'adviser'),
    ('capstone', 'peer'),
  ]) {
    testWidgets('$scope $type reviews edits before publishing', (tester) async {
      final container = await _pump(
        tester,
        scope: scope,
        type: type,
        eventId: scope == 'pit' ? 11 : null,
        stageId: scope == 'capstone' ? 21 : null,
        target: type == 'peer' ? 'individual' : 'both',
        scale: 'Custom Scale',
        customMaxScore: 25,
        criteria: [
          {
            'name': 'Implementation',
            'description': 'The system meets the project requirements.',
            'weight': 33.33,
            'max_score': 25,
            'target_type': type == 'peer' ? 'individual' : 'team',
          },
          {
            'name': 'Presentation',
            'description': 'Explains design choices and answers questions.',
            'weight': 66.67,
            'max_score': 25,
            'target_type': 'individual',
          },
        ],
      );
      final notifier =
          container.read(rubricEngineProvider.notifier) as _Rubrics;
      final nameField = find.descendant(
        of: find.byKey(const ValueKey('rubric-name')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(nameField, 'Final project rubric');
      await tester.ensureVisible(find.text('Publish Rubric'));
      await tester.tap(find.text('Publish Rubric'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final review = find.byType(RubricPublishReview);
      Finder reviewText(String text) =>
          find.descendant(of: review, matching: find.text(text));
      expect(reviewText('Final project rubric'), findsOneWidget);
      expect(reviewText(scope == 'pit' ? 'PIT' : 'Capstone'), findsOneWidget);
      expect(reviewText('First Semester'), findsOneWidget);
      expect(reviewText('Custom (25 points)'), findsOneWidget);
      expect(reviewText('Evaluation criteria (2)'), findsOneWidget);
      expect(reviewText('1. Implementation'), findsOneWidget);
      expect(reviewText('2. Presentation'), findsOneWidget);
      expect(reviewText('33.33%'), findsOneWidget);
      expect(reviewText('66.67%'), findsOneWidget);
      expect(reviewText('Total weight: 100%'), findsOneWidget);
      expect(
        reviewText('Explains design choices and answers questions.'),
        findsOneWidget,
      );
      expect(
        reviewText('Individual · 25 points maximum'),
        type == 'peer' ? findsNWidgets(2) : findsOneWidget,
      );
      expect(
        reviewText(scope == 'pit' ? 'Prototype Showcase' : 'Final Defense'),
        findsOneWidget,
      );
      if (scope == 'pit' && type == 'panel') {
        expect(
          find.descendant(
            of: review,
            matching: find.textContaining(
              'current rubric in that slot will be replaced',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(notifier.savedPayload, isNull);
      await tester.tap(find.byKey(const ValueKey('rubric-review-back')));
      await tester.pumpAndSettle();
      expect(review, findsNothing);
      expect(container.read(unsavedChangesProvider), isTrue);
      expect(
        tester.widget<EditableText>(nameField).controller.text,
        'Final project rubric',
      );
      expect(notifier.savedPayload, isNull);

      await tester.ensureVisible(find.text('Publish Rubric'));
      await tester.tap(find.text('Publish Rubric'));
      await tester.pumpAndSettle();
      final reviewed = tester.widget<RubricPublishReview>(review).payload;
      await tester.tap(find.byKey(const ValueKey('rubric-review-publish')));
      await tester.pumpAndSettle();
      expect(review, findsNothing);
      expect(notifier.savedPayload, reviewed);
      expect(notifier.savedPayload?['status'], 'published');
      expect(container.read(unsavedChangesProvider), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  }

  for (final dark in [false, true]) {
    for (final (width, height) in [
      (320.0, 640.0),
      (390.0, 780.0),
      (1280.0, 714.0),
      (1920.0, 900.0),
    ]) {
      testWidgets('publish review scrolls at $width, dark=$dark', (
        tester,
      ) async {
        final scope = width == 390 || width == 1920 ? 'capstone' : 'pit';
        final container = await _pump(
          tester,
          scope: scope,
          dark: dark,
          width: width,
          height: height,
          criteria: [
            for (var i = 0; i < 10; i++)
              {
                'name': 'Project criterion ${i + 1}',
                'description': i == 0
                    ? ''
                    : 'Demonstrates a working solution, explains the implementation, '
                          'and supports the results with clear evidence.',
                'weight': 10,
                'max_score': 10,
              },
          ],
        );
        await tester.ensureVisible(find.text('Publish Rubric'));
        await tester.tap(find.text('Publish Rubric'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final review = find.byType(RubricPublishReview);
        expect(
          find.descendant(
            of: review,
            matching: find.text('Unassigned template'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: review,
            matching: find.textContaining(
              'published as an unassigned template',
            ),
          ),
          findsOneWidget,
        );
        await capturePreview(
          tester,
          review,
          'rubric-review-${dark ? 'dark' : 'light'}-${width.toInt()}',
          viewport: true,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('rubric-review-criterion-0')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: review,
            matching: find.text('No evaluation guidelines provided.'),
          ),
          findsOneWidget,
        );
        await capturePreview(
          tester,
          review,
          'rubric-review-criteria-${dark ? 'dark' : 'light'}-${width.toInt()}',
          viewport: true,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('rubric-review-criterion-9')),
        );
        await tester.pumpAndSettle();
        final publish = tester.getRect(
          find.byKey(const ValueKey('rubric-review-publish')),
        );
        expect(publish.top, greaterThanOrEqualTo(0));
        expect(publish.bottom, lessThanOrEqualTo(height));
        expect(tester.takeException(), isNull);
        expect(
          (container.read(rubricEngineProvider.notifier) as _Rubrics)
              .savedPayload,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('rubric-review-back')));
        await tester.pumpAndSettle();
      });
    }
  }

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0, 1920.0]) {
      testWidgets('full rubric editor fits $width pixels, dark=$dark', (
        tester,
      ) async {
        await _pump(tester, width: width, dark: dark, creating: true);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('rubric-editor-content')))
              .width,
          width - (width < 600 ? 32 : 80),
        );
        await capturePreview(
          tester,
          find.byType(RubricFullPageEditor),
          'rubric-editor-${dark ? 'dark' : 'light'}-${width.toInt()}',
          viewport: true,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('criterion-weight-0')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(RubricFullPageEditor),
          'rubric-criteria-${dark ? 'dark' : 'light'}-${width.toInt()}',
          viewport: true,
        );
        await tester.ensureVisible(find.text('Publish Rubric'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'copy rubric previews and applies custom scale at $width pixels',
      (tester) async {
        await _pump(tester, width: width, creating: true);
        await tester.tap(find.text('Copy from rubric'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Prototype panel template').first);
        await tester.pumpAndSettle();
        expect(find.text('Implementation'), findsOneWidget);
        expect(find.text('Presentation'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(ShadDialog),
          'rubric-copy-${width.toInt()}',
          viewport: true,
        );
        await tester.tap(find.text('Copy rubric'));
        await tester.pumpAndSettle();
        expect(find.byType(ShadDialog), findsNothing);
        expect(find.text('25 points maximum'), findsNWidgets(2));
        expect(find.text('100% of 100%'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  }
  testWidgets(
    'assigns an existing event, warns on replacement and sends its ID',
    (tester) async {
      final container = await _pump(tester);
      final picker = find.byKey(const ValueKey('pit-event-1-null'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Next Term Event'), findsNothing);
      expect(find.text('Completed Pitch (Locked)'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Completed Pitch (Locked)'),
          matching: find.byType(ShadOption<int>),
        ),
        findsNothing,
      );
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

  testWidgets('editing retains its original semester and filters events', (
    tester,
  ) async {
    final container = await _pump(tester, semesterId: 2);
    expect(find.byKey(const ValueKey('rubric-semester-info')), findsOneWidget);
    expect(find.text('Second Semester'), findsOneWidget);
    expect(find.byKey(const ValueKey('sem-2')), findsNothing);
    final picker = find.byKey(const ValueKey('pit-event-2-null'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('Prototype Showcase'), findsNothing);
    await tester.tap(find.text('Next Term Event').last);
    await tester.pumpAndSettle();
    expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
    final payload = (container.read(rubricEngineProvider.notifier) as _Rubrics)
        .savedPayload!;
    expect(payload['semester_id'], 2);
    expect(payload['pit_event_id'], 13);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('peer uses individual scoring as information', (tester) async {
    await _pump(tester, type: 'peer');
    expect(
      find.byKey(const ValueKey('peer-individual-scoring')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('target-individual')), findsNothing);
    expect(
      find.text('Peer evaluations always grade each student individually.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'suggested names update until customized and reset restores them',
    (tester) async {
      const suggested = '2nd Year PIT — Panel Rubric';
      await _pump(tester, name: suggested);
      final name = find.descendant(
        of: find.byKey(const ValueKey('rubric-name')),
        matching: find.byType(EditableText),
      );
      await tester.tap(find.text('Peer').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(name).controller.text,
        endsWith('Peer Rubric'),
      );
      await tester.enterText(name, 'Prototype presentation rubric');
      await tester.tap(find.text('Panel').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(name).controller.text,
        'Prototype presentation rubric',
      );
      await tester.tap(find.byKey(const ValueKey('reset-rubric-name')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(name).controller.text, suggested);
    },
  );

  testWidgets(
    'custom scale updates saved criterion maxima and rejects invalid input',
    (tester) async {
      final container = await _pump(tester);
      await tester.tap(find.text('Custom').first);
      await tester.pumpAndSettle();
      final points = find.descendant(
        of: find.byKey(const ValueKey('custom-scale-points')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(points, '0');
      await tester.pumpAndSettle();
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isFalse);
      await tester.enterText(points, '25');
      await tester.pumpAndSettle();
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final payload =
          (container.read(rubricEngineProvider.notifier) as _Rubrics)
              .savedPayload!;
      expect(payload['custom_max_score'], 25);
      expect((payload['criteria'] as List).single['max_score'], 25);
      expect((payload['criteria'] as List).single['scale'], 'Custom Scale');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'saved custom scale loads its maximum and clears event assignment',
    (tester) async {
      final container = await _pump(
        tester,
        eventId: 11,
        scale: 'Custom Scale',
        customMaxScore: 50,
      );
      final points = find.descendant(
        of: find.byKey(const ValueKey('custom-scale-points')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(points).controller.text, '50');
      final picker = find.byKey(const ValueKey('pit-event-1-11'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unassigned template').last);
      await tester.pumpAndSettle();
      expect(await container.read(unsavedChangesSaveDraftProvider)!(), isTrue);
      final payload =
          (container.read(rubricEngineProvider.notifier) as _Rubrics)
              .savedPayload!;
      expect(payload['pit_event_id'], isNull);
      expect(payload['custom_max_score'], 50);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'read-only assignment cannot change and Capstone keeps stage selector',
    (tester) async {
      await _pump(tester, eventId: 11, readOnly: true);
      final picker = tester.widget<ShadSelect<int>>(
        find.byKey(const ValueKey('pit-event-1-11')),
      );
      expect(picker.enabled, isFalse);
      expect(find.text('Prototype Showcase'), findsOneWidget);
      await _pump(tester, scope: 'capstone');
      expect(find.text('PIT event (optional)'), findsNothing);
      expect(find.text('Defense stage (optional)'), findsOneWidget);
    },
  );
}
