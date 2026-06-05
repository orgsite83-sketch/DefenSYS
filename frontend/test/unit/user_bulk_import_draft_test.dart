import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/utils/user_bulk_import_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserBulkImportDraft', () {
    test('serializes and deserializes', () {
      final draft = UserBulkImportDraft(
        csv:
            'id_number,first_name,last_name,email,role\n1,A,B,a@b.test,student',
        importType: 'student',
        studentPeriodSource: 'explicit',
        targetSemesterId: '7',
        batchYearLevel: '3rd Year',
        savedAt: DateTime(2026, 6, 4),
        rowCount: 1,
        warningCount: 0,
      );

      final restored = UserBulkImportDraft.fromJson(draft.toJson());

      expect(restored.csv, contains('id_number'));
      expect(restored.importType, 'student');
      expect(restored.targetSemesterId, '7');
      expect(restored.batchYearLevel, '3rd Year');
      expect(restored.rowCount, 1);
    });
  });

  group('loadUserBulkImportDraft', () {
    test('loads draft for user from preferences', () async {
      SharedPreferences.setMockInitialValues({
        'user_data': '{"id":44,"username":"admin"}',
        'user_bulk_import_draft_44': '''
{
  "csv": "id_number,first_name,last_name,email,role\\n1,A,B,a@b.test,student",
  "import_type": "student",
  "student_period_source": "active",
  "target_semester_id": "",
  "batch_year_level": "1st Year",
  "saved_at": "2026-06-04T00:00:00.000",
  "row_count": 1,
  "warning_count": 2
}
''',
      });

      final draft = await loadUserBulkImportDraft();

      expect(draft, isNotNull);
      expect(draft!.studentPeriodSource, 'active');
      expect(draft.batchYearLevel, '1st Year');
      expect(draft.warningCount, 2);
    });

    test('returns null when no draft stored', () async {
      SharedPreferences.setMockInitialValues({});

      final draft = await loadUserBulkImportDraft();

      expect(draft, isNull);
    });
  });
}
