import 'dart:convert';
import 'dart:typed_data';

import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _StudentAuth extends TestAuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 7, 'role': 'student', 'username': 'student'},
  );
}

class _FacultyAuth extends TestAuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 8, 'role': 'faculty', 'username': 'reviewer'},
  );
}

class _FilesClient extends AuthenticatedHttpClient {
  _FilesClient(super.ref);
  @override
  Future<Uint8List> fetchAuthenticatedFile(String fileRef) async =>
      Uint8List.fromList(utf8.encode('The document body remains visible.'));
}

class _RevisionPicker extends FilePicker {
  int requests = 0;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    requests++;
    return FilePickerResult([
      PlatformFile(
        name: 'concept_revision.pdf',
        size: 4,
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    ]);
  }
}

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(size);
}

Map<String, dynamic> _single({String? status}) => {
  'id': 'PAPER',
  'label': 'Project poster',
  'type': 'pre',
  'required': true,
  'file_format': 'pdf',
  'file_policy': {'mode': 'single'},
  'document_slots': [
    {
      'key': 'primary',
      'label': 'Project poster',
      'file_format': 'pdf',
      'required': true,
    },
  ],
  'uploaded': status == 'accepted',
  'can_upload': status != 'accepted',
  'can_faculty_review': true,
  if (status != null)
    'submission': {
      'status': status,
      'file_name': 'poster.pdf',
      'file_url': '/media/poster.pdf',
      'file_size': '139.7 KB',
      'uploaded_by_name': 'Kyle Pineda',
      'uploaded_at': '2026-10-19T03:17:00Z',
      'feedback': status == 'rejected' ? 'Add the validation method.' : '',
      'files': [
        {
          'id': 10,
          'slot_key': 'primary',
          'status': status,
          'revision': 1,
          'file_name': 'poster.pdf',
          'file_url': '/media/poster.pdf',
          'file_size': '139.7 KB',
        },
      ],
    },
};

CapstoneDeliverablesState _state(
  Map<String, dynamic> item, {
  String scope = 'capstone',
}) {
  final stage = <String, dynamic>{
    'stage_label': 'System Concept Pitching',
    'status': 'pending',
    'endorsed': false,
    'deliverables_configured': true,
    'required_total': 1,
    'required_uploaded': item['uploaded'] == true ? 1 : 0,
    'required_complete': item['uploaded'] == true,
    'deliverables': [item],
    'pre': [item],
    'post': [],
  };
  return CapstoneDeliverablesState(
    scope: scope,
    selectedStage: 'System Concept Pitching',
    stageOptions: const ['System Concept Pitching'],
    teams: [
      {
        'id': 7,
        'name': 'Team AgriPulse',
        'year_level': '2nd Year',
        'project_title': 'Crop monitoring and farm records',
        'selected_stage': stage,
        'stages': [stage],
        'members': [],
      },
    ],
  );
}

class _FilesNotifier extends CapstoneDeliverablesNotifier {
  _FilesNotifier(this.initial);
  final CapstoneDeliverablesState initial;
  Map<String, dynamic>? removal;
  Map<String, dynamic>? upload;
  @override
  CapstoneDeliverablesState build() => initial;
  @override
  Future<bool> removeDeliverable(Map<String, dynamic> payload) async {
    removal = payload;
    return true;
  }

  @override
  Future<bool> uploadDocument({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String slotKey,
    required String filename,
    required Uint8List bytes,
    int? fileId,
  }) async {
    upload = {
      'team_id': teamId,
      'stage_label': stageLabel,
      'deliverable_id': deliverableId,
      'slot_key': slotKey,
      'file_id': fileId,
      'filename': filename,
      'bytes': bytes,
    };
    return true;
  }

  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

Map<String, dynamic> _conceptFiles(List<String?> statuses) => {
  'id': 'CONCEPTS',
  'label': 'Concept Papers',
  'type': 'pre',
  'required': true,
  'can_upload': true,
  'can_faculty_review': true,
  'file_format': 'pdf',
  'file_policy': {'mode': 'concepts'},
  'document_slots': [
    for (var i = 0; i < 3; i++)
      {
        'key': 'c${i + 1}',
        'label': 'Concept ${i + 1} · Concept paper',
        'required': true,
        'file_format': 'pdf',
      },
  ],
  'submission': {
    'files': [
      for (var i = 0; i < statuses.length; i++)
        if (statuses[i] != null)
          {
            'id': 10 + i,
            'slot_key': 'c${i + 1}',
            'file_name': 'AgriPulse_Concept_${i + 1}.pdf',
            'file_size': '139.7 KB',
            'file_url': '/media/concept_${i + 1}.pdf',
            'uploaded_by_name': 'Kyle Pineda',
            'uploaded_at': '2026-10-19T03:17:00Z',
            'revision': 1,
            'status': statuses[i],
            if (statuses[i] == 'rejected')
              'feedback': 'Clarify the validation method.',
          },
    ],
  },
};

void main() {
  setUp(() => FilePicker.platform = _RevisionPicker());
  for (final dark in [false, true]) {
    testWidgets(
      'single-file policy retains the original student upload card in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _surface(tester, const Size(390, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('file-card-preview'),
            child: const StudentDeliverablesTab(
              isCapstone: true,
              studentData: null,
              hideHeader: true,
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [
            capstoneDeliverablesProvider.overrideWith(
              () => _FilesNotifier(_state(_single())),
            ),
            authProvider.overrideWith(_StudentAuth.new),
          ],
        );
        expect(find.byType(DocumentGroup), findsNothing);
        expect(find.text('Upload Project poster'), findsOneWidget);
        expect(find.text('Action Required'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_upload_rounded), findsNothing);
        final upload = find.byType(DeliverableUploadTile);
        final container = tester.widget<Container>(
          find.descendant(of: upload, matching: find.byType(Container)).first,
        );
        final context = tester.element(upload);
        expect(
          (container.decoration as BoxDecoration).color,
          DefensysTokens.panelOf(context),
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('file-card-preview')),
          'student-single-file-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  testWidgets(
    'a rejected single-file submission remains available in details even when readiness is false',
    (tester) async {
      await _surface(tester, const Size(440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      await pumpDefensysWidget(
        tester,
        const StudentDeliverablesTab(
          isCapstone: true,
          studentData: null,
          hideHeader: true,
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => _FilesNotifier(_state(_single(status: 'rejected'))),
          ),
        ],
      );
      expect(find.text('poster.pdf'), findsOneWidget);
      expect(find.textContaining('Add the validation method.'), findsOneWidget);
      await tester.tap(find.text('poster.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('FILE PROPERTIES & INFO'), findsOneWidget);
      expect(find.text('Kyle Pineda'), findsOneWidget);
      expect(find.text('View Document'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DeliverableDetailsActions),
          matching: find.text('Upload revision'),
        ),
        findsOneWidget,
      );
      expect(find.text('Replace File'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'faculty single-file cards keep neutral surfaces and expose details beside the viewer',
    (tester) async {
      await _surface(tester, const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      final state = _state(_single(status: 'accepted'), scope: 'pit');
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('faculty-files-preview'),
          child: DeliverablesTablePane(
            state: state,
            isAdviser: true,
            initialTeamId: 7,
          ),
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => _FilesNotifier(state),
          ),
          ...authTestOverrides(),
        ],
      );
      expect(find.byType(DocumentGroup), findsNothing);
      expect(find.text('poster.pdf'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      final reviewAction = tester.getRect(
        find
            .ancestor(
              of: find.text('Request corrections'),
              matching: find.byType(ShadButton),
            )
            .first,
      );
      final fileRow = tester.getRect(
        find
            .ancestor(
              of: find.text('poster.pdf'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(reviewAction.right, closeTo(fileRow.right, 1));
      expect(reviewAction.top, greaterThan(fileRow.bottom));
      final cards = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('Accepted'),
          matching: find.byType(Container),
        ),
      );
      expect(
        cards
            .where((card) => card.decoration is BoxDecoration)
            .map((card) => (card.decoration as BoxDecoration).color),
        contains(DefensysTokens.surface),
      );
      await capturePreview(
        tester,
        find.byKey(const ValueKey('faculty-files-preview')),
        'faculty-single-file',
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Kyle Pineda'), findsOneWidget);
      expect(find.text('View Document'), findsOneWidget);
      expect(find.text('Event'), findsOneWidget);
      expect(find.text('Location / Stage'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grouped files show the slot format before upload and actual extension after upload',
    (tester) async {
      await _surface(tester, const Size(390, 1150));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      final item = {
        'id': 'FILES',
        'label': 'Project files',
        'type': 'pre',
        'required': true,
        'can_upload': true,
        'can_faculty_review': true,
        'file_format': 'any',
        'file_policy': {'mode': 'named'},
        'document_slots': [
          {
            'key': 'paper',
            'label': 'Concept paper',
            'required': true,
            'file_format': 'document',
          },
          {
            'key': 'poster',
            'label': 'Project poster',
            'required': true,
            'file_format': 'pdf',
          },
          {
            'key': 'deck',
            'label': 'Pitch deck',
            'required': true,
            'file_format': 'presentation',
          },
        ],
        'submission': {
          'uploaded_by_name': 'Kyle Pineda',
          'files': [
            {
              'id': 11,
              'slot_key': 'paper',
              'file_name': 'concept.docx',
              'file_size': '121 KB',
              'file_url': '/media/concept.docx',
              'uploaded_at': '2026-10-19T03:17:00Z',
              'revision': 2,
              'status': 'pending',
            },
          ],
        },
      };
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('grouped-files-preview'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DocumentGroup(
              teamId: 7,
              stageLabel: 'System Concept Pitching',
              item: item,
            ),
          ),
        ),
        overrides: [authProvider.overrideWith(_StudentAuth.new)],
      );
      expect(find.text('DOCX'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('PPT'), findsOneWidget);
      expect(find.text('Upload'), findsNWidgets(2));
      expect(find.text('Accept'), findsNothing);
      expect(find.byType(DeliverableUploadedFileTile), findsOneWidget);
      expect(find.text('Upload revision'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('1/3 Uploaded'), findsOneWidget);
      expect(find.text('3 required files'), findsOneWidget);
      expect(find.textContaining('Uploaded by Kyle Pineda'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('grouped-files-preview')),
        'grouped-file-formats',
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Kyle Pineda'), findsOneWidget);
      expect(find.text('121 KB'), findsOneWidget);
      expect(find.text('View Document'), findsOneWidget);
      expect(find.text('Replace File'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the document viewer renders the file without repeating details metadata',
    (tester) async {
      await _surface(tester, const Size(390, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => viewFileInDialog(
              context: context,
              fileUrl: '/media/notes.txt',
              fileName: 'notes.txt',
              propertiesInfo: const DeliverablePropertiesInfo(
                fileSize: '59.8 KB',
                uploader: 'Kyle Pineda',
                timestamp: 'Oct 19, 2026',
              ),
            ),
            child: const Text('View file'),
          ),
        ),
        overrides: [
          authenticatedHttpClientProvider.overrideWith(_FilesClient.new),
        ],
      );
      await tester.tap(find.text('View file'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The document body remains visible.'),
        findsOneWidget,
      );
      expect(find.text('FILE PROPERTIES & INFO'), findsNothing);
      expect(find.text('Kyle Pineda'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('View file'), findsOneWidget);
    },
  );

  for (final scenario in [
    (
      states: <String?>[null, null, null],
      badge: '0/3 Uploaded',
      progress: '3 required files',
    ),
    (
      states: <String?>['pending', null, null],
      badge: '1/3 Uploaded',
      progress: '3 required files',
    ),
    (
      states: <String?>['rejected', null, null],
      badge: '1/3 Uploaded',
      progress: '3 required files',
    ),
    (
      states: <String?>['pending', 'pending', 'pending'],
      badge: 'Under Review',
      progress: '3/3 uploaded',
    ),
    (
      states: <String?>['accepted', 'accepted', 'accepted'],
      badge: 'Accepted',
      progress: '3/3 uploaded',
    ),
    (
      states: <String?>['rejected', 'accepted', 'accepted'],
      badge: 'Corrections requested',
      progress: '3/3 uploaded',
    ),
  ]) {
    testWidgets(
      'group status ${scenario.badge} keeps upload progress ${scenario.progress}',
      (tester) async {
        await _surface(tester, const Size(390, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DocumentGroup(
              teamId: 7,
              stageLabel: 'System Concept Pitching',
              item: _conceptFiles(scenario.states),
            ),
          ),
          overrides: [authProvider.overrideWith(_StudentAuth.new)],
        );
        expect(
          find.text(scenario.badge),
          scenario.badge == 'Corrections requested'
              ? findsNWidgets(2)
              : findsOneWidget,
        );
        expect(find.text(scenario.progress), findsOneWidget);
        expect(
          find.text('Upload revision'),
          scenario.states.contains('rejected') ? findsOneWidget : findsNothing,
        );
        expect(find.text('Remove'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'grouped uploaded tiles match the single-file style at phone width in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _surface(tester, const Size(390, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('grouped-single-style'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: DocumentGroup(
                teamId: 7,
                stageLabel: 'System Concept Pitching',
                item: _conceptFiles(['pending', null, null]),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [authProvider.overrideWith(_StudentAuth.new)],
        );
        expect(find.byType(DeliverableUploadedFileTile), findsOneWidget);
        expect(find.text('PDF Document'), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
        expect(find.textContaining('Uploaded by Kyle Pineda'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('grouped-single-style')),
          'grouped-single-style-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  testWidgets('optional attachments cannot hide missing required slots', (
    tester,
  ) async {
    await _surface(tester, const Size(440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await loadPreviewFonts(force: true);
    final item = _conceptFiles(['accepted', null, null]);
    final slots = item['document_slots'] as List;
    final files = (item['submission'] as Map)['files'] as List;
    for (var i = 1; i <= 2; i++) {
      slots.add({
        'key': 'optional$i',
        'label': 'Supporting file $i',
        'required': false,
        'file_format': 'pdf',
      });
      files.add({
        ...Map<String, dynamic>.from(files.first as Map),
        'id': 20 + i,
        'slot_key': 'optional$i',
        'file_name': 'supporting_$i.pdf',
      });
    }
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DocumentGroup(
          teamId: 7,
          stageLabel: 'System Concept Pitching',
          item: item,
        ),
      ),
      overrides: [authProvider.overrideWith(_StudentAuth.new)],
    );
    expect(find.text('3 required files'), findsOneWidget);
    expect(find.text('1/3 Uploaded'), findsOneWidget);
    expect(find.text('Accepted'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing through Details still targets the selected grouped file',
    (tester) async {
      await _surface(tester, const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      final item = _conceptFiles(['pending', null, null]);
      final notifier = _FilesNotifier(_state(item));
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 7,
            stageLabel: 'System Concept Pitching',
            item: item,
          ),
        ),
        overrides: [
          authProvider.overrideWith(_StudentAuth.new),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(find.text('Remove'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Replace File'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove'));
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(notifier.removal, {
        'team_id': 7,
        'stage_label': 'System Concept Pitching',
        'deliverable_id': 'CONCEPTS',
        'file_id': 10,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'faculty keeps review controls and cannot replace or remove files from Details',
    (tester) async {
      await _surface(tester, const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 7,
            stageLabel: 'System Concept Pitching',
            item: _conceptFiles(['pending', null, null]),
          ),
        ),
        overrides: [authProvider.overrideWith(_FacultyAuth.new)],
      );
      expect(find.text('1/3 Uploaded'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Upload'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Upload revision'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('View Document'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'faculty statuses and review actions align right at $width in dark=$dark',
        (tester) async {
          await _surface(tester, Size(width, 1100));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await loadPreviewFonts(force: true);
          await pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: const ValueKey('faculty-group-spacing'),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DocumentGroup(
                  teamId: 7,
                  stageLabel: 'System Concept Pitching',
                  item: _conceptFiles(['rejected', null, null]),
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: [authProvider.overrideWith(_FacultyAuth.new)],
          );
          final group = tester.getRect(find.byType(DocumentGroup));
          final statuses = find.byType(DeliverableStatusBadge);
          final file = tester.getRect(find.byType(DeliverableUploadedFileTile));
          expect(
            tester.getRect(statuses.at(0)).right,
            closeTo(group.right - 15, 1),
          );
          expect(tester.getRect(statuses.at(1)).right, closeTo(file.right, 1));
          final actions = find
              .ancestor(
                of: find.text('Request revision'),
                matching: find.byType(Wrap),
              )
              .first;
          final action = tester.getRect(actions);
          final feedback = tester.getRect(find.textContaining('Feedback:'));
          expect(action.right, closeTo(file.right, 1));
          expect(action.top, greaterThanOrEqualTo(feedback.bottom + 12));
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('faculty-group-spacing')),
            'faculty-group-spacing-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }

  for (final scenario in [
    (status: 'pending', scope: 'pit', label: 'Replace File'),
    (status: 'rejected', scope: 'capstone', label: 'Upload revision'),
  ]) {
    for (final width in [320.0, 1000.0]) {
      testWidgets(
        'details use ${scenario.label} and ${scenario.scope} context at $width',
        (tester) async {
          await _surface(tester, Size(width, 1100));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await loadPreviewFonts(force: true);
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: DocumentGroup(
                teamId: 7,
                stageLabel: 'System Concept Pitching',
                programScope: scenario.scope,
                item: _conceptFiles([scenario.status, null, null]),
              ),
            ),
            overrides: [authProvider.overrideWith(_StudentAuth.new)],
          );
          await tester.tap(find.text('AgriPulse_Concept_1.pdf'));
          await tester.pumpAndSettle();
          expect(
            find.text(scenario.scope == 'pit' ? 'Event' : 'Stage'),
            findsOneWidget,
          );
          expect(find.text('Location / Stage'), findsNothing);
          expect(
            find.descendant(
              of: find.byType(DeliverableDetailsActions),
              matching: find.text(scenario.label),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              scenario.label == 'Replace File'
                  ? 'Upload revision'
                  : 'Replace File',
            ),
            findsNothing,
          );
          final replace = tester.getRect(
            find.descendant(
              of: find.byType(DeliverableDetailsActions),
              matching: find.widgetWithText(OutlinedButton, scenario.label),
            ),
          );
          final remove = tester.getRect(
            find.widgetWithText(OutlinedButton, 'Remove'),
          );
          final view = tester.getRect(
            find
                .ancestor(
                  of: find.text('View Document'),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is FilledButton,
                  ),
                )
                .first,
          );
          expect(replace.height, remove.height);
          expect(replace.height, view.height);
          expect(replace.width, closeTo(remove.width, 1));
          expect(replace.left, view.left);
          expect(remove.right, view.right);
          expect(replace.top, greaterThanOrEqualTo(view.bottom + 10));
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find
                .ancestor(
                  of: find.byType(DeliverableDetailsActions),
                  matching: find.byType(RepaintBoundary),
                )
                .first,
            'file-details-${scenario.status}-${width.toInt()}',
          );
        },
      );
    }
  }

  testWidgets(
    'PIT single-file details use Event and Replace File before corrections',
    (tester) async {
      await _surface(tester, const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      await pumpDefensysWidget(
        tester,
        const StudentDeliverablesTab(
          isCapstone: false,
          studentData: null,
          hideHeader: true,
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => _FilesNotifier(
              _state(_single(status: 'pending'), scope: 'pit'),
            ),
          ),
          authProvider.overrideWith(_StudentAuth.new),
        ],
      );
      await tester.tap(find.text('poster.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Event'), findsOneWidget);
      expect(find.text('Location / Stage'), findsNothing);
      expect(find.text('Replace File'), findsOneWidget);
      expect(find.text('Upload revision'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (
      faculty: false,
      canUpload: true,
      status: 'rejected',
      dark: false,
      width: 320.0,
    ),
    (
      faculty: false,
      canUpload: true,
      status: 'Needs Revision',
      dark: true,
      width: 320.0,
    ),
    (
      faculty: false,
      canUpload: true,
      status: 'rejected',
      dark: false,
      width: 390.0,
    ),
    (
      faculty: false,
      canUpload: true,
      status: 'Needs Revision',
      dark: true,
      width: 390.0,
    ),
    (
      faculty: false,
      canUpload: false,
      status: 'rejected',
      dark: false,
      width: 320.0,
    ),
    (
      faculty: true,
      canUpload: true,
      status: 'rejected',
      dark: false,
      width: 320.0,
    ),
  ]) {
    testWidgets('revision shortcut obeys upload ownership and locks: $scenario', (
      tester,
    ) async {
      await _surface(tester, Size(scenario.width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts(force: true);
      final item = _conceptFiles([scenario.status, null, null]);
      item['can_upload'] = scenario.canUpload;
      final notifier = _FilesNotifier(_state(item));
      final picker = _RevisionPicker();
      final originalPicker = FilePicker.platform;
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = originalPicker);
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('revision-card'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DocumentGroup(
              teamId: 7,
              stageLabel: 'System Concept Pitching',
              item: item,
            ),
          ),
        ),
        theme: scenario.dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        overrides: [
          authProvider.overrideWith(
            scenario.faculty ? _FacultyAuth.new : _StudentAuth.new,
          ),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(find.text('1/3 Uploaded'), findsOneWidget);
      expect(find.text('Corrections requested'), findsOneWidget);
      final canRevise = !scenario.faculty && scenario.canUpload;
      final fileType = tester.getRect(find.text('PDF Document'));
      expect(fileType.height, lessThan(20));
      expect(
        find.text('Upload revision'),
        canRevise ? findsOneWidget : findsNothing,
      );
      if (canRevise) {
        expect(find.text('Details'), findsNothing);
        final revision = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Upload revision'),
        );
        if (scenario.width == 320) {
          expect(
            tester.getSize(find.text('AgriPulse_Concept_1.pdf')).width,
            greaterThan(120),
          );
          expect(revision.top, greaterThan(fileType.bottom));
        } else {
          expect(revision.top, lessThan(fileType.bottom));
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('revision-card')),
          'student-revision-card-${scenario.width.toInt()}-${scenario.dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Upload revision'));
        await tester.pumpAndSettle();
        expect(picker.requests, 1);
        expect(notifier.upload, {
          'team_id': 7,
          'stage_label': 'System Concept Pitching',
          'deliverable_id': 'CONCEPTS',
          'slot_key': 'c1',
          'file_id': 10,
          'filename': 'concept_revision.pdf',
          'bytes': [37, 80, 68, 70],
        });
      } else {
        expect(find.text('Details'), findsOneWidget);
        expect(picker.requests, 0);
        expect(notifier.upload, isNull);
      }
      await tester.tap(find.text('AgriPulse_Concept_1.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('View Document'), findsOneWidget);
      expect(find.text('Kyle Pineda'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DeliverableDetailsActions),
          matching: find.text('Upload revision'),
        ),
        canRevise ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
