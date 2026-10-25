import 'dart:async';
import 'dart:convert';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/widgets/team_import_review.dart';
import 'package:defensys/screens/web/faculty/team_roster_screen.dart';
import 'package:defensys/services/academic/team_roster_service.dart';
import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/screens/web/admin/student_teams/components/team_roster_import_panel.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

class _Formation extends Fake implements TeamFormationService {
  bool empty = false, fail = false;
  final loads = <String>[];

  @override
  Future<Map<String, dynamic>> options(String level, String? event) async {
    loads.add(level);
    if (fail) throw Exception('Class list unavailable');
    return {
      'sections': [
        {'name': 'BSIT-1B'},
      ],
      'can_manage_policy': false,
      'students': [
        if (!empty)
          for (final id in [10, 11, 20, 21])
            {
              'id': id,
              'name': 'Student $id',
              'username': 'student-$id',
              'section': 'BSIT-1B',
              'assigned': true,
            },
        {'id': 99, 'name': 'Other section', 'section': 'BSIT-1A'},
      ],
    };
  }
}

Future<void> _confirmStudents(WidgetTester tester) async {
  final checkbox = find.byKey(const ValueKey('confirm-generation-students'));
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: checkbox,
      matching: find.textContaining('I confirm these'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Continue to grouping'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue to grouping'));
  await tester.pumpAndSettle();
}

class _Service extends Fake implements TeamRosterService {
  final pendingValidation = <Completer<Map<String, dynamic>>>[];
  bool deferValidation = false;
  bool canGenerate = true;
  bool noSections = false;
  final loads = <Map<String, dynamic>>[];
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
  Future<Map<String, dynamic>> load(Map<String, dynamic> scope) async {
    loads.add(Map<String, dynamic>.from(scope));
    if (noSections) {
      return {
        'semester': '1st Semester, A.Y. 2026-2027',
        'year_level': '1st Year',
        'section': null,
        'fingerprint': null,
        'scope_options': [],
        'can_generate': false,
        'can_import_sections': scope['workspace'] == 'operations',
        'rosters': [],
      };
    }
    return {
      'year_level': '1st Year',
      'section': 'BSIT-1B',
      'fingerprint': 'review-state',
      'scope_options': [
        {'year_level': '1st Year', 'section': 'BSIT-1B'},
      ],
      'can_generate': canGenerate,
      'can_import_sections': scope['workspace'] == 'operations',
      'rosters': jsonDecode(jsonEncode(rosters)),
    };
  }

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> data) async {
    submitted = data;
    pending = data;
    if (data['validation_only'] == true) {
      if (deferValidation) {
        final pending = Completer<Map<String, dynamic>>();
        pendingValidation.add(pending);
        return pending.future;
      }
      final rows = (data['teams'] as List).cast<Map<String, dynamic>>();
      final results = [
        for (var i = 0; i < rows.length; i++)
          {
            'row': i + 1,
            'group_key': rows[i]['group_key'],
            'ready': !(rows[i]['member_ids'] as List).contains('Unknown'),
            'issues': (rows[i]['member_ids'] as List).contains('Unknown')
                ? ['Student account was not found.']
                : <String>[],
            'warnings': <String>[],
          },
      ];
      return {
        'rows': results,
        'ready': results.every((r) => r['ready'] == true),
        'section_summaries': teamImportSummaries(rows, []),
      };
    }
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
      if (data['operation'] == 'import')
        'section_summaries': teamImportSummaries(
          (data['teams'] as List).cast<Map<String, dynamic>>(),
          [],
        ),
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
  setUpAll(() => loadPreviewFonts(force: true));
  testWidgets(
    'unsectioned PIT cohort shows setup guidance and recovers after refresh',
    (tester) async {
      final service = _Service()..noSections = true;
      await loadPreviewFonts();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(
          initialYear: '1st Year',
          initialEvent: '1st Year Expo',
        ),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      expect(find.text('Import teams or assign instructors'), findsOneWidget);
      expect(find.text('Import teams'), findsOneWidget);
      expect(find.text('Assign instructors'), findsOneWidget);
      expect(
        find.textContaining('1st Semester, A.Y. 2026-2027'),
        findsOneWidget,
      );
      expect(find.text('Unable to complete this action'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Import teams'), findsOneWidget);
      expect(find.text('Generate teams'), findsNothing);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(TeamRosterScreen),
        'team-roster-no-sections',
        viewport: true,
      );

      service.noSections = false;
      await tester.tap(find.text('Refresh sections'));
      await tester.pumpAndSettle();
      expect(find.text('Import teams or assign instructors'), findsNothing);
      expect(find.text('1st Year Expo'), findsWidgets);
      expect(find.text('Import teams'), findsOneWidget);
      expect(service.loads, hasLength(2));
      expect(service.loads.last['year_level'], '1st Year');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty cohort navigates to the User Management instructor tab', (
    tester,
  ) async {
    final service = _Service()..noSections = true;
    final router = GoRouter(
      initialLocation: '/faculty/student-teams/roster',
      routes: [
        GoRoute(
          path: '/faculty/student-teams/roster',
          builder: (_, _) =>
              const Scaffold(body: TeamRosterScreen(initialYear: '1st Year')),
        ),
        GoRoute(
          path: '/faculty/cohort',
          builder: (_, state) => Scaffold(
            body: Text('User Management: ${state.uri.queryParameters['tab']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpDefensysWidget(
      tester,
      MaterialApp.router(routerConfig: router),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.tap(find.text('Assign instructors'));
    await tester.pumpAndSettle();
    expect(find.text('User Management: instructors'), findsOneWidget);
    service.noSections = false;
    router.go('/faculty/student-teams/roster');
    await tester.pumpAndSettle();
    expect(find.text('Import teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT lead can import all sections before a section exists', (
    tester,
  ) async {
    final service = _Service()..noSections = true;
    Uri? importedContext;
    final router = GoRouter(
      initialLocation: '/faculty/student-teams/roster',
      routes: [
        GoRoute(
          path: '/faculty/student-teams/roster',
          builder: (_, _) => const Scaffold(
            body: TeamRosterScreen(
              initialYear: '1st Year',
              initialEvent: '1st Year Expo',
            ),
          ),
        ),
        GoRoute(
          path: '/faculty/student-teams/creation',
          builder: (_, state) {
            importedContext = state.uri;
            return const Scaffold(body: Text('All section team import'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpDefensysWidget(
      tester,
      MaterialApp.router(routerConfig: router),
      overrides: [teamRosterServiceProvider.overrideWithValue(service)],
    );
    await tester.tap(find.text('Import teams'));
    await tester.pumpAndSettle();
    expect(find.text('All section team import'), findsOneWidget);
    expect(importedContext?.queryParameters['tab'], 'import');
    expect(importedContext?.queryParameters['level'], '1st Year PIT');
    expect(importedContext?.queryParameters['event'], '1st Year Expo');
    expect(importedContext?.queryParameters.containsKey('section'), isFalse);
    service.noSections = false;
    router.pop(true);
    await tester.pumpAndSettle();
    expect(find.text('Import teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets(
    'top toolbar exposes both Lead import scopes and compact status help',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(),
        overrides: [teamRosterServiceProvider.overrideWithValue(_Service())],
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('roster-actions'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('roster-status'))).dy,
        ),
      );
      expect(
        find.widgetWithText(WorkflowNotice, 'Default for upcoming events'),
        findsNothing,
      );
      expect(find.text('Default for upcoming events'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(TeamRosterScreen),
        'team-roster-toolbar-lead',
        viewport: true,
      );
      await tester.tap(find.byKey(const ValueKey('roster-status')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Ongoing, completed and custom event rosters keep their saved teams.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Team roster').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import teams'));
      await tester.pumpAndSettle();
      expect(find.text('All sections with instructors'), findsOneWidget);
      await tester.tap(find.text('Selected section · BSIT-1B'));
      await tester.pumpAndSettle();
      expect(find.text('Import a roster'), findsOneWidget);
      expect(find.text('Target: Current roster · BSIT-1B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('instructor import opens only its selected section', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(instructor: true, initialEvent: '1st Year Expo'),
      overrides: [teamRosterServiceProvider.overrideWithValue(_Service())],
    );
    expect(find.byKey(const ValueKey('roster-import-menu')), findsNothing);
    await tester.tap(find.text('Import teams'));
    await tester.pumpAndSettle();
    expect(find.text('All sections with instructors'), findsNothing);
    expect(find.text('Target: 1st Year Expo · BSIT-1B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'instructor import validates automatically and shows shared details in confirmation',
    (tester) async {
      final service = _Service();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(instructor: true, initialEvent: '1st Year Expo'),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.tap(find.text('Import teams'));
      await tester.pumpAndSettle();
      final dynamic page = tester.state(find.byType(TeamRosterScreen));
      await page.processFiles([
        const PickedTabularFile(
          name: 'shared.csv',
          extension: 'csv',
          bytes: [],
          text:
              'System Name:,Societree\nProject Manager:,Ana Reyes\n'
              'Team Name,Module,Section,Team Members\nCore,Directory,BSIT-1B,Ana Reyes\n'
              'Auth,Sign in,BSIT-1B,Luis Santos\n',
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(service.submitted?['workspace'], 'instructor');
      expect(service.submitted?['validation_only'], isTrue);
      expect(find.text('Shared system · BSIT-1B'), findsOneWidget);
      expect(find.text('Societree'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shared-system-BSIT-1B')),
          matching: find.text('Ana Reyes'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ready'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Review replacement').first);
      await tester.tap(find.text('Review replacement').first);
      await tester.pumpAndSettle();
      expect(service.submitted?['validation_only'], isNull);
      expect(find.text('Shared system · BSIT-1B'), findsOneWidget);
      expect(find.text('Societree'), findsOneWidget);
      expect(service.applied, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'instructor edits discard out-of-order validation and block replacement',
    (tester) async {
      final service = _Service()..deferValidation = true;
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(instructor: true, initialEvent: '1st Year Expo'),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.tap(find.text('Import teams'));
      await tester.pumpAndSettle();
      final dynamic page = tester.state(find.byType(TeamRosterScreen));
      await page.processFiles([
        const PickedTabularFile(
          name: 'teams.csv',
          extension: 'csv',
          bytes: [],
          text:
              'Team Name,PIT Project,Section,Team Members\nCore,Directory,BSIT-1B,Ana Reyes\n',
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 450));
      final key = (page.importRows as List).first['group_key'];
      page.scheduleImportValidation();
      await tester.pump(const Duration(milliseconds: 450));
      service.pendingValidation.last.complete({
        'ready': false,
        'rows': [
          {
            'row': 1,
            'group_key': key,
            'ready': false,
            'issues': ['Student account was not found.'],
            'warnings': <String>[],
          },
        ],
      });
      await tester.pumpAndSettle();
      service.pendingValidation.first.complete({
        'ready': true,
        'rows': [
          {
            'row': 1,
            'group_key': key,
            'ready': true,
            'issues': <String>[],
            'warnings': <String>[],
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Student account was not found.'),
        findsOneWidget,
      );
      expect((page.importValidation as Map)['ready'], isFalse);
      expect(service.applied, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Lead all-section import follows the selected Current roster', (
    tester,
  ) async {
    Uri? importContext;
    final router = GoRouter(
      initialLocation: '/faculty/student-teams/roster',
      routes: [
        GoRoute(
          path: '/faculty/student-teams/roster',
          builder: (_, _) => const Scaffold(
            body: TeamRosterScreen(initialEvent: '1st Year Expo'),
          ),
        ),
        GoRoute(
          path: '/faculty/student-teams/creation',
          builder: (_, state) {
            importContext = state.uri;
            return const Scaffold(body: Text('All sections import'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpDefensysWidget(
      tester,
      MaterialApp.router(routerConfig: router),
      overrides: [teamRosterServiceProvider.overrideWithValue(_Service())],
    );
    final rosterSelect = find.byWidgetPredicate(
      (widget) => widget is WorkflowSelect && widget.label == 'Roster',
    );
    await tester.tap(
      find.descendant(
        of: rosterSelect,
        matching: find.byType(ShadSelect<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current roster').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import teams'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All sections with instructors'));
    await tester.pumpAndSettle();
    expect(find.text('All sections import'), findsOneWidget);
    expect(importContext?.queryParameters['level'], '1st Year PIT');
    expect(importContext?.queryParameters.containsKey('section'), isFalse);
    expect(importContext?.queryParameters.containsKey('event'), isFalse);
  });

  testWidgets(
    'removing an instructor file clears staging and ignores its pending validation',
    (tester) async {
      final service = _Service()..deferValidation = true;
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(instructor: true, initialEvent: '1st Year Expo'),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.tap(find.text('Import teams'));
      await tester.pumpAndSettle();
      final dynamic page = tester.state(find.byType(TeamRosterScreen));
      const file = PickedTabularFile(
        name: 'section-roster.csv',
        extension: 'csv',
        bytes: [],
        text:
            'Team Name,PIT Project,Section,Team Members\nCore,Directory,BSIT-1B,Ana Reyes\n',
      );
      await page.processFiles([file]);
      await tester.pump(const Duration(milliseconds: 450));
      final key = (page.importRows as List).single['group_key'];
      final remove = find.byKey(const ValueKey('remove-roster-file-file0'));
      expect(
        find.byKey(const ValueKey('roster-uploaded-files')),
        findsOneWidget,
      );
      expect(find.text('Teams staged: 1'), findsOneWidget);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      service.pendingValidation.single.complete({
        'ready': true,
        'rows': [
          {
            'row': 1,
            'group_key': key,
            'ready': true,
            'issues': <String>[],
            'warnings': <String>[],
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('roster-uploaded-files')), findsNothing);
      expect(
        find.text('Drop a spreadsheet here or choose a file'),
        findsOneWidget,
      );
      expect(page.fileName, isNull);
      expect(page.importRows, isEmpty);
      expect(page.importValidation, isNull);
      expect(page.importChecking, isFalse);
      expect(page.review, isNull);
      expect(service.applied, isNull);
      expect(service.rosters.last['team_count'], 2);
      service.deferValidation = false;
      await page.processFiles([file]);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('roster-uploaded-files')),
        findsOneWidget,
      );
      expect((page.importValidation as Map)['ready'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing one instructor upload preserves other files and edited teams',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Service();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(instructor: true, initialEvent: '1st Year Expo'),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.tap(find.text('Import teams'));
      await tester.pumpAndSettle();
      final dynamic page = tester.state(find.byType(TeamRosterScreen));
      const remainingName =
          'PIT-BSIT-1B-shared-system-team-roster-with-reviewed-modules.csv';
      await page.processFiles([
        const PickedTabularFile(
          name: 'first.csv',
          extension: 'csv',
          bytes: [],
          text:
              'Team Name,PIT Project,Section,Team Members\nCore,Directory,BSIT-1B,Ana Reyes\n',
        ),
        const PickedTabularFile(
          name: remainingName,
          extension: 'csv',
          bytes: [],
          text:
              'Team Name,PIT Project,Section,Team Members\nAuth,Sign in,BSIT-1B,Luis Santos\n',
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      (page.importRows as List).last['team_name'] = 'Edited Auth';
      final remove = find.byKey(const ValueKey('remove-roster-file-file0'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(TeamRosterScreen),
        'instructor-uploaded-files-390',
        viewport: true,
      );
      await tester.tap(remove);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('roster-uploaded-file0')), findsNothing);
      expect(
        find.byKey(const ValueKey('roster-uploaded-file1')),
        findsOneWidget,
      );
      expect(page.fileName, remainingName);
      expect((page.importRows as List).single['team_name'], 'Edited Auth');
      expect((page.importRows as List).single['member_ids'], ['Luis Santos']);
      expect((page.importValidation as Map)['ready'], isTrue);
      expect((service.submitted?['teams'] as List), hasLength(1));
      expect(service.applied, isNull);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Import teams'), findsNothing);
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
        overrides: [
          teamRosterServiceProvider.overrideWithValue(service),
          teamFormationServiceProvider.overrideWithValue(_Formation()),
        ],
      );
      await tester.ensureVisible(find.text('Generate teams'));
      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();
      expect(find.text('Import & confirm students'), findsOneWidget);
      expect(find.text('Students per team'), findsNothing);
      expect(find.text('2. Configure grouping'), findsNothing);
      expect(service.submitted, isNull);
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('continue-generation-grouping')),
            )
            .enabled,
        isFalse,
      );
      final panel = tester.widget<TeamRosterImportPanel>(
        find.byType(TeamRosterImportPanel),
      );
      expect(panel.section, 'BSIT-1B');
      expect(panel.students.map((s) => s['id']), [10, 11, 20, 21]);
      await _confirmStudents(tester);
      expect(find.text('Students per team'), findsOneWidget);
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
      expect(service.submitted?['confirmed_student_ids'], [10, 11, 20, 21]);
      expect(service.applied, isNull);
      await tester.ensureVisible(find.text('Back').last);
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(find.text('Students per team'), findsOneWidget);
      await tester.ensureVisible(find.text('Back to students'));
      await tester.tap(find.text('Back to students'));
      await tester.pumpAndSettle();
      expect(find.byType(TeamRosterImportPanel), findsOneWidget);
      expect(
        tester
            .widget<ShadCheckbox>(
              find.byKey(const ValueKey('confirm-generation-students')),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('empty section must import students before grouping', (
    tester,
  ) async {
    final service = _Service();
    final formation = _Formation()..empty = true;
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(instructor: true),
      overrides: [
        teamRosterServiceProvider.overrideWithValue(service),
        teamFormationServiceProvider.overrideWithValue(formation),
      ],
    );
    await tester.tap(find.text('Generate teams'));
    await tester.pumpAndSettle();
    expect(find.text('Import students first'), findsOneWidget);
    expect(find.text('Import Class List'), findsOneWidget);
    expect(find.text('Students per team'), findsNothing);
    expect(
      find.byKey(const ValueKey('confirm-generation-students')),
      findsNothing,
    );
    expect(
      tester
          .widget<ShadButton>(
            find.byKey(const ValueKey('continue-generation-grouping')),
          )
          .enabled,
      isFalse,
    );
    expect(service.submitted, isNull);

    // The shared importer refreshes this step only after committing section assignments.
    formation.empty = false;
    final importer = tester.widget<TeamRosterImportPanel>(
      find.byType(TeamRosterImportPanel),
    );
    await importer.onImported();
    await tester.pumpAndSettle();
    expect(find.text('Import students first'), findsNothing);
    expect(formation.loads, ['1st Year PIT', '1st Year PIT']);
    await _confirmStudents(tester);
    expect(find.text('4 confirmed students · BSIT-1B'), findsOneWidget);
    expect(service.submitted, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('class-list errors and staged imports block grouping', (
    tester,
  ) async {
    final formation = _Formation()..fail = true;
    await pumpDefensysWidget(
      tester,
      const TeamRosterScreen(),
      overrides: [
        teamRosterServiceProvider.overrideWithValue(_Service()),
        teamFormationServiceProvider.overrideWithValue(formation),
      ],
    );
    await tester.tap(find.text('Generate teams'));
    await tester.pumpAndSettle();
    expect(find.text('Class list unavailable'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(
            find.byKey(const ValueKey('continue-generation-grouping')),
          )
          .enabled,
      isFalse,
    );
    formation.fail = false;
    await tester.ensureVisible(find.text('Retry class list'));
    await tester.tap(find.text('Retry class list'));
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const ValueKey('confirm-generation-students'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    final importer = tester.widget<TeamRosterImportPanel>(
      find.byType(TeamRosterImportPanel),
    );
    importer.onDirtyChanged!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<ShadCheckbox>(checkbox).value, isFalse);
    expect(
      tester
          .widget<ShadButton>(
            find.byKey(const ValueKey('continue-generation-grouping')),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.text('Apply or remove the staged class list before continuing.'),
      findsOneWidget,
    );
    importer.onDirtyChanged!(false);
    importer.onBusyChanged!(true);
    formation.fail = true;
    await importer.onImported();
    await tester.pumpAndSettle();
    expect(find.text('Class list unavailable'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(
            find.widgetWithText(ShadButton, 'Retry class list'),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Cancel'))
          .enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

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
      final choice = find.byKey(const ValueKey('project-choice-1'));
      await tester.ensureVisible(choice);
      await tester.tap(
        find.descendant(of: choice, matching: find.text('Start new')),
      );
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
            .widget<SegmentedButton<String>>(
              find.byKey(const ValueKey('project-choice-1')),
            )
            .selected,
        {'new'},
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
      find.byKey(const ValueKey('project-bulk-continue')),
    );
    await tester.tap(find.byKey(const ValueKey('project-bulk-continue')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ShadButton, 'Review project choices'),
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Review project choices'));
    await tester.pumpAndSettle();
    expect(service.submitted?['team_modes'], {'1': 'new', '2': 'new'});
  });

  testWidgets(
    'bulk buttons change only selected teams before current-roster review',
    (tester) async {
      final service = _Service();
      await pumpDefensysWidget(
        tester,
        const TeamRosterScreen(),
        overrides: [teamRosterServiceProvider.overrideWithValue(service)],
      );
      await tester.ensureVisible(find.text('Project setup'));
      await tester.tap(find.text('Project setup'));
      await tester.pumpAndSettle();
      final first = find.descendant(
        of: find.byKey(const ValueKey('project-team-1')),
        matching: find.text('Team FreshStart'),
      );
      final second = find.descendant(
        of: find.byKey(const ValueKey('project-team-2')),
        matching: find.text('Team Portal'),
      );
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byKey(const ValueKey('project-choice-1')),
            )
            .onSelectionChanged,
        isNull,
      );
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      for (final mode in ['continue', 'new']) {
        expect(
          tester
              .widget<ShadButton>(find.byKey(ValueKey('project-bulk-$mode')))
              .enabled,
          isFalse,
        );
      }
      await tester.tap(second);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('project-bulk-new')),
      );
      await tester.tap(find.byKey(const ValueKey('project-bulk-new')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('1 keeping existing · 1 starting new'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ShadButton, 'Review project choices'),
      );
      await tester.tap(
        find.widgetWithText(ShadButton, 'Review project choices'),
      );
      await tester.pumpAndSettle();
      expect(service.submitted?['event_id'], isNull);
      expect(service.submitted?['team_modes'], {'1': 'continue', '2': 'new'});
      expect(
        find.text('Apply project choices to Current roster'),
        findsOneWidget,
      );
      expect(service.applied, isNull);
    },
  );

  testWidgets('locked and shared teams cannot change project choices', (
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
    for (final mode in ['continue', 'new']) {
      expect(
        tester
            .widget<ShadButton>(find.byKey(ValueKey('project-bulk-$mode')))
            .enabled,
        isFalse,
      );
    }
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
        tester.view.physicalSize = Size(width, width >= 820 ? 900 : 1600);
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
          overrides: [
            teamRosterServiceProvider.overrideWithValue(service),
            teamFormationServiceProvider.overrideWithValue(_Formation()),
          ],
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
        final choice = find.byKey(const ValueKey('project-choice-1'));
        await tester.ensureVisible(choice);
        await tester.tap(
          find.descendant(of: choice, matching: find.text('Start new')),
        );
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-project-selected-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
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
        await tester.ensureVisible(find.text('Team roster'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-students-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('View Roster (4)'));
        await tester.tap(find.text('View Roster (4)'));
        await tester.pumpAndSettle();
        expect(find.text('Student 10 (student-10)'), findsOneWidget);
        expect(find.text('Other section'), findsNothing);
        expect(tester.takeException(), isNull);
        await _confirmStudents(tester);
        await tester.ensureVisible(find.text('Team roster'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-grouping-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.ensureVisible(find.text('Review roster'));
        await tester.tap(find.text('Review roster'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Team roster'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(TeamRosterScreen),
          'team-roster-generated-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
