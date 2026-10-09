import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/defense/defense_scheduler_provider.dart';
import 'package:defensys/services/grading/rubric_engine_provider.dart';

import '../helpers/auth_test_overrides.dart';

class _SchedulerProbe extends ConsumerStatefulWidget {
  const _SchedulerProbe();

  @override
  ConsumerState<_SchedulerProbe> createState() => _SchedulerProbeState();
}

class _SchedulerProbeState extends ConsumerState<_SchedulerProbe> {
  final draft = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    });
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    return Column(
      children: [
        TextField(key: const Key('schedule-draft'), controller: draft),
        for (final rubric in state.rubrics) Text(rubric['name'].toString()),
      ],
    );
  }
}

void main() {
  testWidgets(
    'returning to retained scheduler after publishing refreshes options and retains its draft',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var published = false;
      var schedulerLoads = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.contains('/defense/schedules')) {
            schedulerLoads++;
            return http.Response(
              jsonEncode({
                'rubrics': [
                  if (published) {'id': 7, 'name': 'Fresh panel rubric'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/publish/')) {
            published = true;
          }
          if (request.url.path.contains('/grading/grades')) {
            throw StateError('Rubric save must not eagerly load Grade Center');
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(resetApiHttpClientForTesting);
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AdminRoutes.defenseScheduler,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, __, shell) => AdminShell(navigationShell: shell),
            branches: [
              StatefulShellBranch(
                initialLocation: AdminRoutes.defenseScheduler,
                routes: [
                  GoRoute(
                    path: AdminRoutes.defenseScheduler,
                    builder: (_, __) => const _SchedulerProbe(),
                  ),
                ],
              ),
              StatefulShellBranch(
                initialLocation: AdminRoutes.rubrics,
                routes: [
                  GoRoute(
                    path: AdminRoutes.rubrics,
                    builder: (_, __) => const Text('Rubric workspace'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(schedulerLoads, 1);
      await tester.enterText(
        find.byKey(const Key('schedule-draft')),
        'Room 301 draft',
      );
      router.go(AdminRoutes.rubrics);
      await tester.pumpAndSettle();
      expect(
        await container.read(rubricEngineProvider.notifier).publishRubric(7),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(schedulerLoads, 1);
      router.go(AdminRoutes.defenseScheduler);
      await tester.pumpAndSettle();
      expect(schedulerLoads, 2);
      expect(find.text('Fresh panel rubric'), findsOneWidget);
      expect(find.text('Room 301 draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
