import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/team_detail/academic_progress_card.dart';
import 'package:defensys/theme/app_theme.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

const _grades = <Map<String, dynamic>>[
  {
    'id': 7,
    'stage_label': 'Concept Proposal',
    'display_semester': '1st Semester · 2026–2027',
    'final_grade': '89.25',
    'status': 'pending',
    'is_officially_complete': true,
    'result': 'passed',
    'verdict': 'approved',
  },
  {
    'id': 8,
    'stage_label': 'Project Proposal',
    'display_semester': '1st Semester · 2026–2027',
    'final_grade': '81.50',
    'status': 'pending',
    'is_officially_complete': false,
    'result': 'revisions_pending',
    'verdict': 'approved_with_revisions',
    'rubric_target_type': 'individual',
    'peer_per_student': [
      {'student_id': 10, 'final_grade': '83.00'},
      {'student_id': 11, 'final_grade': '80.00'},
    ],
  },
];

Widget _card({
  List<Map<String, dynamic>> grades = _grades,
  String? error,
  VoidCallback? onRetry,
  ValueChanged<Map<String, dynamic>>? onView,
}) => AcademicProgressCard(
  grades: grades,
  stageLabels: const ['Concept Proposal', 'Project Proposal', 'Final Defense'],
  currentStage: 'Project Proposal',
  isCapstone: true,
  isLoading: false,
  error: error,
  onRetry: onRetry ?? () {},
  onViewEvaluation: onView ?? (_) {},
);

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'official results, provisional averages, and unevaluated stages remain distinct',
    (tester) async {
      Map<String, dynamic>? opened;
      await pumpDefensysWidget(
        tester,
        _card(onView: (grade) => opened = grade),
      );
      expect(find.text('89.25'), findsOneWidget);
      expect(find.text('Finalized'), findsOneWidget);
      expect(find.text('81.50'), findsOneWidget);
      expect(find.text('Provisional'), findsOneWidget);
      expect(find.text('Team average'), findsOneWidget);
      expect(find.text('83.00'), findsNothing);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Defense: Approved with Revisions'), findsOneWidget);
      expect(find.text('Not evaluated'), findsOneWidget);
      await tester.tap(find.text('View evaluation details').at(1));
      expect(opened?['id'], 8);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a zero score is recorded without claiming a provisional pass or failure',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        _card(
          grades: const [
            {
              'id': 9,
              'stage_label': 'Concept Proposal',
              'panel_score': '0.00',
              'final_grade': '0.00',
              'result': 'failed',
            },
          ],
        ),
      );
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('Provisional'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Defense: Failed'), findsNothing);
    },
  );

  testWidgets(
    'published grades show the stored result when there is no verdict',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        _card(
          grades: const [
            {
              'id': 9,
              'stage_label': 'Concept Proposal',
              'final_grade': '65.00',
              'status': 'published',
              'result': 'failed',
            },
          ],
        ),
      );
      expect(find.text('Finalized'), findsOneWidget);
      expect(find.text('Defense: Failed'), findsOneWidget);
      expect(find.text('Provisional'), findsNothing);
    },
  );

  testWidgets('grade errors show a retry instead of an unevaluated stage', (
    tester,
  ) async {
    var retried = false;
    await pumpDefensysWidget(
      tester,
      _card(
        error: 'Grades could not be loaded.',
        onRetry: () => retried = true,
      ),
    );
    expect(find.text('Grades could not be loaded.'), findsOneWidget);
    expect(find.text('Not evaluated'), findsNothing);
    expect(find.text('89.25'), findsNothing);
    await tester.tap(find.text('Retry grades'));
    expect(retried, isTrue);
  });

  testWidgets('a team without stages or grades has a clear empty state', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      AcademicProgressCard(
        grades: const [],
        stageLabels: const [],
        isCapstone: false,
        isLoading: false,
        onRetry: () {},
        onViewEvaluation: (_) {},
      ),
    );
    expect(find.text('No evaluations recorded yet.'), findsOneWidget);
    expect(find.text('View evaluation details'), findsNothing);
  });

  for (final preview in [
    ('desktop', const Size(620, 740), AppTheme.theme),
    ('narrow', const Size(340, 850), AppTheme.theme),
    ('dark', const Size(620, 740), AppTheme.mistDarkTheme),
  ]) {
    testWidgets('academic progress fits the ${preview.$1} layout', (
      tester,
    ) async {
      tester.view.physicalSize = preview.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(key: key, child: _card()),
        theme: preview.$3,
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(key),
        'academic_progress/${preview.$1}',
      );
    });
  }
}
