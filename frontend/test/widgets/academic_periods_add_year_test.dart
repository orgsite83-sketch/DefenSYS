import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';

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
        {
          'id': 1,
          'label': label,
          'semesters': [],
        }
      ],
      selectedSchoolYearId: 1,
      message: 'School year $label added.',
    );
    return true;
  }
}

void main() {
  testWidgets('Add school year dialog does not throw disposed controller error during dismissal',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(_FakeEmptyAcademicPeriodNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.mistDarkTheme,
          home: const Scaffold(
            body: AcademicPeriodsScreen(),
          ),
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
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add School Year')), findsOneWidget);

    // Enter school year
    await tester.enterText(find.byType(TextField), '2026-2027');
    await tester.pump();

    // Tap "Add Year" button inside dialog
    final addYearButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Add Year'),
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
  });
}
