import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/academic/student_capstone_history.dart';
import 'package:defensys/screens/web/admin/student_teams/components/historical_team_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
}

void main() {
  test(
    'participation labels are per student and handle ordinal exceptions',
    () {
      expect(capstoneParticipationLabel(1), '1st participation');
      expect(capstoneParticipationLabel(2), '2nd participation');
      expect(capstoneParticipationLabel(11), '11th participation');
      expect(capstoneParticipationLabel(null), 'History needs review');
    },
  );
  for (final width in [390.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'history shows individual participation with no copy action at $width $dark',
        (tester) async {
          await loadPreviewFonts();
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpDefensysWidget(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showHistoricalTeam(context, {
                  'id': 5,
                  'name': 'Previous team',
                  'project_title': 'Preserved project',
                  'display_semester': '2nd Semester, A.Y. 2025–2026',
                  'project_version': 1,
                  'status': 'Failed',
                  'leader_name': 'Ana Reyes',
                  'members': [
                    {
                      'student_id': 1,
                      'name': 'Ana Reyes',
                      'capstone_participation': {'number': 2},
                    },
                    {
                      'student_id': 2,
                      'name': 'Bea Santos',
                      'capstone_participation': {'number': 1},
                    },
                  ],
                  'assessments': <dynamic>[],
                }),
                child: const Text('Open history'),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: [authProvider.overrideWith(_Auth.new)],
          );
          await tester.tap(find.text('Open history'));
          await tester.pumpAndSettle();
          expect(find.text('Ana Reyes'), findsOneWidget);
          expect(find.text('2nd participation'), findsOneWidget);
          expect(find.text('1st participation'), findsOneWidget);
          expect(find.text('Copy members to new intake'), findsNothing);
          expect(find.text('Reuse roster'), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(Dialog),
            'capstone-history-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
