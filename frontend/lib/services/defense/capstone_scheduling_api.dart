import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/config/api_config.dart';
import 'package:defensys/services/authenticated_client.dart';

final capstoneSchedulingApiProvider = Provider(
  (ref) => CapstoneSchedulingApi(ref.read(authenticatedHttpClientProvider)),
);

class CapstoneSchedulingApi {
  CapstoneSchedulingApi(this.client);
  final AuthenticatedHttpClient client;
  String get base => ApiConfig.defenseSchedulesUrl;

  Future<Map<String, dynamic>> workspace() async {
    final response = await client.get(Uri.parse('$base/capstone-workspace/'));
    return _decode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> savePeople(Map<String, dynamic> payload) =>
      _post('capstone-workspace', payload);

  Future<Map<String, dynamic>> preview(Map<String, dynamic> payload) =>
      _post('generate-plan', {'planning_mode': 'adviser_auto', ...payload});

  Future<Map<String, dynamic>> confirm(String token, String key) =>
      _post('confirm-plan', {
        'planning_mode': 'adviser_auto',
        'preview_token': token,
        'idempotency_key': key,
      });

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await client.post(
      Uri.parse('$base/$path/'),
      body: jsonEncode(data),
    );
    return _decode(response.statusCode, response.body);
  }

  Map<String, dynamic> _decode(int status, String body) {
    dynamic data;
    try {
      data = jsonDecode(body);
    } catch (_) {
      throw Exception(_responseError(status));
    }
    if (data is! Map) throw Exception(_responseError(status));
    if (status < 200 || status >= 300) {
      String flatten(dynamic value) => value is Map
          ? value.entries.map((e) => '${e.key}: ${flatten(e.value)}').join('\n')
          : value is List
          ? value.map(flatten).join(' ')
          : '$value';
      throw Exception(flatten(data));
    }
    return Map<String, dynamic>.from(data);
  }

  String _responseError(int status) => status >= 500
      ? 'The scheduling service is temporarily unavailable (HTTP $status). Please retry.'
      : status >= 400
      ? 'Could not load scheduling data (HTTP $status). Please retry.'
      : 'The scheduling service returned an unexpected response. Please retry.';
}
