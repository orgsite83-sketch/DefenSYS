import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/services/defense/defense_board_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Client implements AuthenticatedHttpClient {
  final requested = <Uri>[];
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    requested.add(uri);
    return http.Response(jsonEncode({'schedules': []}), 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedClient implements AuthenticatedHttpClient {
  final requests = <Completer<http.Response>>[];
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    final response = Completer<http.Response>();
    requests.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'switching programs removes stale rows and ignores older responses',
    () async {
      final client = _DelayedClient();
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final board = container.read(defenseBoardProvider.notifier);
      final capstone = board.fetchBoard(scope: 'capstone');
      client.requests[0].complete(
        http.Response(
          jsonEncode({
            'counts': {'scope_total': 1},
            'stage_options': ['Concept Proposal'],
            'advisers': [
              {'id': 1, 'name': 'Capstone adviser'},
            ],
            'sections': [
              {'name': 'BSIT-3A'},
            ],
            'schedules': [
              {'id': 1, 'scope': 'capstone'},
            ],
          }),
          200,
        ),
      );
      await capstone;
      final refresh = board.fetchBoard();
      final pit = board.fetchBoard(scope: 'pit');
      expect(container.read(defenseBoardProvider).scope, 'pit');
      expect(container.read(defenseBoardProvider).schedules, isEmpty);
      expect(container.read(defenseBoardProvider).counts, isEmpty);
      expect(container.read(defenseBoardProvider).stageOptions, isEmpty);
      expect(container.read(defenseBoardProvider).advisers, isEmpty);
      expect(container.read(defenseBoardProvider).sections, isEmpty);
      expect(container.read(defenseBoardProvider).isLoading, isTrue);
      client.requests[2].complete(
        http.Response(
          jsonEncode({
            'schedules': [
              {'id': 2, 'scope': 'pit'},
            ],
          }),
          200,
        ),
      );
      await pit;
      client.requests[1].complete(
        http.Response(
          jsonEncode({
            'schedules': [
              {'id': 1, 'scope': 'capstone'},
            ],
          }),
          200,
        ),
      );
      await refresh;
      expect(container.read(defenseBoardProvider).schedules.single['id'], 2);
      expect(container.read(defenseBoardProvider).scope, 'pit');
    },
  );

  test('operations retain their workspace when filters change', () async {
    final client = _Client();
    final container = ProviderContainer(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final board = container.read(defenseBoardProvider.notifier);
    await board.fetchBoard(scope: 'pit');
    await board.fetchBoard(search: 'Showcase', section: 'BSIT-2A');
    expect(client.requested.first.queryParameters, {
      'workspace': 'operations',
      'scope': 'pit',
    });
    expect(client.requested.last.queryParameters, {
      'workspace': 'operations',
      'scope': 'pit',
      'search': 'Showcase',
      'section': 'BSIT-2A',
    });
  });

  test(
    'generic defense records retain student and other faculty access',
    () async {
      final client = _Client();
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      await container.read(teamDefenseProvider.notifier).fetch();
      expect(client.requested.single.queryParameters, {'scope': 'capstone'});
    },
  );

  test('adviser dashboard explicitly requests its own advisees', () async {
    final client = _Client();
    final container = ProviderContainer(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await container
        .read(teamDefenseProvider.notifier)
        .fetch(workspace: 'adviser');
    expect(client.requested.single.queryParameters, {
      'scope': 'capstone',
      'workspace': 'adviser',
    });
  });

  test('instructor feed requests assigned section teams', () async {
    final client = _Client();
    final container = ProviderContainer(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await container.read(pitInstructorDefenseProvider.notifier).fetch();
    expect(client.requested.single.queryParameters, {
      'scope': 'pit',
      'workspace': 'instructor',
    });
  });
}
