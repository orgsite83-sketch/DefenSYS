import 'package:defensys/screens/web/faculty/pit_lead/pit_lead_dashboard_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';

void main() {
  for (final width in [320.0, 390.0, 500.0, 768.0, 1024.0, 1200.0, 1400.0]) {
    for (final populated in [false, true]) {
      testWidgets('PIT dashboard fits $width with populated=$populated', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var openedScheduler = false;
        final errors = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
          previousErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        await pumpDefensysWidget(
          tester,
          PitLeadDashboardContent(
            facultyName: 'Ricardo Fontanilla',
            data: {
              'pit_lead_year': '1st Year',
              'active_semester': '1st Semester, A.Y. 2026-2027',
              'pit_lead_overview': {
                'stats': {
                  'students_in_cohort': 12,
                  'pit_teams': 1,
                  'pending_grades': 1,
                },
                'upcoming_defenses_list': populated
                    ? [
                        {
                          'team_name': 'Team SkyLedger',
                          'project_title': 'Smart Campus Prototype',
                          'stage_label': 'PIT Demo',
                          'date': '2026-10-03',
                          'start_time': '10:00 AM',
                          'room': 'Lab 1',
                          'panelist_count': 2,
                        },
                      ]
                    : [],
                'team_pipeline': {
                  'total_teams': 1,
                  'ready_for_defense': 1,
                  'teams_with_instructor': 1,
                  'stage_distribution': [
                    {'label': 'PIT Demo', 'count': 1},
                  ],
                },
                'action_items': populated
                    ? [
                        {
                          'id': 'ready',
                          'title': 'One PIT team is ready for defense',
                          'description':
                              'Review verified deliverables and schedule this team.',
                          'severity': 'action',
                          'target_section': 'defense_scheduler',
                          'button_label': 'Review Queue',
                        },
                      ]
                    : [],
                'recent_activity': [],
              },
            },
            onOpenStudentTeams: () {},
            onOpenScheduler: () => openedScheduler = true,
            onOpenGradeCenter: () {},
            onOpenRubrics: () {},
            onOpenCohort: () {},
            onOpenPitEvents: () {},
            onOpenAuditCompliance: () {},
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: errors.map((e) => e.toString()).join('\n'),
        );
        await tester.ensureVisible(find.text('Schedule PIT Event'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Schedule PIT Event'));
        expect(openedScheduler, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
