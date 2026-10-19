import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/curriculum_analytics_screen.dart';
import 'package:defensys/services/academic/curriculum_explorer_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/auth/auth_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';

final _captureKey = GlobalKey();
Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['CURRICULUM_CAPTURE_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final image =
        await (_captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(path).createSync(recursive: true);
    File('$path/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _mount(
  WidgetTester tester, {
  double width = 1200,
  double height = 1100,
  bool dark = false,
  bool unclassified = false,
  bool unpublished = false,
  bool multipleSources = false,
  bool startAtAssessment = true,
  bool noAssessments = false,
  String? pitYearLevel,
  _SourceFileClient? sourceClient,
}) async {
  final fonts = FontLoader('Inter');
  fonts.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  fonts.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await fonts.load();
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
  icons.addFont(
    rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
  );
  await icons.load();
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_AnalyticsAdmin.new),
        curriculumExplorerProvider.overrideWith(
          () => _FakeExplorer(
            unclassified: unclassified,
            unpublished: unpublished,
            sourceUrl: sourceClient != null,
            multipleSources: multipleSources,
            startAtAssessment: startAtAssessment,
            noAssessments: noAssessments,
            pitYearLevel: pitYearLevel,
          ),
        ),
        if (sourceClient != null)
          authenticatedHttpClientProvider.overrideWithValue(sourceClient),
      ],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: 'Inter',
            scaffoldBackgroundColor: dark
                ? DefensysTokens.mistBackground
                : DefensysTokens.background,
          ),
          home: Scaffold(
            body: CurriculumAnalyticsScreen(pitYearLevel: pitYearLevel),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('years remain reachable before assessment results exist', (
    tester,
  ) async {
    await _mount(tester, startAtAssessment: false, noAssessments: true);
    expect(
      find.textContaining('No recorded assessment results yet'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('year-2026-2027')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assessment-stage:1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('overview reveals year then assessment without stacking charts', (
    tester,
  ) async {
    await _mount(tester, startAtAssessment: false);
    expect(find.text('Performance over time'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('performance-clustered-chart')),
      findsNothing,
    );
    expect(find.byType(SfCartesianChart), findsOneWidget);
    await _capture(tester, 'workspace-overview');
    await tester.tap(find.byKey(const ValueKey('year-2026-2027')));
    await tester.pumpAndSettle();
    expect(find.text('Stage and event results · 2026-2027'), findsOneWidget);
    expect(find.byKey(const ValueKey('academic-year-chart')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assessment-stage:1')));
    await tester.pumpAndSettle();
    expect(find.text('Evaluator components'), findsOneWidget);
    expect(find.text('Performance by criterion'), findsOneWidget);
    expect(find.text('Review priorities'), findsNothing);
    await _capture(tester, 'workspace-assessment');
    await tester.tap(find.byKey(const ValueKey('analytics-root')));
    await tester.pumpAndSettle();
    expect(find.text('Performance over time'), findsOneWidget);
    expect(find.byKey(const ValueKey('criterion-problem')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assessment retains criterion, team, source and pending drilldowns',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.byKey(const ValueKey('criterion-problem')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('team-1:1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('6.00 / 10'), findsOneWidget);
      expect(
        find.textContaining('Support the problem with stakeholder evidence.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-pending')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team-3:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-1:1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PIT Lead overview is locked and exports the selected range', (
    tester,
  ) async {
    await _mount(tester, pitYearLevel: '2nd Year', startAtAssessment: false);
    expect(find.text('PIT · 2nd Year'), findsOneWidget);
    expect(find.text('Capstone'), findsNothing);
    expect(find.text('PIT year level'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CurriculumAnalyticsScreen)),
    );
    expect(
      (container.read(curriculumExplorerProvider.notifier) as _FakeExplorer)
          .fetches,
      1,
    );
    expect(container.read(curriculumExplorerProvider).query.yearLevel, '2');
    expect(container.read(curriculumExplorerProvider).query.year, isEmpty);
    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(find.text('Export meeting report'), findsOneWidget);
    expect(find.textContaining('PIT / Year 2'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing PIT year assignment cannot load admin analytics', (
    tester,
  ) async {
    await _mount(tester, pitYearLevel: '');
    expect(
      find.text(
        'A PIT year assignment is required to view curriculum analytics.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SfCartesianChart), findsNothing);
  });

  testWidgets(
    'project mix and yearly output replace one another and groups reveal records',
    (tester) async {
      await _mount(tester, startAtAssessment: false);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-mix-pie')), findsOneWidget);
      expect(find.text('Documented technologies'), findsOneWidget);
      expect(find.byType(SfCartesianChart), findsNothing);
      await _capture(tester, 'workspace-project-mix');
      await tester.tap(find.byKey(const ValueKey('view-yearly-output')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('project-output-chart')),
        findsOneWidget,
      );
      expect(find.byType(SfCircularChart), findsNothing);
      await tester.tap(find.byKey(const ValueKey('year-2026-2027')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-mix-pie')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('project-group-category-React')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-2:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-3:1')), findsNothing);
      expect(find.byType(SfCircularChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'domain selection and performance evaluator state survive navigation',
    (tester) async {
      await _mount(tester);
      final tabs = find.byKey(const ValueKey('performance-evaluator-tabs'));
      await tester.tap(find.descendant(of: tabs, matching: find.text('Peer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Domain'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('project-group-domain-Healthcare')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-2:1')), findsNothing);
      await tester.tap(find.text('Back to project mix'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadTabs<String>>(
              find.byKey(const ValueKey('project-mix-tabs')),
            )
            .value,
        'domain',
      );
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(tester.widget<ShadTabs<String>>(tabs).value, 'peer');
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'workspace overview and mix fit 320px in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _mount(tester, width: 320, dark: dark, startAtAssessment: false);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Project insights'));
        await tester.tap(find.text('Project insights'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('view-all-projects')),
        );
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          dark ? 'workspace-phone-dark' : 'workspace-phone-light',
        );
      },
    );
  }

  testWidgets(
    'project evidence explains estimates with actual source passages',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project focus'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('project-group-category-Web Development')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-1:1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overview-source-doc1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('overview-source-doc3')), findsNothing);
      expect(find.text('D2 · Concept Paper'), findsNothing);
      final overviewSize = tester.getSize(
        find.byKey(const ValueKey('project-dialog-body')),
      );
      await tester.tap(find.byKey(const ValueKey('project-view-sources')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('project-dialog-body'))),
        overviewSize,
      );
      expect(
        find.byKey(const ValueKey('project-classification-explanation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Supporting passages for the estimates'));
      await tester.pumpAndSettle();
      expect(
        find.text('We implement a web application using React.'),
        findsOneWidget,
      );
      await _capture(tester, 'project-classification-evidence');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sources identify overview evidence and keep file actions visible',
    (tester) async {
      await _mount(
        tester,
        multipleSources: true,
        sourceClient: _SourceFileClient(),
      );
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project focus'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('project-group-category-Web Development')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-1:1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('overview-source-doc1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('overview-source-doc3')),
        findsOneWidget,
      );
      expect(find.text('D2 · Concept Paper'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('project-view-sources')));
      await tester.pumpAndSettle();
      expect(find.text('Used in this overview'), findsOneWidget);
      expect(find.text('Additional documents'), findsOneWidget);
      expect(
        find.text('Used for: computing focus, domain and platform.'),
        findsOneWidget,
      );
      expect(find.text('Used for: background.'), findsOneWidget);
      expect(find.text('Open'), findsNWidgets(3));
      expect(
        tester.getTopLeft(find.text('D1 · Project proposal')).dy,
        lessThan(tester.getTopLeft(find.text('D2 · Concept Paper')).dy),
      );
      expect(find.text('Extracted text and terms'), findsNothing);
      await _capture(tester, 'sources-desktop');
      await tester.tap(find.byKey(const ValueKey('project-view-overview')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('profile-source-description')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected source'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('D3 · Approved Concept Paper')).dy,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short phone keeps the header and close action fixed while sources scroll',
    (tester) async {
      await _mount(tester, width: 320, height: 640, multipleSources: true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('criterion-problem')),
      );
      await tester.tap(find.byKey(const ValueKey('criterion-problem')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('team-1:1')));
      await tester.tap(find.byKey(const ValueKey('team-1:1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-view-sources')));
      await tester.pumpAndSettle();
      final header = tester.getRect(
        find.byKey(const ValueKey('project-dialog-title')),
      );
      final close = tester.getRect(find.text('Close'));
      final scrollbar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('project-evidence-scrollbar')),
      );
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('project-scroll-sources')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(scrollbar.controller!.offset, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('project-dialog-title'))),
        header,
      );
      expect(tester.getRect(find.text('Close')), close);
      expect(close.bottom, lessThanOrEqualTo(640));
      await _capture(tester, 'short-phone-fixed-dialog');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source list shows deliverable metadata and unavailable files', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('criterion-problem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-1:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-view-sources')));
    await tester.pumpAndSettle();
    final source = find.text('D1 · Project proposal');
    await tester.ensureVisible(source);
    expect(source, findsOneWidget);
    expect(find.text('CloudSync_Proposal.pdf'), findsNothing);
    expect(
      find.text('Concept Proposal · Pre-defense · Approved'),
      findsOneWidget,
    );
    expect(find.text('By Recorded uploader'), findsNothing);
    final details = find.byKey(const ValueKey('source-details-doc1'));
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('By Recorded uploader'), findsOneWidget);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('By Recorded uploader'), findsNothing);
    expect(find.text('Source file is unavailable.'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    await _capture(tester, 'source-document-metadata');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source preview uses authenticated repository viewer and retries failures',
    (tester) async {
      final client = _SourceFileClient();
      await _mount(tester, sourceClient: client);
      await tester.tap(find.byKey(const ValueKey('criterion-problem')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('team-1:1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-view-sources')));
      await tester.pumpAndSettle();
      final source = find.text('D1 · Project proposal');
      await tester.ensureVisible(source);
      final open = find.byKey(const ValueKey('open-source-doc1'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(client.requests, ['/api/media/deliverables/current.png']);
      expect(find.text('Source document could not open'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('curriculum-evidence-dialog')),
        findsOneWidget,
      );
      client.fail = false;
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final viewer = tester.widget<UniversalMobileFileViewerDialog>(
        find.byType(UniversalMobileFileViewerDialog),
      );
      expect(viewer.fileName, 'CloudSync_Proposal.png');
      expect(viewer.fileBytes, client.bytes);
      expect(client.requests.length, 2);
      expect(find.text('Source document could not open'), findsNothing);
      await _capture(tester, 'source-document-viewer');
      Navigator.of(
        tester.element(find.byType(UniversalMobileFileViewerDialog)),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('curriculum-evidence-dialog')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'fits 320px with ${dark ? 'dark' : 'light'} shadcn components',
      (tester) async {
        await _mount(
          tester,
          width: 320,
          height: 780,
          dark: dark,
          multipleSources: true,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, dark ? 'phone-dark' : 'phone-light');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('criterion-problem')),
        );
        await tester.tap(find.byKey(const ValueKey('criterion-problem')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('team-1:1')));
        await tester.tap(find.byKey(const ValueKey('team-1:1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(tester, dark ? 'phone-popup-dark' : 'phone-popup-light');
        final assessmentLabel = find.descendant(
          of: find.byKey(const ValueKey('project-view-assessments')),
          matching: find.text('Assessments'),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(assessmentLabel)
              .didExceedMaxLines,
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('project-view-overview')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('project-overview')), findsOneWidget);
        await _capture(
          tester,
          dark ? 'phone-overview-dark' : 'phone-overview-light',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('profile-source-description')),
        );
        await tester.tap(
          find.byKey(const ValueKey('profile-source-description')),
        );
        await tester.pumpAndSettle();
        final source = find.text('D3 · Approved Concept Paper');
        expect(source, findsOneWidget);
        // A profile source link focuses the matching document row.
        expect(find.text('Selected source'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          dark ? 'phone-source-dark' : 'phone-source-light',
        );
      },
    );
  }
}

class _AnalyticsAdmin extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(user: {'id': 1, 'role': 'admin'}, isRestoring: false);
}

class _FakeExplorer extends CurriculumExplorerNotifier {
  _FakeExplorer({
    this.unclassified = false,
    this.unpublished = false,
    this.sourceUrl = false,
    this.multipleSources = false,
    this.startAtAssessment = true,
    this.noAssessments = false,
    this.pitYearLevel,
  });
  final bool unclassified, unpublished, sourceUrl, multipleSources;
  final bool startAtAssessment;
  final bool noAssessments;
  final String? pitYearLevel;
  int fetches = 0;
  @override
  CurriculumExplorerState build() => CurriculumExplorerState(
    query: CurriculumExplorerQuery(
      scope: pitYearLevel == null ? 'capstone' : 'pit',
      yearLevel: pitYearLevel?.isNotEmpty == true
          ? pitYearLevel!.substring(0, 1)
          : '1',
      view: startAtAssessment ? 'assessment' : 'overview',
      year: startAtAssessment ? '2026-2027' : '',
    ),
  );
  @override
  Future<void> fetch(CurriculumExplorerQuery q) async {
    fetches++;
    if (q.initial && q.year.isEmpty) {
      q = q.copyWith(year: '2026-2027', initial: false);
    }
    final ctx = q.scope == 'capstone' ? 'stage:1' : 'event:1';
    state = CurriculumExplorerState(
      query: q.copyWith(
        context: q.year.isEmpty ? '' : ctx,
        yearFrom: '2025-2026',
        yearTo: '2026-2027',
      ),
      data: {
        'academic_years': ['2025-2026', '2026-2027'],
        'academic_year': q.year,
        'year_from': '2025-2026',
        'year_to': '2026-2027',
        'range_years': ['2025-2026', '2026-2027'],
        'comparison': q.scope == 'capstone' ? 'stage:1' : 'pit:1:expo',
        'comparison_options': [
          if (!noAssessments)
            {
              'id': q.scope == 'capstone' ? 'stage:1' : 'pit:1:expo',
              'label': q.scope == 'capstone'
                  ? 'Concept Proposal'
                  : 'Programming Expo',
            },
        ],
        'stage_results': [
          {
            'id': ctx,
            'label': q.scope == 'capstone'
                ? 'Concept Proposal'
                : 'Programming Expo',
            'score': 70,
            'assessed': 2,
            'eligible': 3,
            'pending': 1,
          },
        ],
        'matched_students': 2,
        'project_status': q.projectStatus,
        'project_output': [
          {'academic_year': '2025-2026', 'count': 1},
          {'academic_year': '2026-2027', 'count': 2},
        ],
        'scope': q.scope,
        'projects_count': 3,
        'performance': {
          'selections': [
            {'id': 'team:1', 'label': 'CloudSync', 'kind': 'team'},
            {'id': 'student:1', 'label': 'Recorded student', 'kind': 'student'},
          ],
          'contexts': [
            if (q.year.isNotEmpty)
              {
                'id': ctx,
                'label': q.scope == 'capstone'
                    ? 'Concept Proposal'
                    : 'Programming Expo',
                'components': [
                  for (final role in [
                    'panel',
                    'peer',
                    if (q.scope == 'capstone') 'adviser',
                  ])
                    {
                      'id': role,
                      'label': '${role[0].toUpperCase()}${role.substring(1)}',
                      'score': unpublished
                          ? null
                          : role == 'peer'
                          ? 80
                          : 70,
                      'assessed': unpublished ? 0 : 2,
                      'eligible': 3,
                      'shared': role == 'peer' ? 0 : 2,
                      'available': true,
                    },
                ],
              },
          ],
        },
        'assessment_summary': {
          'score': unpublished ? null : 70,
          'assessed': unpublished ? 0 : 2,
          'eligible': 3,
          'pending': unpublished ? 3 : 1,
          'teams': _projects(!unpublished),
        },
        'annual_performance': [
          {
            'academic_year': '2025-2026',
            'score': 76.2,
            'assessed': 3,
            'eligible': 3,
          },
          {
            'academic_year': '2026-2027',
            'score': 70.0,
            'assessed': 2,
            'eligible': 3,
            'in_progress': true,
          },
        ],
        'semesters': [
          {'id': '1', 'label': '1st Semester'},
        ],
        'contexts': q.year.isEmpty
            ? []
            : [
                {
                  'id': ctx,
                  'label': q.scope == 'capstone'
                      ? 'Concept Proposal'
                      : 'Programming Expo',
                },
              ],
        'roles': [
          for (final r
              in q.scope == 'capstone'
                  ? ['panel', 'adviser', 'peer']
                  : ['panel', 'peer'])
            {'id': r, 'label': '${r[0].toUpperCase()}${r.substring(1)}'},
        ],
        'criteria': q.year.isEmpty
            ? []
            : [
                {
                  'id': 'problem',
                  'name': 'Problem relevance',
                  'score': 70,
                  'rubric_id': 1,
                  'rubric_name': 'Concept panel rubric',
                  'assessed': 2,
                  'eligible': 3,
                  'below': 1,
                  'target_type': q.role == 'peer' ? 'individual' : 'team',
                  'teams': _projects(true),
                },
              ],
        'projects': _projects(false),
        'project_analytics': {
          'coverage': {
            'with_technologies': unclassified ? 0 : 2,
            'classified': unclassified ? 0 : 2,
            'unresolved': unclassified ? 3 : 1,
            'domains_resolved': 2,
          },
          'categories': [
            if (!unclassified)
              {'category': 'Web Development', 'count': 2, 'percentage': 66.7},
          ],
          'domains': [
            {'category': 'Healthcare', 'count': 1, 'percentage': 33.3},
            {
              'category': 'Agriculture & Environment',
              'count': 1,
              'percentage': 33.3,
            },
            {'category': 'Unresolved domain', 'count': 1, 'percentage': 33.3},
          ],
          'technologies': [
            if (!unclassified)
              {'category': 'React', 'count': 2, 'percentage': 66.7},
          ],
          'unresolved_reasons': [
            {
              'category': 'no_documents',
              'count': unclassified ? 3 : 1,
              'percentage': unclassified ? 100 : 33.3,
            },
          ],
          'observations': [
            '${unclassified ? 0 : 2} of 3 projects have an estimated computing focus.',
          ],
          'performance': [
            if (!unclassified && q.year.isNotEmpty)
              {
                'id': 'problem',
                'name': 'Problem relevance',
                'rubric': 'Concept panel rubric',
                'semester': '1st Semester',
                'target_type': 'team',
                'categories': [
                  {
                    'category': 'Web Development',
                    'score': 70,
                    'assessed_teams': 2,
                    'eligible_teams': 2,
                  },
                ],
              },
          ],
        },
        'project_trends': [
          for (final year in ['2025-2026', '2026-2027'])
            {
              'academic_year': year,
              'projects_count': 3,
              'classified': unclassified ? 0 : 2,
              'distribution': [
                if (!unclassified) {'category': 'Web Development', 'count': 2},
                {'category': 'Unclassified', 'count': unclassified ? 3 : 1},
              ],
              'domains': [
                {'category': 'Healthcare', 'count': 1},
                {'category': 'Agriculture & Environment', 'count': 1},
                {'category': 'Unresolved domain', 'count': 1},
              ],
            },
        ],
        'project_distribution': [
          if (!unclassified)
            {'category': 'Web Development', 'count': 2, 'percentage': 66.7},
          {
            'category': 'Unclassified',
            'count': unclassified ? 3 : 1,
            'percentage': unclassified ? 100 : 33.3,
          },
        ],
      },
    );
  }

  List<Map<String, dynamic>> _projects(bool scores) => [
    for (final (i, name, value) in [
      (1, 'CloudSync', 60),
      (2, 'HarvestLink', 80),
      (3, 'PendingTeam', null),
    ])
      {
        'id': '$i:1',
        'team_name': name,
        'project_title': '$name project',
        'project_version': 1,
        'category': !unclassified && i < 3 ? 'Web Development' : 'Unclassified',
        'domain': i == 1
            ? 'Healthcare'
            : i == 2
            ? 'Agriculture & Environment'
            : 'Unresolved domain',
        'technologies': !unclassified && i < 3 ? ['React'] : [],
        'classification_status': !unclassified && i < 3
            ? 'estimated'
            : 'unresolved',
        'classification_reason_code': !unclassified && i < 3
            ? 'supported'
            : 'no_documents',
        if (scores) 'score': value,
        'assessed': 1,
        'eligible': 2,
      },
  ];
  @override
  Future<Map<String, dynamic>> detail(
    String projectId, {
    bool allAssessments = false,
  }) async => {
    'scope': state.query.scope,
    'classification': {
      'label': unclassified ? 'Unclassified' : 'Web Development',
      'status': unclassified ? 'unresolved' : 'estimated',
      'reason': unclassified
          ? 'No readable project evidence is available.'
          : 'Estimated from project documents.',
      'domain': 'Healthcare',
      'evidence': [
        {
          'term': 'web application',
          'section': 'Objectives',
          'excerpt': 'We implement a web application using React.',
        },
        {
          'term': 'React',
          'section': 'Objectives',
          'excerpt': 'We implement a web application using React.',
        },
      ],
      'domain_evidence': [
        {
          'term': 'patient',
          'section': 'Abstract',
          'excerpt': 'Patients use the proposed application.',
          'document_id': 'doc1',
          'source_label': 'D1 · Project proposal',
        },
      ],
      'model_version': 'project-focus-3.0-test',
      'document_id': 'doc1',
      'source_label': 'D1 · Project proposal',
    },
    'profile': unclassified
        ? {}
        : {
            'description': {
              'text':
                  'CloudSync brings patient registration, appointment scheduling and care records into one proposed web application.',
              'section': 'Background of the Study',
              'document_id': multipleSources ? 'doc3' : 'doc1',
              'source_label': multipleSources
                  ? 'D3 · Approved Concept Paper'
                  : 'D1 · Project proposal',
            },
            'platforms': [
              {
                'name': 'Web',
                'status': 'proposed',
                'section': 'Abstract',
                'document_id': 'doc1',
                'source_label': 'D1 · Project proposal',
              },
            ],
          },
    'assessments': [
      {
        'id': 1,
        'label': state.query.scope == 'capstone'
            ? 'Concept Proposal'
            : 'Programming Expo',
        'academic_year': '2026-2027',
        'semester': '1st Semester',
        'criteria': [
          {
            'name': 'Problem relevance',
            'rubric_id': 1,
            'evaluation_type': 'panel',
            'score': 6,
            'max_score': 10,
            'percentage': 60,
            'records': [
              {
                'evaluator': 'Recorded panelist',
                'score': 6,
                'max_score': 10,
                'remarks': 'Support the problem with stakeholder evidence.',
              },
            ],
          },
        ],
      },
    ],
    'documents': [
      if (multipleSources) ...[
        {
          'id': 'doc2',
          'file_name': 'concept.pdf',
          'display_name': 'D2 · Concept Paper',
          'stage': 'Concept Proposal',
          'status': 'Approved',
          'deliverable_type': 'pre',
          'url': '/api/media/deliverables/concept.pdf',
        },
        {
          'id': 'doc3',
          'file_name': 'approved.pdf',
          'display_name': 'D3 · Approved Concept Paper',
          'stage': 'Concept Proposal',
          'status': 'Approved',
          'deliverable_type': 'post',
          'url': '/api/media/deliverables/approved.pdf',
        },
      ],
      {
        'id': 'doc1',
        'file_name': sourceUrl
            ? 'CloudSync_Proposal.png'
            : 'CloudSync_Proposal.pdf',
        'display_name': 'D1 · Project proposal',
        'deliverable_id': 'D1',
        'label': 'Project proposal',
        'stage': 'Concept Proposal',
        'deliverable_type': 'pre',
        'status': 'Approved',
        'uploaded_by': 'Recorded uploader',
        'uploaded_at': '2026-10-05T08:00:00Z',
        if (sourceUrl) 'url': '/api/media/deliverables/current.png',
        'excerpt': 'This web application supports local users.',
        'topics': ['web application', 'database'],
      },
    ],
  };
}

class _SourceFileClient implements AuthenticatedHttpClient {
  final requests = <String>[];
  bool fail = true;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List> fetchAuthenticatedFile(String fileRef) async {
    requests.add(fileRef);
    if (fail) throw Exception('Failed to load file (404)');
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
