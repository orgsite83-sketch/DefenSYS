import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/admin/repository_provider.dart';
import 'package:defensys/services/grading/adviser_grading_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/services/pit/weekly_progress_provider.dart';

class _DelayedClient implements AuthenticatedHttpClient {
  final reads = <Completer<http.Response>>[];
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    final result = Completer<http.Response>();
    reads.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final readers = <String, Future<void> Function(ProviderContainer)>{
    'library': (c) => c.read(repositoryProvider.notifier).fetchForStudent(),
    'adviser grades': (c) => c.read(adviserGradingProvider.notifier).fetchAll(),
    'weekly reports': (c) =>
        c.read(weeklyProgressProvider.notifier).fetchReports(),
    'defense': (c) => c.read(teamDefenseProvider.notifier).fetch(),
  };
  final rows = <String, List<Map<String, dynamic>> Function(ProviderContainer)>{
    'library': (c) => c.read(repositoryProvider).entries,
    'adviser grades': (c) => c.read(adviserGradingProvider).grades,
    'weekly reports': (c) => c.read(weeklyProgressProvider).reports,
    'defense': (c) => c.read(teamDefenseProvider).schedules,
  };
  http.Response snapshot(int id) => http.Response(
    jsonEncode({
      for (final key in ['entries', 'grades', 'reports', 'schedules'])
        key: [
          {'id': id},
        ],
    }),
    200,
  );
  for (final entry in readers.entries) {
    test(
      '${entry.key} ignores a read completed after a newer refresh',
      () async {
        final client = _DelayedClient();
        final container = ProviderContainer(
          overrides: [
            authenticatedHttpClientProvider.overrideWithValue(client),
          ],
        );
        addTearDown(container.dispose);
        final earlier = entry.value(container);
        final latest = entry.value(container);
        expect(client.reads.length, 2);
        client.reads[1].complete(snapshot(2));
        await latest;
        client.reads[0].complete(snapshot(1));
        await earlier;
        expect(rows[entry.key]!(container).single['id'], 2);
      },
    );
  }
}
