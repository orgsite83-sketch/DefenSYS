import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/widgets/defensys_skeleton.dart';

void main() {
  testWidgets('DefensysSkeleton.list shows placeholder rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefensysSkeleton.list(count: 3, rowHeight: 40),
        ),
      ),
    );

    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('DefensysSkeleton.teamSummaryCard renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefensysSkeleton.teamSummaryCard(),
        ),
      ),
    );

    expect(find.byType(Container), findsWidgets);
  });
}
