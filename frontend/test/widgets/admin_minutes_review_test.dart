import 'dart:async';
import 'dart:io';

import 'package:defensys/screens/web/admin/defense_board/defense_board_screen.dart';
import 'package:defensys/screens/web/faculty/documenter/minutes_form_screen.dart';
import 'package:defensys/screens/web/faculty/e_signature_upload_dialog.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/minutes/minutes_pdf_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Admin extends AuthNotifier {
  _Admin({this.hasSignature = true, this.user = const {'role': 'admin'}});
  final bool hasSignature;
  final Map<String, dynamic> user;
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    user: {
      'id': 1,
      ...user,
      'e_signature': hasSignature ? '/signature.png' : null,
    },
  );
  void uploadSignature() => state = state.copyWith(
    user: {...state.user!, 'e_signature': '/signature.png'},
  );
}

class _Board extends DefenseBoardNotifier {
  _Board({this.minutesStatus = 'adviser_signed', this.cancelled = false});
  final String minutesStatus;
  final bool cancelled;
  int refreshes = 0;
  @override
  DefenseBoardState build() => DefenseBoardState(
    scope: 'capstone',
    schedules: [
      {
        'id': 18,
        'team_id': 7,
        'team_name': 'Team BioPulse',
        'project_title': 'Vital Triage',
        'scope': 'capstone',
        'session_id': 'concept',
        'semester_id': 3,
        'defense_stage_id': 2,
        'stage_label': 'Concept Proposal',
        'scheduled_date': '2026-10-04',
        'start_time': '08:30:00',
        'room': 'Room 301',
        'status': cancelled ? 'cancelled' : 'done',
        'display_status': cancelled ? 'cancelled' : 'completed',
        'minutes_status': minutesStatus,
        'panelists': [],
        'documenter_name': 'Cecilia Magbanua',
      },
    ],
  );
  @override
  Future<void> fetchBoard({
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? adviser,
    String? section,
    String? successMessage,
  }) async {
    refreshes++;
    if (successMessage != null) {
      state = state.copyWith(
        schedules: [
          {...state.schedules.single, 'minutes_status': 'completed'},
        ],
        message: successMessage,
      );
    }
  }
}

class _Scheduler extends DefenseSchedulerNotifier {
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
}

Future<void> _open(
  WidgetTester tester,
  _Client client, {
  _Admin? admin,
  _Board? board,
  String badge = 'Awaiting chairman',
  bool dark = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpDefensysWidget(
    tester,
    const DefenseBoardScreen(),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      authProvider.overrideWith(() => admin ?? _Admin()),
      defenseBoardProvider.overrideWith(() => board ?? _Board()),
      defenseSchedulerProvider.overrideWith(_Scheduler.new),
      authenticatedHttpClientProvider.overrideWithValue(client),
    ],
  );
  await tester.ensureVisible(find.text(badge));
  await tester.tap(find.text(badge));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _waitForPdf(WidgetTester tester) async {
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

final _signButton = find.byKey(const ValueKey('minutes-chairman-sign'));

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
    'chairman badge opens signing PDF and uploads signature without leaving the board',
    (tester) async {
      await tester.runAsync(() => loadPreviewFonts(force: true));
      final admin = _Admin(hasSignature: false);
      final board = _Board();
      await _open(tester, client, admin: admin, board: board);
      await _waitForPdf(tester);
      expect(find.byType(MinutesFormScreen), findsNothing);
      expect(find.text('Review minutes'), findsOneWidget);
      expect(
        find.text('Team BioPulse · Concept Proposal · Chairman review'),
        findsOneWidget,
      );
      expect(find.text('Sign as project adviser'), findsNothing);
      expect(find.text('Review and sign'), findsNothing);
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
        'admin-minutes-review',
      );
      await tester.tap(find.text('Upload signature'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ESignatureUploadDialog), findsOneWidget);
      admin.uploadSignature();
      Navigator.pop(tester.element(find.byType(ESignatureUploadDialog)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<ShadButton>(_signButton).enabled, isTrue);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MinutesPdfDialog), findsNothing);
      expect(find.text('Awaiting chairman'), findsOneWidget);
      expect(find.byType(MinutesFormScreen), findsNothing);
      expect(board.refreshes, 1);
      verifyNever(() => client.post(any(), headers: any(named: 'headers')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chairman signs once, retries in the dialog and refreshes finalized board status',
    (tester) async {
      final board = _Board();
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
      await _open(tester, client, board: board);
      await _waitForPdf(tester);
      await tester.tap(find.text('Sign as chairman'));
      await tester.pump();
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
      await tester.tap(find.text('Sign as chairman'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(attempts, 2);
      expect(find.byType(MinutesPdfDialog), findsNothing);
      expect(find.byType(MinutesFormScreen), findsNothing);
      expect(find.text('Finalized'), findsOneWidget);
      expect(board.refreshes, 2);
      final calls = verify(
        () => client.post(captureAny(), headers: any(named: 'headers')),
      ).captured.cast<Uri>();
      expect(
        calls.every(
          (uri) => uri.path == '/api/defense/minutes/18/sign-chairman/',
        ),
        isTrue,
      );
      await tester.tap(find.text('Finalized'));
      await tester.pump(const Duration(milliseconds: 500));
      await _waitForPdf(tester);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(_signButton, findsNothing);
      expect(requests.last, '/api/defense/minutes/18/pdf/');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  for (final (status, cancelled, badge) in [
    ('draft', false, 'Draft'),
    ('submitted', false, 'Awaiting adviser'),
    ('adviser_signed', true, 'Awaiting chairman'),
  ]) {
    testWidgets(
      '$status cancelled=$cancelled remains preview-only for chairman',
      (tester) async {
        await _open(
          tester,
          client,
          board: _Board(minutesStatus: status, cancelled: cancelled),
          badge: badge,
        );
        await _waitForPdf(tester);
        expect(_signButton, findsNothing);
        expect(find.text('Upload signature'), findsNothing);
        expect(find.byType(MinutesFormScreen), findsNothing);
        verifyNever(() => client.post(any(), headers: any(named: 'headers')));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  }

  testWidgets(
    'failed preview cannot be signed and superuser uses chairman review',
    (tester) async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response('{"detail":"Access denied"}', 403),
      );
      await _open(
        tester,
        client,
        admin: _Admin(user: const {'role': 'faculty', 'is_superuser': true}),
      );
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
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('faculty board readers cannot sign as chairman', (tester) async {
    await _open(tester, client, admin: _Admin(user: const {'role': 'faculty'}));
    await _waitForPdf(tester);
    expect(_signButton, findsNothing);
    expect(find.text('Upload signature'), findsNothing);
    expect(find.byType(MinutesFormScreen), findsNothing);
    verifyNever(() => client.post(any(), headers: any(named: 'headers')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
