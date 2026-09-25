import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/table/table.dart';

import '../helpers/pump_app.dart';

void main() {
  final sampleItems = [
    {'id': 1, 'name': 'Item One', 'stage': 'Concept', 'status': 'Active'},
    {'id': 2, 'name': 'Item Two', 'stage': 'Final', 'status': 'Pending'},
  ];

  final sampleColumns = [
    DefensysTableColumn<Map<String, dynamic>>(
      title: 'NAME',
      flex: 1.5,
      minWidth: 200,
      cellBuilder: (context, item, _) => Text(item['name'] as String),
    ),
    DefensysTableColumn<Map<String, dynamic>>(
      title: 'DEFENSE STAGE',
      flex: 1.0,
      minWidth: 150,
      cellBuilder: (context, item, _) => DefensysTableCell.stageBadge(item['stage'] as String),
    ),
    DefensysTableColumn<Map<String, dynamic>>(
      title: 'STATUS',
      flex: 0.8,
      minWidth: 100,
      cellBuilder: (context, item, _) => Text(item['status'] as String),
    ),
  ];

  testWidgets('DefensysDataTable renders headers and rows in wide container', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      DefensysDataTable<Map<String, dynamic>>(
        items: sampleItems,
        columns: sampleColumns,
      ),
    );

    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('DEFENSE STAGE'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);

    expect(find.text('Item One'), findsOneWidget);
    expect(find.text('Item Two'), findsOneWidget);
    expect(find.text('Concept'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
  });

  testWidgets('DefensysDataTable sticky action column stays pinned', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool actionTapped = false;

    await pumpDefensysWidget(
      tester,
      DefensysDataTable<Map<String, dynamic>>(
        items: sampleItems,
        columns: sampleColumns,
        stickyActionColumn: DefensysActionColumn(
          title: 'ACTION',
          width: 80,
          builder: (context, item, index) => IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => actionTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('ACTION'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    expect(actionTapped, isTrue);
  });

  testWidgets('DefensysDataTable renders skeleton loader when isLoading is true', (tester) async {
    await pumpDefensysWidget(
      tester,
      DefensysDataTable<Map<String, dynamic>>(
        items: const [],
        columns: sampleColumns,
        isLoading: true,
        skeletonRowCount: 4,
      ),
    );

    // Items should not be displayed
    expect(find.text('Item One'), findsNothing);
  });

  testWidgets('DefensysDataTable renders empty state when items list is empty', (tester) async {
    await pumpDefensysWidget(
      tester,
      DefensysDataTable<Map<String, dynamic>>(
        items: const [],
        columns: sampleColumns,
        isLoading: false,
      ),
    );

    expect(find.text('No records found'), findsOneWidget);
  });

  testWidgets('DefensysSegmentedControl renders items and fires onChanged', (tester) async {
    String selected = 'active';

    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          return DefensysSegmentedControl<String>(
            value: selected,
            items: const [
              DefensysSegmentItem(value: 'active', label: 'Current Term'),
              DefensysSegmentItem(value: 'history', label: 'History'),
            ],
            onChanged: (val) {
              setState(() => selected = val);
            },
          );
        },
      ),
    );

    expect(find.text('Current Term'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(selected, 'history');
  });

  testWidgets('DefensysTableCard renders search field and filter bar', (tester) async {
    final searchCtrl = TextEditingController(text: 'Initial');
    String submittedQuery = '';

    await pumpDefensysWidget(
      tester,
      DefensysTableCard(
        searchController: searchCtrl,
        searchHint: 'Search test...',
        onSearchSubmitted: (q) => submittedQuery = q,
        filterControls: const [
          Text('Filter Slot'),
        ],
        child: const Text('Table Content'),
      ),
    );

    expect(find.text('Filter Slot'), findsOneWidget);
    expect(find.text('Table Content'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Test clear button
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(searchCtrl.text, isEmpty);
    expect(submittedQuery, isEmpty);
  });

  testWidgets('DefensysTablePagination displays page information and navigates', (tester) async {
    int page = 0;
    int rows = 10;

    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          return DefensysTablePagination(
            currentPage: page,
            totalItems: 35,
            rowsPerPage: rows,
            itemLabel: 'rubrics',
            onPageChanged: (p) => setState(() => page = p),
            onRowsPerPageChanged: (r) => setState(() => rows = r),
          );
        },
      ),
    );

    expect(find.text('Showing 1–10 of 35 rubrics'), findsOneWidget);

    // Tap page 2 button
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(page, 1);
    expect(find.text('Showing 11–20 of 35 rubrics'), findsOneWidget);
  });
}
