import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/defense/template_configuration.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/deliverable_template.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

final _image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=',
);

class _Picker extends FilePicker {
  PlatformFile? next = PlatformFile(
    name: 'Poster.png',
    size: _image.length,
    bytes: _image,
  );
  List<String>? extensions;
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
    extensions = allowedExtensions;
    return next == null ? null : FilePickerResult([next!]);
  }
}

class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"stage":{"id":7}}')),
      200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _Picker();
  });
  tearDown(resetApiHttpClientForTesting);

  testWidgets(
    'PDF requirement accepts an image draft without saving or changing required',
    (tester) async {
      final picker = _Picker();
      final previous = FilePicker.platform;
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = previous);
      final item = <String, dynamic>{
        'label': 'Paper',
        'deliverable_id': 'D1',
        'file_format': 'pdf',
        'required': true,
      };
      var changes = 0;
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (_, update) => DeliverableTemplateEditor(
            item: item,
            onChanged: () => update(() => changes++),
          ),
        ),
      );
      expect(find.text('No template attached'), findsOneWidget);
      await tester.tap(find.text('Upload template'));
      await tester.pumpAndSettle();
      expect(find.text('Poster.png'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(item['template'], isNull);
      expect(item['template_action'], 'replace');
      expect(item['file_format'], 'pdf');
      expect(item['required'], isTrue);
      expect(
        picker.extensions,
        containsAll(['docx', 'png', 'mp4', 'mp3', 'zip']),
      );
      expect(changes, 1);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
      expect(item['template'], isNull);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('No template attached'), findsOneWidget);
      expect(item['_templateFile'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled replacement retains the saved attachment', (
    tester,
  ) async {
    final picker = _Picker()..next = null;
    final previous = FilePicker.platform;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = previous);
    final saved = {
      'id': 3,
      'original_name': 'Original.docx',
      'byte_size': 82,
      'file_url': '/api/media/files/original.docx',
    };
    final item = <String, dynamic>{'template': saved};
    await pumpDefensysWidget(
      tester,
      DeliverableTemplateEditor(item: item, onChanged: () {}),
    );
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(item['template'], same(saved));
    expect(item['template_action'], isNull);
    expect(find.text('Original.docx'), findsOneWidget);
  });

  testWidgets('locked setup keeps preview and disables attachment mutations', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      DeliverableTemplateEditor(
        enabled: false,
        item: {
          'template': {
            'id': 3,
            'original_name': 'Poster.png',
            'byte_size': 82,
            'file_url': '/api/media/files/poster.png',
          },
        },
        onChanged: () {},
      ),
    );
    final preview = tester.widget<TextButton>(
      find.ancestor(of: find.text('Preview'), matching: find.byWidgetPredicate((widget) => widget is TextButton)).first,
    );
    expect(preview.onPressed, isNotNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Replace'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'student preview uses authenticated reads and closing changes no state',
    (tester) async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(_image, 200);
        }),
      );
      final template = {
        'id': 3,
        'original_name': 'Poster.png',
        'file_url': '/api/media/files/poster.png',
      };
      await pumpDefensysWidget(
        tester,
        DeliverableTemplateDownload(template: template),
        overrides: authTestOverrides(),
      );
      expect(find.text('Download template'), findsOneWidget);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(requests.single.method, 'GET');
      expect(requests.single.headers['Authorization'], startsWith('Bearer '));
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Download template'), findsOneWidget);
      expect(template['id'], 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing template does not reserve a placeholder row', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const DeliverableTemplateDownload(template: null),
    );
    expect(find.text('Template'), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Download template'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'long template filename fits narrow ${dark ? 'dark' : 'light'} layout',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DeliverableTemplateEditor(
                item: {
                  'template': {
                    'id': 3,
                    'original_name': '${'very-long-poster-name-' * 8}.png',
                    'byte_size': 82,
                    'file_url': '/api/media/files/poster.png',
                  },
                },
                onChanged: () {},
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Preview'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'multipart setup sends template bytes independently of PDF submission type',
    () async {
      final client = _RecordingClient();
      setApiHttpClientForTesting(client);
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final row = <String, dynamic>{
        'deliverable_id': 'D1',
        'label': 'Poster',
        'file_format': 'pdf',
        'template_action': 'replace',
        'template_selection_name': 'Poster.png',
        '_templateFile': PlatformFile(
          name: 'Poster.png',
          size: _image.length,
          bytes: _image,
        ),
      };
      await saveTemplateConfiguration(
        container.read(authenticatedHttpClientProvider),
        'PATCH',
        Uri.parse('http://localhost/api/defense/stages/7/'),
        {
          'deliverables': [row],
          '_templateDrafts': templateDrafts([row], []),
        },
      );
      final request = client.requests.single as http.MultipartRequest;
      final configuration = jsonDecode(request.fields['configuration']!) as Map;
      final definition = (configuration['deliverables'] as List).single as Map;
      expect(definition['file_format'], 'pdf');
      expect(definition.containsKey('_templateFile'), isFalse);
      expect(definition.containsKey('template_action'), isFalse);
      expect(request.files.single.filename, 'Poster.png');
      final operation =
          (configuration['template_changes'] as List).single as Map;
      expect(operation['deliverable_id'], 'D1');
      expect(operation['upload_key'], request.files.single.field);
    },
  );

  test(
    'restored browser file selection requires reselection before sending',
    () async {
      final client = _RecordingClient();
      setApiHttpClientForTesting(client);
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final row = <String, dynamic>{
        'deliverable_id': 'D1',
        'label': 'Poster',
        'template_action': 'replace',
        'template_selection_name': 'Poster.png',
      };
      await expectLater(
        saveTemplateConfiguration(
          container.read(authenticatedHttpClientProvider),
          'PATCH',
          Uri.parse('http://localhost/api/defense/stages/7/'),
          {
            'deliverables': [row],
            '_templateDrafts': templateDrafts([row], []),
          },
        ),
        throwsStateError,
      );
      expect(client.requests, isEmpty);
    },
  );
}
