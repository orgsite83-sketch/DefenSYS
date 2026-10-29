import 'dart:async';
import 'dart:convert';

import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/team_deliverables_screen.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/shared_deliverables_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _stage(int teamId, {bool shared = true}) => {
  'stage_label': 'Project Proposal',
  'deliverables_configured': true,
  'required_total': 1,
  'pre': [
    {
      'id': 'MODULE',
      'label': 'Module report',
      'required': true,
      'file_policy': {'mode': 'single'},
    },
  ],
  'post': <Map<String, dynamic>>[],
  'concept_workflow': {'enabled': false},
  if (shared)
    'shared_deliverables_summary': {
      'team_id': teamId,
      'section_id': 11,
      'section': 'BSIT-3A',
      'context_id': 42,
      'stage_label': 'Project Proposal',
      'project_manager_name': 'Gabriel Navarro',
      'pre_complete': false,
      'post_complete': false,
    },
};

CapstoneDeliverablesState _state({
  bool shared = true,
  String scope = 'capstone',
}) => CapstoneDeliverablesState(
  selectedStage: 'Project Proposal',
  stageOptions: const ['Project Proposal', 'Final Defense'],
  scope: scope,
  workspace: scope == 'pit' ? 'instructor' : 'adviser',
  teams: [
    for (var id = 1; id <= 2; id++)
      {
        'id': id,
        'name': 'Team $id',
        'section': 'BSIT-3A',
        'members': [],
        'selected_stage': _stage(id, shared: shared),
        'stages': [_stage(id, shared: shared)],
      },
  ],
);

Map<String, dynamic> _group({String title = 'Agricultural Supply Platform'}) =>
    {
      'team_id': 1,
      'section': 'BSIT-3A',
      'stage_label': 'Project Proposal',
      'project_manager_name': 'Gabriel Navarro',
      'identity': 'shared-stage-42',
      'review_token': 'current-review-token',
      'concept_selection_enabled': false,
      'selected_key': 'c2',
      'systems': [
        {'key': 'c1', 'title': 'Earlier system proposal'},
        {'key': 'c2', 'title': title},
      ],
      'requirements': [
        {
          'deliverable_id': 'SYSTEM',
          'label': 'Shared design specification',
          'required': true,
          'deliverable_type': 'pre',
          'status': 'pending',
          'file_policy': {'mode': 'concepts'},
          'documents': [
            for (var i = 1; i <= 2; i++)
              {
                'key': 'c$i:spec',
                'system_key': 'c$i',
                'label': 'Design specification',
                'required': true,
                'can_upload': false,
                'can_review': i == 2,
                'file': {
                  'id': i,
                  'file_name': 'system_$i.pdf',
                  'status': 'pending',
                  'revision': 1,
                },
              },
          ],
        },
        {
          'deliverable_id': 'NOTES',
          'label': 'Integration notes',
          'required': false,
          'deliverable_type': 'pre',
          'status': 'missing',
          'file_policy': {'mode': 'single'},
          'documents': [
            {
              'key': 'primary',
              'label': 'Integration notes',
              'file_format': 'pdf',
              'can_upload': false,
              'can_review': false,
            },
          ],
        },
      ],
    };

http.Response _response(Map<String, dynamic>? group) =>
    http.Response(jsonEncode({'shared_deliverables': group}), 200);

class _Deliverables extends CapstoneDeliverablesNotifier {
  int refreshes = 0;
  @override
  CapstoneDeliverablesState build() => _state(scope: 'pit');
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {
    refreshes++;
  }
}

class _Grades extends AdviserGradingNotifier {
  @override
  Future<void> fetchAll() async {}
}

class _Weekly extends WeeklyProgressNotifier {
  @override
  Future<void> fetchReports() async {}
}

class _Defense extends PitInstructorDefenseNotifier {
  @override
  Future<void> fetch({String? workspace}) async {}
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  for (final width in [1400.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('normal shared workspace at $width, dark=$dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final requests = <http.Request>[];
        setApiHttpClientForTesting(
          MockClient((request) async {
            requests.add(request);
            return _response(_group());
          }),
        );
        final state = ValueNotifier(_state());
        addTearDown(state.dispose);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<CapstoneDeliverablesState>(
              valueListenable: state,
              builder: (context, value, _) => DeliverablesTablePane(
                state: value,
                isAdviser: true,
                compactFaculty: true,
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: authTestOverrides(),
        );
        expect(requests, isEmpty);
        expect(find.byType(SharedDeliverablesPanel), findsNothing);

        Future<void> choose(String key, String label) async {
          if (width == 1400) {
            await tester.tap(find.byKey(ValueKey('faculty-team-choice-$key')));
          } else {
            await tester.tap(find.byType(DropdownButtonFormField<String>));
            await tester.pumpAndSettle();
            await tester.tap(find.text(label).last);
          }
          await tester.pumpAndSettle();
        }

        await choose('s11-42', 'Shared system · BSIT-3A');
        expect(requests.single.method, 'GET');
        expect(requests.single.url.queryParameters, {
          'team_id': '1',
          'stage_label': 'Project Proposal',
        });
        expect(find.text('Agricultural Supply Platform'), findsOneWidget);
        expect(find.text('Project manager: Gabriel Navarro'), findsOneWidget);
        expect(find.text('Shared design specification'), findsOneWidget);
        expect(find.text('Integration notes'), findsOneWidget);
        expect(find.text('system_2.pdf'), findsOneWidget);
        expect(find.text('system_1.pdf'), findsNothing);
        expect(find.text('Earlier system proposal'), findsNothing);
        expect(find.text('System 1'), findsNothing);
        expect(find.text('Earlier proposals (1)'), findsNothing);
        expect(find.text('Accept file'), findsOneWidget);
        final upload = tester.widget<DeliverableUploadTile>(
          find.byType(DeliverableUploadTile),
        );
        expect(upload.enabled, isFalse);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('shared-deliverables-workspace')),
          'normal-shared-workspace-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );

        await choose('t2', 'Team 2');
        expect(find.byType(SharedDeliverablesPanel), findsNothing);
        expect(find.text('Module report'), findsOneWidget);
        expect(find.text('Team details'), findsOneWidget);
        await choose('s11-42', 'Shared system · BSIT-3A');
        expect(requests, hasLength(2));

        // Changing to a stage with no shared requirements removes the entry
        // and the previous stage's files, while retaining the team workspace.
        state.value = _state(shared: false).copyWith(
          selectedStage: 'Final Defense',
          teams: [
            for (final team in _state(shared: false).teams)
              {
                ...team,
                'selected_stage': {
                  ..._stage(team['id'] as int, shared: false),
                  'stage_label': 'Final Defense',
                },
                'stages': [
                  {
                    ..._stage(team['id'] as int, shared: false),
                    'stage_label': 'Final Defense',
                  },
                ],
              },
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('Shared system · BSIT-3A'), findsNothing);
        expect(find.text('system_2.pdf'), findsNothing);
        expect(find.text('Module report'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'screen places shared files in the sidebar and refreshes after review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final writes = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          final group = _group();
          if (request.method == 'POST') {
            writes.add(jsonDecode(request.body) as Map<String, dynamic>);
            final requirement = (group['requirements'] as List).first as Map;
            final document = (requirement['documents'] as List).last as Map;
            (document['file'] as Map)['status'] = 'accepted';
            document['can_review'] = false;
          }
          return _response(group);
        }),
      );
      final deliverables = _Deliverables();
      await pumpDefensysWidget(
        tester,
        const TeamDeliverablesScreen(isPitInstructor: true),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => deliverables),
          adviserGradingProvider.overrideWith(_Grades.new),
          weeklyProgressProvider.overrideWith(_Weekly.new),
          pitInstructorDefenseProvider.overrideWith(_Defense.new),
        ],
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('Concept review'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('faculty-team-choice-s11-42')),
      );
      await tester.pumpAndSettle();
      final refreshes = deliverables.refreshes;
      await tester.tap(find.text('Accept file'));
      await tester.pumpAndSettle();
      expect(writes.single['team_id'], 1);
      expect(writes.single['slot_key'], 'c2:spec');
      expect(writes.single['review_token'], 'current-review-token');
      expect(writes.single['status'], 'accepted');
      expect(deliverables.refreshes, greaterThan(refreshes));
      expect(find.text('Accept file'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stage changes ignore a late shared response', (tester) async {
    final earlier = Completer<http.Response>();
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.queryParameters['stage_label'] == 'Project Proposal') {
          return earlier.future;
        }
        return _response(_group(title: 'Final-stage system'));
      }),
    );
    final stage = ValueNotifier('Project Proposal');
    addTearDown(stage.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authTestOverrides(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<String>(
                valueListenable: stage,
                builder: (context, value, _) => SharedDeliverablesSection(
                  teamId: 1,
                  stageLabel: value,
                  embedded: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    stage.value = 'Final Defense';
    await tester.pumpAndSettle();
    expect(find.text('Final-stage system'), findsOneWidget);
    earlier.complete(_response(_group(title: 'Stale proposal system')));
    await tester.pumpAndSettle();
    expect(find.text('Final-stage system'), findsOneWidget);
    expect(find.text('Stale proposal system'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
