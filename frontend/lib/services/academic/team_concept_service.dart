import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

final teamConceptServiceProvider = Provider<TeamConceptService>(
  (ref) => TeamConceptService(ref.watch(authenticatedHttpClientProvider)),
);

class TeamConceptService {
  TeamConceptService(this.client);
  final AuthenticatedHttpClient client;

  Uri _uri(int teamId, String stage) =>
      Uri.parse('${ApiConfig.capstoneDeliverablesUrl}/concepts/').replace(
        queryParameters: {
          'team_id': '$teamId',
          'stage_label': stage,
          'response_mode': 'concept_titles',
        },
      );

  Future<Map<String, dynamic>> load(int teamId, String stage) async =>
      _decode(await client.get(_uri(teamId, stage)));

  Future<Map<String, dynamic>> save(
    int teamId,
    String stage,
    List<Map<String, dynamic>> concepts,
    String token,
  ) async => _decode(
    await client.post(
      _uri(teamId, stage),
      body: jsonEncode({
        'team_id': teamId,
        'stage_label': stage,
        'action': 'save_draft_titles',
        'concepts': concepts,
        'review_token': token,
      }),
    ),
  );

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        body is Map
            ? body['detail'] ?? 'Could not save concept titles.'
            : '$body',
      );
    }
    return Map<String, dynamic>.from((body as Map)['concept_workflow'] as Map);
  }
}
