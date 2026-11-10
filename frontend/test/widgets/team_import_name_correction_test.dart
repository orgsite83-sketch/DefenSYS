import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/team_import_reference_corrections.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';

const johnley = 'MATABALAN, Johnley L.';
const unresolved = <Map<String, dynamic>>[
  {'field': 'member_ids', 'reference': johnley, 'status': 'ambiguous'},
  {'field': 'leader_id', 'reference': johnley, 'status': 'ambiguous'},
  {
    'field': 'adviser_name',
    'reference': 'GINBERT A. FERNANDEZ',
    'status': 'selection_required',
  },
];

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  testWidgets(
    'correction selects one of duplicate accounts and updates member and leader IDs',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = <Map<String, dynamic>>[
        {
          'team_name': 'CodeCrafters',
          'section': 'BSIT-3D',
          'project_title': '',
          'member_ids': [johnley, 'other'],
          'leader_id': johnley,
          'adviser_name': 'GINBERT A. FERNANDEZ',
        },
      ];
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeamBulkImportReviewTable(
                rows: rows,
                previewRows: const [
                  {
                    'row': 1,
                    'ready': false,
                    'issues': ['Select the registered account.'],
                    'reference_resolutions': unresolved,
                  },
                ],
                isCapstoneAdmin: true,
                pitLeadYear: null,
                showIssuesOnly: false,
                studentOptions: const [
                  {
                    'id': 900,
                    'username': '2023304712',
                    'name': 'JOHNLEY L MATABALAN',
                  },
                  {
                    'id': 901,
                    'username': 'duplicate-student',
                    'name': 'JOHNLEY L MATABALAN',
                  },
                ],
                adviserOptions: const [
                  {'id': 999, 'username': '207', 'name': 'GINBERT FERNANDEZ'},
                ],
                onRowChanged: (_) => changes++,
                onDeleteRow: (_) {},
                onAddRow: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Select account'),
        findsNWidgets(2),
      ); // Leader shares the member correction.
      await tester.tap(
        find.byKey(const ValueKey('resolve-member_ids-$johnley')),
      );
      await tester.pumpAndSettle();
      expect(find.text('JOHNLEY L MATABALAN (2023304712)'), findsOneWidget);
      expect(
        find.text('JOHNLEY L MATABALAN (duplicate-student)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('select-account-2023304712')));
      await tester.pumpAndSettle();
      expect(rows.single['member_ids'], ['2023304712', 'other']);
      expect(rows.single['leader_id'], '2023304712');
      expect(changes, 1);
      await tester.tap(
        find.byKey(const ValueKey('resolve-adviser_name-GINBERT A. FERNANDEZ')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-account-207')));
      await tester.pumpAndSettle();
      expect(rows.single['adviser_name'], '207');
      expect(rows.single['adviser_id'], '207');
      expect(changes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an open correction cannot change another team after its row is removed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = <Map<String, dynamic>>[
        {
          'team_name': 'Removed team',
          'member_ids': [johnley],
          'leader_id': johnley,
        },
        {
          'team_name': 'Remaining team',
          'member_ids': ['remaining'],
          'leader_id': 'remaining',
        },
      ];
      late StateSetter refresh;
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return SingleChildScrollView(
                  child: TeamBulkImportReviewTable(
                    rows: rows,
                    previewRows: const [
                      {'row': 1, 'reference_resolutions': unresolved},
                    ],
                    isCapstoneAdmin: true,
                    pitLeadYear: null,
                    showIssuesOnly: false,
                    studentOptions: const [
                      {'username': '2023304712', 'name': 'JOHNLEY L MATABALAN'},
                    ],
                    onRowChanged: (_) => changes++,
                    onDeleteRow: (_) {},
                    onAddRow: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('resolve-member_ids-$johnley')),
      );
      await tester.pumpAndSettle();
      refresh(() => rows.removeAt(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-account-2023304712')));
      await tester.pumpAndSettle();
      expect(rows.single['member_ids'], ['remaining']);
      expect(rows.single['leader_id'], 'remaining');
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual registered ID works with an empty account list and keyboard open',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefensysShadcnScope(
              child: TeamImportReferenceCorrections(
                resolutions: [unresolved.first],
                onSelected: (_, username) => selected = username,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, '2023304712');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use ID and validate'));
      await tester.tap(find.text('Use ID and validate'));
      await tester.pumpAndSettle();
      expect(selected, '2023304712');
      expect(tester.takeException(), isNull);
    },
  );

  for (final useFieldPicker in [false, true]) {
    testWidgets(
      'one adviser selection updates the batch using field picker=$useFieldPicker',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rows = <Map<String, dynamic>>[
          {
            'team_name': 'First team',
            'section': 'BSIT-3A',
            'member_ids': ['a'],
            'leader_id': 'a',
            'adviser_name': 'GINBERT A. FERNANDEZ',
          },
          {
            'team_name': 'Second team',
            'section': 'BSIT-4D',
            'member_ids': ['b'],
            'leader_id': 'b',
            'adviser_name': 'FERNANDEZ, Ginbert A',
          },
        ];
        final changed = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TeamBulkImportReviewTable(
                  rows: rows,
                  previewRows: [
                    for (var i = 0; i < rows.length; i++)
                      {
                        'row': i + 1,
                        'reference_resolutions': [
                          {
                            'field': 'adviser_name',
                            'reference': rows[i]['adviser_name'],
                            'status': 'ambiguous',
                            'reference_key': 'ginbert a fernandez',
                          },
                        ],
                      },
                  ],
                  isCapstoneAdmin: true,
                  pitLeadYear: null,
                  showIssuesOnly: false,
                  adviserOptions: const [
                    {'username': '207', 'name': 'GINBERT A FERNANDEZ'},
                    {'username': '208', 'name': 'GINBERT A FERNANDEZ'},
                  ],
                  onRowChanged: changed.add,
                  onDeleteRow: (_) {},
                  onAddRow: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          useFieldPicker
              ? find.byKey(const ValueKey('adviser_selector_1'))
              : find.byKey(
                  const ValueKey('resolve-adviser_name-GINBERT A. FERNANDEZ'),
                ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          useFieldPicker
              ? find.text('@207')
              : find.byKey(const ValueKey('select-account-207')),
        );
        await tester.pumpAndSettle();
        expect(rows.map((r) => r['adviser_name']), ['207', '207']);
        expect(changed, [0, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [390.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('correction picker fits $width ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundaryKey = GlobalKey();
        String? selected;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness, fontFamily: 'Inter'),
              home: Scaffold(
                body: DefensysShadcnScope(
                  child: TeamImportReferenceCorrections(
                    resolutions: const [
                      {
                        'field': 'member_ids',
                        'reference': 'BONGCAC, Ryza Mae G.',
                        'status': 'not_found',
                      },
                      {
                        'field': 'adviser_name',
                        'reference': 'GINBERT A. FERNANDEZ',
                        'status': 'matched',
                        'match_kind': 'omitted_initial',
                        'name': 'GINBERT FERNANDEZ',
                        'username': '207',
                      },
                    ],
                    students: const [
                      {
                        'username': 'client-ryza',
                        'name': 'RYZA MAY G. BONGCAC',
                      },
                    ],
                    faculty: const [
                      {'username': '207', 'name': 'GINBERT FERNANDEZ'},
                    ],
                    onSelected: (_, username) => selected = username,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('resolve-member_ids-BONGCAC, Ryza Mae G.')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Uploaded reference: BONGCAC, Ryza Mae G.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Spelling differs: MAE versus MAY'), findsOneWidget);
        expect(selected, isNull);
        if (Platform.environment['DEFENSYS_REVIEW_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../.tmp/client-name-correction-${width.toInt()}-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(
          find.byKey(const ValueKey('select-account-client-ryza')),
        );
        await tester.pumpAndSettle();
        expect(selected, 'client-ryza');
      });
    }
  }
}
