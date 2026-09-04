import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/grading/rubric_engine_provider.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';

import '../helpers/pump_app.dart';

class MockRubricEngineNotifier extends RubricEngineNotifier {
  MockRubricEngineNotifier({
    Map<String, dynamic>? activeSemester,
    List<Map<String, dynamic>>? semesters,
  })  : _activeSemester = activeSemester,
        _semesters = semesters ?? [];

  final Map<String, dynamic>? _activeSemester;
  final List<Map<String, dynamic>> _semesters;
  int fetchCallCount = 0;

  @override
  RubricEngineState build() {
    return RubricEngineState(
      isLoading: false,
      activeSemester: _activeSemester,
      semesters: _semesters,
      rubrics: [],
    );
  }

  void updateActiveSemester(Map<String, dynamic> sem, List<Map<String, dynamic>> semesters) {
    state = state.copyWith(
      activeSemester: sem,
      semesters: semesters,
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
  }) async {
    fetchCallCount++;
  }
}

void main() {
  testWidgets('RubricFullPageEditor preserves typed drafts while adopting newly active semester', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final rubricNotifier = MockRubricEngineNotifier(
      activeSemester: null,
      semesters: [],
    );

    await pumpDefensysWidget(
      tester,
      Scaffold(
        body: RubricFullPageEditor(
          onBack: () {},
        ),
      ),
      overrides: [
        rubricEngineProvider.overrideWith(() => rubricNotifier),
      ],
    );
    await tester.pumpAndSettle();

    // Type a rubric name
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'My Draft Capstone Rubric');
    await tester.pumpAndSettle();

    expect(find.text('My Draft Capstone Rubric'), findsOneWidget);

    // Simulate semester activated from Academic Periods tab
    final newSem = {
      'id': 42,
      'label': '1st Semester',
      'school_year': '2024-2025',
      'display_name': '1st Semester, A.Y. 2024-2025',
      'is_active': true,
    };
    rubricNotifier.updateActiveSemester(newSem, [newSem]);
    await tester.pumpAndSettle();

    // Verify user's typed name is STILL intact!
    expect(find.text('My Draft Capstone Rubric'), findsOneWidget);

    // Verify semester dropdown updated with the newly active semester
    expect(find.textContaining('1st Semester, A.Y. 2024-2025'), findsOneWidget);
  });

  test('ActiveAdminSectionNotifier correctly changes sections and notifies listeners', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(activeAdminSectionProvider),
      DefensysAdminSection.overview,
    );

    container
        .read(activeAdminSectionProvider.notifier)
        .setSection(DefensysAdminSection.rubrics);
    expect(
      container.read(activeAdminSectionProvider),
      DefensysAdminSection.rubrics,
    );

    container
        .read(activeAdminSectionProvider.notifier)
        .setSection(DefensysAdminSection.defenseStages);
    expect(
      container.read(activeAdminSectionProvider),
      DefensysAdminSection.defenseStages,
    );

    container
        .read(activeAdminSectionProvider.notifier)
        .setSection(DefensysAdminSection.gradeCenter);
    expect(
      container.read(activeAdminSectionProvider),
      DefensysAdminSection.gradeCenter,
    );
  });
}
