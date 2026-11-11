import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/deliverable_submission_detail_modal.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/repository/deliverable_requirement_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _item = {
  'id': 'D3',
  'label': 'Prototype Source Code',
  'type': 'post',
  'required': true,
  'uploaded': false,
  'can_upload': true,
  'file_format': 'archive',
  'suggested_file_name': 'Project_PrototypeSourceCode.pdf',
};
const _team = {'id': 7, 'name': 'Team Prototype'};

class _Deliverables extends CapstoneDeliverablesNotifier {
  _Deliverables({this.item = _item});
  final Map<String, dynamic> item;
  final uploads = <({String filename, Uint8List bytes})>[];

  void changeStage() => state = state.copyWith(selectedStage: 'Other stage');

  @override
  CapstoneDeliverablesState build() => CapstoneDeliverablesState(
    selectedStage: 'Final Defense',
    stageOptions: const ['Final Defense'],
    teams: [
      {
        ..._team,
        'selected_stage': {
          'stage_label': 'Final Defense',
          'deliverables_configured': true,
          'vault_unlocked': true,
          'deliverables': [item],
        },
      },
    ],
  );

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
    uploads.add((filename: filename, bytes: bytes));
    return true;
  }
}

class _Picker extends FilePicker {
  String extension = 'zip';
  String? filename;

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
  }) async => FilePickerResult([
    PlatformFile(
      name: filename ?? 'Local source code.$extension',
      size: 16,
      bytes: Uint8List(16),
    ),
  ]);
}

Future<void> _openStudentUpload(
  WidgetTester tester,
  _Deliverables notifier, {
  bool isCapstone = true,
  bool dark = false,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    StudentDeliverablesTab(
      isCapstone: isCapstone,
      studentData: const {'year_level': '2'},
      hideHeader: true,
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
    overrides: [capstoneDeliverablesProvider.overrideWith(() => notifier)],
  );
  final card = find.byKey(
    ValueKey('student-requirement-${notifier.item['id']}'),
  );
  await tester.ensureVisible(card);
  await tester.tap(
    find.descendant(of: card, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FilePicker.platform = _Picker());

  test(
    'recommendations respect configured formats and compatible templates',
    () {
      for (final entry in {
        'archive': 'zip',
        'video': 'mp4',
        'image': 'png',
        'spreadsheet': 'xlsx',
        'audio': 'mp3',
        'pdf': 'pdf',
      }.entries) {
        final format = DeliverableFormatInfo.fromFormat(entry.key);
        expect(
          format.recommendedFileName('Project.pdf'),
          'Project.${entry.value}',
        );
        expect(format.recommendedFileName('Project'), 'Project.${entry.value}');
      }
      expect(
        DeliverableFormatInfo.fromFormat(
          'archive',
        ).recommendedFileName('Code.rar'),
        'Code.rar',
      );
      expect(
        DeliverableFormatInfo.fromFormat(
          'presentation',
        ).recommendedFileName('Slides.pdf'),
        'Slides.pdf',
      );
      expect(
        DeliverableFormatInfo.fromFormat('archive').recommendedFileName(''),
        isEmpty,
      );
    },
  );

  for (final isCapstone in [true, false]) {
    for (final extension in ['zip', 'rar', '7z']) {
      testWidgets(
        'student confirms $extension rename before upload capstone=$isCapstone',
        (tester) async {
          final picker = _Picker()..extension = extension;
          FilePicker.platform = picker;
          final notifier = _Deliverables();
          await _openStudentUpload(tester, notifier, isCapstone: isCapstone);
          expect(find.text('Filename will be adjusted'), findsOneWidget);
          expect(find.text('Local source code.$extension'), findsOneWidget);
          expect(
            find.text('Project_PrototypeSourceCode.$extension'),
            findsOneWidget,
          );
          expect(notifier.uploads, isEmpty);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(notifier.uploads, isEmpty);
          expect(find.byType(DeliverableRequirementDialog), findsOneWidget);
          // Cancelling must also release the picker guard for the next attempt.
          await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Rename and upload'));
          await tester.pumpAndSettle();
          expect(
            notifier.uploads.single.filename,
            'Project_PrototypeSourceCode.$extension',
          );
          expect(notifier.uploads.single.bytes, Uint8List(16));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scenario in ['matching name', 'pre', 'no recommendation']) {
    testWidgets('student skips rename confirmation for $scenario', (
      tester,
    ) async {
      final picker = _Picker();
      if (scenario == 'matching name') {
        picker.filename = 'Project_PrototypeSourceCode.zip';
      }
      FilePicker.platform = picker;
      final notifier = _Deliverables(
        item: {
          ..._item,
          if (scenario == 'pre') 'type': 'pre',
          if (scenario == 'no recommendation') 'suggested_file_name': '',
        },
      );
      await _openStudentUpload(tester, notifier);
      expect(find.text('Filename will be adjusted'), findsNothing);
      expect(
        notifier.uploads.single.filename,
        picker.filename ?? 'Local source code.zip',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'student cannot upload to a changed stage after rename confirmation',
    (tester) async {
      final notifier = _Deliverables();
      await _openStudentUpload(tester, notifier);
      notifier.changeStage();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename and upload'));
      await tester.pumpAndSettle();
      expect(notifier.uploads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('rename confirmation wraps long names on phone dark=$dark', (
      tester,
    ) async {
      const original =
          'Local_source_code_with_a_very_long_original_filename_for_the_final_project.7z';
      const target =
          '2026_BSIT_Team_Prototype_Final_Defense_Complete_Project_Source_Code.7z';
      FilePicker.platform = _Picker()..filename = original;
      final notifier = _Deliverables(
        item: {..._item, 'suggested_file_name': target},
      );
      await _openStudentUpload(tester, notifier, width: 320, dark: dark);
      expect(find.text(original), findsOneWidget);
      expect(find.text(target), findsOneWidget);
      expect(notifier.uploads, isEmpty);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(ShadDialog).last,
        'deliverable-rename-phone-${dark ? 'dark' : 'light'}',
        viewport: true,
      );
      // System Back also cancels rather than granting permission to upload.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Filename will be adjusted'), findsNothing);
      expect(notifier.uploads, isEmpty);
      expect(find.byType(DeliverableRequirementDialog), findsOneWidget);
    });
  }

  // The older shared dialog also supports changing a pending file and Copy.
  testWidgets(
    'shared upload recommendation and Copy follow archive selection',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPicker = FilePicker.platform;
      final picker = _Picker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = previousPicker);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpDefensysWidget(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showUploadDialog(
              context: context,
              ref: ref,
              team: _team,
              stageLabel: 'Final Defense',
              item: _item,
            ),
            child: const Text('Open upload'),
          ),
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
        ],
      );
      await tester.tap(find.text('Open upload'));
      await tester.pumpAndSettle();
      expect(find.text('Project_PrototypeSourceCode.zip'), findsOneWidget);
      expect(find.text('Project_PrototypeSourceCode.pdf'), findsNothing);

      for (final extension in ['zip', 'rar', '7z']) {
        picker.extension = extension;
        await tester.tap(
          extension == 'zip'
              ? find.text('Click to browse or drop your document here')
              : find.byTooltip('Change file'),
        );
        await tester.pumpAndSettle();
        final expected = 'Project_PrototypeSourceCode.$extension';
        expect(find.text(expected), findsOneWidget);
        expect(find.text('Project_PrototypeSourceCode.pdf'), findsNothing);
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(clipboard, expected);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Submit Deliverable'));
      await tester.pumpAndSettle();
      expect(find.text('Project_PrototypeSourceCode.7z'), findsNWidgets(2));
      expect(find.text('Project_PrototypeSourceCode.pdf'), findsNothing);
      // Inspect the proposed repository name without submitting any file.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
