import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import 'grade_masterlist_provider.dart';

String newOutcomeBatchId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class OutcomeDisseminationApi {
  OutcomeDisseminationApi(this.client);
  final AuthenticatedHttpClient client;

  Future<Map<String, dynamic>> _request(
    String route, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.gradeCenterUrl}/$route',
    ).replace(query: query == null ? null : masterlistQueryKey(query));
    final response =
        await (body == null
                ? client.get(uri)
                : client.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final detail = decoded is Map
          ? decoded['detail'] ?? decoded.values.toList()
          : decoded;
      throw Exception(detail is List ? detail.join(' ') : '$detail');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> preview(
    Map<String, String> filters,
    List<int>? gradeIds,
  ) => _request(
    'outcome-dissemination/preview/',
    body: {'filters': filters, if (gradeIds != null) 'grade_ids': gradeIds},
  );

  Future<Map<String, dynamic>> confirm(String token, String batchId) =>
      _request(
        'outcome-dissemination/confirm/',
        body: {'review_token': token, 'batch_id': batchId},
      );

  Future<Map<String, dynamic>> hold(
    int gradeId,
    Map<String, dynamic> metadata,
    bool held,
    String reason,
  ) => _request(
    '$gradeId/outcome-dissemination/hold/',
    body: {
      'version': metadata['version'],
      'schedule_id': metadata['schedule_id'],
      'held': held,
      'reason': reason,
    },
  );

  Future<Map<String, dynamic>> history(Map<String, String> filters) =>
      _request('outcome-dissemination/history/', query: filters);
}

final outcomeDisseminationApiProvider = Provider<OutcomeDisseminationApi>(
  (ref) => OutcomeDisseminationApi(ref.read(authenticatedHttpClientProvider)),
);
