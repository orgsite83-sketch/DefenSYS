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
      expect(find.textContaining('0 sessions are scheduled'), findsOneWidget);
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
}
