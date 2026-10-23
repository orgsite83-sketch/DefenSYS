import 'package:defensys/screens/web/admin/grade_center/grade_center_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../helpers/pump_app.dart';

void main() {
  for (final pending in [false, true]) {
    testWidgets(
      'configured verdict choices follow panel qualification, pending=$pending',
      (tester) async {
        final grade = <String, dynamic>{
          'id': 1,
          'verdict': '',
          'scope': 'capstone',
          'workflow': {
            'assessment_policy': {'version': 1},
            'outcome_rule': {
              'allowed_verdicts': pending ? [] : ['for_redefense'],
            },
          },
        };
        await pumpDefensysWidget(
          tester,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => GradeCenterActions.showVerdictDialog(
                context: context,
                ref: ref,
                grade: grade,
              ),
              child: const Text('Record outcome'),
            ),
          ),
        );
        await tester.tap(find.text('Record outcome'));
        await tester.pumpAndSettle();
        final choices = tester.widgetList<Radio<String>>(
          find.byType(Radio<String>),
        );
        expect(
          choices
              .where((radio) => radio.enabled == true)
              .map((radio) => radio.value)
              .toList(),
          pending ? [] : ['for_redefense'],
        );
        expect(
          find.text('Require adviser verification of corrections'),
          findsNothing,
        );
        final submit = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Submit Verdict'),
        );
        expect(submit.onPressed == null, pending);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('revision clearance and PIT keep their separate result basis', () {
    expect(
      gradeResult({'verdict': 'approved_with_revisions', 'final_grade': 90}),
      'revisions_pending',
    );
    expect(
      gradeResult({
        'verdict': 'approved_with_revisions',
        'revisions_cleared_at': '2026-10-23',
        'final_grade': 40,
      }),
      'passed',
    );
    expect(
      gradeDisplayStatus({
        'scope': 'pit',
        'verdict': 'approved',
        'final_grade': 40,
      }),
      'failed',
    );
  });
  test(
    'a pending server result cannot become a pass from an academic total',
    () {
      expect(
        gradeDisplayStatus({
          'status': 'pending',
          'result': 'pending',
          'final_grade': 95,
          'workflow': {
            'assessment_policy': {'version': 1},
          },
        }),
        'pending',
      );
    },
  );

  test(
    'configured hearings without a result still await the recorded outcome',
    () {
      expect(
        gradeDisplayStatus({
          'status': 'pending',
          'final_grade': 95,
          'workflow': {
            'assessment_policy': {'version': 1},
          },
        }),
        'pending',
      );
    },
  );

  test('an approved defense can retain a low academic grade', () {
    expect(
      gradeDisplayStatus({
        'status': 'pending',
        'verdict': 'approved',
        'final_grade': 45,
      }),
      'approved',
    );
  });

  test('unconfigured legacy numeric results keep their original basis', () {
    expect(
      gradeDisplayStatus({'status': 'pending', 'final_grade': 80}),
      'passed',
    );
    expect(
      gradeDisplayStatus({'status': 'pending', 'final_grade': 70}),
      'failed',
    );
  });
}
