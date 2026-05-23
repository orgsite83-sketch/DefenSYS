import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/utils/team_bulk_import_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TeamBulkImportDraft', () {
    test('serializes and deserializes', () {
      final draft = TeamBulkImportDraft(
        rows: [
          {'team_name': 'Team A', 'member_ids': ['1']},
        ],
        adviserFilter: 'all',
        savedAt: DateTime(2026, 5, 10),
        issueCount: 0,
      );

      final restored = TeamBulkImportDraft.fromJson(draft.toJson());

      expect(restored.rows, hasLength(1));
      expect(restored.adviserFilter, 'all');
      expect(restored.issueCount, 0);
    });
  });

  group('loadTeamBulkImportDraft', () {
    test('loads draft for user from preferences', () async {
      SharedPreferences.setMockInitialValues({
        'user_data': '{"id":99,"username":"admin"}',
        'team_bulk_import_draft_99': '''
{
  "rows": [{"team_name": "Saved"}],
  "adviser_filter": "all",
  "saved_at": "2026-05-10T00:00:00.000",
  "issue_count": 1
}
''',
      });

      final draft = await loadTeamBulkImportDraft();

      expect(draft, isNotNull);
      expect(draft!.rows.first['team_name'], 'Saved');
      expect(draft.issueCount, 1);
    });

    test('returns null when no draft stored', () async {
      SharedPreferences.setMockInitialValues({});

      final draft = await loadTeamBulkImportDraft();

      expect(draft, isNull);
    });
  });
}
