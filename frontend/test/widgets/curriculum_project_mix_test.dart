import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/widgets/curriculum_workspace_views.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/theme/defensys_tokens.dart';

final captureKey = GlobalKey();
Future<void> capture(WidgetTester tester, String name) async {
  final path = Platform.environment['CURRICULUM_CAPTURE_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final rendered =
        await (captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    Directory(path).createSync(recursive: true);
    File('$path/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    rendered.dispose();
  });
}

final projects = <Map<String, dynamic>>[
  for (final (area, count) in [
    ('Events & Community Engagement', 3),
    ('Information & Document Services', 2),
    ('Learning & Academic Support', 2),
    ('Food & Dining Services', 1),
    ('Health & Wellbeing', 1),
    ('Helpdesk & Inquiries', 1),
    ('Library & Resource Services', 1),
    ('Lost & Found Services', 1),
    ('Onboarding & Orientation', 1),
    ('Printing Services', 1),
  ])
    for (var i = 0; i < count; i++)
      {
        'application_area': area,
        'category': 'Information Systems',
        'domain': 'Education',
        'technologies': <String>[],
      },
];

Future<void> mount(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  List<Map<String, dynamic>>? rows,
  void Function(String, String)? onGroup,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fonts = FontLoader('Inter');
  fonts.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  fonts.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await fonts.load();
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
  icons.addFont(
    rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
  );
  await icons.load();
  var dimension = 'application_area';
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: 'Inter',
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: dark
                ? DefensysTokens.mistBackground
                : DefensysTokens.background,
            child: DefensysShadcnScope(
              child: StatefulBuilder(
                builder: (_, setState) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: CurriculumProjectMix(
                    data: {
                      'projects': rows ?? projects,
                      'project_analytics': {
                        'coverage': {
                          'classified': (rows ?? projects).length,
                          'with_technologies': 0,
                        },
                      },
                    },
                    status: 'completed',
                    onStatus: (_) {},
                    onGroup: onGroup ?? (_, _) {},
                    onOutput: () {},
                    dimension: dimension,
                    onDimension: (value) => setState(() => dimension = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'purpose ranks preserve counts, expand all groups and drill into the selected area',
    (tester) async {
      List<String>? selected;
      await mount(tester, onGroup: (field, value) => selected = [field, value]);
      expect(find.text('14 completed projects'), findsOneWidget);
      expect(find.text('3 / 14 · 21%'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('project-group-application_area-Printing Services'),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'project-group-application_area-Events & Community Engagement',
          ),
        ),
      );
      expect(selected, ['application_area', 'Events & Community Engagement']);
      await tester.ensureVisible(
        find.byKey(const ValueKey('show-project-groups')),
      );
      await tester.tap(find.byKey(const ValueKey('show-project-groups')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('project-group-application_area-Printing Services'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1440.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'mixed purposes and one-category focus fit $width ${dark ? 'dark' : 'light'}',
        (tester) async {
          await mount(tester, width: width, dark: dark);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'project-mix-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          if (width < 500) {
            await tester.tap(
              find.byKey(
                const ValueKey('project-mix-dimension-application_area'),
              ),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Project focus').last);
          await tester.pumpAndSettle();
          expect(
            find.text('All 14 projects share this computing focus.'),
            findsOneWidget,
          );
          expect(find.text('14 / 14 · 100%'), findsOneWidget);
          await capture(
            tester,
            'project-focus-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          if (width < 500) {
            await tester.tap(
              find.byKey(const ValueKey('project-mix-dimension-category')),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Domain').last);
          await tester.pumpAndSettle();
          expect(
            find.text('All 14 projects share this domain.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'missing purpose evidence stays explicit and empty selections have no bars',
    (tester) async {
      await mount(
        tester,
        rows: [
          {'category': 'Unclassified', 'domain': 'Unresolved domain'},
        ],
      );
      expect(find.text('Unresolved application area'), findsOneWidget);
      expect(
        find.text('The project needs more evidence for this grouping.'),
        findsOneWidget,
      );
      await mount(tester, rows: []);
      expect(find.text('No projects match this selection'), findsOneWidget);
      expect(find.byKey(const ValueKey('project-mix-bars')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
