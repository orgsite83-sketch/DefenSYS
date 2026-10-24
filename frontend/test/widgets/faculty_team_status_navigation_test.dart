import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_team_choice_label.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _team(int id, String name, String code) {
  final selected = <String, dynamic>{
    'stage_label': 'Final Defense',
    'deliverables_configured': code != 'not_configured',
    'stage_status_detail': code == 'not_configured' ? 'pending' : code,
  };
  return {
    'id': id,
    'name': name,
    'members': [],
    'current_stage': 'Proposal Defense',
    'selected_stage': selected,
    'stages': [
      {'stage_label': 'Proposal Defense', 'status': 'passed'},
      selected,
    ],
  };
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final width in [1400.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'team choices show selected-stage statuses at $width, dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final state = ValueNotifier(
            CapstoneDeliverablesState(
              selectedStage: 'Final Defense',
              teams: [
                _team(1, 'Team AgriPulse', 'needs_review'),
                _team(2, 'Team ClimateNode', 'awaiting_files'),
                _team(3, 'Team CropVision', 'scheduled'),
                _team(4, 'Team SoilSense', 'not_configured'),
              ],
            ),
          );
          addTearDown(state.dispose);
          var selectedId = 1;
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: const ValueKey('team-navigation-capture'),
                child: ValueListenableBuilder<CapstoneDeliverablesState>(
                  valueListenable: state,
                  builder: (context, value, _) => DeliverablesTablePane(
                    state: value,
                    isAdviser: true,
                    compactFaculty: true,
                    onSelectedTeamChanged: (id) => selectedId = id,
                  ),
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: authTestOverrides(),
          );

          Finder teamChoice(int id) => width == 1400
              ? find.byKey(ValueKey('faculty-team-choice-t$id'))
              : find.byType(DropdownButtonFormField<String>);
          if (width == 1400) {
            for (final (id, label) in [
              (1, 'Needs review'),
              (2, 'Awaiting files'),
              (3, 'Scheduled'),
              (4, 'Not configured'),
            ]) {
              expect(
                find.descendant(of: teamChoice(id), matching: find.text(label)),
                findsOneWidget,
              );
            }
            await tester.tap(teamChoice(2));
          } else {
            expect(
              find.descendant(
                of: teamChoice(1),
                matching: find.text('Needs review'),
              ),
              findsOneWidget,
            );
            await tester.tap(teamChoice(1));
            await tester.pumpAndSettle();
            expect(find.text('Scheduled'), findsWidgets);
            expect(find.text('Not configured'), findsWidgets);
            await tester.tap(find.text('Team ClimateNode').last);
          }
          await tester.pumpAndSettle();
          expect(selectedId, 2);
          final selected = find
              .byType(FacultyTeamChoiceLabel)
              .evaluate()
              .map((element) => element.widget as FacultyTeamChoiceLabel)
              .firstWhere((label) => label.label == 'Team ClimateNode');
          expect(selected.status?.code, 'awaiting_files');

          // Refreshing one team's status keeps that team selected.
          state.value = state.value.copyWith(
            teams: [
              _team(1, 'Team AgriPulse', 'needs_review'),
              _team(2, 'Team ClimateNode', 'scheduled'),
              _team(3, 'Team CropVision', 'scheduled'),
              _team(4, 'Team SoilSense', 'not_configured'),
            ],
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: teamChoice(2),
              matching: find.text('Scheduled'),
            ),
            findsWidgets,
          );
          expect(selectedId, 2);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('team-navigation-capture')),
            'team-navigation-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );

          // A historical stage replaces statuses without switching teams.
          state.value = state.value.copyWith(
            selectedStage: 'Proposal Defense',
            teams: [
              for (final team in state.value.teams)
                {...team, 'selected_stage': (team['stages'] as List).first},
            ],
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: teamChoice(2), matching: find.text('Passed')),
            findsWidgets,
          );
          expect(selectedId, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'review group refresh selects another matching team and excludes finished reviews',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final teams = ValueNotifier([
        _team(1, 'Team AgriPulse', 'needs_review'),
        _team(2, 'Team ClimateNode', 'needs_review'),
        _team(3, 'Team CropVision', 'scheduled'),
      ]);
      addTearDown(teams.dispose);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: teams,
            builder: (context, value, _) => DeliverablesTablePane(
              state: CapstoneDeliverablesState(
                selectedStage: 'Final Defense',
                teams: value,
              ),
              isAdviser: true,
              compactFaculty: true,
              activeTriageFilter: TeamTriageFilter.forReview,
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Teams (2)'), findsOneWidget);
      expect(find.text('Team CropVision'), findsNothing);
      teams.value = [
        _team(1, 'Team AgriPulse', 'scheduled'),
        _team(2, 'Team ClimateNode', 'needs_review'),
        _team(3, 'Team CropVision', 'scheduled'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Teams (1)'), findsOneWidget);
      expect(find.text('Team AgriPulse'), findsNothing);
      expect(find.text('Team ClimateNode'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
