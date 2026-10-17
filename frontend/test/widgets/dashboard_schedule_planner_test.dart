import 'package:defensys/screens/web/shared/dashboard_schedule_planner.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_planner_client.dart';
import '../helpers/capture_preview.dart';

void main() {
  testWidgets(
    'planner selects a day for summaries and opens only the chosen session',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final emptyDay = now.day == 1 ? 2 : 1;
      final emptyDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${emptyDay.toString().padLeft(2, '0')}';
      final client = FakePlannerClient([
        {
          'session_id': 'pit-session',
          'date': date,
          'scope': 'pit',
          'event_name': 'System Concept Pitching',
          'room': 'Room 301',
          'team_count': 8,
          'time_blocks': [
            {'start': '${date}T08:00', 'end': '${date}T12:00'},
            {'start': '${date}T13:00', 'end': '${date}T17:00'},
          ],
        },
        {
          'session_id': 'capstone-session',
          'date': date,
          'scope': 'capstone',
          'event_name': 'Proposal Defense',
          'room': 'Room 402',
          'team_count': 4,
          'time_blocks': [
            {'start': '${date}T13:00', 'end': '${date}T17:00'},
          ],
        },
      ]);
      await loadPreviewFonts();
      final router = GoRouter(
        initialLocation: '/admin/overview',
        routes: [
          GoRoute(
            path: '/admin/overview',
            builder: (_, __) => const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 600,
                  child: RepaintBoundary(
                    key: ValueKey('planner-preview'),
                    child: ColoredBox(
                      color: Colors.white,
                      child: DashboardSchedulePlanner(workspace: 'admin'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/defense-board',
            builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authenticatedHttpClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 sessions are scheduled for 12 teams'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'System Concept Pitching has 8 teams scheduled in Room 301',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('8:00 AM to 12:00 PM, then 1:00 PM to 5:00 PM'),
        findsOneWidget,
      );
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(client.requested.last.queryParameters['start'], isNotEmpty);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('planner-preview')),
        'dashboard-schedule-planner',
      );

      await tester.tap(find.byKey(ValueKey('planner-day-$emptyDate')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/overview');
      expect(find.textContaining('0 sessions'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('planner-session-pit-session')),
        findsNothing,
      );

      await tester.tap(find.byKey(ValueKey('planner-day-$date')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/overview');
      expect(
        find.textContaining('2 sessions are scheduled for 12 teams'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('planner-session-pit-session')),
        findsOneWidget,
      );

      await tester.tap(
        find.textContaining('System Concept Pitching has 8 teams'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('date=$date'), findsOneWidget);
      expect(find.textContaining('session=pit-session'), findsOneWidget);
    },
  );

  for (final width in [320.0, 600.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'shared bookings and history fit $width dark=$dark and respect cohort access',
        (tester) async {
          tester.view.physicalSize = Size(width, 2000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts(force: true);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final previous = today.subtract(const Duration(days: 7));
          String iso(DateTime value) =>
              '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
          Map<String, dynamic> session(
            String id,
            DateTime day,
            String state, {
            bool other = false,
          }) {
            final date = iso(day);
            return {
              'session_id': id,
              'date': date,
              'scope': other ? 'capstone' : 'pit',
              'year_levels': [other ? '4th Year' : '1st Year'],
              'event_name': other ? 'Proposal Defense' : 'Prototype Showcase',
              'room': 'Room 301',
              'team_count': 2,
              'status_counts': {state: 2},
              'can_open': !other,
              'time_blocks': [
                {'start': '${date}T08:00', 'end': '${date}T10:00'},
              ],
              if (other)
                'venues': [
                  {
                    'room': 'Room 301',
                    'time_blocks': [
                      {'start': '${date}T08:00', 'end': '${date}T10:00'},
                    ],
                  },
                  {
                    'room': 'Lab 2',
                    'time_blocks': [
                      {'start': '${date}T13:00', 'end': '${date}T15:00'},
                    ],
                  },
                ],
            };
          }

          final client = FakePlannerClient([
            session('own', today, 'scheduled'),
            session('other', today, 'scheduled', other: true),
            session('past', previous, 'scheduled'),
            session('assessed', previous, 'assessed'),
            session('complete', previous, 'completed'),
            session('archived', previous, 'archived'),
          ]);
          final router = GoRouter(
            initialLocation: '/faculty/overview',
            routes: [
              GoRoute(
                path: '/faculty/overview',
                builder: (context, _) => Scaffold(
                  body: SingleChildScrollView(
                    child: RepaintBoundary(
                      key: const ValueKey('history-preview'),
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: const DashboardSchedulePlanner(
                          workspace: 'faculty',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/faculty/defense-board',
                builder: (_, state) =>
                    Scaffold(body: Text(state.uri.toString())),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authenticatedHttpClientProvider.overrideWithValue(client),
              ],
              child: MaterialApp.router(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'Inter',
                ),
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('1st Year PIT · Booked'), findsOneWidget);
          expect(find.text('4th Year Capstone · Booked'), findsOneWidget);
          expect(
            find.textContaining(
              'in Room 301 from 8:00 AM to 10:00 AM; in Lab 2 from 1:00 PM to 3:00 PM',
            ),
            findsOneWidget,
          );
          expect(find.text('Other cohort · For planning'), findsOneWidget);
          expect(find.text('Capstone'), findsOneWidget);
          expect(find.text('Schedule history'), findsNothing);
          final other = tester.widget<InkWell>(
            find.byKey(const ValueKey('planner-session-other')),
          );
          expect(other.onTap, isNull);
          await tester.tap(find.byKey(const ValueKey('planner-session-other')));
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/faculty/overview',
          );
          await capturePreview(
            tester,
            find.byKey(const ValueKey('history-preview')),
            'shared-bookings-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );

          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(find.text('Schedule history'), findsOneWidget);
          expect(
            find.textContaining('4 sessions were scheduled for 8 teams'),
            findsOneWidget,
          );
          expect(find.text('1st Year PIT · Past schedule'), findsOneWidget);
          expect(find.text('1st Year PIT · Attempt assessed'), findsOneWidget);
          expect(find.text('1st Year PIT · Completed'), findsOneWidget);
          expect(find.text('1st Year PIT · Archived'), findsOneWidget);
          expect(
            find.textContaining('Prototype Showcase had 2 teams scheduled'),
            findsNWidgets(4),
          );
          expect(find.textContaining('Prototype Showcase has'), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('history-preview')),
            'schedule-history-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );

          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(
            find.text('No sessions were scheduled for this day.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Today'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('planner-session-own')));
          await tester.pumpAndSettle();
          expect(find.textContaining('session=own'), findsOneWidget);
          expect(find.textContaining('date=${iso(today)}'), findsOneWidget);
        },
      );
    }
  }
}
