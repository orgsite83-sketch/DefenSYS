import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:defensys/screens/web/faculty/e_signature_upload_dialog.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/e_signature_provider.dart';
import 'package:defensys/widgets/signature_draw_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

final _image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _Auth extends AuthNotifier {
  _Auth(this.hasSignature);
  final bool hasSignature;

  @override
  AuthState build() => AuthState(
    isRestoring: false,
    user: {
      'id': 1,
      'name': 'Test Faculty',
      'role': 'faculty',
      'e_signature': hasSignature ? '/signature.png' : null,
    },
  );
}

class _Files implements AuthenticatedHttpClient {
  Uint8List bytes = _image;
  final requests = <String>[];

  @override
  Future<Uint8List> fetchAuthenticatedFile(String fileRef) async {
    requests.add(fileRef);
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Signatures extends ESignatureService {
  _Signatures(this.providerRef, this.files) : super(providerRef);
  final Ref providerRef;
  final _Files files;
  final uploads = <(Uint8List, String)>[];
  bool succeed = true;

  @override
  Future<bool> uploadSignature(Uint8List bytes, String filename) async {
    uploads.add((bytes, filename));
    if (!succeed) return false;
    files.bytes = bytes;
    providerRef.read(authProvider.notifier).updateCurrentUser({
      ...providerRef.read(authProvider).user!,
      'e_signature': '/signature.png',
    });
    return true;
  }
}

class _Picker extends FilePicker {
  FilePickerResult? result;
  bool requestedBytes = false;

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
    requestedBytes = withData;
    return result;
  }
}

void main() {
  late _Files files;
  late _Signatures signatures;
  setUp(() => FilePicker.platform = _Picker());

  Finder elevatedButton(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      )
      .first;

  Future<void> pumpDialog(
    WidgetTester tester, {
    bool hasSignature = false,
    double width = 900,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    files = _Files();
    await pumpDefensysWidget(
      tester,
      const ESignatureUploadDialog(),
      overrides: [
        authProvider.overrideWith(() => _Auth(hasSignature)),
        authenticatedHttpClientProvider.overrideWithValue(files),
        eSignatureProvider.overrideWith((ref) {
          signatures = _Signatures(ref, files);
          return signatures;
        }),
      ],
    );
    // Initialize the lazy service even when drawing is cancelled.
    ProviderScope.containerOf(
      tester.element(find.byType(ESignatureUploadDialog)),
    ).read(eSignatureProvider);
  }

  Future<void> drawAndSave(WidgetTester tester) async {
    await tester.tap(find.text('Draw Signature'));
    await tester.pumpAndSettle();
    final pad = find.descendant(
      of: find.byType(SignatureDrawDialog),
      matching: find.byKey(const ValueKey('signature-drawing-pad')),
    );
    await tester.dragFrom(
      tester.getTopLeft(pad) + const Offset(30, 70),
      const Offset(110, 35),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save & Apply'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('drawing saves a transparent PNG and refreshes the preview', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text('Draw Signature'), findsOneWidget);
    expect(find.text('Upload Image'), findsOneWidget);
    await drawAndSave(tester);

    expect(signatures.uploads, hasLength(1));
    final (bytes, name) = signatures.uploads.single;
    expect(name, 'drawn_signature.png');
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels!.getUint8(3), 0);
      expect(
        List.generate(
          pixels.lengthInBytes ~/ 4,
          (i) => pixels.getUint8(i * 4 + 3),
        ).any((alpha) => alpha > 0),
        isTrue,
      );
      image.dispose();
      codec.dispose();
    });
    expect(files.requests, ['/signature.png']);
    expect(find.text('E-signature saved successfully.'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Replace Image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clear and cancel preserve an existing signature on a narrow screen',
    (tester) async {
      await pumpDialog(tester, hasSignature: true, width: 360);
      await tester.tap(find.text('Draw Signature'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = elevatedButton('Save & Apply');
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      final pad = find.descendant(
        of: find.byType(SignatureDrawDialog),
        matching: find.byKey(const ValueKey('signature-drawing-pad')),
      );
      await tester.dragFrom(
        tester.getTopLeft(pad) + const Offset(30, 70),
        const Offset(80, 35),
      );
      await tester.pump();
      expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
      await tester.tap(find.text('Clear Pad'));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(signatures.uploads, isEmpty);
      expect(find.text('Active'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed drawing save leaves the old preview and permits retry', (
    tester,
  ) async {
    await pumpDialog(tester, hasSignature: true);
    signatures.succeed = false;
    await drawAndSave(tester);
    expect(signatures.uploads, hasLength(1));
    expect(
      find.textContaining('Could not save your signature.'),
      findsOneWidget,
    );
    expect(find.text('Active'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(elevatedButton('Draw Signature')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload requests bytes and cancellation re-enables the actions', (
    tester,
  ) async {
    final picker = _Picker();
    final oldPicker = FilePicker.platform;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = oldPicker);
    await pumpDialog(tester);
    await tester.tap(find.text('Upload Image'));
    await tester.pumpAndSettle();
    expect(picker.requestedBytes, isTrue);
    expect(signatures.uploads, isEmpty);
    picker.result = FilePickerResult([
      PlatformFile(name: 'signature.png', size: _image.length, bytes: _image),
    ]);
    await tester.tap(find.text('Upload Image'));
    await tester.pumpAndSettle();
    expect(signatures.uploads.single.$2, 'signature.png');
    expect(find.text('Active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
