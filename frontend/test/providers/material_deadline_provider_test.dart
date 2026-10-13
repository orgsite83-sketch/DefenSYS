import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/defense/defense_board_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  test(
    'extension sends the reviewed time, reason and revision, then refreshes board and dependents',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.method == 'POST'
                  ? {
                      'schedule': {'id': 7, 'revision': 3},
                    }
                  : {
                      'schedules': [
                        {'id': 7, 'revision': 3},
                      ],
                      'counts': {},
                    },
            ),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final deadline = DateTime.utc(2030, 11, 20, 1);
      await container
          .read(defenseBoardProvider.notifier)
          .extendMaterialDeadline(
            scheduleId: 7,
            revision: 2,
            deadline: deadline,
            reason: 'Adviser approved additional preparation time.',
          );
      expect(
        requests.first.url.path,
        '/api/defense/schedules/7/material-deadline/',
      );
      expect(jsonDecode(requests.first.body), {
        'deadline': deadline.toIso8601String(),
        'revision': 2,
        'reason': 'Adviser approved additional preparation time.',
      });
      expect(requests.last.method, 'GET');
      expect(
        container.read(defenseBoardProvider).schedules.single['revision'],
        3,
      );
      expect(container.read(dataRefreshProvider)[DataArea.repository], 1);
      expect(container.read(dataRefreshProvider)[DataArea.audit], 1);
    },
  );

  test(
    'stale extension stays failed and does not pretend to refresh or notify students',
    () async {
      var calls = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'detail': 'These records changed. Refresh before saving.',
            }),
            409,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(defenseBoardProvider.notifier)
            .extendMaterialDeadline(
              scheduleId: 7,
              revision: 2,
              deadline: DateTime.utc(2030, 11, 20),
              reason: 'Extra preparation time.',
            ),
        throwsException,
      );
      expect(calls, 1);
      expect(container.read(dataRefreshProvider), isEmpty);
      expect(container.read(defenseBoardProvider).message, isNull);
    },
  );
}
