import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/shared_deliverables_editor.dart';
import 'package:defensys/widgets/repository/shared_deliverables_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _document(
  String key,
  String label, {
  String system = '',
}) => {
  'key': key,
  'label': label,
  'system_key': system,
  'file_format': 'pdf',
  'max_file_size': 50 * 1024 * 1024,
  'required': true,
  'can_upload': true,
  'can_review': false,
};

Map<String, dynamic> _group() => {
  'team_id': 1,
  'section': 'BSIT-3A',
  'stage_label': 'Concept Proposal',
  'project_manager_name': 'Gabriel Navarro',
  'systems': [
    {'key': 'c1', 'title': 'Smart Agricultural Supply Platform'},
    {'key': 'c2', 'title': 'Campus Resource Management'},
  ],
  'requirements': [
    {
      'deliverable_id': 'FORM',
      'label': 'Approved Concept Hearing Form',
      'required': true,
      'deliverable_type': 'pre',
      'status': 'missing',
      'file_policy': {'mode': 'single'},
      'documents': [_document('primary', 'Approved Concept Hearing Form')],
    },
    {
      'deliverable_id': 'PAPERS',
      'label': 'Concept paper',
      'required': true,
      'deliverable_type': 'pre',
      'status': 'missing',
      'file_policy': {'mode': 'concepts'},
      'documents': [
        _document('c1:paper', 'Concept paper', system: 'c1'),
        _document('c2:paper', 'Concept paper', system: 'c2'),
      ],
    },
    {
      'deliverable_id': 'DECK',
      'label': 'Pitch deck',
      'required': false,
      'deliverable_type': 'pre',
      'status': 'missing',
      'file_policy': {'mode': 'concepts'},
      'documents': [
        _document('c1:deck', 'Pitch deck', system: 'c1'),
        _document('c2:deck', 'Pitch deck', system: 'c2'),
      ],
    },
  ],
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets(
    'shared setup is visible, copies requirements, and keeps its settings independent',
    (tester) async {
      var rows = <Map<String, dynamic>>[];
      final team = <Map<String, dynamic>>[
        {
          'deliverable_id': 'D1',
          'label': 'Section endorsement',
          'deliverable_type': 'pre',
          'required': true,
          'file_format': 'pdf',
          'file_policy': {'mode': 'single'},
        },
      ];
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, update) => SingleChildScrollView(
            child: SharedDeliverablesEditor(
              value: rows,
              teamDeliverables: team,
              deliverableType: 'pre',
              conceptsEnabled: true,
              onChanged: (value) => update(() => rows = value),
            ),
          ),
        ),
      );
      expect(find.text('Whole shared system deliverables'), findsOneWidget);
      expect(
        find.text('No shared system deliverables configured.'),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('Add shared system deliverable'), findsOneWidget);
      expect(find.text('Copy team checklist'), findsOneWidget);
      await tester.tap(find.text('Copy team checklist'));
      await tester.pumpAndSettle();
      expect(rows.single['label'], 'Section endorsement');
      expect(rows.single['deliverable_id'], startsWith('SHARED_'));
      await tester.enterText(
        find.byType(TextFormField).first,
        'Shared endorsement',
      );
      expect(rows.single['label'], 'Shared endorsement');
      expect(team.single['label'], 'Section endorsement');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('post-defense has its own visible shared checklist', (
    tester,
  ) async {
    final rows = defaultSharedDeliverables();
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: SharedDeliverablesEditor(
          value: rows,
          teamDeliverables: const [],
          deliverableType: 'post',
          conceptsEnabled: true,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Whole shared system deliverables'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.tap(find.text('Approved concept paper').last);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Approved concept paper'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Concept papers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(760, 1100), const Size(360, 1000)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'PM upload cards support mixed scopes at ${size.width} ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts();
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SharedDeliverablesPanel(group: _group()),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          expect(
            find.text('Upload Approved Concept Hearing Form'),
            findsOneWidget,
          );
          expect(find.text('Upload Concept paper'), findsOneWidget);
          expect(find.text('Upload Pitch deck'), findsOneWidget);
          expect(find.text('Awaiting PM upload'), findsNWidgets(3));
          await tester.tap(find.text('System 2'));
          await tester.pumpAndSettle();
          expect(find.text('Campus Resource Management'), findsOneWidget);
          expect(
            find.text('Upload Approved Concept Hearing Form'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(SharedDeliverablesPanel),
            'shared-pm-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        },
      );
    }
  }

  test('shared readiness remains separate from an endorsed team', () {
    final status = TeamWorkflowStatus.fromStage({
      'deliverables_configured': true,
      'endorsed': true,
      'shared_deliverables_summary': {'pre_complete': false},
    });
    expect(status.code, 'shared_clearance_pending');
  });

  for (final dark in [false, true]) {
    for (final width in [1100.0, 390.0]) {
      testWidgets(
        'accepted shared archive file has details but no revision controls ($width, $dark)',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts();
          final group = _group()..['selected_key'] = 'c1';
          group['requirements'] = [
            {
              'deliverable_id': 'FINAL',
              'label': 'Approved concept paper',
              'deliverable_type': 'post',
              'file_format': 'pdf',
              'required': true,
              'status': 'accepted',
              'file_policy': {'mode': 'single'},
              'documents': [
                {
                  ..._document('primary', 'Approved concept paper'),
                  // Old or stale API permissions must not reopen an accepted archive.
                  'can_upload': true, 'can_review': true,
                  'suggested_file_name': 'SmartAgriculturalSupplyPlatform.pdf',
                  'file': {
                    'id': 21,
                    'file_name': 'Approved_Shared_Paper.pdf',
                    'revision': 1,
                    'status': 'accepted',
                    'file_url': '/protected/shared-final.pdf',
                  },
                },
              ],
            },
          ];
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SharedDeliverablesPanel(group: group),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          expect(find.text('Accepted & archived'), findsOneWidget);
          expect(find.text('Revision 1 · Archived'), findsOneWidget);
          expect(find.text('Request revision'), findsNothing);
          expect(find.text('Upload revision'), findsNothing);
          expect(find.text('Accept file'), findsNothing);
          expect(find.text('Details'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(SharedDeliverablesPanel),
            'shared-archived-readonly-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final dark in [false, true]) {
    for (final width in [1100.0, 390.0]) {
      testWidgets(
        'selected system owns the final paper and alternatives stay in history ($width, $dark)',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts();
          final group = _group()..['selected_key'] = 'c2';
          (group['requirements'] as List).add({
            'deliverable_id': 'FINAL',
            'label': 'Approved shared concept paper',
            'deliverable_type': 'post',
            'required': true,
            'status': 'missing',
            'file_policy': {'mode': 'single'},
            'documents': [
              _document('primary', 'Approved shared concept paper')
                ..['can_upload'] = false,
            ],
          });
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SharedDeliverablesPanel(group: group),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          expect(find.text('Selected section system'), findsOneWidget);
          expect(find.text('Smart Agricultural Supply Platform'), findsNothing);
          expect(
            find.text('Upload Approved shared concept paper'),
            findsOneWidget,
          );
          expect(find.text('System 1'), findsNothing);
          expect(find.text('Earlier proposals (1)'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(SharedDeliverablesPanel),
            'shared-selected-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.ensureVisible(find.text('Earlier proposals (1)'));
          await tester.tap(find.text('Earlier proposals (1)'));
          await tester.pumpAndSettle();
          expect(
            find.text('Smart Agricultural Supply Platform'),
            findsOneWidget,
          );
          expect(
            find.text('Upload Approved shared concept paper'),
            findsOneWidget,
          );
          expect(find.text('Back to selected system'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('accepted team modules identify the outstanding PM upload', () {
    final status = TeamWorkflowStatus.fromStage({
      'deliverables_configured': true,
      'has_done_schedule': true,
      'archive_complete': false,
      'assessment_progress': {
        'panel_complete': true,
        'display_status': 'pending_post_defense',
      },
      'post_defense_completion': {
        'team_complete': true,
        'shared_complete': false,
        'shared': {'status': 'awaiting_pm_upload'},
      },
    });
    expect(status.code, 'awaiting_pm_upload');
    expect(status.nextStep, contains('project manager'));
  });

  testWidgets(
    'selected per-system final stays visible while browsing earlier proposals',
    (tester) async {
      final group = _group()..['selected_key'] = 'c2';
      (group['requirements'] as List).add({
        'deliverable_id': 'FINAL',
        'label': 'Selected shared paper',
        'deliverable_type': 'post',
        'required': true,
        'status': 'missing',
        'file_policy': {'mode': 'concepts'},
        'documents': [
          _document('c2:paper', 'Selected shared paper', system: 'c2'),
        ],
      });
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(child: SharedDeliverablesPanel(group: group)),
      );
      expect(find.text('Upload Selected shared paper'), findsOneWidget);
      await tester.ensureVisible(find.text('Earlier proposals (1)'));
      await tester.tap(find.text('Earlier proposals (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Upload Selected shared paper'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
