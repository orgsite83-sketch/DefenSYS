import 'package:defensys/screens/web/faculty/adviser/adviser_defense_tab.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_dashboard_content.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/adviser_defense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _ScheduledDefenseNotifier extends AdviserDefenseNotifier {
  @override
  AdviserDefenseState build() => const AdviserDefenseState(
    schedules: [
      {
        'id': 18,
        'team_id': 7,
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'scheduled_date': '2026-10-20',
        'start_time': '09:30:00',
        'room': 'Room 301',
        'status': 'scheduled',
        'minutes_status': 'submitted',
        'panelists': [
          {'name': 'Prof. Santos'},
        ],
      },
      {
        'id': 19,
        'team_id': 99,
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'scheduled_date': '2026-10-21',
        'room': 'Room 302',
      },
    ],
  );

  @override
  Future<void> fetch({String? workspace}) async {}
}

class _PublishedGradeNotifier extends AdviserGradingNotifier {
  @override
  AdviserGradingState build() => const AdviserGradingState(
    grades: [
      {
        'id': 42,
        'schedule_id': 18,
        'team_id': 7,
        'stage_label': 'Concept Proposal',
        'status': 'published',
        'result': 'passed',
      },
    ],
  );

  @override
  Future<void> fetchAll() async {}
}

class _DashboardDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    teams: [
      {
        'id': 7,
        'current_stage': 'Concept Proposal',
        'stages': [
          {
            'stage_label': 'Concept Proposal',
            'deliverables_configured': true,
            'required_complete': false,
            'pre': [
              {
                'id': 'PAPER',
                'type': 'pre',
                'required': true,
                'uploaded': false,
              },
            ],
          },
        ],
      },
    ],
  );

  @override
  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

class _UpcomingDefenseNotifier extends AdviserDefenseNotifier {
  @override
  AdviserDefenseState build() {
    final date = DateTime.now();
    final scheduledDate =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return AdviserDefenseState(
      schedules: [
        {
          'id': 18,
          'team_id': 7,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'scheduled_date': scheduledDate,
          'start_time': '09:30:00',
          'room': 'Room 301',
          'status': 'scheduled',
          'minutes_status': 'submitted',
        },
        {
          'id': 19,
          'team_id': 99,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'scheduled_date': scheduledDate,
          'start_time': '10:30:00',
          'room': 'Room 302',
          'status': 'scheduled',
        },
      ],
    );
  }

  @override
  Future<void> fetch({String? workspace}) async {}
}

void main() {
  testWidgets('endorsed team shows post-defense files as locked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: const CapstoneDeliverablesState(
            selectedStage: 'Concept Proposal',
            stageOptions: ['Concept Proposal'],
            teams: [
              {
                'id': 7,
                'name': 'Team BioPulse',
                'current_stage': 'Concept Proposal',
                'stages': [
                  {
                    'stage_label': 'Concept Proposal',
                    'deliverables_configured': true,
                    'required_complete': true,
                    'endorsement_review': {
                      'can_review_and_endorse': true,
                      'review_token': 'reviewed-files',
                      'files': [],
                    },
                    'endorsed': true,
                    'archive_unlocked': false,
                    'pre': [],
                    'post': [
                      {
                        'id': 'FINAL',
                        'label': 'Final Manuscript',
                        'type': 'post',
                        'required': true,
                        'uploaded': false,
                        'can_upload': false,
                      },
                    ],
                  },
                ],
              },
            ],
          ),
          isAdviser: true,
        ),
      ),
      overrides: [
        adviserDefenseProvider.overrideWith(_ScheduledDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('Post-Defense Deliverables'), findsOneWidget);
    expect(find.text('Final Manuscript'), findsOneWidget);
    expect(
      find.textContaining('Student uploads and faculty review open once'),
      findsOneWidget,
    );
    expect(find.text('Awaiting student upload'), findsNothing);
  });

  testWidgets('adviser team footer is outlined without paging controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    int? openedTeam = -1;

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: AdviserDashboardContent(
          data: {
            'advised_teams': List.generate(
              5,
              (index) => {'id': index + 1, 'name': 'Advised Team ${index + 1}'},
            ),
          },
          facultyName: 'Ricardo Fontanilla',
          onOpenGrades: (_, _) {},
          onOpenDeliverables: (id) => openedTeam = id,
          onOpenDefense: (_, _) {},
        ),
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(
          _DashboardDeliverablesNotifier.new,
        ),
        adviserDefenseProvider.overrideWith(_UpcomingDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('Advised Team 1'), findsOneWidget);
    expect(find.text('Advised Team 5'), findsNothing);
    expect(find.byKey(const Key('team-page-next')), findsNothing);
    final openTeams = find.widgetWithText(
      OutlinedButton,
      'Open Capstone Teams',
    );
    expect(openTeams, findsOneWidget);
    await tester.tap(openTeams);
    expect(openedTeam, isNull);
  });

  testWidgets('dashboard shows adviser actions and only assigned defenses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    int? openedDefense;
    String? openedStage;

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: AdviserDashboardContent(
          data: const {
            'active_semester': '1st Semester, A.Y. 2026-2027',
            'advised_teams': [
              {
                'id': 7,
                'name': 'Team BioPulse',
                'projectTitle': 'Vital Triage',
                'semester': '1st Semester',
                'schoolYear': '2026-2027',
              },
              {
                'id': 99,
                'name': 'Team Old',
                'projectTitle': 'Past project',
                'semester': '2nd Semester',
                'schoolYear': '2025-2026',
              },
            ],
          },
          facultyName: 'Ricardo Fontanilla',
          onOpenGrades: (_, _) {},
          onOpenDeliverables: (_) {},
          onOpenDefense: (teamId, stageLabel) {
            openedDefense = teamId;
            openedStage = stageLabel;
          },
        ),
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(
          _DashboardDeliverablesNotifier.new,
        ),
        adviserDefenseProvider.overrideWith(_UpcomingDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('My actions'), findsOneWidget);
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('Defense Schedule'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('My teams')).dx,
      lessThan(tester.getTopLeft(find.text('Defense Schedule')).dx),
    );
    expect(
      tester.getTopLeft(find.text('My actions')).dy,
      greaterThan(tester.getTopLeft(find.text('Defense Schedule')).dy),
    );
    expect(find.text('Awaiting files'), findsOneWidget);
    expect(find.textContaining('Room 301'), findsOneWidget);
    expect(find.textContaining('Room 302'), findsNothing);
    expect(find.text('Team Old'), findsNothing);
    expect(
      find.text('Concept Proposal · Minutes ready to sign'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Actions for Team BioPulse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense records'));
    await tester.pumpAndSettle();
    expect(openedDefense, 7);

    await tester.tap(find.textContaining('Room 301'));
    expect(openedDefense, 7);
    expect(openedStage, 'Concept Proposal');

    await tester.tap(find.text('Concept Proposal · Minutes ready to sign'));
    expect(openedDefense, 7);
    expect(openedStage, 'Concept Proposal');
  });

  testWidgets('adviser dossier shows roster and the team Defense tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final state = CapstoneDeliverablesState(
      selectedStage: 'Concept Proposal',
      stageOptions: const ['Concept Proposal'],
      teams: [
        {
          'id': 7,
          'name': 'Team BioPulse',
          'project_title': 'Vital Triage System',
          'year_level': '3rd Year',
          'section': 'IT3A',
          'current_stage': 'Concept Proposal',
          'members': [
            {'id': 1, 'name': 'Ryan Torres', 'role': 'leader'},
            {'id': 2, 'name': 'Nina Villanueva', 'role': 'member'},
          ],
          'stages': [
            {
              'stage_label': 'Concept Proposal',
              'deliverables_configured': true,
              'required_complete': false,
              'pre': [],
              'post': [],
            },
          ],
        },
      ],
    );

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(state: state, isAdviser: true),
      ),
      overrides: [
        adviserDefenseProvider.overrideWith(_ScheduledDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('Team roster (2)'), findsOneWidget);
    expect(find.text('Export teams'), findsOneWidget);
    expect(find.text('Export team summary'), findsOneWidget);
    expect(find.textContaining('Review first'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Export teams')).dx,
      greaterThan(tester.getTopLeft(find.text('Teams (1)')).dx),
    );
    expect(
      tester.getTopLeft(find.text('Export team summary')).dy,
      closeTo(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byKey(const Key('adviser-team-summary')),
                matching: find.text('Awaiting files'),
              ),
            )
            .dy,
        16,
      ),
    );
    final summary = find.byKey(const Key('adviser-team-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('Project title')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Vital Triage System')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Year level: 3rd Year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Section: IT3A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Team roster (2)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Next step')),
      findsOneWidget,
    );
    expect(find.text('Ryan Torres'), findsOneWidget);
    expect(find.text('Nina Villanueva'), findsOneWidget);
    expect(find.text('Defense'), findsOneWidget);
    expect(find.text('Download grade report'), findsOneWidget);
    expect(
      find.textContaining(
        'The team needs to upload the required before-endorsement files.',
      ),
      findsOneWidget,
    );
    final pendingEndorseButton = find.ancestor(
      of: find.text('Endorse team'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(
      tester.widget<ElevatedButton>(pendingEndorseButton).onPressed,
      isNull,
    );

    await tester.tap(find.text('Defense'));
    await tester.pumpAndSettle();
    expect(find.text('Room 301'), findsOneWidget);
    expect(find.text('Awaiting adviser signature'), findsOneWidget);
    expect(find.text('Published result: Passed'), findsOneWidget);
    expect(find.text('Room 302'), findsNothing);
  });

  testWidgets('endorsement is available at the top after required acceptance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            selectedStage: 'Concept Proposal',
            stageOptions: const ['Concept Proposal'],
            teams: [
              {
                'id': 7,
                'name': 'Team BioPulse',
                'project_title':
                    'A long project title about emergency response and patient monitoring',
                'year_level': '3rd Year',
                'section': 'IT3A',
                'current_stage': 'Concept Proposal',
                'stages': [
                  {
                    'stage_label': 'Concept Proposal',
                    'deliverables_configured': true,
                    'required_complete': true,
                    'endorsement_review': {
                      'can_review_and_endorse': true,
                      'review_token': 'reviewed-files',
                      'files': [],
                    },
                    'required_total': 1,
                    'required_uploaded': 1,
                    'pre': [
                      {
                        'id': 1,
                        'label': 'Concept Paper',
                        'required': true,
                        'submission': {'status': 'accepted'},
                      },
                      {
                        'id': 2,
                        'label': 'Pitch Deck',
                        'type': 'pre',
                        'required': true,
                        'requirement_timing': 'defense',
                        'materials_status': 'awaiting_schedule',
                        'materials_submitted': false,
                        'uploaded': false,
                      },
                    ],
                    'materials_readiness': {
                      'status': 'awaiting_schedule',
                      'required_total': 1,
                      'submitted_total': 0,
                      'missing': [
                        {'id': 2, 'materials_status': 'awaiting_schedule'},
                      ],
                    },
                    'post': [],
                  },
                ],
              },
            ],
          ),
          isAdviser: true,
        ),
      ),
      overrides: [
        adviserDefenseProvider.overrideWith(_ScheduledDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    final endorseButton = find.ancestor(
      of: find.text('Endorse team'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    final summary = find.byKey(const Key('adviser-team-summary'));
    expect(endorseButton, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: endorseButton),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Awaiting endorsement')),
      findsOneWidget,
    );
    expect(tester.widget<ElevatedButton>(endorseButton).onPressed, isNotNull);
    expect(find.text('Stage status'), findsNothing);
    expect(find.text('Next step'), findsOneWidget);
    expect(find.text('Before endorsement'), findsOneWidget);
    expect(find.text('Before defense'), findsOneWidget);
    expect(find.textContaining('No defense date yet'), findsNothing);
    expect(find.textContaining('Defense files ·'), findsNothing);
    expect(find.text('Due after scheduling'), findsNothing);
    expect(
      find.text(
        'These files do not block endorsement or scheduling. The upload deadline appears once the defense is scheduled.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Awaiting endorsement').last).dx,
      greaterThan(tester.getTopLeft(find.text('Team BioPulse').last).dx + 150),
    );
    expect(
      tester.getTopLeft(find.text('Awaiting endorsement').last).dy,
      lessThan(tester.getTopLeft(endorseButton).dy),
    );
    expect(
      tester.getTopLeft(endorseButton).dy,
      lessThan(tester.getTopLeft(find.text('Pre-Defense Requirements')).dy),
    );
    await tester.tap(endorseButton);
    await tester.pumpAndSettle();
    expect(find.text('Endorse team'), findsNWidgets(2));
    expect(
      find.textContaining('remain due by their scheduled deadline'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
  });

  testWidgets('one stage selection updates every adviser team dossier', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    String selectedStage = 'Concept Proposal';
    CapstoneDeliverablesState buildState() => CapstoneDeliverablesState(
      selectedStage: selectedStage,
      stageOptions: const ['Concept Proposal', 'Project Proposal'],
      teams: [
        {
          'id': 7,
          'name': 'Team One',
          'current_stage': 'Concept Proposal',
          'stages': [
            {
              'stage_label': 'Concept Proposal',
              'deliverables_configured': true,
              'required_complete': true,
              'endorsement_review': {
                'can_review_and_endorse': true,
                'review_token': 'reviewed-files',
                'files': [],
              },
              'endorsed': true,
              'stage_status_detail': 'endorsed',
              'pre': [],
              'post': [],
            },
            {
              'stage_label': 'Project Proposal',
              'deliverables_configured': true,
              'required_complete': true,
              'endorsement_review': {
                'can_review_and_endorse': true,
                'review_token': 'reviewed-files',
                'files': [],
              },
              'endorsed': false,
              'required_total': 1,
              'required_uploaded': 1,
              'pre': [
                {
                  'id': 11,
                  'label': 'Project Brief',
                  'required': true,
                  'submission': {'status': 'accepted'},
                },
              ],
              'post': [],
            },
          ],
        },
        {
          'id': 8,
          'name': 'Team Two',
          'current_stage': 'Concept Proposal',
          'stages': [
            {
              'stage_label': 'Concept Proposal',
              'deliverables_configured': true,
              'required_complete': true,
              'endorsement_review': {
                'can_review_and_endorse': true,
                'review_token': 'reviewed-files',
                'files': [],
              },
              'endorsed': true,
              'stage_status_detail': 'endorsed',
              'pre': [],
              'post': [],
            },
            {
              'stage_label': 'Project Proposal',
              'deliverables_configured': true,
              'required_complete': false,
              'endorsed': false,
              'required_total': 1,
              'required_uploaded': 0,
              'pre': [],
              'post': [],
            },
          ],
        },
      ],
    );

    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: Column(
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => selectedStage = 'Project Proposal'),
                child: const Text('Switch stage'),
              ),
              DeliverablesTablePane(state: buildState(), isAdviser: true),
            ],
          ),
        ),
      ),
      overrides: [
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('Endorse team'), findsNothing);
    await tester.tap(find.text('Switch stage'));
    await tester.pumpAndSettle();

    expect(find.text('Awaiting endorsement'), findsNWidgets(2));
    expect(find.text('Awaiting files'), findsOneWidget);
    expect(find.text('Project Brief'), findsOneWidget);
    expect(find.text('Concept Proposal'), findsNothing);

    await tester.tap(find.text('Team Two').first);
    await tester.pumpAndSettle();
    expect(find.text('Awaiting files'), findsNWidgets(2));
    final endorseButton = find.ancestor(
      of: find.text('Endorse team'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(endorseButton).onPressed, isNull);
  });

  testWidgets('team Defense tab explains when no schedule exists', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const AdviserDefenseTab(teamId: 7, selectedStage: 'Concept Proposal'),
    );
    expect(find.text('No defense scheduled yet'), findsOneWidget);
  });

  testWidgets('mobile team link opens its Defense detail directly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            selectedStage: 'Concept Proposal',
            teams: [
              {
                'id': 7,
                'name': 'Team BioPulse',
                'project_title':
                    'A long project title about emergency response and patient monitoring',
                'year_level': '3rd Year',
                'section': 'IT3A',
                'current_stage': 'Concept Proposal',
                'members': [
                  {'name': 'Ryan Torres', 'role': 'leader'},
                ],
                'stages': [
                  {
                    'stage_label': 'Concept Proposal',
                    'deliverables_configured': true,
                    'required_complete': true,
                    'endorsement_review': {
                      'can_review_and_endorse': true,
                      'review_token': 'reviewed-files',
                      'files': [],
                    },
                    'endorsed': false,
                    'pre': [],
                    'post': [],
                  },
                ],
              },
            ],
          ),
          isAdviser: true,
          initialTeamId: 7,
          initialTab: 3,
        ),
      ),
      overrides: [
        adviserDefenseProvider.overrideWith(_ScheduledDefenseNotifier.new),
        adviserGradingProvider.overrideWith(_PublishedGradeNotifier.new),
      ],
    );

    expect(find.text('Back to Team List'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('adviser-team-summary')),
        matching: find.text('Team roster (1)'),
      ),
      findsOneWidget,
    );
    expect(find.text('Room 301'), findsOneWidget);
  });
}
