import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/repository_provider.dart';
import '../helpers/auth_test_overrides.dart';

void main() {
  tearDown(resetApiHttpClientForTesting);

  test(
    'catalog paging retains filters and project detail loads only on request',
    () async {
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          return http.Response(
            jsonEncode({
              'entries': [
                {
                  'id': 'entry-$offset',
                  'project_key': 'project-$offset',
                  'catalog_summary': true,
                },
              ],
              'pagination': {'has_more': offset == 0},
              'counts': {'total': 2},
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(repositoryProvider.notifier);
      await notifier.fetchCatalog(
        filters: {
          'subject': 'health',
          'deliverable': 'custom:D1',
          'sort': 'title',
        },
      );
      expect(requests, hasLength(1));
      expect(requests.single.path, endsWith('/catalog/'));
      expect(container.read(repositoryProvider).hasMore, isTrue);
      await notifier.fetchCatalog(append: true);
      expect(container.read(repositoryProvider).entries, hasLength(2));
      expect(requests.last.queryParameters, containsPair('offset', '1'));
      expect(
        requests.last.queryParameters,
        containsPair('deliverable', 'custom:D1'),
      );
      expect(requests.last.queryParameters, containsPair('subject', 'health'));
      expect(container.read(repositoryProvider).hasMore, isFalse);
      await notifier.fetchProject('project:one');
      expect(requests.last.path, endsWith('/project/'));
      expect(requests.last.queryParameters, {'project_key': 'project:one'});
    },
  );
}
