import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/bulk_import_view.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/utils/import/user_bulk_import_draft.dart';

void main() {
  testWidgets(
    'assignment labels and filtering preserve the full faculty upload',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const csv =
          'id_number,first_name,last_name,email,role\n'
          '206,Ricardo,Fontanilla,206@ustp.edu.ph,"PIT Lead 1st Year, Panelist"\n'
          '207,Maricel,Suarez,207@ustp.edu.ph,faculty\n'
          '208,Dennis,Ritchie,208@ustp.edu.ph,admin\n';
      final draft = UserBulkImportDraft(
        csv: csv,
        importType: 'faculty',
        studentPeriodSource: 'active',
        targetSemesterId: '',
        batchYearLevel: '',
        savedAt: DateTime(2026, 10, 3),
        rowCount: 3,
      );
      SharedPreferences.setMockInitialValues({
        'defensys_user': '{"id":44,"username":"review-test-admin"}',
        'user_bulk_import_draft_44': jsonEncode(draft.toJson()),
      });
      List<Map<String, dynamic>>? submitted;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkImportView(
              state: const UserManagementState(
                isLoading: false,
                users: [
                  {'username': '207', 'email': '207@ustp.edu.ph'},
                ],
                guestCodes: [],
              ),
              academicState: const AcademicPeriodState(),
              onBack: () {},
              onConfirmUpload: (users, _) => submitted = users,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final title in [
        'Name',
        'Faculty ID',
        'Email',
        'Role assignments',
        'Import status',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('PIT Lead · 1st Year'), findsOneWidget);
      expect(find.text('Panelist'), findsOneWidget);
      expect(find.text('Faculty'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Existing Account'), findsOneWidget);
      expect(find.text('Ready to Import'), findsNWidgets(2));

      // Search only narrows the review, including the visible role assignments.
      await tester.enterText(find.byType(TextField), 'panelist');
      await tester.pumpAndSettle();
      expect(find.text('Ricardo Fontanilla'), findsOneWidget);
      expect(find.text('Maricel Suarez'), findsNothing);
      expect(find.text('Faculty'), findsNothing);

      final confirm = find.text('Confirm Import (3 Faculty)');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(submitted, hasLength(3));
      expect(submitted![0], containsPair('role', 'faculty'));
      expect(submitted![0], containsPair('is_pit_lead', true));
      expect(submitted![0], containsPair('pit_lead_year', '1st Year'));
      expect(submitted![0], containsPair('is_panelist', true));
      expect(submitted![1], containsPair('role', 'faculty'));
      expect(submitted![1], containsPair('is_pit_lead', false));
      expect(submitted![2], containsPair('role', 'admin'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
