import 'package:defensys/screens/web/admin/student_teams/components/student_teams_grid.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_stage_summary.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/table/table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _independent = <String, dynamic>{
  'id': 1,
  'name': 'Team ClayCircuit',
  'section': 'BSIT-3B',
  'semester_id': 2,
  'year_level': '3rd Year',
  'level': 'Capstone',
  'adviser_name': 'Renato Villanueva',
  'defense_context': {
    'current_stage': 'Concept Proposal',
    'stage_status': 'preparing',
    'stage_verdict': 'for_redefense',
    'concept_workflow': {
      'enabled': true,
      'status': 'draft',
      'section_project_id': null,
      'shared_import_pending': false,
      'required_count': 3,
      'title_progress': {'provided_count': 0, 'required_count': 3},
      'concepts': [
        {'key': 'c1', 'title': ''},
        {'key': 'c2', 'title': ''},
        {'key': 'c3', 'title': ''},
      ],
      'next_step': 'Students submit the independent concept titles.',
    },
  },
};

const _shared = <String, dynamic>{
  'id': 2,
  'name': 'Team ThreadAtlas',
  'project_title': 'MakersMap: Artisan Profiles & Discovery Module',
  'section': 'BSIT-3B',
  'semester_id': 2,
  'year_level': '3rd Year',
  'level': 'Capstone',
  'adviser_name': 'Analiza Corpuz',
  'defense_context': {
    'current_stage': 'Concept Proposal',
    'stage_verdict': 'approved',
    'concept_workflow': {
      'enabled': true,
      'status': 'approved',
      'section_project_id': 8,
      'section_selected_key': 'c1',
      'system_concepts': [
        {'key': 'c1', 'title': 'HABI: Artisan Heritage & Craft Exchange'},
        {'key': 'c2', 'title': 'Community Recycling'},
        {'key': 'c3', 'title': 'Local Tourism'},
      ],
      'next_step': 'Submit the required post-defense files.',
    },
  },
};

Finder get _tables => find.byWidgetPredicate(
  (widget) => widget is DefensysDataTable<Map<String, dynamic>>,
);

Future<void> _pumpGroups(
  WidgetTester tester,
  List<Map<String, dynamic>> teams, {
  bool dark = false,
}) async {
  // Layout checks use the app's Inter metrics, including outside preview runs.
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    SingleChildScrollView(
      child: GroupedSectionView(
        state: StudentTeamsState(teams: teams),
        isPit: false,
        searchQuery: 'Team',
        onOpenTeamDetail: (_) {},
      ),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
  );
}

void main() {
  for (final dark in [false, true]) {
    for (final width in [1440.0, 390.0]) {
      testWidgets('outcome and shared membership fit $width, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpGroups(tester, [_shared, _independent], dark: dark);
        final tables = tester
            .widgetList<DefensysDataTable<Map<String, dynamic>>>(_tables)
            .toList();
        expect(
          tables.map((table) => table.items.map((team) => team['id']).toList()),
          [
            [1],
            [2],
          ],
        );
        expect(find.text('2 teams'), findsOneWidget);
        expect(find.text('Independent projects'), findsOneWidget);
        expect(find.text('Re-defense required'), findsOneWidget);
        expect(find.text('Awaiting student submission'), findsOneWidget);
        expect(
          find.text('Students submit the independent concept titles.'),
          findsOneWidget,
        );
        expect(find.text('No stage update'), findsNothing);
        final heading = find.text('Shared system proposals · Concept Proposal');
        expect(
          tester.getTopLeft(find.text('Team ClayCircuit')).dy,
          lessThan(tester.getTopLeft(heading).dy),
        );
        expect(
          tester.getTopLeft(find.text('Team ThreadAtlas')).dy,
          greaterThan(tester.getTopLeft(heading).dy),
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(GroupedSectionView),
          'team-outcomes-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }

  testWidgets(
    'adviser filter hides empty shared group without changing section count',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGroups(tester, [_shared, _independent]);
      await tester.tap(
        find.descendant(
          of: find.byType(Tooltip),
          matching: find.text('Renato Villanueva'),
        ),
      );
      await tester.pumpAndSettle();
      final table = tester.widget<DefensysDataTable<Map<String, dynamic>>>(
        _tables,
      );
      expect(table.items.single['id'], 1);
      expect(find.text('2 teams'), findsOneWidget);
      expect(
        find.text('Shared system proposals · Concept Proposal'),
        findsNothing,
      );
      expect(find.text('Team ThreadAtlas'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('independent-only section never shows a shared heading', (
    tester,
  ) async {
    await _pumpGroups(tester, [_independent]);
    expect(_tables, findsOneWidget);
    expect(find.text('1 team'), findsOneWidget);
    expect(find.textContaining('Shared system proposals'), findsNothing);
    expect(find.text('Independent projects'), findsNothing);
  });

  testWidgets('title review and re-defense statuses have usable labels', (
    tester,
  ) async {
    for (final (code, label) in [
      ('submitted', 'Awaiting title review'),
      ('changes_requested', 'Title revision requested'),
      ('for_redefense', 'Re-defense required'),
    ]) {
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => currentStageBadge(context, {
            'defense_context': {
              'concept_workflow': {'enabled': true, 'status': code},
            },
          }),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('No stage update'), findsNothing);
    }
  });

  testWidgets(
    'final failure and historical rows do not request new submissions',
    (tester) async {
      final defense = Map<String, dynamic>.from(
        _independent['defense_context'] as Map,
      );
      await pumpDefensysWidget(
        tester,
        TeamStageStatus(
          team: {
            ..._independent,
            'defense_context': {...defense, 'stage_verdict': 'failed'},
          },
        ),
      );
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Awaiting student submission'), findsNothing);
      expect(
        find.text('Students submit the independent concept titles.'),
        findsNothing,
      );
      await pumpDefensysWidget(
        tester,
        TeamStageStatus(
          team: {
            ..._independent,
            'term_status': 'historical',
            'is_editable': false,
          },
        ),
      );
      expect(find.text('Re-defense required'), findsOneWidget);
      expect(
        find.text('Students submit the independent concept titles.'),
        findsNothing,
      );
    },
  );
}
