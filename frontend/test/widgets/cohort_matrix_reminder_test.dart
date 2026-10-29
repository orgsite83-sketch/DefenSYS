import 'dart:async';
import 'dart:convert';

import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _team() => {
  'id': 7,
  'name': 'Team AgriPulse',
  'current_stage': 'Concept Proposal',
  'selected_stage': {
    'stage_label': 'Concept Proposal',
    'required_total': 2,
    'pre': [
      {
        'id': 'DECK',
        'label': 'Pitch Deck',
        'type': 'pre',
        'required': true,
        'can_upload': true,
        'file_policy': {'mode': 'named'},
        'document_slots': [
          for (var i = 1; i <= 3; i++)
            {
              'key': 'c$i:deck',
              'label': 'Concept $i · Pitch Deck',
              'required': true,
            },
        ],
        'submission': {
          'files': [
            {
              'id': 10,
              'slot_key': 'c1:deck',
              'file_name': 'concept_deck.pptx',
              'file_url': '/media/concept_deck.pptx',
              'status': 'rejected',
              'revision': 1,
            },
          ],
        },
      },
      {'id': 'FORM', 'label': 'Adviser Acceptance Form', 'required': true},
    ],
    'post': [
      {
        'id': 'FINAL',
        'label': 'Approved Concept Paper',
        'type': 'post',
        'required': true,
        'can_upload': true,
        'file_policy': {'mode': 'named'},
        'document_slots': [
          {'key': 'primary', 'label': 'Final paper', 'required': true},
        ],
      },
      {
        'id': 'ARCHIVE',
        'label': 'Project Archive',
        'type': 'post',
        'required': true,
        'can_upload': true,
        'file_policy': {'mode': 'multiple', 'min_files': 2, 'max_files': 5},
      },
    ],
  },
  'members': [],
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  tearDown(resetApiHttpClientForTesting);

  for (final dark in [false, true]) {
    testWidgets(
      'admin matrix offers reminders and no submission actions in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final requests = <http.Request>[];
        final response = Completer<http.Response>();
        setApiHttpClientForTesting(
          MockClient((request) {
            requests.add(request);
            return response.future;
          }),
        );
        final team = _team();
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: CohortSubmissionsMatrix(
              teams: [team],
              state: CapstoneDeliverablesState(
                selectedStage: 'Concept Proposal',
                teams: [team],
              ),
              isAdviser: false,
              initialExpandedTeamId: 7,
            ),
          ),
          overrides: authTestOverrides(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Remind'), findsNWidgets(5));
        expect(find.text('Upload'), findsNothing);
        expect(find.text('Upload revision'), findsNothing);
        expect(find.text('Add attachments'), findsNothing);
        expect(requests, isEmpty);
        await capturePreview(
          tester,
          find.byType(CohortSubmissionsMatrix),
          'matrix-reminders-${dark ? 'dark' : 'light'}',
          viewport: true,
        );

        final finalPaper = find.byWidgetPredicate(
          (widget) => widget is DocumentGroup && widget.item['id'] == 'FINAL',
        );
        final remind = find.descendant(
          of: finalPaper,
          matching: find.text('Remind'),
        );
        await tester.ensureVisible(remind);
        await tester.tap(remind);
        await tester.pump();
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.url.path, '/api/teams/7/remind/');
        expect(jsonDecode(requests.single.body), {
          'stage_label': 'Concept Proposal',
          'deliverable_id': 'FINAL',
        });
        final reminderButtons = tester.widgetList<ShadButton>(
          find.ancestor(
            of: find.text('Remind'),
            matching: find.byType(ShadButton),
          ),
        );
        expect(
          reminderButtons.every(
            (button) => !button.enabled || button.onPressed == null,
          ),
          isTrue,
        );
        response.complete(http.Response('{}', 200));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('concept_deck.pptx'));
        await tester.tap(find.text('concept_deck.pptx'));
        await tester.pumpAndSettle();
        expect(find.text('View Document'), findsOneWidget);
        expect(find.text('Replace File'), findsNothing);
        expect(find.text('Upload revision'), findsNothing);
        expect(find.text('Remove'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
