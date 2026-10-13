import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_presets.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_presets_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StageDeliverablePresetManager', () {
    test('builtInPresets contains standard academic milestones', () {
      final presets = StageDeliverablePresetManager.builtInPresets;
      expect(presets.length, greaterThanOrEqualTo(3));

      final concept = presets.firstWhere((p) => p.id == 'concept_hearing');
      expect(concept.name, contains('Concept'));
      expect(concept.deliverables.length, greaterThanOrEqualTo(4));

      final finalStage = presets.firstWhere((p) => p.id == 'final_defense');
      expect(finalStage.name, contains('Final'));
      expect(finalStage.deliverables.any((d) => d['deliverable_type'] == 'post'), isTrue);
    });

    test('cloneDeliverables generates unique order IDs and strips controllers', () {
      final source = [
        {
          'label': 'Manuscript',
          'deliverable_type': 'pre',
          '_labelController': 'dummy',
        },
        {
          'label': 'Final Approval',
          'deliverable_type': 'post',
        },
      ];

      final cloned = StageDeliverablePresetManager.cloneDeliverables(source);
      expect(cloned.length, 2);
      expect(cloned[0]['deliverable_id'], 'D1');
      expect(cloned[0]['display_order'], 1);
      expect(cloned[0].containsKey('_labelController'), isFalse);
      expect(cloned[1]['deliverable_id'], 'D2');
      expect(cloned[1]['display_order'], 2);
    });

    test('saves, retrieves, and deletes custom presets', () async {
      final items = [
        {'label': 'Custom Proposal Form', 'deliverable_type': 'pre', 'required': true},
      ];

      await StageDeliverablePresetManager.saveCustomPreset('Department Special', items);
      var customs = await StageDeliverablePresetManager.loadCustomPresets();
      expect(customs.length, 1);
      expect(customs.first.name, 'Department Special');

      await StageDeliverablePresetManager.deleteCustomPreset(customs.first.id);
      customs = await StageDeliverablePresetManager.loadCustomPresets();
      expect(customs.isEmpty, isTrue);
    });
  });

  group('StageDeliverablePresetsBar widget', () {
    testWidgets('renders preset bar with Load Preset and Copy options', (tester) async {
      final existingStages = [
        {
          'id': 1,
          'label': 'Title Hearing 2025',
          'deliverables': [
            {'label': 'Form A', 'deliverable_type': 'pre'},
          ],
        },
      ];

      List<Map<String, dynamic>> applied = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StageDeliverablePresetsBar(
              existingStages: existingStages,
              currentDeliverables: const [],
              onApplyDeliverables: (items) => applied = items,
            ),
          ),
        ),
      );

      expect(find.text('Quick Presets:'), findsOneWidget);
      expect(find.text('Load Preset'), findsOneWidget);
      expect(find.text('Copy from Stage'), findsOneWidget);

      // Open Load Preset menu
      await tester.tap(find.text('Load Preset'));
      await tester.pumpAndSettle();

      expect(find.text('RECOMMENDED TEMPLATES'), findsOneWidget);
      expect(find.text('Concept Proposal / Title Hearing'), findsOneWidget);

      // Tap preset
      await tester.tap(find.text('Concept Proposal / Title Hearing'));
      await tester.pumpAndSettle();

      expect(applied.isNotEmpty, isTrue);
      expect(applied.first['label'], 'Adviser Acceptance Form');
    });
  });
}
