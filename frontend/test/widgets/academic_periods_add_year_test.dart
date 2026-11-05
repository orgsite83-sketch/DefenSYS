import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/academic_periods/widgets/add_school_year_dialog.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _FakeEmptyAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      isLoading: false,
      schoolYears: [],
      selectedSchoolYearId: null,
      activeSemester: null,
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}

  @override
  Future<bool> addSchoolYear(String label) async {
    state = state.copyWith(isSaving: true, clearError: true);
    // Simulate slight delay then success
    state = AcademicPeriodState(
      isLoading: false,
      isSaving: false,
      schoolYears: [
        {'id': 1, 'label': label, 'semesters': []},
      ],
      selectedSchoolYearId: 1,
      message: 'School year $label added.',
    );
    return true;
  }
}

void main() {
  testWidgets('Year dropdown fits light, dark, and phone layouts', (
    tester,
  ) async {
    await loadPreviewFonts(force: true);
    for (final config in [(900.0, false), (900.0, true), (360.0, false)]) {
      tester.view.physicalSize = Size(config.$1, 850);
      tester.view.devicePixelRatio = 1;
      await pumpDefensysWidget(
        tester,
        const AddSchoolYearDialog(existingLabels: []),
        theme: config.$2 ? AppTheme.mistDarkTheme : AppTheme.theme,
      );
      await tester.tap(find.byType(ShadSelect<int>));
      await tester.pumpAndSettle();
      expect(find.text('Add another'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(ShadDialog),
        'school-year-${config.$1.toInt()}-${config.$2 ? 'dark' : 'light'}',
        viewport: true,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'Add school year dialog does not throw disposed controller error during dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            academicPeriodProvider.overrideWith(
              _FakeEmptyAcademicPeriodNotifier.new,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.mistDarkTheme,
            home: const Scaffold(body: AcademicPeriodsScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify empty state is present
      expect(find.text('No School Years Configured'), findsOneWidget);

      // Tap "+ Add Year"
      await tester.tap(find.text('Add Year').first);
      await tester.pumpAndSettle();

      // The dialog should be open
      expect(find.byType(ShadDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ShadDialog),
          matching: find.text('Add School Year'),
        ),
        findsOneWidget,
      );

      expect(find.byType(ShadSelect<int>), findsOneWidget);

      // Tap "Add Year" button inside dialog
      final addYearButton = find.descendant(
        of: find.byType(ShadDialog),
        matching: find.widgetWithText(ShadButton, 'Add Year'),
      );
      await tester.tap(addYearButton);

      // Pump a single frame while dialog is animating out
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Check if any widget exceptions occurred during dialog dismissal
      expect(tester.takeException(), isNull);

      // Drain toastification timer
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('Preloaded years exclude saved years and extend consecutively', (
    tester,
  ) async {
    final current = DateTime.now().year;
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<String>(
                  context: context,
                  builder: (_) => AddSchoolYearDialog(
                    existingLabels: ['$current-${current + 1}'],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var count = 1; count <= 2; count++) {
      await tester.tap(find.byType(ShadSelect<int>));
      await tester.pumpAndSettle();
      expect(find.text('$current-${current + 1}'), findsNothing);
      await tester.ensureVisible(find.text('Add another'));
      await tester.tap(find.text('Add another'));
      await tester.pumpAndSettle();
      final next = current + 3 + count;
      expect(find.text('$next-${next + 1}'), findsOneWidget);
      expect(saved, isNull);
    }
    await tester.tap(find.widgetWithText(ShadButton, 'Add Year'));
    await tester.pumpAndSettle();
    expect(saved, '${current + 5}-${current + 6}');
    expect(tester.takeException(), isNull);
  });
}
