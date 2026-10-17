import 'dart:convert';

import 'package:defensys/services/defense/team_defense_provider.dart';
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

void main() {
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
