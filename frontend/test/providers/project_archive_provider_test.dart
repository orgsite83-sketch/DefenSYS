import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'current semester opens once, survives track changes, and allows root navigation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'entries': [],
              'folder_browser': {
                'folder_key': 'current-semester',
                'group_by': 'team',
                'breadcrumbs': [
                  {'title': '2026-2027', 'key': 'current-year'},
                  {'title': '1st Semester', 'key': 'current-semester'},
                ],
                'folders': [],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(resetApiHttpClientForTesting);
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(projectArchiveProvider.notifier);

      await notifier.fetchEntries(openCurrentSemester: true);
      expect(requests.last.queryParameters['open_current_semester'], '1');
      expect(
        container.read(projectArchiveProvider).folderKey,
        'current-semester',
      );

      await notifier.fetchEntries(type: 'pit');
      expect(requests.last.queryParameters['folder_key'], 'current-semester');
      expect(
        requests.last.queryParameters.containsKey('open_current_semester'),
        isFalse,
      );

      await notifier.fetchEntries(folderKey: '');
      expect(requests.last.queryParameters.containsKey('folder_key'), isFalse);
      expect(
        requests.last.queryParameters.containsKey('open_current_semester'),
        isFalse,
      );
    },
  );
}
