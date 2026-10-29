import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/api_config.dart';
import '../services/network/authenticated_client.dart';

GoRoute legacyMinutesNotificationRoute(String workspace) => GoRoute(
  path: 'minutes/:scheduleId',
  redirect: workspace == 'admin'
      ? (_, state) =>
            '/admin/defense-board?minutes=${state.pathParameters['scheduleId']}'
      : null,
  builder: (context, state) => AdviserMinutesNotificationRedirect(
    key: ValueKey(state.uri.path),
    scheduleId: int.parse(state.pathParameters['scheduleId']!),
  ),
);

/// Read a notification's exact schedule without inheriting board filters or
/// initializing a minutes draft. The server applies workspace permissions.
Future<Map<String, dynamic>> fetchMinutesNotificationSchedule(
  AuthenticatedHttpClient client,
  int scheduleId, {
  required String workspace,
}) async {
  final uri = Uri.parse('${ApiConfig.defenseBoardUrl}/').replace(
    queryParameters: {
      'schedule_id': '$scheduleId',
      'scope': 'capstone',
      'workspace': workspace,
    },
  );
  final response = await client.get(uri);
  if (response.statusCode != 200) {
    throw Exception('Unable to load this defense record. Please try again.');
  }
  final data = jsonDecode(response.body);
  final schedules = data is Map ? data['schedules'] : null;
  if (schedules is List) {
    for (final schedule in schedules.whereType<Map>()) {
      if (schedule['id']?.toString() == '$scheduleId') {
        return Map<String, dynamic>.from(schedule);
      }
    }
  }
  throw Exception(
    'This defense record is no longer available or you do not have access.',
  );
}

/// Compatibility for old adviser notification URLs, including saved links.
/// The documenter editor remains on its own dedicated route.
class AdviserMinutesNotificationRedirect extends ConsumerStatefulWidget {
  const AdviserMinutesNotificationRedirect({
    super.key,
    required this.scheduleId,
  });

  final int scheduleId;

  @override
  ConsumerState<AdviserMinutesNotificationRedirect> createState() =>
      _AdviserMinutesNotificationRedirectState();
}

class _AdviserMinutesNotificationRedirectState
    extends ConsumerState<AdviserMinutesNotificationRedirect> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final schedule = await fetchMinutesNotificationSchedule(
        ref.read(authenticatedHttpClientProvider),
        widget.scheduleId,
        workspace: 'adviser',
      );
      if (!mounted) return;
      final teamId = int.tryParse('${schedule['team_id']}');
      if (teamId == null || teamId < 1) throw const FormatException();
      context.go(
        Uri(
          path: '/faculty/deliverables/teams/$teamId',
          queryParameters: {
            'scope': 'capstone',
            'tab': 'defense',
            'stage': '${schedule['stage_label'] ?? ''}',
          },
        ).toString(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'This defense record is unavailable. Retry or open Capstone Teams.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: _error == null
        ? const CircularProgressIndicator()
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              TextButton(onPressed: _open, child: const Text('Retry')),
              TextButton(
                onPressed: () => context.go('/faculty/deliverables'),
                child: const Text('Capstone Teams'),
              ),
            ],
          ),
  );
}
