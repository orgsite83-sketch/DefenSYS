import 'dart:convert';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);
  test(
    'combined review sends the displayed snapshot and uses the returned list',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'teams': [], 'stage_options': [], 'scope': 'capstone'}),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final result = await container
          .read(capstoneDeliverablesProvider.notifier)
          .reviewAndEndorseTeam(7, 'Concept Proposal', 'displayed-files-token');
      expect(result, true);
      final post = requests.singleWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/repository/deliverables/review-endorse/');
      expect(jsonDecode(post.body), {
        'team_id': 7,
        'stage_label': 'Concept Proposal',
        'review_token': 'displayed-files-token',
      });
      expect(requests, hasLength(1));
      expect(post.url.queryParameters['response_mode'], 'team');
      expect(container.read(capstoneDeliverablesProvider).error, isNull);
    },
  );
}
