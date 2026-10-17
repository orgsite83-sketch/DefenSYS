import 'package:defensys/screens/web/faculty/dashboard_widgets.dart';
import 'package:defensys/screens/web/shared/dashboard_schedule_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  for (final scope in ['pit', 'capstone']) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 680.0]) {
        testWidgets(
          '$scope personal calendar preserves scope and history at $width dark=$dark',
          (tester) async {
            tester.view.physicalSize = Size(width, 1600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await loadPreviewFonts(force: true);
            final now = DateTime.now();
            final previous = DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(const Duration(days: 7));
            String iso(DateTime value) =>
                '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
            final stage = scope == 'pit'
                ? 'Prototype Showcase'
                : 'Proposal Defense';
            final year = scope == 'pit' ? '2nd Year' : '4th Year';
            Map<String, dynamic> schedule(
              int id,
              int team,
              DateTime date,
              String state,
            ) => {
              'id': id,
              'team_id': team,
              'team_name': 'Untrusted feed name',
              'scope': scope,
              'team_level': '$year ${scope == 'pit' ? 'PIT' : 'Capstone'}',
              'stage_label': stage,
              'scheduled_date': iso(date),
              'start_time': '09:30:00',
              'slot_duration': 90,
              'room': 'Room 301',
              'status': state == 'completed' || state == 'assessed'
                  ? 'done'
                  : 'scheduled',
              'display_status': state,
              'materials_readiness': {
                'required_total': 2,
                'submitted_total': 1,
              },
            };
            int? openedTeam;
            String? openedStage;
            await pumpDefensysWidget(
              tester,
              SingleChildScrollView(
                child: RepaintBoundary(
                  key: const ValueKey('personal-calendar-preview'),
                  child: DefenseScheduleCalendar(
                    title: 'Defense Schedule',
                    subtitle: scope == 'pit'
                        ? 'Your assigned teams only'
                        : 'Your advisees only',
                    programScope: scope,
                    loading: false,
                    hasError: false,
                    teamNames: const {7: 'Team BioPulse'},
                    schedules: [
                      schedule(1, 7, now, 'scheduled'),
                      schedule(2, 99, now, 'scheduled'),
                      schedule(3, 7, previous, 'completed'),
                      schedule(4, 99, previous, 'completed'),
                    ],
                    onOpenDefense: (team, stage) {
                      openedTeam = team;
                      openedStage = stage;
                    },
                  ),
                ),
              ),
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: 'Inter',
              ),
            );
            expect(find.byType(DashboardSchedulePlanner), findsOneWidget);
            expect(find.text('Today'), findsOneWidget);
            expect(find.text('Week'), findsOneWidget);
            expect(find.text('Month'), findsOneWidget);
            expect(
              find.textContaining('1 defense is scheduled for 1 team'),
              findsOneWidget,
            );
            expect(
              find.textContaining('Team BioPulse is scheduled for $stage'),
              findsOneWidget,
            );
            expect(find.textContaining('9:30 AM to 11:00 AM'), findsOneWidget);
            expect(find.text('1/2 defense materials uploaded'), findsOneWidget);
            expect(find.textContaining('Untrusted feed name'), findsNothing);
            await tester.tap(find.textContaining('Team BioPulse is scheduled'));
            await tester.pumpAndSettle();
            expect(openedTeam, 7);
            expect(openedStage, stage);
            await capturePreview(
              tester,
              find.byKey(const ValueKey('personal-calendar-preview')),
              '$scope-calendar-${width.toInt()}-${dark ? 'dark' : 'light'}',
            );
            await tester.tap(find.byIcon(Icons.chevron_left));
            await tester.pumpAndSettle();
            expect(find.text('Schedule history'), findsOneWidget);
            expect(
              find.textContaining('1 defense was scheduled for 1 team'),
              findsOneWidget,
            );
            expect(
              find.textContaining('Team BioPulse was scheduled'),
              findsOneWidget,
            );
            expect(
              find.text(
                '$year ${scope == 'pit' ? 'PIT' : 'Capstone'} · Completed',
              ),
              findsOneWidget,
            );
            await tester.tap(find.text('Month'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
