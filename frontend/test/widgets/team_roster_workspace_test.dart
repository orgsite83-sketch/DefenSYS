import 'dart:convert';
import 'package:defensys/screens/web/faculty/team_roster_screen.dart';
import 'package:defensys/services/academic/team_roster_service.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> _team(int id, String name) => {
  'id': id,
  'name': name,
  'leader_id': id * 10,
  'leader_name': 'Ana Reyes',
  'members': [
    {'id': id * 10, 'name': 'Ana Reyes', 'username': 'ana'},
    {'id': id * 10 + 1, 'name': 'Luis Santos', 'username': 'luis'},
  ],
  'project_title': 'Campus appointment system',
  'carry_title': 'Campus appointment system',
  'project_choice': 'continue',
  'project_locked': false,
  'shared_project': false,
  'project_status': 'Carried forward',
  'confirmed': false,
  'ready': false,
  'setup_opened': false,
};

class _Service extends Fake implements TeamRosterService {
  bool canGenerate = true;
  Map<String, dynamic>? submitted;
  String? applied;
  Map<String, dynamic>? pending;
  final rosters = <Map<String, dynamic>>[
    {
      'id': null,
      'name': 'Current roster',
      'status': 'Default for upcoming events',
      'source': 'current',
      'locked': false,
      'completed': false,
      'can_request_setup': true,
      'team_count': 2,
      'student_count': 4,
      'ready_count': 0,
      'teams': [_team(1, 'Team FreshStart'), _team(2, 'Team Portal')],
    },
    {
      'id': 10,
      'name': 'System Concept Pitching',
      'status': 'Completed · roster locked',
      'source': 'custom',
      'locked': true,
      'completed': true,
      'can_request_setup': false,
      'team_count': 2,
      'student_count': 4,
      'ready_count': 2,
      'teams': [_team(1, 'Team FreshStart'), _team(2, 'Team Portal')],
    },
    {
      'id': 11,
      'name': '1st Year Expo',
      'status': 'Uses current roster',
      'source': 'current',
      'locked': false,
      'completed': false,
      'can_request_setup': true,
      'concept_enabled': false,
      'team_count': 2,
      'student_count': 4,
      'ready_count': 0,
      'teams': [_team(1, 'Team FreshStart'), _team(2, 'Team Portal')],
    },
  ];
  @override
  Future<Map<String, dynamic>> load(Map<String, dynamic> scope) async => {
    'year_level': '1st Year',
    'section': 'BSIT-1B',
    'fingerprint': 'review-state',
    'scope_options': [
      {'year_level': '1st Year', 'section': 'BSIT-1B'},
    ],
    'can_generate': canGenerate,
    'rosters': jsonDecode(jsonEncode(rosters)),
  };
  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> data) async {
    submitted = data;
    pending = data;
    if (data['operation'] == 'projects') {
      final selected = rosters.firstWhere((r) => r['id'] == data['event_id']);
      final ids = data['team_ids'] as List;
      final modes = data['team_modes'] as Map;
      final rows = (selected['teams'] as List)
          .where((t) => ids.contains(t['id']))
          .map(
            (t) => {
              ...Map<String, dynamic>.from(t),
              'previous_title': t['project_title'],
              'project_title': modes['${t['id']}'] == 'new'
                  ? ''
                  : t['project_title'],
              'project_action': modes['${t['id']}'] == 'new'
                  ? 'Start new project'
                  : 'Keep existing project',
              'needs_project': modes['${t['id']}'] == 'new',
            },
          )
          .toList();
      return {
        'preview_token': 'signed-project-review',
        'operation': 'projects',
        'event_setup': data['event_id'] != null,
        'teams': rows,
        'target': selected['name'],
        'team_count': ids.length,
        'kept_project_count': modes.values.where((v) => v == 'continue').length,
        'new_project_count': modes.values.where((v) => v == 'new').length,
        'affected_events': ['1st Year Expo'],
        'preserved_events': ['System Concept Pitching'],
        'confirmation': data['event_id'] == null
            ? 'Apply project choices to Current roster'
            : 'Confirm projects & request details',
      };
    }
    return {
      'preview_token': 'signed-review',
      'teams': [_team(1, 'Team FreshStart')],
      'target': data['event_id'] == null ? 'Current roster' : '1st Year Expo',
      'confirmation': data['event_id'] == null
          ? 'Set as current roster for upcoming events'
          : 'Apply to 1st Year Expo',
      'team_count': 1,
      'previous_team_count': 2,
      'student_count': 2,
      'omitted_student_count': 2,
      'affected_events': data['event_id'] == null ? ['1st Year Expo'] : [],
      'preserved_events': ['System Concept Pitching'],
    };
  }

  @override
  Future<Map<String, dynamic>> apply(String token) async {
    applied = token;
    if (pending?['operation'] == 'projects') {
      final target = rosters.firstWhere((r) => r['id'] == pending!['event_id']);
      if (pending!['event_id'] != null) target['locked'] = true;
      return {'requested_count': (pending!['team_ids'] as List).length};
    }
    return {'created_count': 1};
  }

  @override
  Future<Map<String, dynamic>> correct(Map<String, dynamic> data) async {
    submitted = data;
    final team = (rosters[2]['teams'] as List).first as Map<String, dynamic>;
    team['name'] = data['name'];
    team['project_title'] = data['project_title'];
    team['confirmed'] = false;
    return {'corrected': true};
  }

  @override
  Future<Map<String, dynamic>> requestSetup(Map<String, dynamic> data) async {
    submitted = data;
    rosters[2]['can_request_setup'] = false;
    rosters[2]['locked'] = true;
    return {'requested_count': (data['team_ids'] as List).length};
  }
}

void main() {
  testWidgets('copy is reviewed for the selected event before applying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Service();
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: '1st Year Expo', instructor: true),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.tap(find.text('Copy roster'));
    await tester.pumpAndSettle();
    expect(find.text('Copy an existing roster'), findsOneWidget);
    await tester.tap(find.text('Review roster'));
    await tester.pumpAndSettle();
    expect(service.submitted?['event_id'], 11);
    expect(service.submitted?['workspace'], 'instructor');
    expect(service.applied, isNull);
    expect(find.text('Save as: 1st Year Expo · BSIT-1B'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply to 1st Year Expo'));
    await tester.tap(find.text('Apply to 1st Year Expo'));
    await tester.pumpAndSettle();
    expect(service.applied, 'signed-review');
  });

  testWidgets('completed roster exposes export but no replacement or setup', (
    tester,
  ) async {
    final service = _Service();
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: 'System Concept Pitching'),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    expect(find.text('Copy roster'), findsNothing);
    expect(find.text('Import roster'), findsNothing);
    expect(find.text('Generate teams'), findsNothing);
    expect(find.text('Project setup'), findsNothing);
    expect(find.text('Export roster'), findsOneWidget);
    expect(find.text('Copy to Current roster'), findsOneWidget);
    await tester.ensureVisible(find.text('Copy to Current roster'));
    await tester.tap(find.text('Copy to Current roster'));
    await tester.pumpAndSettle();
    expect(find.text('Target: Current roster · BSIT-1B'), findsOneWidget);
  });

  testWidgets(
    'new current roster explicitly identifies affected and preserved events',
    (tester) async {
      final service = _Service();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.ensureVisible(find.text('Generate teams'));
      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review roster'));
      await tester.tap(find.text('Review roster'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Upcoming events using this roster: 1st Year Expo'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Event rosters preserved: System Concept Pitching'),
        findsOneWidget,
      );
      expect(
        find.text('Set as current roster for upcoming events'),
        findsOneWidget,
      );
      expect(service.submitted?['operation'], 'generate');
    },
  );

  testWidgets('project setup targets the event and selected section teams', (
    tester,
  ) async {
    final service = _Service();
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: '1st Year Expo', instructor: true),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.ensureVisible(find.text('Project setup'));
    await tester.tap(find.text('Project setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ShadButton, 'Review project choices'),
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Review project choices'));
    await tester.pumpAndSettle();
    expect(service.submitted?['team_ids'], [1, 2]);
    expect(service.submitted?['event_id'], 11);
    expect(service.submitted?['team_modes'], {
      '1': 'continue',
      '2': 'continue',
    });
    expect(service.applied, isNull);
    await tester.ensureVisible(find.text('Confirm projects & request details'));
    await tester.tap(find.text('Confirm projects & request details'));
    await tester.pumpAndSettle();
    expect(service.applied, 'signed-project-review');
    expect(find.text('Copy roster'), findsNothing);
  });

  testWidgets(
    'individual project choices are reviewed before changing a confirmed team',
    (tester) async {
      final service = _Service();
      final team = (service.rosters[2]['teams'] as List).first;
      team['setup_opened'] = true;
      team['confirmed'] = true;
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(initialEvent: '1st Year Expo'),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.ensureVisible(find.text('Team FreshStart'));
      await tester.tap(find.text('Team FreshStart'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Project options'));
      await tester.tap(find.text('Project options'));
      await tester.pumpAndSettle();
      final choice = find.descendant(
        of: find.byKey(const ValueKey('project-choice-1')),
        matching: find.byType(ShadSelect<String>),
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new project').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(ShadButton, 'Review project choices'),
      );
      await tester.tap(
        find.widgetWithText(ShadButton, 'Review project choices'),
      );
      await tester.pumpAndSettle();
      expect(service.submitted?['team_ids'], [1]);
      expect(service.submitted?['team_modes'], {'1': 'new'});
      expect(find.text('Previous: Campus appointment system'), findsOneWidget);
      expect(service.applied, isNull);
      await tester.ensureVisible(find.text('Back').last);
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowSelect>(
              find.byKey(const ValueKey('project-choice-1')),
            )
            .value,
        'new',
      );
      expect(service.applied, isNull);
    },
  );

  testWidgets('first-event teams without projects automatically start fresh', (
    tester,
  ) async {
    final service = _Service();
    for (final team in service.rosters[2]['teams'] as List) {
      team['project_title'] = '';
      team['carry_title'] = '';
      team['project_choice'] = 'new';
    }
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: '1st Year Expo'),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.ensureVisible(find.text('Project setup'));
    await tester.tap(find.text('Project setup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-choice-1')), findsNothing);
    expect(find.text('New project required'), findsNWidgets(2));
    await tester.ensureVisible(
      find.widgetWithText(ShadButton, 'Review project choices'),
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Review project choices'));
    await tester.pumpAndSettle();
    expect(service.submitted?['team_modes'], {'1': 'new', '2': 'new'});
  });

  testWidgets('bulk project action reviews current-roster scope', (
    tester,
  ) async {
    final service = _Service();
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.ensureVisible(find.text('Project setup'));
    await tester.tap(find.text('Project setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a bulk action'));
    await tester.tap(find.text('Choose a bulk action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start new projects').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ShadButton, 'Review project choices'),
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Review project choices'));
    await tester.pumpAndSettle();
    expect(service.submitted?['event_id'], isNull);
    expect(service.submitted?['team_modes'], {'1': 'new', '2': 'new'});
    expect(
      find.text('Apply project choices to Current roster'),
      findsOneWidget,
    );
    expect(service.applied, isNull);
  });

  testWidgets('locked and shared teams cannot use the new-project dropdown', (
    tester,
  ) async {
    final service = _Service();
    final teams = service.rosters[2]['teams'] as List;
    teams[0]['project_locked'] = true;
    teams[1]['shared_project'] = true;
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: '1st Year Expo'),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.ensureVisible(find.text('Project setup'));
    await tester.tap(find.text('Project setup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-choice-1')), findsNothing);
    expect(find.byKey(const ValueKey('project-choice-2')), findsNothing);
    expect(
      tester
          .widget<ShadCheckbox>(find.byKey(const ValueKey('project-team-1')))
          .enabled,
      isFalse,
    );
    expect(
      find.text('Managed through the shared concept workflow.'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.widgetWithText(ShadButton, 'Review project choices'),
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Review project choices'));
    await tester.pumpAndSettle();
    expect(service.submitted?['team_ids'], [2]);
    expect(service.submitted?['team_modes'], {'2': 'continue'});
  });

  testWidgets('title correction keeps the selected event and detail revision', (
    tester,
  ) async {
    final service = _Service();
    service.rosters[2]['can_correct_details'] = true;
    (service.rosters[2]['teams'] as List).first['details_revision'] = 2;
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(initialEvent: '1st Year Expo', instructor: true),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.ensureVisible(find.text('Team FreshStart'));
    await tester.tap(find.text('Team FreshStart'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Correct team details'));
    await tester.tap(find.text('Correct team details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText).last,
      'Corrected project title',
    );
    await tester.tap(find.text('Save correction'));
    await tester.pumpAndSettle();
    expect(service.submitted?['event_id'], 11);
    expect(service.submitted?['revision'], 2);
    expect(service.submitted?['project_title'], 'Corrected project title');
    expect(find.text('Corrected project title'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final width in [1440.0, 390.0, 320.0]) {
      testWidgets('roster fits ${width.toInt()}px ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        final service = _Service();
        await pumpDefensysWidget(
          tester,
          const TeamRosterScreen(
            initialEvent: '1st Year Expo',
            instructor: true,
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [teamRosterServiceProvider.overrideWithValue(service)],
        );
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Project setup'));
        await tester.tap(find.text('Project setup'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-projects-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
        final choice = find.descendant(
          of: find.byKey(const ValueKey('project-choice-1')),
          matching: find.byType(ShadSelect<String>),
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-project-dropdown-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Start new project').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(ShadButton, 'Review project choices'),
        );
        await tester.tap(
          find.widgetWithText(ShadButton, 'Review project choices'),
        );
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-project-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Back').last);
        await tester.tap(find.text('Back').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Generate teams'));
        await tester.tap(find.text('Generate teams'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review roster'));
        await tester.tap(find.text('Review roster'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
