import 'dart:typed_data';

import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/deliverable_submission_detail_modal.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          'deliverables': [_item],
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
}

class _Picker extends FilePicker {
  String extension = 'zip';

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
      name: 'Local source code.$extension',
      size: 16,
      bytes: Uint8List(16),
    ),
  ]);
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

  for (final student in [true, false]) {
    testWidgets(
      '${student ? 'student' : 'shared'} upload recommendation and Copy follow archive selection',
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
          student
              ? const StudentDeliverablesTab(
                  isCapstone: true,
                  studentData: null,
                  hideHeader: true,
                )
              : Consumer(
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
        await tester.tap(
          find.text(student ? 'Upload Prototype Source Code' : 'Open upload'),
        );
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
}
