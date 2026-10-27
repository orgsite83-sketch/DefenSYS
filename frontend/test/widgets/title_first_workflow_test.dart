import 'package:defensys/widgets/repository/title_review_card.dart';
import 'package:defensys/widgets/repository/concept_revision_dialog.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/concept_review_section.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';
import '../helpers/auth_test_overrides.dart';

Map<String, dynamic> title(String state, {bool student = false}) => {
  'key': 'c1',
  'title': 'Autonomous Soil Sensor & Dynamic Drip Irrigation Module',
  'system_title': 'Smart Agro-Industrial IoT & Sustainable Supply Platform',
  'title_review': {
    'state': state,
    'status_label': state == 'accepted'
        ? 'Title accepted'
        : state == 'submitted'
        ? 'Awaiting title review'
        : 'Awaiting student submission',
    'can_edit': student,
    'can_submit': student,
    'can_accept': !student && state == 'submitted',
    'can_request_revision':
        !student && (state == 'submitted' || state == 'accepted'),
  },
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final version in [1, 2]) {
    testWidgets(
      'deliverables hides duplicate title controls for workflow $version',
      (tester) async {
        await pumpDefensysWidget(
          tester,
          ConceptWorkspace(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            showTitleCard: false,
            stage: {
              'concept_workflow': {
                'enabled': true,
                'title_workflow_version': version,
                'section_project_id': 7,
                'concepts': [title('submitted')],
              },
            },
          ),
          overrides: authTestOverrides(),
        );
        expect(find.byType(TitleReviewCard), findsNothing);
        expect(find.text('Review shared systems'), findsNothing);
        expect(find.text('Concept 1'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('submitted title permits upload before adviser acceptance', (
    tester,
  ) async {
    for (final submitted in [false, true]) {
      final concept = title(submitted ? 'submitted' : 'draft');
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            focused: true,
            concepts: [concept],
            titleWorkflow: const {'title_workflow_version': 2},
            item: {
              'id': 'CONCEPTS',
              'label': 'Concept paper',
              'type': 'pre',
              'can_upload': true,
              'file_policy': {'mode': 'concepts'},
              'document_slots': [
                {
                  'key': 'c1:paper',
                  'label': 'Concept paper',
                  'required': true,
                  'upload_blocker': submitted
                      ? ''
                      : 'Submit this title in Team before uploading its file.',
                },
              ],
            },
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Upload'), submitted ? findsOneWidget : findsNothing);
      expect(
        find.text('Submit this title in Team before uploading its file.'),
        submitted ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'concept review previews files and reserves file decisions for By team',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final concept = title('submitted');
      final workflow = {
        'enabled': true,
        'title_workflow_version': 2,
        'round_id': 12,
        'module_review_token': 'current-title-version',
        'concepts': [concept],
      };
      final item = <String, dynamic>{
        'id': 'CONCEPTS',
        'label': 'Concept paper',
        'type': 'pre',
        'can_faculty_review': false,
        'file_policy': {'mode': 'concepts'},
        'document_slots': [
          {'key': 'c1:paper', 'label': 'Concept paper', 'required': true},
        ],
        'submission': {
          'files': [
            {
              'id': 18,
              'slot_key': 'c1:paper',
              'file_name': 'Team_AgriPulse_Concept_1.pdf',
              'revision': 1,
              'status': 'pending',
            },
          ],
        },
      };
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Team AgriPulse',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ConceptWorkspace(
                    teamId: 8,
                    stageLabel: 'Concept Proposal',
                    stage: {'concept_workflow': workflow},
                    onReviewFiles: (_) {},
                    paperBuilder: (_) => DocumentGroup(
                      teamId: 8,
                      stageLabel: 'Concept Proposal',
                      item: item,
                      focused: true,
                      framed: true,
                      showConceptContext: false,
                      concepts: [concept],
                      titleWorkflow: workflow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Accept module title'), findsOneWidget);
      expect(find.text('Team_AgriPulse_Concept_1.pdf'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Request revision'), findsNothing);
      expect(find.text('Next file'), findsNothing);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(ConceptWorkspace),
        'title-first-desktop',
        viewport: true,
      );
    },
  );

  testWidgets(
    'an open title request retains the version the adviser was reviewing',
    (tester) async {
      var version = 'original';
      late StateSetter refresh;
      final sent = <String>[];
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, update) {
            refresh = update;
            final snapshot = version;
            return DefensysShadcnScope(
              child: TitleReviewCard(
                concept: title('accepted'),
                onAction: (action, title, reason) async {
                  sent.add('$snapshot:$reason');
                  return true;
                },
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Request title revision'));
      await tester.pumpAndSettle();
      refresh(() => version = 'background-refresh');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText),
        'Reconsider this module.',
      );
      await tester.tap(find.text('Send revision request'));
      await tester.pumpAndSettle();
      expect(sent, ['original:Reconsider this module.']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'submitted title can be accepted without a paper; adviser cannot edit it',
    (tester) async {
      final actions = <String>[];
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: TitleReviewCard(
            concept: title('submitted'),
            onAction: (action, text, reason) async {
              actions.add(action);
              return true;
            },
          ),
        ),
      );
      expect(find.text('Accept module title'), findsOneWidget);
      expect(find.text('Request title revision'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('Accept module title'));
      await tester.pumpAndSettle();
      expect(actions, ['accept_title']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted title keeps revision available without a file and hands off to files',
    (tester) async {
      var opened = false;
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: ConceptReviewSection(
            onReviewFiles: () => opened = true,
            titleReview: TitleReviewCard(
              concept: title('accepted'),
              onAction: (_, _, _) async => true,
            ),
            deliverables: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('Request title revision'), findsOneWidget);
      await tester.tap(find.text('Review files'));
      expect(opened, isTrue);
      await tester.tap(find.text('Request title revision'));
      await tester.pumpAndSettle();
      expect(find.text('Paper only'), findsNothing);
      expect(find.text('Title and paper'), findsNothing);
      await tester.tap(find.text('Send revision request'));
      await tester.pumpAndSettle();
      expect(find.text('Explain what needs to change.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file revision defaults to paper only and can return both in one request',
    (tester) async {
      ConceptRevision? request;
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => request = await showConceptRevisionDialog(
              context,
              description: 'Concept_Paper.pdf · Revision 2',
              titleAvailable: true,
            ),
            child: const Text('Request revision'),
          ),
        ),
      );
      await tester.tap(find.text('Request revision'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'paper',
      );
      await tester.tap(find.text('Title and paper'));
      await tester.enterText(
        find.byType(EditableText),
        'Revise the module scope and its paper.',
      );
      await tester.tap(find.text('Send revision request'));
      await tester.pumpAndSettle();
      expect(request?.scope, 'title_and_paper');
      expect(request?.feedback, 'Revise the module scope and its paper.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('student submits the proposed title explicitly', (tester) async {
    String? action, proposed;
    await pumpDefensysWidget(
      tester,
      DefensysShadcnScope(
        child: TitleReviewCard(
          concept: title('draft', student: true),
          onAction: (value, text, reason) async {
            action = value;
            proposed = text;
            return true;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'Revised sensor module');
    await tester.tap(find.text('Submit module title'));
    await tester.pumpAndSettle();
    expect(action, 'submit_title');
    expect(proposed, 'Revised sensor module');
    expect(find.text('Accept module title'), findsNothing);
  });

  testWidgets(
    'title actions wrap at phone width and preserve the desktop style',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TitleReviewCard(
                concept: title('submitted'),
                onAction: (_, _, _) async => true,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(TitleReviewCard),
        'title-first-phone',
        viewport: true,
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets('nested title and files fit at 320px, dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = '';
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConceptWorkspace(
              teamId: 8,
              stageLabel: 'Concept Proposal',
              stage: {
                'concept_workflow': {
                  'enabled': true,
                  'title_workflow_version': 2,
                  'concepts': [title('accepted')],
                },
              },
              onReviewFiles: (key) => selected = key,
              paperBuilder: (_) => DocumentGroup(
                teamId: 8,
                stageLabel: 'Concept Proposal',
                focused: true,
                framed: true,
                showConceptContext: false,
                item: const {
                  'id': 'PAPER',
                  'label': 'Concept paper',
                  'file_policy': {'mode': 'concepts'},
                  'document_slots': [
                    {
                      'key': 'c1:paper',
                      'label': 'Concept paper',
                      'required': true,
                    },
                  ],
                  'submission': {
                    'files': [
                      {
                        'id': 18,
                        'slot_key': 'c1:paper',
                        'file_name': 'ColdChain_Concept_Paper.pdf',
                        'revision': 1,
                        'status': 'pending',
                      },
                    ],
                  },
                },
              ),
            ),
          ),
        ),
        overrides: authTestOverrides(),
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
      );
      expect(find.byType(ConceptReviewSection), findsOneWidget);
      expect(find.text('Title accepted'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      await tester.ensureVisible(find.text('Review files'));
      await tester.tap(find.text('Review files'));
      expect(selected, 'c1');
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(ConceptWorkspace),
        'nested-concept-320-${dark ? 'dark' : 'light'}',
        viewport: true,
      );
    });
  }
}
