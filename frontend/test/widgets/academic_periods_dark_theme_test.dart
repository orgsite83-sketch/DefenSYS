import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/screens/web/admin/academic_periods/widgets/academic_cycle_card.dart';

import '../helpers/capture_preview.dart';

class _FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState(
    schoolYears: [
      {
        'id': 2,
        'label': '2025-2026',
        'semesters': [
          {'id': 9, 'label': '2nd Semester', 'is_active': false},
        ],
      },
      {
        'id': 1,
        'label': '2026-2027',
        'semesters': [
          {
            'id': 10,
            'label': '1st Semester',
            'is_active': true,
            'starts_on': '2026-01-01',
            'ends_on': '2026-06-01',
            'capstone_program_phase': 'capstone_2',
            'capstone_peer_evaluation_enabled': true,
            'capstone_adviser_grading_enabled': false,
          },
          {
            'id': 11,
            'label': '2nd Semester',
            'is_active': false,
            'starts_on': '2026-07-01',
            'ends_on': '2026-12-01',
            'capstone_program_phase': 'capstone_1',
            'capstone_peer_evaluation_enabled': false,
            'capstone_adviser_grading_enabled': false,
          },
        ],
      },
    ],
    // An older selection must not hide the current semester on initial load.
    selectedSchoolYearId: 2,
    activeSemester: {
      'id': 10,
      'school_year_id': 1,
      'display_name': '1st Semester, A.Y. 2026-2027',
    },
  );

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class _LoadingAcademicPeriodNotifier extends _FakeAcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState(isLoading: true);

  void finishLoading() => state = super.build();
}

void main() {
  testWidgets(
    'Current semester remains clear across widths, themes, and larger text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await loadPreviewFonts(force: true);
      try {
        for (final config in [
          (1920.0, false, 1.0),
          (1920.0, true, 1.0),
          (1280.0, false, 1.0),
          (1280.0, true, 1.0),
          (900.0, false, 1.0),
          (900.0, true, 1.0),
          (390.0, false, 1.0),
          (390.0, true, 1.0),
          (320.0, false, 1.25),
          (320.0, true, 1.25),
        ]) {
          final (width, dark, scale) = config;
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                academicPeriodProvider.overrideWith(
                  _FakeAcademicPeriodNotifier.new,
                ),
              ],
              child: MaterialApp(
                theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const Scaffold(body: AcademicPeriodsScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Academic periods'), findsOneWidget);
          expect(find.text('Active'), findsOneWidget);
          expect(find.text('Open semester'), findsNWidgets(2));
          expect(find.bySemanticsLabel('Peer enabled'), findsOneWidget);
          expect(find.bySemanticsLabel('Adviser disabled'), findsNWidgets(2));
          expect(find.text('2nd Semester'), findsOneWidget);
          expect(find.text('Upcoming'), findsNothing);
          expect(find.text('LIVE'), findsNothing);
          expect(
            tester.getTopLeft(find.text('A.Y. 2026-2027')).dy,
            lessThan(tester.getTopLeft(find.text('A.Y. 2025-2026')).dy),
          );
          final year = tester.widget<Container>(
            find.byKey(const ValueKey('academic-year-1')),
          );
          final decoration = year.decoration! as BoxDecoration;
          expect(
            decoration.color,
            dark ? DefensysTokens.mistSurface : DefensysTokens.surface,
          );
          expect(
            (decoration.border! as Border).top.color,
            dark ? DefensysTokens.mistBorder : DefensysTokens.border,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width / dark=$dark / scale=$scale',
          );
          await capturePreview(
            tester,
            find.byType(AcademicPeriodsScreen),
            'academic-periods-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );

          await tester.ensureVisible(find.text('A.Y. 2025-2026'));
          await tester.tap(find.text('A.Y. 2025-2026'));
          await tester.pumpAndSettle();
          expect(find.text('2nd Semester'), findsNWidgets(2));
          expect(find.text('Inactive'), findsNWidgets(2));
          expect(find.text('Upcoming'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Year headers support Tab, Space, and Enter', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(_FakeAcademicPeriodNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: AcademicPeriodsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Add school year.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Current year.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('1st Semester'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('1st Semester'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loading layout fits each theme and resolves into semester rows', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      for (final config in [
        (1280.0, false),
        (1280.0, true),
        (320.0, false),
        (320.0, true),
      ]) {
        tester.view.physicalSize = Size(config.$1, 1000);
        tester.view.devicePixelRatio = 1;
        final notifier = _LoadingAcademicPeriodNotifier();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [academicPeriodProvider.overrideWith(() => notifier)],
            child: MaterialApp(
              theme: config.$2 ? AppTheme.mistDarkTheme : AppTheme.theme,
              home: const Scaffold(body: AcademicPeriodsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AcademicCycleSkeleton), findsOneWidget);
        expect(
          find.bySemanticsLabel('Loading academic periods'),
          findsOneWidget,
        );
        expect(find.text('No school years yet'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(AcademicPeriodsScreen),
          'academic-periods-loading-${config.$1.toInt()}-${config.$2 ? 'dark' : 'light'}',
          viewport: true,
        );
        notifier.finishLoading();
        await tester.pumpAndSettle();
        expect(find.byType(AcademicCycleSkeleton), findsNothing);
        expect(find.text('Active'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    } finally {
      semantics.dispose();
    }
  });
}
