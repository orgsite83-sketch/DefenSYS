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
        curriculumExplorerProvider.overrideWith(
          () => _FakeExplorer(
            unclassified: unclassified,
            unpublished: unpublished,
            sourceUrl: sourceClient != null,
            multipleSources: multipleSources,
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
          home: Scaffold(body: const CurriculumAnalyticsScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'year > criterion > team > source evidence, with null and individual states',
    (tester) async {
      await _mount(tester);
      expect(find.byType(SfCartesianChart), findsNothing);
      expect(find.byType(ShadTabs<String>), findsWidgets);
      expect(find.text('Performance by criterion'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cohort-primary-metric')),
        findsOneWidget,
      );
      expect(find.text('Review priorities'), findsOneWidget);
      await _capture(tester, 'performance-overview');
      await tester.tap(find.byKey(const ValueKey('compare-academic-years')));
      await tester.pumpAndSettle();
      expect(find.byType(SfCartesianChart), findsOneWidget);
      await _capture(tester, 'academic-years');
      await tester.tap(find.byKey(const ValueKey('year-2026-2027')));
      await tester.pumpAndSettle();
      expect(find.text('Performance by criterion'), findsOneWidget);
      expect(find.byType(SfCartesianChart), findsNothing);
      await _capture(tester, 'criteria');
      await tester.tap(find.byKey(const ValueKey('criterion-problem')));
      await tester.pumpAndSettle();
      expect(find.text('Problem relevance / teams'), findsOneWidget);
      expect(find.byKey(const ValueKey('team-1:1')), findsOneWidget);
      await _capture(tester, 'teams');
      await tester.tap(find.byKey(const ValueKey('team-1:1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('curriculum-evidence-dialog')),
        findsOneWidget,
      );
      expect(find.text('Recorded rubric results'), findsOneWidget);
      expect(find.textContaining('6.00 / 10'), findsOneWidget);
      expect(
        find.textContaining('Support the problem with stakeholder evidence.'),
        findsOneWidget,
      );
      await _capture(tester, 'evidence');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Problem relevance / teams'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-pending')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team-3:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-1:1')), findsNothing);
      expect(find.text('Awaiting'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project focus bars have independent counts and accessible category drilldown',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      expect(find.byType(SfCircularChart), findsNothing);
      expect(find.text('Primary computing focus'), findsOneWidget);
      expect(find.text('Application domains'), findsOneWidget);
      expect(find.text('Classification coverage'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      await _capture(tester, 'project-focus');
      await tester.tap(find.byKey(const ValueKey('category-Web Development')));
      await tester.pumpAndSettle();
      expect(find.text('Web Development projects'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-1:1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-overview')), findsOneWidget);
      expect(find.text('Background of the Study'), findsOneWidget);
      expect(find.text('Source excerpt'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('project-dialog-title')),
        findsOneWidget,
      );
      expect(find.text('CloudSync · Version 1'), findsOneWidget);
      expect(find.text('D1 · Project proposal'), findsOneWidget);
      expect(find.text('Computing focus source'), findsNothing);
      expect(find.text('Main features'), findsNothing);
      expect(find.text('Recorded rubric results'), findsNothing);
      await _capture(tester, 'project-overview-desktop');
      await tester.tap(find.byKey(const ValueKey('project-view-sources')));
      await tester.pumpAndSettle();
      expect(find.text('Project documents'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT resets Capstone state and uses its own events and year level',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('PIT'));
      await tester.pumpAndSettle();
      expect(find.text('PIT year level'), findsOneWidget);
      expect(find.byType(SfCartesianChart), findsNothing);
      expect(find.text('Concept Proposal'), findsNothing);
      expect(find.text('Event'), findsOneWidget);
      expect(find.text('Adviser'), findsNothing);
      expect(find.textContaining('Programming Expo'), findsWidgets);
      await _capture(tester, 'pit-events');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unclassified cohort opens real projects without a pie', (
    tester,
  ) async {
    await _mount(tester, unclassified: true);
    await tester.tap(find.text('Project insights'));
    await tester.pumpAndSettle();
    expect(find.byType(SfCircularChart), findsNothing);
    expect(find.text('Unresolved focus'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    expect(
      find.textContaining('No supported computing estimates yet.'),
      findsOneWidget,
    );
    await _capture(tester, 'projects-unclassified');
    await tester.ensureVisible(
      find.byKey(const ValueKey('category-Unclassified')),
    );
    await tester.tap(find.byKey(const ValueKey('category-Unclassified')));
    await tester.pumpAndSettle();
    expect(find.text('Unclassified projects'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-1:1')));
    await tester.pumpAndSettle();
    expect(find.text('Computing focus needs more evidence'), findsOneWidget);
    expect(
      find.text(
        'Platform and technologies have not been identified in the available text.',
      ),
      findsOneWidget,
    );
    expect(find.text('Platform'), findsNothing);
    expect(find.text('Documented technologies'), findsNothing);
    expect(find.textContaining('No readable background'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-view-sources')));
    await tester.pumpAndSettle();
    expect(find.text('Project documents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unpublished grades stay empty while rubric evidence remains usable',
    (tester) async {
      await _mount(tester, unpublished: true);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('No published grades yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('criterion-problem')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-problem')));
      await tester.pumpAndSettle();
      expect(find.text('Problem relevance / teams'), findsOneWidget);
      expect(find.byKey(const ValueKey('team-1:1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('project overview fits narrow dark layout', (tester) async {
    await _mount(tester, width: 320, dark: true, unclassified: true);
    await tester.ensureVisible(find.text('Project insights'));
    await tester.tap(find.text('Project insights'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('category-Unclassified')),
    );
    await _capture(tester, 'projects-phone-dark');
  });

  testWidgets(
    'domain and technology bars open only their contributing projects',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('domain-Healthcare')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-2:1')), findsNothing);
      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('technology-React')),
      );
      await tester.tap(find.byKey(const ValueKey('technology-React')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-2:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-3:1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus performance cell drills into category-filtered rubric teams',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      final cell = find.byKey(
        const ValueKey('focus-performance-problem-Web Development'),
      );
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await _capture(tester, 'project-performance-heatmap');
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.text('Project focus: Web Development'), findsOneWidget);
      expect(find.byKey(const ValueKey('team-1:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-3:1')), findsNothing);
      await tester.tap(find.text('Show all teams'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team-3:1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project evidence explains estimates with actual source passages',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.text('Project insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-Web Development')));
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
      await tester.tap(find.byKey(const ValueKey('category-Web Development')));
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

  testWidgets('classified chart layout fits narrow light mode', (tester) async {
    await _mount(tester, width: 320);
    await tester.ensureVisible(find.text('Project insights'));
    await tester.tap(find.text('Project insights'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('project-trend-year-2026-2027')),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'project-trends-phone-light');
    expect(tester.takeException(), isNull);
  });

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

class _FakeExplorer extends CurriculumExplorerNotifier {
  _FakeExplorer({
    this.unclassified = false,
    this.unpublished = false,
    this.sourceUrl = false,
    this.multipleSources = false,
  });
  final bool unclassified, unpublished, sourceUrl, multipleSources;
  @override
  CurriculumExplorerState build() => const CurriculumExplorerState();
  @override
  Future<void> fetch(CurriculumExplorerQuery q) async {
    final ctx = q.scope == 'capstone' ? 'stage:1' : 'event:1';
    state = CurriculumExplorerState(
      query: q.copyWith(context: q.year.isEmpty ? '' : ctx),
      data: {
        'academic_years': ['2025-2026', '2026-2027'],
        'scope': q.scope,
        'projects_count': 3,
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
