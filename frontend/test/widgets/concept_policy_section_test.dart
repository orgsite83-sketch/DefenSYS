import 'package:defensys/screens/web/admin/student_teams/dialogs/edit_section_dialog.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _PolicyNotifier extends StudentTeamsNotifier {
  Map<String, dynamic>? saved;
  @override
  StudentTeamsState build() => const StudentTeamsState();
  @override
  Future<Map<String, dynamic>> fetchSectionDetails(int teamId) async => {
    'section': 'BSIT-4A',
    'system_name': 'Hospital Management System',
    'year_level': '4th Year',
    'semester_label': '1st Semester 2026-2027',
    'team_count': 1,
    'students': [],
    'concept_contexts': [
      {
        'key': 'capstone:10',
        'label': 'Concept Proposal',
        'policy': {'mode': 'auto'},
        'teams': [
          {
            'id': 5,
            'name': 'Team MedRecord',
            'override': {'mode': 'auto'},
            'effective_policy': {
              'mode': 'assigned',
              'required_count': 1,
              'assigned_title': 'Patient Records',
            },
            'imported_assignment': {
              'mode': 'assigned',
              'assigned_title': 'Patient Records',
            },
            'has_submissions': true,
            'locked': false,
          },
        ],
      },
    ],
  };
  @override
  Future<bool> updateSectionDetails(
    int teamId,
    Map<String, dynamic> payload, {
    String? scope,
  }) async {
    saved = payload;
    return true;
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'section concept policies review before saving ${dark ? 'dark' : 'light'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(760, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts();
        final notifier = _PolicyNotifier();
        await pumpDefensysWidget(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const EditSectionDialog(teamId: 5),
              ),
              child: const Text('Open section'),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          overrides: [studentTeamsProvider.overrideWith(() => notifier)],
        );
        await tester.tap(find.text('Open section'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Concept Proposal'));
        await tester.tap(find.text('Concept Proposal'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Current: 1 concept'), findsOneWidget);
        await tester.ensureVisible(find.byType(WorkflowChoice).first);
        await tester.tap(find.byType(WorkflowChoice).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Require multiple proposals').last);
        await tester.pumpAndSettle();
        expect(find.text('3 concepts'), findsOneWidget);
        await capturePreview(
          tester,
          find
              .ancestor(
                of: find.byType(EditSectionDialog),
                matching: find.byType(RepaintBoundary),
              )
              .first,
          'concept-section-policy-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.byKey(const Key('save-section-details')));
        await tester.pumpAndSettle();
        expect(find.text('Review concept requirements'), findsOneWidget);
        expect(notifier.saved, isNull);
        await tester.tap(find.text('Apply reviewed changes'));
        await tester.pumpAndSettle();
        expect(notifier.saved?['confirm_concept_changes'], isTrue);
        final change =
            (notifier.saved!['concept_policy_changes'] as List).single as Map;
        expect(change['section_policy'], {
          'mode': 'proposals',
          'required_count': 3,
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'assigned concept title is visible and cannot be edited by the student',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 5,
            stageLabel: 'Concept Proposal',
            stage: {
              'concept_workflow': {
                'enabled': true,
                'assigned': true,
                'can_edit': true,
                'can_edit_titles': false,
                'status': 'concept_review_pending',
                'round': 1,
                'history': [],
                'concepts': [
                  {'key': 'c1', 'title': 'Patient Records'},
                ],
              },
            },
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Assigned concept review'), findsOneWidget);
      expect(find.text('Patient Records'), findsOneWidget);
      expect(find.text('Save concept titles'), findsNothing);
      expect(tester.widget<ShadInput>(find.byType(ShadInput)).enabled, isFalse);
    },
  );

  test(
    'automatic paper definition is idempotent and keeps custom settings',
    () {
      final items = <Map<String, dynamic>>[];
      ensureConceptPapers(items, {'enabled': true});
      final proposal = items.singleWhere(
        (d) => d['file_policy']['mode'] == 'concepts',
      );
      proposal['label'] = 'Department Concept Papers';
      ensureConceptPapers(items, {'enabled': true});
      expect(items, hasLength(2));
      expect(proposal['label'], 'Department Concept Papers');
      final approved = items.singleWhere(
        (d) => d['file_policy']['purpose'] == 'approved_concept',
      );
      expect(approved['required'], isTrue);
      expect(approved['deliverable_type'], 'post');
    },
  );
}
