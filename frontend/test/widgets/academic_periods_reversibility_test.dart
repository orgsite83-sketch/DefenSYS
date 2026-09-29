import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';

class _FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  final List<Map<String, dynamic>> _years;
  bool deleteCalled = false;
  bool updateCalled = false;

  _FakeAcademicPeriodNotifier(this._years);

  @override
  AcademicPeriodState build() {
    return AcademicPeriodState(
      isLoading: false,
      schoolYears: _years,
      selectedSchoolYearId: _years.isNotEmpty ? _years.first['id'] as int : null,
      activeSemester: null,
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}

  @override
  Future<bool> deleteSchoolYear(int schoolYearId) async {
    deleteCalled = true;
    state = state.copyWith(
      schoolYears: state.schoolYears.where((y) => y['id'] != schoolYearId).toList(),
      selectedSchoolYearId: null,
      message: 'School year deleted.',
    );
    return true;
  }

  @override
  Future<bool> updateSchoolYear(int schoolYearId, String label) async {
    updateCalled = true;
    final updated = state.schoolYears.map((y) {
      if (y['id'] == schoolYearId) {
        return {...y, 'label': label};
      }
      return y;
    }).toList();
    state = state.copyWith(schoolYears: updated, message: 'School year updated.');
    return true;
  }
}

void main() {
  testWidgets('Renders Edit and Delete actions on empty School Year and shows empty state escape hatch',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final notifier = _FakeAcademicPeriodNotifier([
      {
        'id': 101,
        'label': '2026-2027',
        'semesters': <Map<String, dynamic>>[],
      }
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(() => notifier),
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

    // 1. Check that the school year label is displayed in the card title and rich text
    expect(find.textContaining('2026-2027'), findsWidgets);

    // 2. Check that the "Delete School Year" secondary action button is visible in the empty state
    expect(find.text('Delete School Year'), findsOneWidget);

    // 3. Open school year options menu
    final optionsMenu = find.byTooltip('School year options');
    expect(optionsMenu, findsOneWidget);
    await tester.tap(optionsMenu);
    await tester.pumpAndSettle();

    // 4. Tap "Edit School Year" to open edit dialog
    expect(find.text('Edit School Year'), findsOneWidget);
    await tester.tap(find.text('Edit School Year'));
    await tester.pumpAndSettle();

    expect(find.text('Edit School Year'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    // Dismiss edit dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 5. Tap the empty state "Delete School Year" button
    await tester.tap(find.text('Delete School Year'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog appears
    expect(find.text('Delete School Year'), findsWidgets);
    expect(find.text('Delete'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(notifier.deleteCalled, isTrue);

    // Drain toastification timer
    await tester.pump(const Duration(seconds: 4));
  });
}
