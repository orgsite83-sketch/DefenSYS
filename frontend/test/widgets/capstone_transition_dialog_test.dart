import 'package:defensys/screens/web/admin/academic_periods/widgets/semester_transition_dialog.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> _preview({bool blocked = false}) => {
  'current_semester': {'display_name': '2nd Semester, AY 2025–2026'},
  'target_semester': {'display_name': '1st Semester, AY 2026–2027'},
  'preview_revision': 'review-v1',
  'can_switch': !blocked,
  'impact_counts': {'pit_teams': 2},
  'effects': [
    {
      'key': 'pit_teams',
      'count': 2,
      'message':
          'This semester has 2 PIT teams. PIT starts fresh next semester.',
    },
    {
      'key': 'capstone_evaluation_closure',
      'message':
          'Peer and adviser submissions close automatically for the outgoing semester.',
    },
  ],
  'issues': [
    if (blocked)
      {
        'key': 'pending_grades',
        'blocking': true,
        'message': '3 grade records are still pending.',
        'route': '/admin/grade-center',
        'action_label': 'Review grades',
      },
  ],
  'capstone_review': {
    'kind': 'continue',
    'teams': [
      {
        'team_id': 1,
        'name': 'Team Cedar',
        'project_title': 'Laboratory booking',
        'outcome': 'open',
        'destination': 'continue',
        'can_include': true,
        'pending_enrollment': true,
        'section_progression': {'source_section': 'BSIT-3A', 'section': 'BSIT-4A', 'issues': []},
      },
      {
        'team_id': 2,
        'name': 'Team Atlas',
        'project_title': 'Campus asset tracker',
        'outcome': 'failed',
        'destination': 'failed_history',
        'can_include': false,
        'reason':
            'Finalized Failed. Returning students join a new Capstone 1 intake.',
      },
      if (blocked)
        {
          'team_id': 3,
          'name': 'Team Orion',
          'project_title': 'Queue management',
          'outcome': 'needs_review',
          'destination': 'needs_review',
          'can_include': false,
          'reason': 'Source-term clearance is incomplete.',
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
  Future<Map<String, dynamic>?> fetchTransitionPreview(int semesterId) async =>
      _preview();
  @override
  Future<bool> activateSemester(
    int semesterId, {
    bool force = false,
    String reason = '',
    String previewRevision = '',
    String? requestId,
  }) async {
    calls++;
    submitted = {
      'semester_id': semesterId,
      'force': force,
      'reason': reason,
      'preview_revision': previewRevision,
      'request_id': requestId,
    };
    if (reject) {
      state = state.copyWith(
        error: 'The assessment changed. Refresh the review.',
      );
    }
    return !reject;
  }
}

Future<_Periods> _pump(
  WidgetTester tester, {
  bool dark = false,
  double width = 1200,
  bool blocked = false,
  Map<String, dynamic>? preview,
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
              preview: preview ?? _preview(blocked: blocked),
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
  testWidgets(
    'continuation is ready before enrollment with no recovery choices',
    (tester) async {
      final notifier = await _pump(tester);
      expect(find.text('Ready for Capstone 2'), findsOneWidget);
      expect(find.text('Section: BSIT-3A → BSIT-4A'), findsOneWidget);
      expect(find.text('Failed · History'), findsOneWidget);
      expect(find.text('Needs review'), findsNothing);
      expect(find.text('Enrollment needed'), findsNothing);
      expect(find.text('Returning teams'), findsNothing);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('transition-preview')),
        'capstone-transition-review-light',
      );
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      final outgoing = find.byKey(const ValueKey('semester-switch-outgoing'));
      final incoming = find.byKey(const ValueKey('semester-switch-incoming'));
      expect(tester.widget(outgoing), isA<ShadCard>());
      expect(tester.widget(incoming), isA<ShadCard>());
      expect(
        find.descendant(of: incoming, matching: find.text('1 Capstone team')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: incoming,
          matching: find.text('Continue to Capstone 2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: outgoing, matching: find.text('2 PIT teams')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: outgoing,
          matching: find.textContaining('1 failed Capstone team'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: incoming,
          matching: find.textContaining('1 failed Capstone team'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: outgoing, matching: find.text('1 Capstone team')),
        findsNothing,
      );
      expect(tester.getTopLeft(outgoing).dy, tester.getTopLeft(incoming).dy);
      expect(
        tester.getTopLeft(outgoing).dx,
        lessThan(tester.getTopLeft(incoming).dx),
      );
      expect(
        find.text('Student enrollment can be rolled over after this switch.'),
        findsOneWidget,
      );
      expect(find.text('Semester switch summary'), findsOneWidget);
      expect(find.text('Next active semester'), findsOneWidget);
      expect(find.text('Outgoing semester'), findsOneWidget);
      expect(find.text('Ready to activate'), findsOneWidget);
      final summary = find.byKey(const ValueKey('semester-switch-summary'));
      expect(find.descendant(of: summary, matching: outgoing), findsOneWidget);
      expect(
        find.descendant(
          of: incoming,
          matching: find.text('PIT starts fresh next semester.'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Peer and adviser submissions close automatically'),
        findsOneWidget,
      );
      expect(find.text('Needs attention before switching'), findsNothing);
      expect(
        find.byKey(const ValueKey('semester-switch-attention')),
        findsNothing,
      );
      expect(find.text('View outgoing teams'), findsNothing);
      expect(find.text('Open evaluation settings'), findsNothing);
      expect(find.byType(ShadCheckbox), findsNothing);
      expect(tester.widget<ShadButton>(_confirm()).onPressed, isNotNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('transition-preview')),
        'capstone-transition-confirm-light',
      );
      await tester.tap(_confirm());
      await tester.pumpAndSettle();
      expect(notifier.calls, 1);
      expect(notifier.submitted!['preview_revision'], 'review-v1');
      expect(notifier.submitted!['request_id'], isNotEmpty);
      expect(notifier.submitted!.containsKey('decisions'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a fresh Capstone 1 intake keeps completed records in the outgoing card',
    (tester) async {
      final preview = _preview();
      preview['current_semester'] = {
        'display_name': '1st Semester, AY 2026–2027',
      };
      preview['target_semester'] = {
        'display_name': '2nd Semester, AY 2026–2027',
      };
      preview['capstone_review'] = {
        'kind': 'close_cycle',
        'teams': [
          {
            'team_id': 1,
            'name': 'Team Cedar',
            'project_title': 'Laboratory booking',
            'outcome': 'completed',
            'destination': 'history',
            'can_include': false,
          },
        ],
      };
      await _pump(tester, preview: preview);
      await tester.tap(_continue());
      await tester.pumpAndSettle();
      final outgoing = find.byKey(const ValueKey('semester-switch-outgoing'));
      final incoming = find.byKey(const ValueKey('semester-switch-incoming'));
      expect(
        find.descendant(
          of: outgoing,
          matching: find.textContaining('1 completed Capstone team'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: incoming,
          matching: find.text('New Capstone 1 intake'),
        ),
        findsOneWidget,
      );
      expect(find.text('Continue to Capstone 2'), findsNothing);
      expect(tester.widget<ShadButton>(_confirm()).enabled, isTrue);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('transition-preview')),
        'semester-cards-new-intake',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('semester blockers need a reason for calendar override', (
    tester,
  ) async {
    final notifier = await _pump(tester, blocked: true);
    await tester.tap(_continue());
    await tester.pumpAndSettle();
    expect(find.text('Needs attention before switching'), findsOneWidget);
    expect(find.text('3 grade records are still pending.'), findsOneWidget);
    expect(find.text('Review grades'), findsOneWidget);
    final attention = find.byKey(const ValueKey('semester-switch-attention'));
    expect(tester.widget(attention), isA<ShadCard>());
    expect(
      find.descendant(of: attention, matching: find.text('Review grades')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('semester-switch-summary')),
        matching: find.text('Review grades'),
      ),
      findsNothing,
    );
    expect(find.text('Ready to activate'), findsNothing);
    expect(tester.widget<ShadButton>(_confirm()).onPressed, isNull);
    expect(tester.widget<ShadButton>(_confirm()).enabled, isFalse);
    await tester.ensureVisible(find.byType(ShadCheckbox));
    await tester.pumpAndSettle();
    await capturePreview(
      tester,
      find.byKey(const ValueKey('transition-preview')),
      'capstone-confirm-attention-light',
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(ShadCheckbox)) + const Offset(9, 9),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(_confirm()).onPressed, isNull);
    await tester.ensureVisible(find.byType(EditableText));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText),
      'Approved calendar exception',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(_confirm()).enabled, isTrue);
    await tester.tap(_confirm());
    await tester.pumpAndSettle();
    expect(notifier.submitted!['force'], true);
    expect(notifier.submitted!['reason'], 'Approved calendar exception');
  });
  testWidgets('rejected confirmation offers a fresh review', (tester) async {
    final notifier = await _pump(tester);
    notifier.reject = true;
    await tester.tap(_continue());
    await tester.pumpAndSettle();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();
    expect(
      find.text('The assessment changed. Refresh the review.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh review'));
    await tester.pumpAndSettle();
    expect(find.text('Ready for Capstone 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [1200.0, 390.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets('review fits $width ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final blocked = width == 390 && dark;
        await _pump(tester, width: width, dark: dark, blocked: blocked);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('transition-preview')),
          'capstone-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(_continue());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final outgoing = find.byKey(const ValueKey('semester-switch-outgoing'));
        final incoming = find.byKey(const ValueKey('semester-switch-incoming'));
        if (width < 640) {
          expect(
            tester.getTopLeft(outgoing).dy,
            lessThan(tester.getTopLeft(incoming).dy),
          );
          expect(
            tester.getSize(outgoing).width,
            tester.getSize(incoming).width,
          );
        }
        if (blocked) {
          await tester.ensureVisible(find.byType(ShadCheckbox));
          await tester.pumpAndSettle();
          expect(tester.widget<ShadButton>(_confirm()).onPressed, isNull);
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('transition-preview')),
          'capstone-confirm-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }
}
