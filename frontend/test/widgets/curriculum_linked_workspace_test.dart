import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/curriculum_analytics_screen.dart';
import 'package:defensys/services/academic/curriculum_explorer_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

final _capture = GlobalKey();
const _years = ['2025-2026', '2026-2027'];
const _projects = [
  {
    'id': '1:1',
    'academic_year': '2025-2026',
    'project_title': 'Learning resource portal',
    'team_name': 'Aster',
    'application_area': 'Academic support',
    'domain': 'Education',
    'category': 'Unclassified',
    'classification_status': 'unresolved',
    'technologies': ['Flutter'],
  },
  {
    'id': '2:1',
    'academic_year': '2026-2027',
    'project_title': 'Clinic appointment system',
    'team_name': 'Bayan',
    'application_area': 'Appointment services',
    'domain': 'Health',
    'category': 'Web Development',
    'classification_status': 'estimated',
    'technologies': ['React'],
  },
  {
    'id': '3:1',
    'academic_year': '2026-2027',
    'project_title': 'Student records service',
    'team_name': 'Luntian',
    'application_area': 'Academic support',
    'domain': 'Education',
    'category': 'Information Systems',
    'classification_status': 'estimated',
    'technologies': ['Django'],
  },
];

Future<(ProviderContainer, List<Uri>)> _mount(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  bool performance = false,
}) async {
  registerFallbackValue(Uri.parse('http://localhost'));
  final client = _Client(), requests = <Uri>[];
  final font = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await font.load();
  await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      ))
      .load();
  when(() => client.get(any())).thenAnswer((invocation) async {
    final uri = invocation.positionalArguments[0] as Uri;
    requests.add(uri);
    final context = uri.queryParameters['context'] ?? 'stage:1';
    final role = uri.queryParameters['evaluation_type'] ?? 'panel';
    final contexts = [
      {
        'id': 'stage:1',
        'label': 'Proposal',
        'components': [
          {
            'id': 'panel',
            'label': 'Panel',
            'score': 82,
            'available': true,
            'assessed': 2,
            'eligible': 3,
          },
        ],
      },
      {
        'id': 'stage:2',
        'label': 'Final defense',
        'components': [
          {
            'id': 'panel',
            'label': 'Panel',
            'score': 89,
            'available': true,
            'assessed': 2,
            'eligible': 3,
          },
          {
            'id': 'peer',
            'label': 'Peer',
            'score': 86,
            'available': true,
            'assessed': 2,
            'eligible': 3,
          },
        ],
      },
    ];
    Map<String, dynamic> criterion(String id, String name) => {
      'id': id,
      'name': name,
      'score': 86,
      'rubric_name': 'Final rubric',
      'target_type': 'team',
      'assessed': 2,
      'eligible': 3,
      'below': 0,
    };
    final evidence = !uri.queryParameters.containsKey('workspace');
    final activeCriterion = context == 'stage:1'
        ? criterion('problem', 'Problem relevance')
        : role == 'peer'
        ? criterion('contribution', 'Contribution')
        : criterion('implementation', 'Implementation');
    return http.Response(
      jsonEncode({
        'scope': 'capstone',
        'academic_year': '2026-2027',
        'academic_years': _years,
        'year_from': _years.first,
        'year_to': _years.last,
        'range_years': _years,
        'context': context,
        'evaluation_type': role,
        if (!performance) 'project_collection': _projects,
        'projects': _projects,
        'project_output': [
          {'academic_year': _years.first, 'count': 1},
          {'academic_year': _years.last, 'count': 2},
        ],
        if (performance) ...{
          'contexts': [
            for (final c in contexts) {'id': c['id'], 'label': c['label']},
          ],
          'performance': {'contexts': contexts, 'selections': []},
          'criteria': [
            if (evidence)
              {
                ...activeCriterion,
                'teams': [
                  for (var i = 0; i < _projects.length; i++)
                    {
                      ..._projects[i],
                      'score': i == 0
                          ? 88
                          : i == 1
                          ? 84
                          : null,
                    },
                ],
              }
            else
              activeCriterion,
          ],
          'criteria_complete': evidence,
          'assessment_bundles': {
            'stage:1': {
              'panel': {
                'criteria': [criterion('problem', 'Problem relevance')],
              },
            },
            'stage:2': {
              'panel': {
                'criteria': [criterion('implementation', 'Implementation')],
              },
              'peer': {
                'criteria': [criterion('contribution', 'Contribution')],
              },
            },
          },
        },
      }),
      200,
    );
  });
  final container = ProviderContainer(
    overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  await container
      .read(curriculumExplorerProvider.notifier)
      .fetch(
        CurriculumExplorerQuery(
          view: performance ? 'year' : 'projects',
          year: performance ? _years.last : '',
        ),
      );
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: DefensysTokens.fontFamilyInter,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          backgroundColor: dark
              ? DefensysTokens.mistBackground
              : DefensysTokens.background,
          body: RepaintBoundary(
            key: _capture,
            child: ColoredBox(
              color: dark
                  ? DefensysTokens.mistBackground
                  : DefensysTokens.background,
              child: const CurriculumAnalyticsScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, requests);
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['CURRICULUM_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  testWidgets('project year and ranking remain linked without refetching', (
    tester,
  ) async {
    final (container, requests) = await _mount(tester);
    expect(requests, hasLength(1));
    expect(
      find.byKey(const ValueKey('project-yearly-mix-chart')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('project-group-application_area-Appointment services'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('project-yearly-mix-chart')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('project-2:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-3:1')), findsNothing);
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project insights'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-2:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-3:1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('project-year-2025-2026')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(container.read(curriculumExplorerProvider).query.year, _years.first);
    expect(find.byKey(const ValueKey('project-1:1')), findsOneWidget);
    expect(
      find.textContaining('Education · Flutter · Needs review'),
      findsOneWidget,
    );
    await _screenshot(tester, 'linked-projects-light');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an evaluator selection updates only its criteria with no workspace request',
    (tester) async {
      final (container, requests) = await _mount(tester, performance: true);
      expect(find.text('Proposal · Panel criteria'), findsOneWidget);
      await tester.tap(find.text('Assessment coverage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('assessment-stage:2-peer')),
      );
      await tester.tap(find.byKey(const ValueKey('assessment-stage:2-peer')));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('Final defense · Peer criteria'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('criterion-contribution')),
        findsOneWidget,
      );
      expect(container.read(curriculumExplorerProvider).query.role, 'peer');
      expect(find.byKey(const ValueKey('criterion-problem')), findsNothing);
      expect(
        find.byKey(const ValueKey('performance-clustered-chart')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('criterion-contribution')),
      );
      await tester.tap(find.byKey(const ValueKey('criterion-contribution')));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(find.textContaining('0 of 2 assessed teams'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('performance-clustered-chart')),
        findsOneWidget,
      );
      expect(
        explorerRows(
          (container.read(curriculumExplorerProvider).data['performance']
              as Map)['contexts'],
        ),
        hasLength(2),
      );
      await tester.tap(find.byKey(const ValueKey('criterion-contribution')));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      await tester.ensureVisible(find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(
        container.read(curriculumExplorerProvider).data['criteria_complete'],
        true,
      );
      expect(
        explorerRows(
          (container.read(curriculumExplorerProvider).data['performance']
              as Map)['contexts'],
        ),
        hasLength(2),
      );
      await _screenshot(tester, 'linked-performance-light');
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 900.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('linked workspace fits $width ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        await _mount(tester, width: width, dark: dark);
        await _screenshot(
          tester,
          'linked-projects-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
