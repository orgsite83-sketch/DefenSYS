import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

final teamRosterServiceProvider = Provider<TeamRosterService>(
  (ref) => TeamRosterService(ref.watch(authenticatedHttpClientProvider)),
);

class TeamRosterService {
  TeamRosterService(this.client);
  final AuthenticatedHttpClient client;
  String get base => '${ApiConfig.teamsUrl}/rosters';

  Future<Map<String, dynamic>> load(Map<String, dynamic> scope) async => decode(
    await client.get(
      Uri.parse('$base/').replace(queryParameters: query(scope)),
    ),
  );
  Future<Map<String, dynamic>> preview(Map<String, dynamic> data) async =>
      decode(
        await client.post(Uri.parse('$base/preview/'), body: jsonEncode(data)),
      );
  Future<Map<String, dynamic>> apply(String token) async => decode(
    await client.post(
      Uri.parse('$base/apply/'),
      body: jsonEncode({'preview_token': token}),
    ),
  );
  Future<Map<String, dynamic>> requestSetup(Map<String, dynamic> data) async =>
      decode(
        await client.post(
          Uri.parse('$base/project-setup/'),
          body: jsonEncode(data),
        ),
      );
  Future<Map<String, dynamic>> export(Map<String, dynamic> scope) async =>
      decode(
        await client.get(
          Uri.parse('$base/export/').replace(queryParameters: query(scope)),
        ),
      );
  Future<Map<String, dynamic>> confirm(
    int team,
    int event,
    Map<String, dynamic> data,
  ) async => decode(
    await client.patch(
      Uri.parse('${ApiConfig.teamsUrl}/$team/events/$event/setup/'),
      body: jsonEncode(data),
    ),
  );

  Future<Map<String, dynamic>> correct(Map<String, dynamic> data) async =>
      decode(
        await client.patch(
          Uri.parse('$base/project-setup/'),
          body: jsonEncode(data),
        ),
      );

  Map<String, String> query(Map<String, dynamic> data) => {
    for (final entry in data.entries)
      if (entry.value != null && '${entry.value}'.isNotEmpty)
        entry.key: '${entry.value}',
  };

  Map<String, dynamic> decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'The server could not complete this request (${response.statusCode}).',
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data is Map) {
      return Map<String, dynamic>.from(data);
    }
    String message(dynamic value) => value is Map
        ? value.values.map(message).join(' ')
        : value is List
        ? value.map(message).join(' ')
        : '$value';
    throw Exception(message(data));
  }
}
