import 'package:defensys/screens/web/admin/academic_periods/widgets/add_semester_dialog.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Periods extends AcademicPeriodNotifier {
  final calls = <Map<String, dynamic>>[];
  @override
  AcademicPeriodState build() => const AcademicPeriodState();
  @override
  Future<Map<String, dynamic>?> fetchCreateTransitionPreview(
    int year,
    Map<String, dynamic> draft,
  ) async => {
    'current_semester': null,
    'target_semester': draft,
    'preview_revision': 'calendar-preview',
    'can_switch': true,
    'issues': <dynamic>[],
  };
  @override
  Future<bool> addSemester(
    int year,
    String label, {
    String? startsOn,
    String? endsOn,
    bool setActive = false,
    Map<String, dynamic> activation = const {},
  }) async {
    calls.add({
      'label': label,
      'starts_on': startsOn,
      'ends_on': endsOn,
      'active': setActive,
      ...activation,
    });
    return true;
  }
}

void main() {
  testWidgets(
    'Shadcn term form validates dates and creates an active term with its calendar',
    (tester) async {
      final notifier = _Periods();
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const AddSemesterDialog(
                year: {'id': 1, 'label': '2024-2025', 'semesters': <dynamic>[]},
              ),
            ),
            child: const Text('Open term form'),
          ),
        ),
        overrides: [academicPeriodProvider.overrideWith(() => notifier)],
      );
      await tester.tap(find.text('Open term form'));
      await tester.pumpAndSettle();
      final select = tester.widget<WorkflowSelect>(find.byType(WorkflowSelect));
      select.onChanged('1st Semester');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Add Term'))
            .enabled,
        isFalse,
      );
      tester
          .widget<ShadDatePicker>(
            find.byKey(const ValueKey('semester-start-date')),
          )
          .onChanged!(DateTime(2024, 1, 10));
      await tester.pumpAndSettle();
      tester
          .widget<ShadDatePicker>(
            find.byKey(const ValueKey('semester-end-date')),
          )
          .onChanged!(DateTime(2024, 1, 10));
      await tester.pumpAndSettle();
      expect(find.text('End date must be after start date.'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Add Term'))
            .enabled,
        isFalse,
      );
      tester
          .widget<ShadDatePicker>(
            find.byKey(const ValueKey('semester-end-date')),
          )
          .onChanged!(DateTime(2025, 6, 15));
      await tester.pumpAndSettle();
      expect(
        find.text('Use your institution’s official academic calendar.'),
        findsNothing,
      );
      tester.widget<ShadSwitch>(find.byType(ShadSwitch)).onChanged!(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add & Activate'));
      await tester.pumpAndSettle();
      expect(notifier.calls.single, containsPair('active', true));
      expect(notifier.calls.single, containsPair('starts_on', '2024-01-10'));
      expect(notifier.calls.single, containsPair('ends_on', '2025-06-15'));
      expect(
        notifier.calls.single,
        containsPair('preview_revision', 'calendar-preview'),
      );
    },
  );

  testWidgets(
    'Term dialog fits both themes and narrow screens with DefenSYS controls',
    (tester) async {
      await loadPreviewFonts(force: true);
      for (final config in [(900.0, false), (900.0, true), (360.0, false)]) {
        tester.view.physicalSize = Size(config.$1, 850);
        tester.view.devicePixelRatio = 1;
        await pumpDefensysWidget(
          tester,
          const AddSemesterDialog(
            year: {'id': 1, 'label': '2024-2025', 'semesters': <dynamic>[]},
          ),
          theme: config.$2 ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [academicPeriodProvider.overrideWith(_Periods.new)],
        );
        expect(find.byType(ShadDialog), findsOneWidget);
        expect(find.byType(ShadDatePicker), findsNWidgets(2));
        expect(find.text('Set as active'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(ShadDialog),
          'semester-calendar-${config.$1.toInt()}-${config.$2 ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
