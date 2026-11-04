import 'dart:convert';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> team(
  int id, {
  String section = 'BSIT-3B',
  String stage = 'Concept Proposal',
}) {
  final payload = {
    'stage_label': stage,
    'pre': [],
    'post': [],
    'concept_workflow': {
      'enabled': true,
      'shared_import_pending': true,
      'system_concepts': [
        {'key': 'c1', 'title': 'HABI platform'},
        {'key': 'c2', 'title': ''},
        {'key': 'c3', 'title': ''},
      ],
    },
  };
  return {
    'id': id,
    'name': 'Module team $id',
    'section': section,
    'semester_id': 4,
    'year_level': '3rd Year',
    'members': [],
    'stages': [payload],
    'selected_stage': payload,
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  test('pending imports group by academic context rather than the PM team', () {
    final entries = pendingSharedReviewsForTeams([
      team(2),
      team(3),
      team(4, section: 'BSIT-3C'),
    ]);
    expect(entries, hasLength(2));
    expect(entries.first['team_id'], 2);
    expect(entries.first['provided'], 1);
    expect(
      pendingSharedReviewsForTeams([team(2)], stageLabel: 'Final Defense'),
      isEmpty,
    );
    final activated = team(2);
    ((activated['selected_stage'] as Map)['concept_workflow']
            as Map)['section_project_id'] =
        7;
    expect(pendingSharedReviewsForTeams([activated]), isEmpty);
  });

  for (final width in [390.0, 1400.0]) {
    testWidgets('adviser opens shared titles before PM submission at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'id': null,
              'imported': true,
              'section': 'BSIT-3B',
              'project_manager_name': 'Nathan CABAHUG',
              'systems': [
                {'key': 'c1', 'title': 'HABI platform'},
                {'key': 'c2', 'title': ''},
                {'key': 'c3', 'title': ''},
              ],
            }),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DeliverablesTablePane(
            state: CapstoneDeliverablesState(
              teams: [team(2)],
              scope: 'capstone',
              workspace: 'adviser',
              selectedStage: 'Concept Proposal',
            ),
            isAdviser: true,
            compactFaculty: true,
            conceptReview: true,
          ),
        ),
        theme: width == 390 ? AppTheme.mistDarkTheme : AppTheme.theme,
        overrides: authTestOverrides(),
      );
      expect(requests, isEmpty);
      expect(find.text('Shared system proposals'), findsNothing);
      if (width == 390) {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Shared systems · BSIT-3B').last);
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, endsWith('/section-concepts/imported/'));
      expect(requests.single.url.queryParameters['team_id'], '2');
      expect(find.text('Shared system proposals'), findsOneWidget);
      expect(find.text('1/3 shared titles provided'), findsWidgets);
      expect(find.text('Project manager: Nathan CABAHUG'), findsOneWidget);
      expect(find.text('System B · Pending proposal'), findsOneWidget);
      expect(find.text('System C · Pending proposal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
