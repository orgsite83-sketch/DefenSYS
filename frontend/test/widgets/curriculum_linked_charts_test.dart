import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/widgets/curriculum_project_distribution.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/widgets/curriculum_chart_palette.dart';
import 'package:defensys/theme/defensys_tokens.dart';

const projects = <Map<String, dynamic>>[
  {
    'id': '1:1',
    'technologies': ['React', 'Django', 'React'],
    'domain': 'Healthcare',
    'category': 'Web Development',
  },
  {
    'id': '2:1',
    'technologies': ['Flutter', 'Firebase'],
    'domain': 'Education',
    'category': 'Mobile Development',
  },
  {
    'id': '3:1',
    'technologies': ['React', 'Firebase'],
    'domain': 'Healthcare',
    'category': 'Web Development',
  },
  {
    'id': '4:1',
    'technologies': [],
    'domain': 'Unresolved domain',
    'category': 'Unclassified',
  },
];

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'three-slice technology pie fits 320px in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final fonts = FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
        await fonts.load();
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var ranking = 'domain';
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: 'Inter',
              brightness: dark ? Brightness.dark : Brightness.light,
              scaffoldBackgroundColor: dark
                  ? DefensysTokens.mistBackground
                  : DefensysTokens.background,
            ),
            home: Scaffold(
              body: DefensysShadcnScope(
                child: StatefulBuilder(
                  builder: (_, setState) => SingleChildScrollView(
                    child: CurriculumProjectDistribution(
                      projects: projects,
                      technology: null,
                      ranking: ranking,
                      onTechnology: (_) {},
                      onRanking: (value) => setState(() => ranking = value),
                      onGroup: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('technology-usage-pie')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Project focus'));
        await tester.tap(find.text('Project focus'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('category-Web Development')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pie counts uses once per project and tabs preserve the selected technology',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? technology;
      var ranking = 'domain';
      List<String>? selectedGroup;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefensysShadcnScope(
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: CurriculumProjectDistribution(
                    projects: projects,
                    technology: technology,
                    ranking: ranking,
                    onTechnology: (value) => setState(() => technology = value),
                    onRanking: (value) => setState(() => ranking = value),
                    onGroup: (field, group) => selectedGroup = [field, group],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chart = tester.widget<SfCircularChart>(
        find.byKey(const ValueKey('technology-usage-pie')),
      );
      final series =
          chart.series.single as PieSeries<Map<String, dynamic>, String>;
      expect(series.dataSource!.map((r) => r['count']).toList(), [2, 2, 2]);
      expect(series.dataSource!.map((r) => r['name']).toList(), [
        'Firebase',
        'React',
        'Other technologies',
      ]);
      final context = tester.element(
        find.byType(CurriculumProjectDistribution),
      );
      expect(
        series.pointColorMapper!(series.dataSource![0], 0),
        CurriculumChartPalette.primary(context),
      );
      expect(
        series.pointColorMapper!(series.dataSource![2], 2),
        CurriculumChartPalette.neutral(context),
      );
      expect(
        find.text('3 / 4 projects have documented technologies.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('technology-Firebase')));
      await tester.pumpAndSettle();
      expect(find.text('Firebase · 2 unique projects'), findsOneWidget);
      await tester.tap(find.text('Project focus'));
      await tester.pumpAndSettle();
      expect(find.text('Firebase · 2 unique projects'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('category-Mobile Development')),
      );
      expect(selectedGroup, ['category', 'Mobile Development']);
      await tester.tap(find.byKey(const ValueKey('technology-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('technology-Flutter')));
      await tester.pumpAndSettle();
      expect(find.text('Flutter · 1 unique projects'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('category-Web Development')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('clear-project-technology')));
      await tester.pumpAndSettle();
      expect(find.text('All technologies · 4 unique projects'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
