import 'dart:io';
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
import 'package:defensys/theme/defensys_tokens.dart';

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
  bool dark = false,
  bool unclassified = false,
  bool unpublished = false,
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
  tester.view.physicalSize = Size(width, 1100);
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
          ),
        ),
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
      expect(find.text('Source project documents'), findsOneWidget);
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
    expect(find.text('Source project documents'), findsOneWidget);
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
        find.byKey(const ValueKey('project-classification-explanation')),
        findsOneWidget,
      );
      await tester.tap(find.text('web application · Objectives'));
      await tester.pumpAndSettle();
      expect(
        find.text('We implement a web application using React.'),
        findsOneWidget,
      );
      await _capture(tester, 'project-classification-evidence');
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

  for (final dark in [false, true]) {
    testWidgets(
      'fits 320px with ${dark ? 'dark' : 'light'} shadcn components',
      (tester) async {
        await _mount(tester, width: 320, dark: dark);
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
      },
    );
  }
}

class _FakeExplorer extends CurriculumExplorerNotifier {
  _FakeExplorer({this.unclassified = false, this.unpublished = false});
  final bool unclassified, unpublished;
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
      'label': 'Web Development',
      'reason': 'Estimated from project documents.',
      'domain': 'Healthcare',
      'evidence': [
        {
          'term': 'web application',
          'section': 'Objectives',
          'excerpt': 'We implement a web application using React.',
        },
      ],
      'domain_evidence': [
        {
          'term': 'patient',
          'section': 'Abstract',
          'excerpt': 'Patients use the proposed application.',
        },
      ],
      'model_version': 'project-focus-3.0-test',
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
      {
        'id': 'doc1',
        'file_name': 'CloudSync_Proposal.pdf',
        'label': 'Project proposal',
        'excerpt': 'This web application supports local users.',
        'topics': ['web application', 'database'],
      },
    ],
  };
}
