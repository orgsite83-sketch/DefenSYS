import 'package:defensys/screens/web/admin/grade_center/defense_workflow_panel.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _WorkflowAuth extends AuthNotifier {
  _WorkflowAuth(this.role, this.id);
  final String role;
  final int id;
  @override
  AuthState build() =>
      AuthState(isRestoring: false, user: {'role': role, 'id': id});
}

Map<String, dynamic> _grade(String verdict, {bool verification = false}) => {
  'id': 1,
  'scope': 'capstone',
  'verdict': verdict,
  'status': 'pending',
  'team_name': 'Team AgriSense',
  'stage_label': 'Concept Proposal',
  'redefense_verification_required': verification,
  'workflow': {
    'chair_id': 2,
    'adviser_id': 3,
    'retake_authorized': false,
    'passed_and_cleared': false,
    'previous_projects': [],
    'recovery_history': [],
  },
};

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'failed teams show admin recovery actions and no scheduling shortcut',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('workflow-preview'),
          child: DefenseWorkflowPanel(grade: _grade('failed')),
        ),
        overrides: [authProvider.overrideWith(() => _WorkflowAuth('admin', 1))],
      );
      expect(find.text('Progression blocked'), findsOneWidget);
      expect(find.text('Authorize another attempt'), findsOneWidget);
      expect(find.text('Authorize replacement concept'), findsOneWidget);
      expect(find.text('Open Defense Scheduler'), findsNothing);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('workflow-preview')),
        'defense-workflow-failed',
      );
      await tester.tap(find.text('Authorize replacement concept'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keep the current adviser and team members.'),
        findsOneWidget,
      );
      final save = find.widgetWithText(FilledButton, 'Save decision');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected concepts only offer replacement recovery', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      DefenseWorkflowPanel(grade: _grade('project_rejected')),
      overrides: [authProvider.overrideWith(() => _WorkflowAuth('admin', 1))],
    );
    expect(find.text('Authorize another attempt'), findsNothing);
    expect(find.text('Authorize replacement concept'), findsOneWidget);
  });

  testWidgets('chair or assigned adviser clears revisions without creating a graded attempt', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      DefenseWorkflowPanel(grade: _grade('approved_with_revisions')),
      overrides: [authProvider.overrideWith(() => _WorkflowAuth('faculty', 2))],
    );
    expect(find.text('Revision clearance pending'), findsOneWidget);
    expect(find.text('Verify and clear revisions'), findsOneWidget);
    expect(find.text('Schedule compliance review'), findsOneWidget);
    expect(find.text('Open Defense Scheduler'), findsNothing);
    expect(find.text('Open Project Archiving'), findsNothing);

    // Adviser (id: 3) also has authority to clear revisions
    await pumpDefensysWidget(
      tester,
      DefenseWorkflowPanel(grade: _grade('approved_with_revisions')),
      overrides: [authProvider.overrideWith(() => _WorkflowAuth('faculty', 3))],
    );
    expect(find.text('Verify and clear revisions'), findsOneWidget);
  });

  testWidgets(
    'adviser verification is optional and distinct from endorsement',
    (tester) async {
      Future<void> show(bool required) => pumpDefensysWidget(
        tester,
        DefenseWorkflowPanel(
          grade: _grade('for_redefense', verification: required),
        ),
        overrides: [
          authProvider.overrideWith(() => _WorkflowAuth('faculty', 3)),
        ],
      );
      await show(false);
      expect(find.text('Verify required corrections'), findsNothing);
      await show(true);
      expect(find.text('Verify required corrections'), findsOneWidget);
      expect(
        find.textContaining('The existing endorsement is retained.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
