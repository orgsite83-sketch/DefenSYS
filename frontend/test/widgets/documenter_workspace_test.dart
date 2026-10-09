import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:defensys/models/documenter_assignment.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/navigation/workspace_preference.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/services/connectivity_provider.dart';
import 'package:defensys/screens/web/faculty/documenter/minutes_form_screen.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/dialogs/documenter_pool_dialog.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/documenter_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/minutes/documenter_assignments_view.dart';
import 'package:defensys/widgets/minutes/minutes_pdf_dialog.dart';
import 'package:defensys/widgets/minutes/faculty_app_workspace_switcher.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Doc extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    token: 'fixture-token',
    user: {'id': 7, 'role': 'faculty', 'is_documenter': true},
  );
}

class _DualRoleDoc extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    token: 'fixture-token',
    user: {
      'id': 7,
      'role': 'faculty',
      'is_documenter': true,
      'is_panelist': true,
    },
  );
}

class _Admin extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 8, 'role': 'admin'});
}

class _Assignments extends DocumenterNotifier {
  @override
  DocumenterState build() {
    final today = DocumenterAssignment.manilaNow
        .toIso8601String()
        .split('T')
        .first;
    return DocumenterState(
      assignments: [
        {
          'id': 20,
          'team_name': 'Team AgriSense',
          'project_title': 'Smart Agriculture Crop & Soil Monitoring',
          'defense_stage_label': 'Concept Proposal',
          'scheduled_date': today,
          'start_time': '08:00:00',
          'room': '301',
          'status': 'scheduled',
          'minutes_status': 'draft',
          'minutes_has_comments': true,
        },
        {
          'id': 21,
          'team_name': 'Team BioPulse',
          'project_title': 'AI Powered Vital Triage',
          'defense_stage_label': 'Concept Proposal',
          'scheduled_date': today,
          'start_time': '08:30:00',
          'room': '301',
          'status': 'done',
          'minutes_status': 'submitted',
        },
      ],
    );
  }

  @override
  Future<void> fetchAssignments() async {}
}

class _Minutes extends DocumenterNotifier {
  @override
  DocumenterState build() => const DocumenterState(
    activeMinutes: {
      'status': 'draft',
      'team_name': 'Team AgriSense',
      'project_title': 'Smart Agriculture',
      'defense_stage_label': 'Concept Proposal',
      'defense_date': '2026-10-09',
      'defense_time': '08:00:00',
      'schedule': {
        'id': 20,
        'documenter': 7,
        'status': 'scheduled',
        'panelists': [],
      },
      'panelist_comments': [
        {
          'id': 1,
          'panelist_role_snapshot': 'Chair',
          'panelist_name_snapshot': 'Jonathan Beltran',
          'comments': 'Calibrate the sensor.',
        },
      ],
    },
  );
  @override
  Future<void> fetchMinutesDetail(int id) async {}
  @override
  Future<bool> saveComments(
    int id,
    List<Map<String, dynamic>> comments,
  ) async => false;
  @override
  Future<bool> autoSaveComments(
    int id,
    List<Map<String, dynamic>> comments,
  ) async => false;
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _AppDocumenter extends _Assignments {
  @override
  Future<void> fetchMinutesDetail(int id) async {
    state = state.copyWith(
      activeMinutes: {
        'status': 'draft',
        'team_name': 'Team AgriSense',
        'schedule': {
          'id': id,
          'documenter': 7,
          'status': 'scheduled',
          'panelists': [],
        },
        'panelist_comments': [
          {
            'id': 1,
            'panelist_name_snapshot': 'Jonathan Beltran',
            'panelist_role_snapshot': 'Chair',
            'comments': 'Calibrate the sensor.',
          },
        ],
      },
    );
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] != '1') return;
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../.tmp/documenter-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void _ignoreMinutes(int _) {}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() => registerFallbackValue(Uri.parse('https://example.test')));
  testWidgets(
    'documenter login route opens assignments and the assigned minutes editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await loadPreviewFonts();
        if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] == '1') {
          await (FontLoader('Poppins')
                ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf')))
              .load();
        }
      });
      final nativeKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: nativeKey,
          child: ProviderScope(
            overrides: [
              authProvider.overrideWith(_Doc.new),
              documenterProvider.overrideWith(_AppDocumenter.new),
              connectivityProvider.overrideWith(_Online.new),
              workspacePreferenceProvider.overrideWith(
                (ref) async => '/documenter',
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) => MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: ref.watch(appRouterProvider),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Documenter workspace'), findsOneWidget);
      await capture(tester, nativeKey, 'phone-app');
      await tester.tap(find.text('Continue minutes'));
      await tester.pumpAndSettle();
      expect(find.byType(MinutesFormScreen), findsOneWidget);
      await capture(tester, nativeKey, 'phone-editor');
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      expect(find.text('Documenter workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'workspace menu exposes eligible roles and honors the save guard',
    (tester) async {
      var guarded = false;
      await pumpDefensysWidget(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: FacultyAppWorkspaceSwitcher(
            currentRoute: '/documenter',
            beforeSwitch: () async {
              guarded = true;
              return false;
            },
          ),
        ),
        overrides: [authProvider.overrideWith(_DualRoleDoc.new)],
      );
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('Panel workspace'), findsOneWidget);
      expect(find.text('Documenter workspace'), findsOneWidget);
      expect(find.text('Student workspace'), findsNothing);
      expect(find.text('Staff web workspace'), findsNothing);
      await tester.tap(find.text('Panel workspace'));
      await tester.pumpAndSettle();
      expect(guarded, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString('app.workspace.7'),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact queue searches, clears and filters signed records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: DocumenterAssignmentsView(onOpenMinutes: _ignoreMinutes),
      ),
      overrides: [documenterProvider.overrideWith(_Assignments.new)],
    );
    await tester.enterText(find.byType(ShadInput), 'agrisense');
    await tester.pumpAndSettle();
    expect(find.text('Team AgriSense'), findsOneWidget);
    expect(find.text('Team BioPulse'), findsNothing);
    await tester.enterText(find.byType(ShadInput), 'unmatched-project');
    await tester.pumpAndSettle();
    expect(find.text('No matching defenses'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    expect(find.text('Team BioPulse'), findsOneWidget);
    expect(find.text('Team AgriSense'), findsNothing);
    expect(find.text('Awaiting adviser signature'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'documenter queue supports large text in a narrow dark viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => loadPreviewFonts(force: true));
      final key = GlobalKey();
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF161618),
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 850),
                textScaler: TextScaler.linear(1.3),
              ),
              child: const SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: DocumenterAssignmentsView(onOpenMinutes: _ignoreMinutes),
              ),
            ),
          ),
        ),
        theme: AppTheme.mistDarkTheme,
        overrides: [documenterProvider.overrideWith(_Assignments.new)],
      );
      expect(find.text('Continue minutes'), findsOneWidget);
      final error = tester.takeException();
      expect(
        error,
        isNull,
        reason: error is FlutterError
            ? error.diagnostics.map((d) => d.toStringDeep()).join('\n')
            : null,
      );
      await capture(tester, key, 'dark-large-text');
    },
  );

  testWidgets(
    'phone assignments have clear actions, signature states and no overflow',
    (tester) async {
      await tester.runAsync(() async {
        await loadPreviewFonts();
        if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] == '1') {
          await (FontLoader('Poppins')
                ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf')))
              .load();
        }
      });
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      final key = GlobalKey();
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: key,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DocumenterAssignmentsView(
              onOpenMinutes: (id) => opened = id,
            ),
          ),
        ),
        overrides: [documenterProvider.overrideWith(_Assignments.new)],
      );
      expect(find.text('Continue minutes'), findsOneWidget);
      expect(find.text('Awaiting adviser signature'), findsOneWidget);
      await tester.tap(find.text('Continue minutes'));
      expect(opened, 20);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'phone-assignments');
    },
  );
  testWidgets('desktop assignments and dark phone editor fit their viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await pumpDefensysWidget(
      tester,
      RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFFF8FAFC),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: DocumenterAssignmentsView(onOpenMinutes: (_) {}),
          ),
        ),
      ),
      overrides: [documenterProvider.overrideWith(_Assignments.new)],
    );
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'desktop-assignments');
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(320, 900);
    await pumpDefensysWidget(
      tester,
      MinutesFormScreen(scheduleId: 20, onBack: () {}),
      theme: AppTheme.mistDarkTheme,
      overrides: [
        authProvider.overrideWith(_Doc.new),
        documenterProvider.overrideWith(_Minutes.new),
      ],
    );
    expect(find.text('Defense details'), findsOneWidget);
    expect(find.text('E-signature required'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('minutes-comment-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed saves keep notes and block leaving the editor', (
    tester,
  ) async {
    var left = false;
    await pumpDefensysWidget(
      tester,
      MinutesFormScreen(scheduleId: 20, onBack: () => left = true),
      overrides: [
        authProvider.overrideWith(_Doc.new),
        documenterProvider.overrideWith(_Minutes.new),
      ],
    );
    await tester.enterText(
      find.byKey(const ValueKey('minutes-comment-1')),
      'Keep this unsaved comment.',
    );
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(left, isFalse);
    expect(find.text('Keep this unsaved comment.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'admin PDF preview reads only PDF endpoint and retries inside the dialog',
    (tester) async {
      final client = _Client();
      final requests = <String>[];
      when(() => client.get(any())).thenAnswer((invocation) async {
        requests.add((invocation.positionalArguments.first as Uri).path);
        return http.Response(
          '{"detail":"Try again"}',
          requests.length == 1 ? 503 : 404,
        );
      });
      await pumpDefensysWidget(
        tester,
        const MinutesPdfDialog(scheduleId: 20, finalized: false),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Minutes have not been prepared yet.'), findsOneWidget);
      expect(requests, [
        '/api/defense/minutes/20/preview/',
        '/api/defense/minutes/20/preview/',
      ]);
      expect(find.byType(MinutesFormScreen), findsNothing);
    },
  );
  testWidgets(
    'pool shows outstanding work and saves explicit eligibility changes',
    (tester) async {
      final client = _Client();
      final payload = {
        'people': [
          {
            'id': 7,
            'name': 'Cecilia Magbanua',
            'role': 'faculty',
            'is_documenter': true,
            'pending_assignments': [
              {'id': 20, 'team_name': 'AgriSense'},
            ],
          },
          {
            'id': 9,
            'name': 'New Documenter',
            'role': 'faculty',
            'is_documenter': false,
            'pending_assignments': [],
          },
        ],
      };
      when(
        () => client.get(any()),
      ).thenAnswer((_) async => http.Response(jsonEncode(payload), 200));
      when(
        () => client.patch(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"detail":"Keep changes"}', 400),
      );
      await pumpDefensysWidget(
        tester,
        const DocumenterPoolDialog(),
        overrides: [
          authProvider.overrideWith(_Admin.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      final blocked = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Cecilia Magbanua'),
      );
      expect(blocked.onChanged, isNull);
      await tester.tap(find.text('New Documenter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final bodies = verify(
        () => client.patch(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(jsonDecode(bodies.single as String)['changes'], [
        {'id': 9, 'is_documenter': true},
      ]);
      expect(find.text('1 pending change(s)'), findsOneWidget);
    },
  );
}
