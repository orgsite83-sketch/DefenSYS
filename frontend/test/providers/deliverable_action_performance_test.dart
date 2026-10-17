import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

Map<String, dynamic> team(
  int id, {
  bool accepted = false,
  bool endorsed = false,
}) => {
  'id': id,
  'name': 'Team $id',
  'selected_stage': {
    'stage_label': 'Concept Proposal',
    'endorsed': endorsed,
    'pre': [
      {
        'id': 'PAPER',
        'submission': {'status': accepted ? 'accepted' : 'pending'},
      },
    ],
  },
  'counts': {
    'teams': 1,
    'ready': accepted || endorsed ? 1 : 0,
    'pending_review': accepted || endorsed ? 0 : 1,
    'missing_requirements': 0,
    'submitted_files': 1,
    'archive_files': 0,
    'deliverables_configured': true,
  },
};

http.Response listResponse(String scope, {String stage = 'Concept Proposal'}) =>
    http.Response(
      jsonEncode({
        'teams': [team(7), team(8)],
        'selected_stage': stage,
        'stage_options': [stage],
        'scope': scope,
        'counts': {
          'teams': 2,
          'pending_review': 2,
          'ready': 0,
          'submitted_files': 2,
        },
      }),
      200,
    );

http.Response actionResponse(
  String scope, {
  bool matches = true,
  bool endorsed = false,
}) => http.Response(
  jsonEncode({
    'response_mode': 'team',
    'team': team(7, accepted: true, endorsed: endorsed),
    'matches_filters': matches,
    'selected_stage': 'Concept Proposal',
    'scope': scope,
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  for (final scope in ['pit', 'capstone']) {
    for (final action in ['review', 'endorse', 'unendorse']) {
      test(
        '$scope $action updates one team and counters with a single request',
        () async {
          final requests = <http.Request>[];
          setApiHttpClientForTesting(
            MockClient((request) async {
              requests.add(request);
              return request.method == 'GET'
                  ? listResponse(scope)
                  : actionResponse(scope, endorsed: action == 'endorse');
            }),
          );
          final container = ProviderContainer(overrides: authTestOverrides());
          addTearDown(container.dispose);
          final notifier = container.read(
            capstoneDeliverablesProvider.notifier,
          );
          await notifier.fetchDeliverables(
            scope: scope,
            selectedStage: 'Concept Proposal',
            yearLevel: '1st Year',
            section: 'BSIT-1A',
            search: 'Team',
          );
          final originalOther = container
              .read(capstoneDeliverablesProvider)
              .teams[1];
          requests.clear();
          final success = switch (action) {
            'review' => await notifier.reviewDeliverable(
              teamId: 7,
              stageLabel: 'Concept Proposal',
              deliverableId: 'PAPER',
              status: 'accepted',
            ),
            'endorse' => await notifier.endorseTeam(7, 'Concept Proposal'),
            _ => await notifier.unendorseTeam(7, 'Concept Proposal'),
          };
          expect(success, true);
          expect(requests, hasLength(1));
          expect(requests.single.method, 'POST');
          expect(requests.single.url.queryParameters, {
            'scope': scope,
            'stage_label': 'Concept Proposal',
            'response_mode': 'team',
            'year_level': '1st Year',
            'section': 'BSIT-1A',
            'search': 'Team',
          });
          final state = container.read(capstoneDeliverablesProvider);
          expect(state.teams, hasLength(2));
          expect(identical(state.teams[1], originalOther), true);
          expect(
            state.teams[0]['selected_stage']['pre'][0]['submission']['status'],
            'accepted',
          );
          expect(state.counts['pending_review'], 1);
          expect(state.counts['ready'], 1);
          expect(state.counts['submitted_files'], 2);
          expect(state.isSaving, false);
          expect(state.error, isNull);
        },
      );
    }
  }

  test(
    'accepted team leaves the pending review filter and counters stay consistent',
    () async {
      var requests = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests++;
          return request.method == 'GET'
              ? listResponse('capstone')
              : actionResponse('capstone', matches: false);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      await notifier.fetchDeliverables(status: 'pending_review');
      await notifier.reviewDeliverable(
        teamId: 7,
        stageLabel: 'Concept Proposal',
        deliverableId: 'PAPER',
        status: 'accepted',
      );
      expect(requests, 2);
      final state = container.read(capstoneDeliverablesProvider);
      expect(state.status, 'pending_review');
      expect(state.teams.single['id'], 8);
      expect(state.counts['teams'], 1);
      expect(state.counts['pending_review'], 1);
      expect(state.counts['ready'], 0);
    },
  );

  test(
    'failed action retains the displayed snapshot and reports the error',
    () async {
      setApiHttpClientForTesting(
        MockClient(
          (request) async => request.method == 'GET'
              ? listResponse('capstone')
              : http.Response('{"detail":"Review is locked."}', 403),
        ),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      await notifier.fetchDeliverables();
      final original = container.read(capstoneDeliverablesProvider).teams;
      expect(await notifier.endorseTeam(7, 'Concept Proposal'), false);
      final state = container.read(capstoneDeliverablesProvider);
      expect(identical(state.teams, original), true);
      expect(state.error, 'Review is locked.');
      expect(state.isSaving, false);
    },
  );

  test(
    'changing stage during a write refreshes the new view and blocks duplicate writes',
    () async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') return pending.future;
          return listResponse(
            'capstone',
            stage:
                request.url.queryParameters['stage_label'] ??
                'Concept Proposal',
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      await notifier.fetchDeliverables();
      final saving = notifier.endorseTeam(7, 'Concept Proposal');
      await notifier.fetchDeliverables(selectedStage: 'Final Defense');
      expect(container.read(capstoneDeliverablesProvider).isSaving, true);
      expect(await notifier.endorseTeam(7, 'Concept Proposal'), false);
      pending.complete(actionResponse('capstone', endorsed: true));
      expect(await saving, true);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(requests.last.method, 'GET');
      expect(requests.last.url.queryParameters['stage_label'], 'Final Defense');
      expect(
        container.read(capstoneDeliverablesProvider).selectedStage,
        'Final Defense',
      );
      expect(container.read(capstoneDeliverablesProvider).isSaving, false);
    },
  );

  test('an older list response cannot overwrite an accepted file', () async {
    final pending = Completer<http.Response>();
    var reads = 0;
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'POST') return actionResponse('capstone');
        return ++reads == 2 ? pending.future : listResponse('capstone');
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(capstoneDeliverablesProvider.notifier);
    await notifier.fetchDeliverables();
    final oldRefresh = notifier.fetchDeliverables();
    await notifier.reviewDeliverable(
      teamId: 7,
      stageLabel: 'Concept Proposal',
      deliverableId: 'PAPER',
      status: 'accepted',
    );
    pending.complete(listResponse('capstone'));
    await oldRefresh;
    expect(
      container
          .read(capstoneDeliverablesProvider)
          .teams[0]['selected_stage']['pre'][0]['submission']['status'],
      'accepted',
    );
  });
}
