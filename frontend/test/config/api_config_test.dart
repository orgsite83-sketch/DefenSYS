import 'package:flutter_test/flutter_test.dart';
import 'package:user/config/api_config.dart';

void main() {
  test('authenticatedMediaUrl maps /media/ to authenticated proxy', () {
    final url = ApiConfig.authenticatedMediaUrl('/media/team_documents/2026/05/report.pdf');
    expect(url, contains('/api/media/files/team_documents/2026/05/report.pdf'));
    expect(url, startsWith('http://'));
  });

  test('authenticatedMediaUrl passes through /api/ paths', () {
    final url = ApiConfig.authenticatedMediaUrl('/api/teams/weekly-progress/1/file/');
    expect(url, endsWith('/api/teams/weekly-progress/1/file/'));
  });
}
