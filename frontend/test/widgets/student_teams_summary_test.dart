import 'package:defensys/screens/web/admin/student_teams/components/student_teams_stage_summary.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _pitState = StudentTeamsState(
  eventName: 'PIT Design',
  teams: [
    {
      'instructor_name': 'Ricardo Fontanilla',
      'defense_context': {
        'event_label': 'PIT Design',
        'scheduling_status': 'ready',
      },
    },
    {
      'instructor_name': 'Ricardo Fontanilla',
      'defense_context': {
        'event_label': 'PIT Design',
        'scheduling_status': 'scheduled',
      },
    },
    {
      // An adviser does not satisfy a PIT section instructor assignment.
      'adviser_name': 'Ana Reyes',
      'defense_context': {
        'event_label': 'PIT Design',
        'scheduling_status': 'preparing',
        'concept_workflow': {'enabled': true, 'status': 'ready_to_schedule'},
      },
    },
    {
      'instructor_name': ' ',
      'defense_context': {
        'event_label': 'Later showcase',
        'scheduling_status': 'ready',
      },
    },
    {
      'instructor_name': 'Ana Reyes',
      'defense_context': {
        'event_label': 'Later showcase',
        'scheduling_status': 'scheduled',
      },
    },
  ],
);

Finder _card(String id) => find.byKey(Key('student-teams-summary-$id'));

void _expectCount(String id, String count) {
  expect(
    find.descendant(of: _card(id), matching: find.text(count)),
    findsOneWidget,
  );
}

void main() {
  testWidgets('source and continuation rows count one team', (tester) async {
    await pumpDefensysWidget(
      tester,
      const StudentTeamsSummaryCards(
        state: StudentTeamsState(
          teams: [
            {'id': 7, 'record_key': '7:3', 'is_editable': false},
            {'id': 7, 'record_key': '7:1', 'is_editable': false},
          ],
        ),
        isPitContext: false,
      ),
    );
    _expectCount('teams', '1');
    _expectCount('ready', '—');
    _expectCount('scheduled', '—');
  });
  testWidgets(
    'PIT counts section instructors and only selected event eligibility',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        const StudentTeamsSummaryCards(state: _pitState, isPitContext: true),
      );

      _expectCount('teams', '5');
      _expectCount('needs-instructor', '2');
      _expectCount('ready', '1');
      _expectCount('scheduled', '1');
      expect(find.text('Needs instructor'), findsOneWidget);
      expect(find.text('Needs adviser'), findsNothing);
      expect(find.text('Selected PIT event'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current roster prompts for event before showing scheduling counts',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        StudentTeamsSummaryCards(
          state: _pitState.copyWith(clearEventName: true),
          isPitContext: true,
        ),
      );

      _expectCount('teams', '5');
      _expectCount('needs-instructor', '2');
      _expectCount('ready', '—');
      _expectCount('scheduled', '—');
      expect(find.text('Select a PIT event'), findsNWidgets(2));
    },
  );

  for (final dark in [false, true]) {
    for (final (width, columns) in [(1440.0, 4), (640.0, 2), (320.0, 1)]) {
      testWidgets('PIT summary fits $width with $columns columns, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          const Padding(
            padding: EdgeInsets.all(16),
            child: StudentTeamsSummaryCards(
              state: _pitState,
              isPitContext: true,
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );

        final rects = [
          for (final id in ['teams', 'needs-instructor', 'ready', 'scheduled'])
            tester.getRect(_card(id)),
        ];
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].left, greaterThanOrEqualTo(16));
          expect(rects[i].right, lessThanOrEqualTo(width - 16));
          expect(rects[i].top, rects[i ~/ columns * columns].top);
          if (i >= columns) {
            expect(rects[i].top, greaterThan(rects[i - columns].bottom));
          }
        }
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(StudentTeamsSummaryCards),
          'pit-team-summary-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
