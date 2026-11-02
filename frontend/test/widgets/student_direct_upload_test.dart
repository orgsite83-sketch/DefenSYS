import 'dart:async';
import 'dart:typed_data';

import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/file_picker.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Deliverables extends CapstoneDeliverablesNotifier {
  _Deliverables(this.item);
  final Map<String, dynamic> item;
  final uploads = <Map<String, dynamic>>[];
  Completer<bool>? pending;

  @override
  CapstoneDeliverablesState build() => CapstoneDeliverablesState(
    selectedStage: 'Proposal',
    stageOptions: const ['Proposal'],
    teams: [
      {
        'id': 7,
        'name': 'Team AgriPulse',
        'semester_id': 1,
        'project_version': 1,
        'selected_stage': {
          'stage_label': 'Proposal',
          'deliverables_configured': true,
          'post_unlocked': true,
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
    uploads.add({
      'team': teamId,
      'stage': stageLabel,
      'deliverable': deliverableId,
      'filename': filename,
      'bytes': bytes,
    });
    state = state.copyWith(isSaving: true);
    final ok = await (pending?.future ?? Future.value(true));
    state = state.copyWith(
      isSaving: false,
      error: ok ? null : 'Please retry the upload.',
    );
    return ok;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Deliverables notifier, {
  double width = 900,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    const StudentDeliverablesTab(
      isCapstone: true,
      studentData: null,
      hideHeader: true,
    ),
    overrides: [capstoneDeliverablesProvider.overrideWith(() => notifier)],
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
  );
  await tester.tap(find.text('Manage files'));
  await tester.pumpAndSettle();
}

void main() {
  FilePicker.platform = TestFilePicker();
  late TestFilePicker picker;
  late FilePicker previous;
  setUp(() {
    previous = FilePicker.platform;
    FilePicker.platform = picker = TestFilePicker();
  });
  tearDown(() => FilePicker.platform = previous);

  for (final format in ['any', 'pdf', 'archive']) {
    testWidgets('$format selects and uploads directly in the requirement', (
      tester,
    ) async {
      final extension = format == 'any'
          ? 'docx'
          : format == 'pdf'
          ? 'pdf'
          : '7z';
      final bytes = Uint8List.fromList([1, 2, 3]);
      picker.result = FilePickerResult([
        PlatformFile(
          name: 'Selected.$extension',
          size: bytes.length,
          bytes: bytes,
        ),
      ]);
      final notifier = _Deliverables({
        'id': 'D1',
        'label': 'Adviser Acceptance Form',
        'type': format == 'archive' ? 'post' : 'pre',
        'required': true,
        'can_upload': true,
        'file_format': format,
        if (format == 'archive') 'suggested_file_name': 'Project_Source.pdf',
      })..pending = Completer<bool>();
      await _open(
        tester,
        notifier,
        width: format == 'archive'
            ? 320
            : format == 'any'
            ? 390
            : 900,
        dark: format == 'archive',
      );
      await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
      await tester.pump();
      expect(picker.calls, 1);
      expect(picker.multiple, isFalse);
      expect(picker.type, format == 'any' ? FileType.any : FileType.custom);
      expect(picker.extensions, format == 'any' ? isNull : contains(extension));
      expect(notifier.uploads, hasLength(1));
      expect(notifier.uploads.single, containsPair('team', 7));
      expect(notifier.uploads.single, containsPair('stage', 'Proposal'));
      expect(notifier.uploads.single, containsPair('deliverable', 'D1'));
      expect(notifier.uploads.single['bytes'], bytes);
      expect(
        notifier.uploads.single['filename'],
        format == 'archive' ? 'Project_Source.7z' : 'Selected.$extension',
      );
      expect(find.text('Submit Deliverable'), findsNothing);
      expect(
        find.text('Click to browse or drop your document here'),
        findsNothing,
      );
      expect(find.text('Uploading...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await capturePreview(
        tester,
        find.byType(Scaffold),
        'direct-upload-$format',
        viewport: true,
      );
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Upload'))
            .enabled,
        isFalse,
      );
      notifier.pending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Uploading...'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancel, validation and failed upload keep the requirement usable',
    (tester) async {
      final notifier = _Deliverables({
        'id': 'D1',
        'label': 'Adviser Acceptance Form',
        'type': 'pre',
        'required': true,
        'can_upload': true,
        'file_format': 'pdf',
        'max_file_size': 10,
      });
      await _open(tester, notifier);
      await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(notifier.uploads, isEmpty);
      for (final file in [
        PlatformFile(name: 'Empty.pdf', size: 0, bytes: Uint8List(0)),
        PlatformFile(name: 'Wrong.docx', size: 3, bytes: Uint8List(3)),
        PlatformFile(name: 'Large.pdf', size: 11, bytes: Uint8List(11)),
      ]) {
        picker.result = FilePickerResult([file]);
        await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
        await tester.pumpAndSettle();
        expect(notifier.uploads, isEmpty);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      picker.result = FilePickerResult([
        PlatformFile(name: 'Valid.pdf', size: 3, bytes: Uint8List(3)),
      ]);
      notifier.pending = Completer<bool>()..complete(false);
      await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(notifier.uploads, hasLength(1));
      expect(find.text('Please retry the upload.'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      notifier.pending = null;
      await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(notifier.uploads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
