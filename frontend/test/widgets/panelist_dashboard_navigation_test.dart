import 'dart:convert';
import 'package:defensys/screens/app/panelist_dashboard.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Guest extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    user: {'id': 42, 'role': 'guest_panelist'},
    isRestoring: false,
  );
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

Map<String, dynamic> _assignment(int id, String name) => {
  'id': id,
  'schedule_id': id,
  'name': name,
  'project_title': 'Project for $name',
  'scope': 'pit',
  'scheduled_date': TeamData.manilaToday.toIso8601String().split('T').first,
  'defense_stage': 'Concept Proposal',
  'start_time': '08:00',
  'room': '301',
  'grading_available': true,
  'evaluation_context': 'context-$id',
  'members': [
    {'id': 1, 'name': 'Alice', 'is_leader': true},
  ],
  'panel_rubric': {
    'target_type': 'team',
    'criteria': [
      {'id': 1, 'name': 'Clarity', 'max_score': 10},
    ],
  },
};
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(Uri.parse('https://example.test')));
  testWidgets(
    'Assignments confirms identity and a failed save blocks leaving the grade sheet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      final assignments = [
        _assignment(20, 'Team SkyLedger'),
        _assignment(21, 'Team BioPulse'),
      ];
      var reversed = false;
      when(() => client.get(any())).thenAnswer((invocation) async {
        final path = (invocation.positionalArguments.first as Uri).path;
        return http.Response(
          json.encode(
            path.contains('guest-assignments')
                ? {
                    'teams': reversed
                        ? assignments.reversed.toList()
                        : assignments,
                  }
                : {'results': []},
          ),
          200,
        );
      });
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => http.Response('{"detail":"Offline"}', 503));
      await pumpDefensysWidget(
        tester,
        const PanelistDashboard(),
        overrides: [
          authProvider.overrideWith(_Guest.new),
          connectivityProvider.overrideWith(_Online.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      await _tap(tester, find.text('Grade Team').first);
      expect(find.text('Team preview'), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(
              find.byType(NavigationBar, skipOffstage: false),
            )
            .selectedIndex,
        0,
      );
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      expect(find.text('Currently grading'), findsOneWidget);
      final score = find.descendant(
        of: find.byType(EvaluationScorePicker),
        matching: find.byKey(const ValueKey('score-value-8')),
      );
      await _tap(tester, score);
      await _tap(tester, find.text('Results').last);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(
        find.text('Couldn’t save draft. Your changes are still here.'),
        findsOneWidget,
      );
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(
          '{"draft":{"saved_at":"2026-10-05T08:00:00+08:00"}}',
          200,
        ),
      );
      await _tap(tester, find.text('Assignments').last);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await _tap(tester, find.text('Grade Team').last);
      expect(find.text('Team preview'), findsOneWidget);
      // A background refresh reorders the list while the preview is open.
      // Confirmation must locate the schedule again, not use its old index.
      reversed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      final sheet = tester.widget<GradeSheetTab>(find.byType(GradeSheetTab));
      expect(sheet.teams[sheet.selectedTeamIndex].scheduleId, '21');
      expect(sheet.selectedTeamIndex, 0);
      expect(find.text('Currently grading'), findsOneWidget);
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
