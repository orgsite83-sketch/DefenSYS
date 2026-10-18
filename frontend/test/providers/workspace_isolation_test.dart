import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/academic/student_teams_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/defense/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/defense_board_provider.dart';
import 'package:defensys/services/defense/defense_scheduler_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Client implements AuthenticatedHttpClient {
  final requests = <Uri>[];
  final pending = <Completer<http.Response>>[];
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    requests.add(uri);
    final response = Completer<http.Response>();
    pending.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    user: {'role': 'faculty', 'is_pit_lead': true, 'pit_lead_year': '3rd Year'},
    token: 'test',
    isRestoring: false,
  );
}

http.Response _snapshot(int id) => http.Response(
  jsonEncode({
    for (final key in ['teams', 'grades', 'schedules'])
      key: [
        {'id': id},
      ],
  }),
  200,
);

void main() {
  late _Client client;
  late ProviderContainer container;
  setUp(() {
    client = _Client();
    container = ProviderContainer(
      overrides: [
        authenticatedHttpClientProvider.overrideWithValue(client),
        authProvider.overrideWith(_Auth.new),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'scheduler and grade center explicitly request management authority',
    () async {
      final scheduler = container
          .read(defenseSchedulerProvider.notifier)
          .fetchSchedules();
      final grades = container.read(gradeCenterProvider.notifier).fetchGrades();
      expect(
        client.requests.every(
          (uri) => uri.queryParameters['workspace'] == 'operations',
        ),
        isTrue,
      );
      for (final response in client.pending) {
        response.complete(_snapshot(1));
      }
      await Future.wait([scheduler, grades]);
    },
  );

  test(
    'team workspace changes clear old rows and ignore old responses',
    () async {
      final teams = container.read(studentTeamsProvider.notifier);
      final initial = teams.fetchTeams(workspace: 'operations');
      client.pending[0].complete(_snapshot(1));
      await initial;
      final earlier = teams.fetchTeams();
      final switched = teams.fetchTeams(
        workspace: 'instructor',
        yearLevel: '2nd Year',
        section: 'BSIT-2A',
      );
      expect(container.read(studentTeamsProvider).teams, isEmpty);
      expect(client.requests.last.queryParameters['workspace'], 'instructor');
      client.pending[2].complete(_snapshot(2));
      await switched;
      client.pending[1].complete(_snapshot(99));
      await earlier;
      expect(container.read(studentTeamsProvider).teams.single['id'], 2);
      expect(container.read(studentTeamsProvider).workspace, 'instructor');
    },
  );

  test(
    'deliverables isolate two PIT workspaces even when the track stays PIT',
    () async {
      final files = container.read(capstoneDeliverablesProvider.notifier);
      final initial = files.fetchDeliverables(
        workspace: 'operations',
        scope: 'pit',
      );
      client.pending[0].complete(_snapshot(1));
      await initial;
      final earlier = files.fetchDeliverables();
      final switched = files.fetchDeliverables(
        workspace: 'instructor',
        scope: 'pit',
        yearLevel: '2nd Year',
      );
      expect(container.read(capstoneDeliverablesProvider).teams, isEmpty);
      expect(client.requests.last.queryParameters['workspace'], 'instructor');
      client.pending[2].complete(_snapshot(2));
      await switched;
      client.pending[1].complete(_snapshot(99));
      await earlier;
      expect(
        container.read(capstoneDeliverablesProvider).teams.single['id'],
        2,
      );
      expect(
        container.read(capstoneDeliverablesProvider).workspace,
        'instructor',
      );
    },
  );

  test(
    'a response for a disposed workspace cannot repopulate its provider',
    () async {
      final earlier = container
          .read(defenseBoardProvider.notifier)
          .fetchBoard();
      container.invalidate(defenseBoardProvider);
      expect(container.read(defenseBoardProvider).schedules, isEmpty);
      client.pending.single.complete(_snapshot(99));
      await earlier;
      expect(container.read(defenseBoardProvider).schedules, isEmpty);
    },
  );

  test(
    'instructor filters do not carry into the PIT operations workspace',
    () async {
      final files = container.read(capstoneDeliverablesProvider.notifier);
      final initial = files.fetchDeliverables(
        workspace: 'instructor',
        scope: 'pit',
        yearLevel: '2nd Year',
        section: 'BSIT-2A',
        search: 'Only instructor',
        selectedStage: 'Second Year Event',
      );
      client.pending[0].complete(_snapshot(1));
      await initial;
      final switched = files.fetchDeliverables(
        workspace: 'operations',
        scope: 'pit',
      );
      expect(client.requests.last.queryParameters, {
        'workspace': 'operations',
        'scope': 'pit',
      });
      client.pending[1].complete(_snapshot(2));
      await switched;
      expect(
        container.read(capstoneDeliverablesProvider).teams.single['id'],
        2,
      );
    },
  );

  test(
    'scheduler disposal drops the previous workspace deduplication entry',
    () async {
      final earlier = container
          .read(defenseSchedulerProvider.notifier)
          .fetchSchedules();
      container.invalidate(defenseSchedulerProvider);
      final latest = container
          .read(defenseSchedulerProvider.notifier)
          .fetchSchedules();
      expect(client.requests.length, 2);
      client.pending[1].complete(_snapshot(2));
      await latest;
      client.pending[0].complete(_snapshot(99));
      await earlier;
      expect(
        container.read(defenseSchedulerProvider).schedules.single['id'],
        2,
      );
    },
  );
}
