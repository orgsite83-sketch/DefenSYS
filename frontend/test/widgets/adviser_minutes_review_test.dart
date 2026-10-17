import 'dart:async';
import 'dart:io';

import 'package:defensys/screens/web/faculty/adviser/adviser_defense_tab.dart';
import 'package:defensys/screens/web/faculty/documenter/minutes_form_screen.dart';
import 'package:defensys/screens/web/faculty/e_signature_upload_dialog.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense/adviser_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/export/defensys_pdf_viewer.dart';
import 'package:defensys/widgets/minutes/minutes_pdf_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Adviser extends AuthNotifier {
  _Adviser({this.hasSignature = true});
  final bool hasSignature;

  @override
  AuthState build() => AuthState(
    isRestoring: false,
    user: {
      'id': 9,
      'role': 'faculty',
      'e_signature': hasSignature ? '/signature.png' : null,
    },
  );

  void signatureUploaded() => state = state.copyWith(
    user: {...state.user!, 'e_signature': '/signature.png'},
  );
}

class _Defense extends AdviserDefenseNotifier {
  _Defense({this.minutesStatus = 'submitted'});
  final String minutesStatus;
  int refreshes = 0;

  @override
  AdviserDefenseState build() => AdviserDefenseState(
    schedules: [
      {
        'id': 18,
        'team_id': 7,
        'team_name': 'Team AgriSense',
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'scheduled_date': '2026-10-04',
        'start_time': '08:00:00',
        'room': 'Room 301',
        'status': 'done',
        'minutes_status': minutesStatus,
      },
    ],
  );

  @override
  Future<void> fetch({String? workspace}) async {
    refreshes++;
    state = AdviserDefenseState(
      schedules: [
        {...state.schedules.single, 'minutes_status': 'adviser_signed'},
      ],
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Client client, {
  _Adviser? adviser,
  _Defense? defense,
  String action = 'Review and sign minutes',
  bool dark = false,
}) async {
  await pumpDefensysWidget(
    tester,
    const SingleChildScrollView(
      child: AdviserDefenseTab(teamId: 7, selectedStage: 'Concept Proposal'),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      authProvider.overrideWith(() => adviser ?? _Adviser()),
      adviserDefenseProvider.overrideWith(() => defense ?? _Defense()),
      authenticatedHttpClientProvider.overrideWithValue(client),
    ],
  );
  await tester.ensureVisible(find.text(action));
  await tester.tap(find.text(action));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _waitForPdf(WidgetTester tester) async {
  // The native viewer writes a temporary PDF outside the fake test clock.
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      if (find.text('1 page').evaluate().isNotEmpty &&
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((page) => page.image != null)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('1 page'), findsOneWidget);
}

final _signButton = find.byKey(const ValueKey('minutes-adviser-sign'));

void main() {
  late _Client client;
  late List<String> requests;
  final pdf = File(
    'assets/template/Minutes-Defense-TEMPLATE.pdf',
  ).readAsBytesSync();
  const channel = MethodChannel('syncfusion_flutter_pdfviewer');

  setUpAll(() => registerFallbackValue(Uri.parse('https://example.test')));

  setUp(() {
    client = _Client();
    requests = [];
    when(() => client.get(any())).thenAnswer((invocation) async {
      requests.add((invocation.positionalArguments.first as Uri).path);
      return http.Response.bytes(pdf, 200);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initializePdfRenderer':
            case 'loadPdfFromFile':
              return '1';
            case 'getPagesWidth':
              return [612.0];
            case 'getPagesHeight':
              return [792.0];
            case 'getPage':
              final args = call.arguments as Map;
              return Uint8List(
                (args['width'] as int) * (args['height'] as int) * 4,
              );
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'adviser previews minutes and uploads a missing signature in place',
    (tester) async {
      final adviser = _Adviser(hasSignature: false);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => loadPreviewFonts());
      await _open(tester, client, adviser: adviser);
      await _waitForPdf(tester);
      expect(find.byType(MinutesFormScreen), findsNothing);
      expect(find.byType(MinutesPdfDialog), findsOneWidget);
      expect(find.byType(ShadDialog), findsOneWidget);
      expect(find.byType(ShadAlert), findsOneWidget);
      expect(find.text('Review minutes'), findsOneWidget);
      expect(find.text('E-signature required'), findsOneWidget);
      expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
      expect(requests, ['/api/defense/minutes/18/preview/']);
      await capturePreview(
        tester,
        find
            .ancestor(
              of: find.byType(MinutesPdfDialog),
              matching: find.byType(RepaintBoundary),
            )
            .first,
        'adviser-minutes-desktop',
      );

      await tester.tap(find.text('Upload signature'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ESignatureUploadDialog), findsOneWidget);
      // The shared uploader refreshes authProvider after a successful upload.
      adviser.signatureUploaded();
      final uploadContext = tester.element(find.byType(ESignatureUploadDialog));
      Navigator.pop(uploadContext);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('E-signature required'), findsNothing);
      expect(find.byType(DefensysPdfViewer), findsOneWidget);
      expect(tester.widget<ShadButton>(_signButton).enabled, isTrue);
      verifyNever(() => client.post(any(), headers: any(named: 'headers')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'signing submits once, keeps errors in preview and refreshes on success',
    (tester) async {
      final defense = _Defense();
      final pending = Completer<http.Response>();
      var attempts = 0;
      when(() => client.post(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) {
          attempts++;
          return attempts == 1
              ? pending.future
              : Future.value(http.Response('{}', 200));
        },
      );
      await _open(tester, client, defense: defense);
      await _waitForPdf(tester);
      await tester.tap(find.text('Sign as project adviser'));
      await tester.pump();
      expect(find.text('Signing…'), findsOneWidget);
      expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
      await tester.tap(find.text('Signing…'), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(MinutesPdfDialog), findsOneWidget);
      expect(attempts, 1);

      pending.complete(
        http.Response('{"detail":"Please retry signing."}', 503),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Please retry signing.'), findsOneWidget);
      expect(find.byType(DefensysPdfViewer), findsOneWidget);
      await tester.tap(find.text('Sign as project adviser'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(attempts, 2);
      expect(find.byType(MinutesPdfDialog), findsNothing);
      expect(defense.refreshes, 1);
      expect(
        find.text('Signed by adviser; awaiting final signature'),
        findsOneWidget,
      );
      expect(find.text('View signed minutes'), findsOneWidget);
      expect(attempts, 2);
      final calls = verify(
        () => client.post(captureAny(), headers: any(named: 'headers')),
      ).captured.cast<Uri>();
      expect(
        calls.every(
          (uri) => uri.path == '/api/defense/minutes/18/sign-adviser/',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  for (final (status, action, endpoint) in [
    ('adviser_signed', 'View signed minutes', 'preview'),
    ('completed', 'View final minutes', 'pdf'),
  ]) {
    testWidgets('$status minutes open as a read-only PDF', (tester) async {
      await _open(
        tester,
        client,
        adviser: _Adviser(hasSignature: false),
        defense: _Defense(minutesStatus: status),
        action: action,
      );
      await _waitForPdf(tester);
      expect(find.byType(MinutesFormScreen), findsNothing);
      expect(find.text('Sign as project adviser'), findsNothing);
      expect(find.text('Upload signature'), findsNothing);
      expect(requests, ['/api/defense/minutes/18/$endpoint/']);
      expect(
        find.text('Download PDF'),
        status == 'completed' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });
  }

  testWidgets('preview failure and missing minutes cannot be signed', (
    tester,
  ) async {
    when(
      () => client.get(any()),
    ).thenAnswer((_) async => http.Response('{"detail":"Access denied"}', 403));
    await _open(tester, client);
    expect(find.text('Access denied'), findsOneWidget);
    expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
    when(
      () => client.get(any()),
    ).thenAnswer((_) async => http.Response('{}', 404));
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Minutes have not been prepared yet.'), findsOneWidget);
    expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
    verifyNever(() => client.post(any(), headers: any(named: 'headers')));
  });

  testWidgets(
    'signing waits for the PDF to load and rejects an unreadable preview',
    (tester) async {
      final pending = Completer<http.Response>();
      when(() => client.get(any())).thenAnswer((_) => pending.future);
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _Adviser()),
              authenticatedHttpClientProvider.overrideWithValue(client),
            ],
            child: const MinutesPdfDialog(
              scheduleId: 18,
              finalized: false,
              allowAdviserSigning: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
      pending.complete(http.Response('invalid PDF', 200));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Unable to preview'), findsOneWidget);
      expect(tester.widget<ShadButton>(_signButton).enabled, isFalse);
      verifyNever(() => client.post(any(), headers: any(named: 'headers')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'adviser review fits a narrow dark screen with the signature prompt',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => loadPreviewFonts(force: true));
      await _open(
        tester,
        client,
        adviser: _Adviser(hasSignature: false),
        dark: true,
      );
      await _waitForPdf(tester);
      expect(find.text('Upload signature'), findsOneWidget);
      expect(find.text('Sign as project adviser'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find
            .ancestor(
              of: find.byType(MinutesPdfDialog),
              matching: find.byType(RepaintBoundary),
            )
            .first,
        'adviser-minutes-dark-phone',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
