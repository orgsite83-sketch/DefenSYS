import 'dart:convert';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/widgets/shared_system_assessment_review.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/grading/automatic_assessment_panel.dart';
import 'package:defensys/widgets/grading/shared_selection_correction_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

Map<String, dynamic> _review({bool allowed = true}) => {
  'id': 5,
  'round_id': 7,
  'selected_key': 'c1',
  'teams': [
    {'id': 11, 'name': 'Team ThreadAtlas'},
    {'id': 12, 'name': 'Team ClayCircuit'},
  ],
  'systems': [
    {'key': 'c1', 'title': 'HABI: Artisan Heritage & Craft Exchange Platform'},
    {
      'key': 'c2',
      'title':
          'Echo Loop: Integrated Community Recycling & Circular Economy Management Platform',
    },
    {'key': 'c3', 'title': 'Community Skills Exchange'},
  ],
  'selection_correction': {
    'is_chair': true,
    'can_correct': allowed,
    'from_key': 'c1',
    'unavailable_reason': allowed
        ? ''
        : 'A participating team already has a recorded outcome.',
    'review_token': 'reviewed-group-token',
    'teams': [
      {
        'id': 11,
        'name': 'Team ThreadAtlas',
        'module_titles': {
          'c1': 'Inventory Management',
          'c2': 'Recycling Pickup Coordination',
        },
      },
      {
        'id': 12,
        'name': 'Team ClayCircuit',
        'module_titles': {
          'c1': 'Catalog and Customer Orders',
          'c2': 'ReuseSmart: Secondhand Goods Exchange & Listings',
        },
      },
    ],
    'history': [],
  },
};

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _reviewChange(WidgetTester tester) async {
  await _tap(
    tester,
    find.text(
      'Echo Loop: Integrated Community Recycling & Circular Economy Management Platform',
    ),
  );
  await tester.enterText(
    find.descendant(of: find.byType(Dialog), matching: find.byType(ShadInput)),
    'The panel agreed on Concept 2; the wrong proposal was clicked.',
  );
  await tester.pump();
  await _tap(tester, find.text('Review correction'));
}

void main() {
  setUpAll(() async {
    registerFallbackValue(Uri.parse('http://localhost'));
    await loadPreviewFonts(force: true);
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('shared correction and all-team review fit $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSharedSelectionCorrection(context, _review()),
              child: const Text('Open correction'),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        await _tap(tester, find.text('Open correction'));
        final button = tester.widget<ShadButton>(
          find.ancestor(
            of: find.text('Review correction'),
            matching: find.byType(ShadButton),
          ),
        );
        expect(button.onPressed, isNull);
        await capturePreview(
          tester,
          find.byType(Dialog),
          'shared-correction-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await _reviewChange(tester);
        expect(find.text('Affects all 2 participating teams'), findsOneWidget);
        expect(find.text('Team ThreadAtlas'), findsOneWidget);
        expect(find.text('Team ClayCircuit'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(Dialog),
          'shared-correction-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await _tap(tester, find.text('Cancel'));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'phone correction remains reachable with enlarged text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSharedSelectionCorrection(context, _review()),
            child: const Text('Open correction'),
          ),
        ),
      );
      await _tap(tester, find.text('Open correction'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await _reviewChange(tester);
      expect(find.text('Affects all 2 participating teams'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only explicit confirmation posts the reviewed shared change', (
    tester,
  ) async {
    final client = _Client();
    Map<String, dynamic>? sent;
    bool? corrected;
    when(() => client.post(any(), body: any(named: 'body'))).thenAnswer((
      call,
    ) async {
      expect(
        (call.positionalArguments.first as Uri).path,
        '/api/repository/section-concepts/5/',
      );
      sent =
          jsonDecode(call.namedArguments[#body] as String)
              as Map<String, dynamic>;
      return http.Response('{"selected_key":"c2"}', 200);
    });
    await pumpDefensysWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => corrected =
              await showSharedSelectionCorrection(context, _review()),
          child: const Text('Open correction'),
        ),
      ),
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    await _tap(tester, find.text('Open correction'));
    await _reviewChange(tester);
    expect(sent, isNull);
    await _tap(tester, find.text('Confirm correction'));
    expect(corrected, isTrue);
    expect(sent, {
      'action': 'correct_selection',
      'round_id': 7,
      'concept_key': 'c2',
      'remarks':
          'The panel agreed on Concept 2; the wrong proposal was clicked.',
      'review_token': 'reviewed-group-token',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a stale correction keeps the review and reason without changing selection',
    (tester) async {
      final client = _Client();
      bool? corrected;
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(
          '{"detail":"The shared assessment changed. Refresh and review the affected teams again."}',
          400,
        ),
      );
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => corrected =
                await showSharedSelectionCorrection(context, _review()),
            child: const Text('Open correction'),
          ),
        ),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await _tap(tester, find.text('Open correction'));
      await _reviewChange(tester);
      await _tap(tester, find.text('Confirm correction'));
      expect(corrected, isNull);
      expect(find.text('Review shared-system correction'), findsOneWidget);
      expect(
        find.text(
          'The panel agreed on Concept 2; the wrong proposal was clicked.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('The shared assessment changed.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(corrected, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('each shared team Outcome opens the common correction', (
    tester,
  ) async {
    for (final id in [11, 12]) {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: {
              'id': id,
              'workflow': {
                'outcome_rule': {
                  'automatic': true,
                  'panel_complete': false,
                  'assessments': [],
                },
                'shared_selection_correction': _review(),
              },
            },
            isChair: true,
          ),
        ),
      );
      expect(find.text('Correct shared selection'), findsNothing);
      await capturePreview(
        tester,
        find.byType(AutomaticAssessmentPanel),
        'outcome-selection-menu-$id',
        viewport: true,
      );
      await _tap(tester, find.byTooltip('More actions'));
      await _tap(tester, find.text('Correct shared selection'));
      await _reviewChange(tester);
      expect(find.text('Affects all 2 participating teams'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
    }
  });

  testWidgets(
    'Outcome correction is disabled after an affected result is recorded',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: {
              'id': 11,
              'workflow': {
                'outcome_rule': {
                  'automatic': true,
                  'panel_complete': false,
                  'assessments': [],
                },
                'shared_selection_correction': _review(allowed: false),
              },
            },
            isChair: true,
          ),
        ),
      );
      expect(find.text('Correct shared selection'), findsNothing);
      expect(
        find.text('A participating team already has a recorded outcome.'),
        findsNothing,
      );
      await _tap(tester, find.byTooltip('More actions'));
      final item = tester.widget<ShadContextMenuItem>(
        find.widgetWithText(ShadContextMenuItem, 'Correct shared selection'),
      );
      expect(item.enabled, isFalse);
      expect(
        find.byTooltip('A participating team already has a recorded outcome.'),
        findsOneWidget,
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Shared systems keeps correction in its header menu dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final team = TeamData(
          name: 'Team ThreadAtlas',
          project: 'Inventory Management',
          defenseDate: 'Concept Proposal',
          teamId: '11',
          scope: 'capstone',
          isCapstone: true,
          members: const [],
          memberDetails: const [],
          criteria: const [],
          isPosted: false,
          gradingWorkspace: {
            'shared_review': {..._review(), 'verdict': 'approved'},
            'shared_materials_configured': true,
            'shared_materials': [
              {
                'id': 1,
                'candidate_key': 'c1',
                'label': 'Concept papers',
                'file_name': 'Concept1_HABI.pdf',
                'file_url': '/protected/c1/',
              },
            ],
          },
        );
        await pumpDefensysWidget(
          tester,
          DefensysShadcnScope(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SharedSystemAssessmentReview(
                team: team,
                onView: (_) {},
                onUpdated: () async {},
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        expect(find.text('Correct shared selection'), findsNothing);
        expect(find.text('System selected'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(SharedSystemAssessmentReview),
          'shared-selection-menu-320-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await _tap(tester, find.byTooltip('More actions'));
        expect(find.text('Correct shared selection'), findsOneWidget);
        await _tap(tester, find.text('Correct shared selection'));
        expect(find.text('Correct shared-system selection'), findsOneWidget);
        await _tap(tester, find.text('Cancel'));
        expect(find.text('Correct shared selection'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
