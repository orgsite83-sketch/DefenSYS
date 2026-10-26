import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../app/data_refresh_provider.dart';
import '../auth_provider.dart';
import '../network/authenticated_client.dart';

/// Query strings are stable family keys; table state survives detail navigation.
String masterlistQueryKey(Map<String, String> params) {
  final keys = params.keys.toList()..sort();
  return Uri(
    queryParameters: {
      for (final key in keys)
        if (params[key]!.isNotEmpty) key: params[key]!,
    },
  ).query;
}

final gradeMasterlistDataProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, query) async {
      ref.watch(dataRefreshProvider);
      ref.watch(authProvider.select((state) => state.user));
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse('${ApiConfig.gradeCenterUrl}/masterlist/?$query'));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final data = decoded is Map ? decoded : const {};
        throw Exception(
          data['detail'] ?? data.values.join(' ') ?? 'Unable to load grades.',
        );
      }
      return Map<String, dynamic>.from(decoded as Map);
    });

class GradeMasterlistSessions
    extends Notifier<Map<String, Map<String, String>>> {
  @override
  Map<String, Map<String, String>> build() => {};

  void save(String key, Map<String, String> params) {
    state = {...state, key: Map<String, String>.from(params)};
  }
}

final gradeMasterlistSessionsProvider =
    NotifierProvider<GradeMasterlistSessions, Map<String, Map<String, String>>>(
      GradeMasterlistSessions.new,
    );
