import 'dart:convert';

import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _ReadinessClient extends AuthenticatedHttpClient {
  _ReadinessClient(super.ref, this.response);
  final http.Response response;
  final requests = <Uri>[];
  final writes = <Map<String, dynamic>>[];
  bool allowClosure = false;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    requests.add(uri);
    return response;
  }

  @override
  Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    if (!allowClosure) throw StateError('Preflight must not write grades');
    writes.add(Map<String, dynamic>.from(jsonDecode(body as String)));
    return http.Response('{"group_settings":{}}', 200);
  }
}

void main() {
  test(
    'closure submits the reviewed identities once and never reuses consent',
    () async {
      late _ReadinessClient client;
      final container = ProviderContainer(
        overrides: [
          authenticatedHttpClientProvider.overrideWith(
            (ref) => client = _ReadinessClient(
              ref,
              http.Response(
                jsonEncode({
                  'grading_total_team_count': 1,
                  'grading_ready_team_count': 0,
                  'completion_ready_team_count': 1,
                  'can_complete': true,
                  'incomplete_teams': [],
                  'redefense_teams': [],
                  'failing_teams': [],
                  'failure_candidates': [
                    {'grade_id': 42, 'team_id': 7, 'team_name': 'Team Retry'},
                  ],
                  'completion_token': 'reviewed-context',
                  'completion_blocker': '',
                }),
                200,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gradeCenterProvider.notifier);
      final readiness = await notifier.checkGroupCompletion(
        scope: 'capstone',
        stageLabel: 'Concept Proposal',
      );
      expect(readiness.readyTeams, 1);
      expect(readiness.failureCandidates.single['grade_id'], 42);
      expect(client.writes, isEmpty);
      readiness.onApproved!({
        'failure_grade_ids': [42],
        'completion_token': readiness.completionToken,
        'closure_reason': 'Assessment window closed.',
      });
      client.allowClosure = true;
      expect(
        await notifier.updateGroupSettings(
          scope: 'capstone',
          stageLabel: 'Concept Proposal',
          isOfficiallyComplete: true,
        ),
        isTrue,
      );
      expect(client.writes.single, {
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'is_officially_complete': true,
        'failure_grade_ids': [42],
        'completion_token': 'reviewed-context',
        'closure_reason': 'Assessment window closed.',
      });
      await notifier.updateGroupSettings(
        scope: 'capstone',
        stageLabel: 'Concept Proposal',
        isOfficiallyComplete: true,
      );
      expect(client.writes.last.containsKey('failure_grade_ids'), isFalse);
      expect(client.writes.last.containsKey('completion_token'), isFalse);
    },
  );

  test(
    'preflight reads the full group without inheriting display filters',
    () async {
      late _ReadinessClient client;
      final container = ProviderContainer(
        overrides: [
          authenticatedHttpClientProvider.overrideWith(
            (ref) => client = _ReadinessClient(
              ref,
              http.Response(
                jsonEncode({
                  'grading_total_team_count': 16,
                  'grading_ready_team_count': 15,
                  'can_complete': false,
                  'is_officially_complete': false,
                  'incomplete_teams': [
                    {
                      'team_name': 'Hidden team',
                      'missing_components': ['panel'],
                    },
                  ],
                  'redefense_teams': [
                    {'team_id': 2, 'team_name': 'Team Retry'},
                  ],
                  'revision_teams': [
                    {'team_id': 3, 'team_name': 'Team Revise'},
                  ],
                  'failing_teams': [],
                }),
                200,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gradeCenterProvider.notifier);
      final readiness = await notifier.checkGroupCompletion(
        scope: 'capstone',
        stageLabel: 'Concept Proposal',
      );
      expect(client.requests.single.queryParameters, {
        'workspace': 'operations',
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
      });
      expect(readiness.totalTeams, 16);
      expect(readiness.canComplete, isFalse);
      expect(readiness.incompleteTeams.single['team_name'], 'Hidden team');
      expect(readiness.redefenseTeams.single['team_name'], 'Team Retry');
      expect(readiness.revisionTeams.single['team_name'], 'Team Revise');
      expect(readiness.failingTeams, isEmpty);
      expect(container.read(gradeCenterProvider).isCheckingCompletion, isFalse);
      expect(container.read(gradeCenterProvider).incompleteTeams, isEmpty);
    },
  );

  test('older readiness responses can omit revision teams', () async {
    final container = ProviderContainer(
      overrides: [
        authenticatedHttpClientProvider.overrideWith(
          (ref) => _ReadinessClient(
            ref,
            http.Response(
              jsonEncode({
                'grading_total_team_count': 1,
                'grading_ready_team_count': 1,
                'can_complete': true,
                'is_officially_complete': false,
                'incomplete_teams': [],
                'redefense_teams': [],
                'failing_teams': [],
              }),
              200,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final readiness = await container
        .read(gradeCenterProvider.notifier)
        .checkGroupCompletion(scope: 'pit', stageLabel: 'PIT Expo');
    expect(readiness.canComplete, isTrue);
    expect(readiness.revisionTeams, isEmpty);
  });

  test(
    'failed preflight releases its busy state and returns no confirmation',
    () async {
      final container = ProviderContainer(
        overrides: [
          authenticatedHttpClientProvider.overrideWith(
            (ref) => _ReadinessClient(
              ref,
              http.Response('{"detail":"Could not check grading"}', 503),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(gradeCenterProvider.notifier)
            .checkGroupCompletion(scope: 'pit', stageLabel: 'PIT Expo'),
        throwsException,
      );
      expect(container.read(gradeCenterProvider).isCheckingCompletion, isFalse);
    },
  );
}
