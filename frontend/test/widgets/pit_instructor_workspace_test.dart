import 'package:defensys/screens/web/faculty/pit_instructor/pit_instructor_dashboard_content.dart';
import 'package:defensys/screens/web/faculty/dashboard_widgets.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/team_deliverables_screen.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _pitStage = {
  'stage_label': 'System Concept Pitching',
  'deliverables_configured': true,
  'required_complete': true,
  'endorsement_required': false,
  'stage_status_detail': 'scheduling_eligible',
  'endorsed': false,
  'required_total': 0,
  'required_uploaded': 0,
  'materials_readiness': {
    'status': 'pending',
    'required_total': 2,
    'submitted_total': 0,
  },
  'pre': [
    {
      'id': 'PAPER',
      'label': 'Concept Paper',
      'type': 'pre',
      'required': true,
      'requirement_timing': 'defense',
      'uploaded': false,
    },
    {
      'id': 'DECK',
      'label': 'Pitch Deck',
      'type': 'pre',
      'required': true,
      'requirement_timing': 'defense',
      'uploaded': false,
    },
  ],
  'post': <Map<String, dynamic>>[],
};

const _pitTeam = {
  'id': 7,
  'name': 'Team AlphaWave',
  'project_title': 'Library tracker',
  'year_level': '1st Year',
  'section': 'BSIT-1A',
  'members': [
    {'id': 1, 'name': 'Pat Rivera', 'role': 'leader'},
    {'id': 2, 'name': 'Nia Cruz', 'role': 'member'},
  ],
  'current_stage': 'System Concept Pitching',
  'stages': [_pitStage],
};

class _PitDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    scope: 'pit',
    selectedStage: 'System Concept Pitching',
    stageOptions: ['System Concept Pitching'],
    teams: [_pitTeam],
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

class _PitGradesNotifier extends AdviserGradingNotifier {
  @override
  Future<void> fetchAll() async {}
}

class _PitWeeklyNotifier extends WeeklyProgressNotifier {
  @override
  Future<void> fetchReports() async {}
}

class _PitDefenseNotifier extends PitInstructorDefenseNotifier {
  @override
  TeamDefenseState build() {
    final date = DateTime.now().add(const Duration(days: 7));
    final scheduledDate =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return TeamDefenseState(
      schedules: [
        {
          'team_id': 7,
          'scope': 'pit',
          'status': 'scheduled',
          'scheduled_date': scheduledDate,
          'start_time': '09:30:00',
          'stage_label': 'System Concept Pitching',
          'room': 'Room 301',
          'materials_readiness': {'required_total': 2, 'submitted_total': 0},
        },
        {
          'team_id': 8,
          'scope': 'pit',
          'status': 'scheduled',
          'scheduled_date': scheduledDate,
          'room': 'Room 302',
        },
      ],
    );
  }

  @override
  Future<void> fetch() async {}
}

void main() {
  testWidgets(
    'instructor dashboard uses adviser layout for assigned PIT teams',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      int? openedTeam;
      int? openedGradeTeam;

      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: PitInstructorDashboardContent(
            data: const {
              'active_semester': '1st Semester, A.Y. 2026-2027',
              'pit_teams': [
                {
                  'id': 7,
                  'name': 'Team AlphaWave',
                  'projectTitle': 'Library tracker',
                  'yearLevel': '1st Year',
                  'section': 'BSIT-1A',
                  'semester': '1st Semester',
                  'schoolYear': '2026-2027',
                },
                {
                  'id': 8,
                  'name': 'Other section',
                  'yearLevel': '1st Year',
                  'section': 'BSIT-1B',
                },
              ],
            },
            facultyName: 'Eduardo Padilla',
            yearLevel: '1st Year',
            section: 'BSIT-1A',
            onOpenDeliverables: (id) => openedTeam = id,
            onOpenGrading: (id) => openedGradeTeam = id,
          ),
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            _PitDeliverablesNotifier.new,
          ),
          pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
        ],
      );

      expect(find.text('My actions'), findsOneWidget);
      expect(find.text('Quick Actions'), findsNothing);
      expect(find.text('Defense schedule & materials'), findsOneWidget);
      expect(find.text('My teams'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('My teams')).dx,
        lessThan(
          tester.getTopLeft(find.text('Defense schedule & materials')).dx,
        ),
      );
      expect(
        tester.getTopLeft(find.text('My actions')).dy,
        greaterThan(
          tester.getTopLeft(find.text('Defense schedule & materials')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('My actions')).dx,
        greaterThan(tester.getTopLeft(find.text('My teams')).dx),
      );
      expect(find.text('2 before defense'), findsOneWidget);
      expect(find.textContaining('Room 301'), findsOneWidget);
      expect(find.textContaining('Room 302'), findsNothing);
      expect(find.text('Ready to schedule'), findsOneWidget);
      expect(
        find.text('No submissions need review right now.'),
        findsOneWidget,
      );
      expect(find.text('Other section'), findsNothing);
      await tester.tap(find.text('Month view'));
      await tester.pump();
      expect(find.text('Week view'), findsOneWidget);
      await tester.tap(find.text('Team AlphaWave').first);
      expect(openedTeam, 7);
      await tester.tap(find.byTooltip('Actions for Team AlphaWave'));
      await tester.pumpAndSettle();
      final menu = tester.widget<PopupMenuButton<int>>(
        find.ancestor(
          of: find.byTooltip('Actions for Team AlphaWave'),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      expect(menu.color, Colors.white);
      expect(menu.shape, isA<RoundedRectangleBorder>());
      await tester.tap(find.text('View grades'));
      expect(openedGradeTeam, 7);
    },
  );

  testWidgets('instructor can page through PIT teams and open the full list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    int? openedTeam = -1;

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: PitInstructorDashboardContent(
          data: {
            'pit_teams': List.generate(
              6,
              (index) => {
                'id': index + 1,
                'name': 'Paging Team ${index + 1}',
                'projectTitle': 'Project ${index + 1}',
              },
            ),
          },
          facultyName: 'Eduardo Padilla',
          onOpenDeliverables: (id) => openedTeam = id,
          onOpenGrading: (_) {},
        ),
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PitDeliverablesNotifier.new),
        pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
      ],
    );

    final previous = find.byKey(const Key('team-page-previous'));
    final next = find.byKey(const Key('team-page-next'));
    expect(find.text('Paging Team 1'), findsOneWidget);
    expect(find.text('Paging Team 5'), findsNothing);
    expect(tester.widget<OutlinedButton>(previous).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(next).onPressed, isNotNull);
    expect(find.text('1–4 of 6'), findsOneWidget);

    await tester.tap(next);
    await tester.pump();
    expect(find.text('Paging Team 1'), findsNothing);
    expect(find.text('Paging Team 5'), findsOneWidget);
    expect(find.text('Paging Team 6'), findsOneWidget);
    expect(find.text('5–6 of 6'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(next).onPressed, isNull);

    await tester.tap(previous);
    await tester.pump();
    expect(find.text('Paging Team 1'), findsOneWidget);

    final viewAll = find.widgetWithText(OutlinedButton, 'View all 6 PIT teams');
    expect(viewAll, findsOneWidget);
    await tester.tap(viewAll);
    expect(openedTeam, isNull);
  });

  test('badge counts each missing material once and keeps review separate', () {
    final team = <String, dynamic>{
      'current_stage': 'Proposal',
      'stages': [
        {
          'stage_label': 'Proposal',
          'deliverables_configured': true,
          'pre': [
            {
              'id': 'DECK',
              'required': true,
              'type': 'pre',
              'requirement_timing': 'defense',
              'materials_submitted': false,
              'materials_status': 'overdue',
              'uploaded': false,
            },
            {
              'id': 'PAPER',
              'required': true,
              'type': 'pre',
              'uploaded': true,
              'submission': {'status': 'pending_review'},
            },
          ],
          'materials_readiness': {
            'status': 'overdue',
            'missing': [
              {'id': 'DECK', 'materials_status': 'overdue'},
            ],
          },
        },
      ],
    };
    final summary = TeamRequirementSummary.fromTeam(team);
    expect(summary.missing, 1);
    expect(summary.awaitingReview, 1);
    expect(summary.label, '1 overdue');
  });

  test('team badge separates endorsement blockers from files due later', () {
    Map<String, dynamic> team({required bool paperUploaded}) => {
      'current_stage': 'Proposal',
      'stages': [
        {
          'stage_label': 'Proposal',
          'deliverables_configured': true,
          'required_complete': paperUploaded,
          'pre': [
            {
              'id': 'PAPER',
              'type': 'pre',
              'required': true,
              'uploaded': paperUploaded,
              'requirement_timing': 'scheduling',
              if (paperUploaded) 'submission': {'status': 'accepted'},
            },
            {
              'id': 'DECK',
              'type': 'pre',
              'required': true,
              'uploaded': false,
              'requirement_timing': 'defense',
              'materials_status': 'awaiting_schedule',
            },
          ],
          'materials_readiness': {
            'status': 'awaiting_schedule',
            'missing': [
              {'id': 'DECK', 'materials_status': 'awaiting_schedule'},
            ],
          },
        },
      ],
    };

    final blocked = TeamRequirementSummary.fromTeam(team(paperUploaded: false));
    expect(blocked.missingForEndorsement, 1);
    expect(blocked.pendingDefenseFiles, 1);
    expect(blocked.label, '1 to endorse');

    final ready = TeamRequirementSummary.fromTeam(team(paperUploaded: true));
    expect(ready.missingForEndorsement, 0);
    expect(ready.pendingDefenseFiles, 1);
    expect(ready.label, '1 due later');
  });

  testWidgets('defense calendar fits a narrow dashboard card', (tester) async {
    tester.view.physicalSize = const Size(350, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final date = DateTime.now().add(const Duration(days: 7));
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DefenseScheduleCalendar(
          title: 'Defense schedule & materials',
          subtitle: 'Select a date to see team defenses and file progress.',
          schedules: [
            {
              'team_id': 7,
              'scheduled_date':
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              'start_time': '09:30:00',
              'stage_label': 'System Concept Pitching',
              'room': 'Room 301',
              'materials_readiness': {
                'required_total': 2,
                'submitted_total': 0,
              },
            },
          ],
          teamNames: const {7: 'Team AlphaWave'},
          loading: false,
          hasError: false,
          onOpenDefense: (_, _) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final selectedDay = find.byKey(
      Key('defense-calendar-day-${date.year}-${date.month}-${date.day}'),
    );
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekdayLabel = tester.widget<Text>(
      find.descendant(
        of: selectedDay,
        matching: find.text(weekdays[date.weekday - 1]),
      ),
    );
    expect(weekdayLabel.style?.color, Colors.white);
    await tester.tap(find.text('Month view'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT files due after scheduling need no endorsement', (
    tester,
  ) async {
    expect(
      DeliverablesTriageHelper.isOverdueOrMissing(
        Map<String, dynamic>.from(_pitTeam),
      ),
      isTrue,
    );
    expect(
      DeliverablesTriageHelper.isReadyForDefense(
        Map<String, dynamic>.from(_pitTeam),
      ),
      isTrue,
    );
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: ['System Concept Pitching'],
            teams: [_pitTeam],
          ),
          isAdviser: false,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );

    expect(find.text('Ready to Schedule'), findsWidgets);
    expect(find.text('Ready for review'), findsNothing);
    expect(find.text('No scheduling uploads required'), findsOneWidget);
    expect(
      find.textContaining(
        'No endorsement needed. This team can be scheduled now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review & endorse'), findsNothing);
  });

  testWidgets('instructor team has read only Schedule tab and scoped exports', (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: ['System Concept Pitching'],
            teams: [_pitTeam],
          ),
          isAdviser: false,
          isPitInstructor: true,
          initialTeamId: 7,
        ),
      ),
      overrides: [
        adviserGradingProvider.overrideWith(_PitGradesNotifier.new),
        pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
      ],
    );

    expect(find.text('Export teams'), findsOneWidget);
    expect(find.text('Export team summary'), findsOneWidget);
    final summary = find.byKey(const Key('instructor-team-summary'));
    expect(summary, findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Project title')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Library tracker')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Year level: 1st Year')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Section: BSIT-1A')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Team roster (2)')), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Next step')), findsOneWidget);
    expect(find.text('Stage status'), findsNothing);
    expect(find.text('PIT: System Concept Pitching'), findsNothing);
    expect(
      tester.getTopLeft(find.descendant(of: summary, matching: find.text('Export team summary'))).dy,
      closeTo(tester.getTopLeft(find.descendant(
        of: summary,
        matching: find.text('Ready to Schedule'),
      )).dy, 16),
    );
    expect(find.textContaining('Review first'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Export teams')).dx,
      greaterThan(tester.getTopLeft(find.text('Teams (1)')).dx),
    );
    await tester.tap(find.text('Export teams'));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Download Excel'), findsOneWidget);
    await tester.tap(find.text('Teams (1)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Schedule'));
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Event schedule'), findsOneWidget);
    expect(find.text('Room: Room 301'), findsOneWidget);
    expect(find.text('Room: Room 302'), findsNothing);
    expect(find.textContaining('minutes', findRichText: true), findsNothing);
  });

  testWidgets('instructor defaults to dossier workspace and matrix exposes assigned teams export', (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const TeamDeliverablesScreen(
        initialScope: 'pit',
        isPitInstructor: true,
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PitDeliverablesNotifier.new),
        adviserGradingProvider.overrideWith(_PitGradesNotifier.new),
        weeklyProgressProvider.overrideWith(_PitWeeklyNotifier.new),
        pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
      ],
    );
    await tester.pump();
    expect(find.byType(DeliverablesTablePane), findsOneWidget);

    // When matrix view is explicitly selected:
    await pumpDefensysWidget(
      tester,
      const TeamDeliverablesScreen(
        initialScope: 'pit',
        isPitInstructor: true,
        initialViewMode: DeliverablesViewMode.matrix,
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PitDeliverablesNotifier.new),
        adviserGradingProvider.overrideWith(_PitGradesNotifier.new),
        weeklyProgressProvider.overrideWith(_PitWeeklyNotifier.new),
        pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
      ],
    );
    await tester.pump();
    expect(find.byType(CohortSubmissionsMatrix), findsOneWidget);
    expect(find.text('Export teams'), findsOneWidget);
  });

  testWidgets('instructor dossier follows the PIT event selected above', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final team = <String, dynamic>{
      ..._pitTeam,
      'stages': [
        _pitStage,
        {
          ..._pitStage,
          'stage_label': 'Prototype Demo',
          'stage_status_detail': 'awaiting_endorsement',
          'endorsement_required': true,
          'required_complete': false,
          'required_total': 1,
          'required_uploaded': 0,
        },
      ],
    };
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'Prototype Demo',
            stageOptions: const ['System Concept Pitching', 'Prototype Demo'],
            teams: [team],
          ),
          isAdviser: false,
          isPitInstructor: true,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );
    final summary = find.byKey(const Key('instructor-team-summary'));
    expect(find.descendant(of: summary, matching: find.text('Awaiting requirements')),
        findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('Ready to Schedule')),
        findsNothing);
    expect(find.text('0/1'), findsWidgets);
  });

  testWidgets('instructor export and team actions fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: ['System Concept Pitching'],
            teams: [_pitTeam],
          ),
          isAdviser: false,
          isPitInstructor: true,
        ),
      ),
      overrides: [
        adviserGradingProvider.overrideWith(_PitGradesNotifier.new),
        pitInstructorDefenseProvider.overrideWith(_PitDefenseNotifier.new),
      ],
    );

    expect(find.text('Teams (1)'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Teams (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team AlphaWave'));
    await tester.pumpAndSettle();
    expect(find.text('Export summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required PIT scheduling files still allow manual endorsement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final stage = <String, dynamic>{
      ..._pitStage,
      'endorsement_required': true,
      'stage_status_detail': 'awaiting_endorsement',
      'required_total': 1,
      'required_uploaded': 1,
      'endorsement_review': {'can_review_and_endorse': true, 'review_token': 'pit-reviewed-files', 'files': []},
      'materials_readiness': {'required_total': 0, 'submitted_total': 0},
      'pre': [
        {
          'id': 'PAPER',
          'label': 'Concept Paper',
          'type': 'pre',
          'required': true,
          'uploaded': true,
          'submission': {'status': 'accepted'},
        },
      ],
    };
    final team = <String, dynamic>{
      ..._pitTeam,
      'stages': [stage],
    };
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: const ['System Concept Pitching'],
            teams: [team],
          ),
          isAdviser: false,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );

    expect(find.text('Ready for review'), findsWidgets);
    final endorseButton = find.ancestor(
      of: find.text('Review & endorse'),
      matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(endorseButton).onPressed, isNotNull);
  });

  testWidgets('compact team card shows the name with a small status below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final stageWithReview = <String, dynamic>{
      ..._pitStage,
      'pre': [
        {
          'id': 'PAPER',
          'label': 'Concept Paper',
          'type': 'pre',
          'required': true,
          'uploaded': true,
          'submission': {'status': 'pending'},
        },
      ],
    };
    final teamWithReview = <String, dynamic>{
      ..._pitTeam,
      'adviser_name': 'Eduardo Padilla',
      'stages': [stageWithReview],
    };

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'System Concept Pitching',
            stageOptions: const ['System Concept Pitching'],
            teams: [teamWithReview],
          ),
          isAdviser: false,
          isPitInstructor: true,
          initialTeamId: 7,
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(_PitGradesNotifier.new)],
    );

    // Keep review status visible without repeating the project title in the list.
    expect(find.text('1 Awaiting Review'), findsOneWidget);

    // No competing separate banners or bottom tags on the compact card list:
    expect(find.text('1 awaiting review'), findsNothing);
    expect(find.text('Library tracker'), findsOneWidget);
  });
}
