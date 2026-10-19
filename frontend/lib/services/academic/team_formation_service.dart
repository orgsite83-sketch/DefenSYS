import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

final teamFormationServiceProvider = Provider<TeamFormationService>((ref) {
  return TeamFormationService(ref.watch(authenticatedHttpClientProvider));
});

class TeamFormationService {
  TeamFormationService(this.client);
  final AuthenticatedHttpClient client;
  String get _base => ApiConfig.teamsUrl;

  Future<Map<String, dynamic>> currentRoster(
    String year,
    String section,
  ) async => _decode(
    await client.get(
      Uri.parse(
        '$_base/current-roster/',
      ).replace(queryParameters: {'year_level': year, 'section': section}),
    ),
  );

  Future<Map<String, dynamic>> selectCurrentRoster(
    Map<String, dynamic> data,
  ) async => _decode(
    await client.post(
      Uri.parse('$_base/current-roster/'),
      body: jsonEncode(data),
    ),
  );

  Future<Map<String, dynamic>> context() async =>
      _decode(await client.get(Uri.parse('$_base/generation/context/')));

  Future<Map<String, dynamic>> importPreview(
    Map<String, dynamic> data, {
    bool roster = false,
  }) async => _decode(
    await client.post(
      Uri.parse('$_base/generation/${roster ? 'roster' : 'import'}/'),
      body: jsonEncode(data),
    ),
  );

  Future<Map<String, dynamic>> importCommit(
    String token, {
    bool roster = false,
  }) async => _decode(
    await client.post(
      Uri.parse('$_base/generation/${roster ? 'roster' : 'import'}/create/'),
      body: jsonEncode({'preview_token': token}),
    ),
  );

  Future<Map<String, dynamic>> options(String level, String? event) async =>
      _decode(
        await client.get(
          Uri.parse('$_base/generation/').replace(
            queryParameters: {
              'level': level,
              if (event != null) 'event_name': event,
            },
          ),
        ),
      );

  Future<Map<String, dynamic>> rosterOptions(
    String level,
    String? event,
  ) async => _decode(
    await client.get(
      Uri.parse('$_base/roster-options/').replace(
        queryParameters: {
          'level': level,
          if (event != null) 'event_name': event,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> preview(Map<String, dynamic> data) async =>
      _decode(
        await client.post(
          Uri.parse('$_base/generation/'),
          body: jsonEncode(data),
        ),
      );

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async =>
      _decode(
        await client.post(
          Uri.parse('$_base/generation/create/'),
          body: jsonEncode(data),
        ),
      );

  Future<void> setPolicy(int eventId, String policy) async {
    _decode(
      await client.patch(
        Uri.parse('$_base/generation/events/$eventId/policy/'),
        body: jsonEncode({'team_membership_policy': policy}),
      ),
    );
  }

  Future<Map<String, dynamic>> setupTasks() async =>
      _decode(await client.get(Uri.parse('$_base/my-setup/')));

  Future<Map<String, dynamic>> completeName(int teamId, String name) async =>
      _decode(
        await client.patch(
          Uri.parse('$_base/$teamId/setup/'),
          body: jsonEncode({'name': name}),
        ),
      );

  Map<String, dynamic> _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'The server could not complete this request (${response.statusCode}).',
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body is Map) {
      return Map<String, dynamic>.from(body);
    }
    String message(dynamic value) {
      if (value is List) return value.map(message).join(' ');
      if (value is Map) return value.values.map(message).join(' ');
      return value.toString();
    }

    throw Exception(message(body));
  }
}
