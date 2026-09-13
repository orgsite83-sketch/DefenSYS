import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/faculty/pit_lead/pit_lead_dashboard_content.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('PitLeadDashboardContent renders matching Admin 2x2 grid and metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockData = {
      'pit_lead_year': '1st Year',
      'active_semester': '1st Semester, A.Y. 2026-2027',
      'pit_lead_overview': {
        'stats': {
          'students_in_cohort': 12,
          'pit_teams': 3,
          'scheduled_events': 1,
          'pending_grades': 2,
          'ready_pit_teams': 1,
        },
        'team_pipeline': {
          'total_teams': 3,
          'ready_for_defense': 1,
          'teams_with_instructor': 3,
          'teams_with_adviser': 0,
          'teams_without_adviser': 0,
          'stage_distribution': [
            {'label': 'Concept Proposal', 'code': 'CP', 'count': 1},
            {'label': 'Project Proposal', 'code': 'PP', 'count': 2},
          ],
        },
        'action_items': [
          {
            'id': 'unscheduled_ready_teams',
            'title': '1 PIT Team Ready for Defense',
            'description': 'Deliverables verified. Review readiness queue to schedule.',
            'severity': 'action',
            'target_section': 'defense_scheduler',
            'button_label': 'Review Queue',
          },
        ],
        'upcoming_defenses_list': [
          {
            'id': 1,
            'team_name': 'Team Apex',
            'project_title': 'Smart Attendance',
            'stage_label': 'Concept Proposal',
            'date': '2026-09-15',
            'start_time': '10:00 AM',
            'room': 'Lab 1',
            'panelist_count': 3,
          }
        ],
        'recent_activity': [],
      },
    };

    var studentTeamsOpened = false;
    var schedulerOpened = false;
    var gradeCenterOpened = false;
    var rubricsOpened = false;
    var cohortOpened = false;
    var pitEventsOpened = false;
    var auditOpened = false;

    await pumpDefensysWidget(
      tester,
      PitLeadDashboardContent(
        data: mockData,
        facultyName: 'Ricardo Fontanilla',
        onOpenStudentTeams: () => studentTeamsOpened = true,
        onOpenScheduler: () => schedulerOpened = true,
        onOpenGradeCenter: () => gradeCenterOpened = true,
        onOpenRubrics: () => rubricsOpened = true,
        onOpenCohort: () => cohortOpened = true,
        onOpenPitEvents: () => pitEventsOpened = true,
        onOpenAuditCompliance: () => auditOpened = true,
      ),
    );

    // Verify Header
    expect(find.text('Welcome, Ricardo Fontanilla!'), findsOneWidget);
    expect(find.text('PIT Lead workspace · 1st Year'), findsOneWidget);

    // Verify 4 Metric Cards
    expect(find.text('Students in Cohort'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Active PIT Teams'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('Scheduled PIT Events'), findsOneWidget);
    expect(find.text('Pending Grades'), findsOneWidget);

    // Verify Quick Actions
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Manage PIT Teams'), findsOneWidget);
    expect(find.text('Schedule PIT Event'), findsOneWidget);
    expect(find.text('Configure Rubrics'), findsOneWidget);
    expect(find.text('PIT Events Setup'), findsOneWidget);

    // Verify Upcoming Events
    expect(find.text('Upcoming PIT Events'), findsOneWidget);
    expect(find.text('Team Apex'), findsOneWidget);
    expect(find.text('Concept Proposal'), findsWidgets);

    // Verify Pipeline
    expect(find.text('PIT Pipeline & Readiness'), findsOneWidget);
    expect(find.text('Total Teams'), findsOneWidget);
    expect(find.text('Stage Ready'), findsOneWidget);
    expect(find.text('With Instructor'), findsOneWidget);

    // Verify Action Items Tab
    expect(find.text('Action Items'), findsOneWidget);
    expect(find.text('Period: 1st Semester, A.Y. 2026-2027'), findsOneWidget);
    expect(find.text('1 PIT Team Ready for Defense'), findsOneWidget);
    expect(find.text('Review Queue'), findsOneWidget);

    // Test Quick Actions click
    await tester.tap(find.text('Manage PIT Teams'));
    expect(studentTeamsOpened, isTrue);

    await tester.tap(find.text('Schedule PIT Event'));
    expect(schedulerOpened, isTrue);

    await tester.tap(find.text('Configure Rubrics'));
    expect(rubricsOpened, isTrue);

    await tester.tap(find.text('PIT Events Setup'));
    expect(pitEventsOpened, isTrue);
  });
}
