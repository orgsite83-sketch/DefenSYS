import 'package:defensys/screens/web/admin/academic_periods/widgets/semester_transition_dialog.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> _preview() => {
  'current_semester': {'display_name': '1st Semester, AY 2027–2028'},
  'target_semester': {'display_name': '2nd Semester, AY 2027–2028'},
  'preview_revision': 'review-v1',
  'can_switch': true,
  'issues': <dynamic>[],
  'capstone_review': {
    'kind': 'close_cycle',
    'teams': [
      {
        'team_id': 1,
        'name': 'Team Cedar',
        'project_title': 'Laboratory booking',
        'outcome': 'completed',
        'destination': 'history',
        'can_include': false,
        'reason': 'All required work is passed and cleared.',
      },
      {
        'team_id': 2,
        'name': 'Team Atlas',
        'project_title': 'Campus asset tracker',
        'outcome': 'failed',
        'destination': 'extended',
        'can_include': true,
        'requires_project_choice': true,
        'original_cohort': '2nd Semester, AY 2026–2027',
        'extension_deadline': '1st Semester, AY 2028–2029',
        'reason': 'Official Failed result. Target enrollment verified.',
      },
      {
        'team_id': 3,
        'name': 'Team Orion',
        'project_title': 'Queue management',
        'outcome': 'failed',
        'destination': 'institutional_review',
        'can_include': false,
        'reason': 'Extension deadline reached.',
      },
    ],
  },
};

class _Periods extends AcademicPeriodNotifier {
  Map<String, dynamic>? submitted;
  bool reject = false;
  int calls = 0;
  @override
  AcademicPeriodState build() => const AcademicPeriodState(isLoading: false);
  @override
  Future<Map<String, dynamic>?> fetchTransitionPreview(
    int semesterId, {
    bool returning = false,
  }) async => _preview();
  @override
  Future<bool> activateSemester(
    int semesterId, {
    bool force = false,
    String reason = '',
    bool returning = false,
    List<Map<String, dynamic>> decisions = const [],
    String previewRevision = '',
    String? requestId,
  }) async {
    calls++;
    submitted = {
      'semester_id': semesterId,
      'decisions': decisions,
      'reason': reason,
      'preview_revision': previewRevision,
      'request_id': requestId,
      'returning': returning,
    };
    if (reject)
      state = state.copyWith(error: 'Enrollment changed. Refresh the review.');
    return !reject;
  }
}

Future<_Periods> _pump(
  WidgetTester tester, {
  bool dark = false,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notifier = _Periods();
  await pumpDefensysWidget(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => RepaintBoundary(
            key: const ValueKey('transition-preview'),
            child: SemesterTransitionDialog(
              semesterId: 20,
              preview: _preview(),
            ),
          ),
        ),
        child: const Text('Open review'),
      ),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
    overrides: [academicPeriodProvider.overrideWith(() => notifier)],
  );
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
  return notifier;
}

Finder _continue() => find.widgetWithText(ShadButton, 'Continue');
Finder _confirm() => find.widgetWithText(ShadButton, 'Confirm switch');

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('all teams are reviewed; project choice and title are required', (
    tester,
  ) async {
    final notifier = await _pump(tester);
    expect(find.text('Team Cedar'), findsOneWidget);
    expect(find.text('Team Atlas'), findsOneWidget);
    expect(find.text('Team Orion'), findsOneWidget);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('transition-preview')),
      'capstone-transition-review-light',
    );
    await tester.tap(_continue());
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(_continue()).onPressed, isNull);
    await tester.tap(find.text('Start a new project'));
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(_continue()).onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byType(ShadInput),
        matching: find.byType(EditableText),
      ),
      'Campus equipment locator',
    );
    await tester.pumpAndSettle();
    await capturePreview(
      tester,
      find.byKey(const ValueKey('transition-preview')),
      'capstone-transition-project-choice',
    );
    await tester.tap(_continue());
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(_confirm()).onPressed, isNull);
    await tester.enterText(
      find.byType(EditableText),
      'Extension decision 2027-11',
    );
    await tester.pumpAndSettle();
    await capturePreview(
      tester,
      find.byKey(const ValueKey('transition-preview')),
      'capstone-transition-confirm-light',
    );
    await tester.tap(_confirm());
    await tester.pumpAndSettle();
    expect(notifier.calls, 1);
    expect(notifier.submitted!['preview_revision'], 'review-v1');
    final choice = (notifier.submitted!['decisions'] as List).single as Map;
    expect(choice['team_id'], 2);
    expect(choice['project_choice'], 'new');
    expect(choice['project_title'], 'Campus equipment locator');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rejected confirmation retains project choices and allows refreshed review',
    (tester) async {
      final notifier = await _pump(tester);
      notifier.reject = true;
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue existing project'));
      await tester.pumpAndSettle();
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText),
        'Approved continuation',
      );
      await tester.pumpAndSettle();
      await tester.tap(_confirm());
      await tester.pumpAndSettle();
      expect(
        find.text('Enrollment changed. Refresh the review.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh review · keep my choices'));
      await tester.pumpAndSettle();
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      expect(tester.widget<ShadButton>(_continue()).onPressed, isNotNull);
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      expect(find.text('Approved continuation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1200.0, 390.0, 320.0]) {
    testWidgets('review and choices fit dark theme at $width', (tester) async {
      await _pump(tester, dark: true, width: width);
      expect(tester.takeException(), isNull);
      if (width == 1200)
        await capturePreview(
          tester,
          find.byKey(const ValueKey('transition-preview')),
          'capstone-transition-review-dark',
        );
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue existing project'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
