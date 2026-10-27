import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

final sectionConceptServiceProvider = Provider<SectionConceptService>(
  (ref) => SectionConceptService(ref.watch(authenticatedHttpClientProvider)),
);

class SectionConceptService {
  SectionConceptService(this.client);
  final AuthenticatedHttpClient client;
  String get base => '${ApiConfig.baseUrl}/repository/section-concepts';

  Future<Map<String, dynamic>> list({int? teamId}) async => decode(
    await client.get(
      Uri.parse('$base/${teamId == null ? '' : '?team_id=$teamId'}'),
    ),
  );

  Future<Map<String, dynamic>> get(int id) async =>
      decode(await client.get(Uri.parse('$base/$id/')));

  Future<Map<String, dynamic>> imported(
    int teamId, {
    String? stageLabel,
  }) async => decode(
    await client.get(
      Uri.parse('$base/imported/').replace(
        queryParameters: {
          'team_id': '$teamId',
          if (stageLabel?.isNotEmpty == true) 'stage_label': stageLabel!,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> saveImported(
    Map<String, dynamic> project,
    List<Map<String, dynamic>> titles,
  ) async => decode(
    await client.post(
      Uri.parse('$base/imported/'),
      body: jsonEncode({
        'team_id': project['team_id'],
        'stage_label': project['stage_label'],
        'review_token': project['review_token'],
        'concepts': titles,
      }),
    ),
  );

  Future<Map<String, dynamic>> tasks() async =>
      decode(await client.get(Uri.parse('$base/?tasks_only=1')));

  Future<Map<String, dynamic>> sharedDeliverables(
    int teamId, {
    String? stageLabel,
  }) async => decode(
    await client.get(
      Uri.parse('$base/shared-deliverables/').replace(
        queryParameters: {
          'team_id': '$teamId',
          if (stageLabel?.isNotEmpty == true) 'stage_label': stageLabel!,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> uploadShared(
    Map<String, dynamic> group,
    String deliverableId,
    String slotKey,
    String name,
    Uint8List bytes,
  ) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$base/shared-deliverables/'))
          ..fields.addAll({
            'team_id': '${group['team_id']}',
            'stage_label': '${group['stage_label']}',
            'review_token': '${group['review_token']}',
            'deliverable_id': deliverableId,
            'slot_key': slotKey,
            'action': 'upload',
          })
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: name),
          );
    return decode(
      await http.Response.fromStream(
        await client.sendAuthenticated(request, retryOn401: false),
      ),
    );
  }

  Future<Map<String, dynamic>> reviewShared(
    Map<String, dynamic> group,
    String deliverableId,
    String slotKey,
    Map<String, dynamic> file,
    String status,
    String feedback,
  ) async => decode(
    await client.post(
      Uri.parse('$base/shared-deliverables/'),
      body: jsonEncode({
        'team_id': group['team_id'],
        'stage_label': group['stage_label'],
        'review_token': group['review_token'],
        'deliverable_id': deliverableId,
        'slot_key': slotKey,
        'file_id': file['id'],
        'legacy': file['legacy'] == true,
        'status': status,
        'feedback': feedback,
        'action': 'review',
        'revision_scope': file['revision_scope'] ?? 'paper',
      }),
    ),
  );

  Future<Map<String, dynamic>> titleAction(
    Map<String, dynamic> project,
    String action,
    Map<String, dynamic> values,
  ) async {
    if (project['imported'] == true) {
      return decode(
        await client.post(
          Uri.parse('$base/imported/'),
          body: jsonEncode({
            'team_id': project['team_id'],
            'stage_label': project['stage_label'],
            'review_token': project['review_token'],
            'action': action,
            ...values,
          }),
        ),
      );
    }
    return this.action(project, action, values);
  }

  Future<Map<String, dynamic>> configure(Map<String, dynamic> data) async =>
      decode(await client.post(Uri.parse('$base/'), body: jsonEncode(data)));

  Future<Map<String, dynamic>> action(
    Map<String, dynamic> project,
    String action, [
    Map<String, dynamic> values = const {},
  ]) async => decode(
    await client.post(
      Uri.parse('$base/${project['id']}/'),
      body: jsonEncode({
        'action': action,
        'round_id': project['round_id'],
        'review_token': project['review_token'],
        ...values,
      }),
    ),
  );

  Future<Map<String, dynamic>> upload(
    Map<String, dynamic> project,
    String key,
    String name,
    Uint8List bytes, {
    String purpose = 'proposal',
  }) async {
    if (project['imported'] == true) {
      project = decode(
        await client.post(
          Uri.parse('$base/imported/'),
          body: jsonEncode({
            'team_id': project['team_id'],
            'stage_label': project['stage_label'],
            'review_token': project['review_token'],
          }),
        ),
      );
    }
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$base/${project['id']}/upload/'),
          )
          ..fields.addAll({
            'round_id': '${project['round_id']}',
            'key': key,
            'purpose': purpose,
          })
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: name),
          );
    return decode(
      await http.Response.fromStream(
        await client.sendAuthenticated(request, retryOn401: false),
      ),
    );
  }

  Map<String, dynamic> decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'The section workspace could not be loaded (${response.statusCode}).',
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body is Map) {
      return Map<String, dynamic>.from(body);
    }
    String message(dynamic value) => value is Map
        ? value.values.map(message).join(' ')
        : value is List
        ? value.map(message).join(' ')
        : '$value';
    throw Exception(message(body));
  }
}
