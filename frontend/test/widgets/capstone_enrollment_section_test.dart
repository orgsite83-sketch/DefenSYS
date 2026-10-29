import 'package:defensys/screens/web/admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> resolution(String section, String source) => {
  'id_number': 'S001',
  'section': section,
  'source': source,
  'message': 'Capstone 2 continuation: BSIT-3A → $section.',
  'team_id': 1,
};

class _Draft extends StudentBatchDraftNotifier {
  @override
  StudentBatchDraftState build() => StudentBatchDraftState(
    freshParsedStudents: [
      {
        'id_number': 'S001',
        'first_name': 'Test',
        'last_name': 'Student',
        'year_level': '4th Year',
        'section': '',
        'role': 'student',
        '_section_resolution': resolution('BSIT-4A', 'inferred'),
      },
    ],
  );
}

class _Users extends UserManagementNotifier {
  String defaultSection = 'BSIT-4A';
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<List<Map<String, dynamic>>> previewEnrollmentSections(
    List<Map<String, dynamic>> students,
    int semesterId,
  ) async => [
    for (final s in students)
      resolution(
        s['section']?.toString().isNotEmpty == true
            ? s['section'] as String
            : defaultSection,
        s['section']?.toString().isNotEmpty == true ? 'explicit' : 'inferred',
      ),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester,
    _Users users,
    Future<bool> Function(List<Map<String, dynamic>>, Map<String, dynamic>?)
    confirm,
  ) async {
    tester.view.physicalSize = const Size(1450, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userManagementProvider.overrideWith(() => users),
          studentBatchDraftProvider.overrideWith(_Draft.new),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: StudentBatchEnrollmentHubView(
              userState: const UserManagementState(),
              academicState: const AcademicPeriodState(
                activeSemester: {'id': 2, 'label': '1st Semester'},
              ),
              onBack: () {},
              onDownloadSample: null,
              onConfirmFreshImport: confirm,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inferred section stays a preview default rather than explicit import input',
    (tester) async {
      List<Map<String, dynamic>>? submitted;
      await open(tester, _Users(), (rows, _) async {
        submitted = rows;
        return true;
      });
      expect(find.text('Section: BSIT-4A (inferred)'), findsOneWidget);
      final button = find.text('Confirm Student Intake (1 students)');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted!.single['section'], '');
      expect(submitted!.single['_section_resolution']['section'], 'BSIT-4A');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed continuation defaults require reviewing the refreshed preview',
    (tester) async {
      final users = _Users()..defaultSection = 'BSIT-4B';
      var imports = 0;
      await open(tester, users, (rows, _) async {
        imports++;
        return true;
      });
      final button = find.text('Confirm Student Intake (1 students)');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(imports, 0);
      expect(find.text('Section: BSIT-4B (inferred)'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(imports, 1);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'administrator can correct the proposed section before enrollment',
    (tester) async {
      List<Map<String, dynamic>>? submitted;
      await open(tester, _Users(), (rows, _) async {
        submitted = rows;
        return true;
      });
      final edit = find.byTooltip('Edit enrollment section');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'BSIT-4C');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Section: BSIT-4C'), findsOneWidget);
      final button = find.text('Confirm Student Intake (1 students)');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted!.single['section'], 'BSIT-4C');
      expect(tester.takeException(), isNull);
    },
  );
}
