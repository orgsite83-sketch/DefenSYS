import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import 'app/data_refresh_provider.dart';
import 'network/authenticated_client.dart';

class AdminAttentionLoadException implements Exception {
  const AdminAttentionLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server validates semester and permissions and returns a bounded page.
final adminAttentionStudentsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, query) async {
      ref.watch(
        dataRefreshProvider.select(
          (value) => (
            value[DataArea.dashboard],
            value[DataArea.teams],
            value[DataArea.academicRecords],
          ),
        ),
      );
      final base = ApiConfig.studentRecordsUrl;
      final uri = Uri.parse(
        '${base.endsWith('/') ? base : '$base/'}attention/?$query',
      );
      final response = await ref
          .watch(authenticatedHttpClientProvider)
          .get(uri);
      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw AdminAttentionLoadException(
          body is Map
              ? body['detail'] ?? 'Could not load students.'
              : 'Could not load students.',
        );
      }
      return Map<String, dynamic>.from(body as Map);
    });
