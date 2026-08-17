import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/searchable_entity_picker.dart';

void main() {
  group('SearchableEntityPicker Widget Tests', () {
    final sampleItems = [
      const EntityPickerItem<String>(
        value: '4011',
        label: 'Marcus VILLAR',
        badge: '4011',
        subtitle: 'Team Alpha • BSCS-4A',
        avatarText: 'MV',
      ),
      const EntityPickerItem<String>(
        value: '4012',
        label: 'Patricia ONG',
        badge: '4012',
        subtitle: 'Team Alpha • BSCS-4A',
        avatarText: 'PO',
      ),
      const EntityPickerItem<String>(
        value: '4013',
        label: 'Ethan SALAZAR',
        badge: '4013',
        subtitle: 'Team Beta • BSIT-4B',
        avatarText: 'ES',
      ),
    ];

    testWidgets('renders hint text when no item is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableEntityPicker<String>(
              items: sampleItems,
              selectedValue: null,
              onChanged: (_) {},
              hintText: 'Search student by ID or name...',
            ),
          ),
        ),
      );

      expect(find.text('Search student by ID or name...'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('renders selected item label and badge when selectedValue is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableEntityPicker<String>(
              items: sampleItems,
              selectedValue: '4011',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Marcus VILLAR'), findsOneWidget);
      expect(find.text('4011'), findsOneWidget);
      expect(find.text('Team Alpha • BSCS-4A'), findsOneWidget);
    });

    testWidgets('opens dropdown overlay on tap and filters items on search', (tester) async {
      String? selectedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SearchableEntityPicker<String>(
                  items: sampleItems,
                  selectedValue: selectedValue,
                  onChanged: (val) {
                    setState(() {
                      selectedValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Tap to open
      await tester.tap(find.byType(SearchableEntityPicker<String>));
      await tester.pumpAndSettle();

      // All 3 items should appear in overlay
      expect(find.text('Marcus VILLAR'), findsOneWidget);
      expect(find.text('Patricia ONG'), findsOneWidget);
      expect(find.text('Ethan SALAZAR'), findsOneWidget);

      // Search for 'Ethan'
      await tester.enterText(find.byType(TextField), 'Ethan');
      await tester.pumpAndSettle();

      // Marcus and Patricia should be filtered out
      expect(find.text('Ethan SALAZAR'), findsOneWidget);
      expect(find.text('Marcus VILLAR'), findsNothing);
      expect(find.text('Patricia ONG'), findsNothing);

      // Tap Ethan to select
      await tester.tap(find.text('Ethan SALAZAR'));
      await tester.pumpAndSettle();

      // Selected state should now show Ethan
      expect(selectedValue, equals('4013'));
      expect(find.text('Ethan SALAZAR'), findsOneWidget);
    });
  });
}
