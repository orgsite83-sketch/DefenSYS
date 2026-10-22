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
      expect(
        finalStage.deliverables.any((d) => d['deliverable_type'] == 'post'),
        isTrue,
      );
    });

    test(
      'cloneDeliverables generates unique order IDs and strips controllers',
      () {
        final source = [
          {
            'label': 'Manuscript',
            'deliverable_type': 'pre',
            '_labelController': 'dummy',
          },
          {'label': 'Final Approval', 'deliverable_type': 'post'},
        ];

        final cloned = StageDeliverablePresetManager.cloneDeliverables(source);
        expect(cloned.length, 2);
        expect(cloned[0]['deliverable_id'], 'D1');
        expect(cloned[0]['display_order'], 1);
        expect(cloned[0].containsKey('_labelController'), isFalse);
        expect(cloned[1]['deliverable_id'], 'D2');
        expect(cloned[1]['display_order'], 2);
      },
    );

    test('legacy presets cannot restore timing or verdict exemptions', () {
      final source = [
        {
          'label': 'Slides',
          'deliverable_type': 'pre',
          'required': true,
          'requirement_timing': 'defense',
          'deadline_hours_before': 72,
        },
        {
          'label': 'Any final document',
          'deliverable_type': 'post',
          'required': true,
          'verdict_condition': 'revisions_only',
        },
      ];
      final cloned = StageDeliverablePresetManager.cloneDeliverables(source);
      for (final item in cloned) {
        expect(item['requirement_timing'], 'scheduling');
        expect(item['deadline_hours_before'], 24);
        expect(item['verdict_condition'], 'all_pass');
      }
      expect(source.first['requirement_timing'], 'defense');
      expect(source.last['verdict_condition'], 'revisions_only');
    });

    test('saves, retrieves, and deletes custom presets', () async {
      final items = [
        {
          'label': 'Custom Proposal Form',
          'deliverable_type': 'pre',
          'required': true,
        },
      ];

      await StageDeliverablePresetManager.saveCustomPreset(
        'Department Special',
        items,
      );
      var customs = await StageDeliverablePresetManager.loadCustomPresets();
      expect(customs.length, 1);
      expect(customs.first.name, 'Department Special');

      await StageDeliverablePresetManager.deleteCustomPreset(customs.first.id);
      customs = await StageDeliverablePresetManager.loadCustomPresets();
      expect(customs.isEmpty, isTrue);
    });

    test('keeps Capstone and each PIT year in separate preset lists', () async {
      final items = [
        {'label': 'Pitch Deck', 'deliverable_type': 'pre'},
      ];
      await StageDeliverablePresetManager.saveCustomPreset(
        'Concept Proposal',
        items,
      );
      await StageDeliverablePresetManager.saveCustomPreset(
        'First Year Pitch',
        items,
        scope: DeliverablePresetScope.pit,
        yearLevel: '1st Year',
      );
      await StageDeliverablePresetManager.saveCustomPreset(
        'Second Year Pitch',
        items,
        scope: DeliverablePresetScope.pit,
        yearLevel: '2nd Year',
      );

      expect(
        (await StageDeliverablePresetManager.loadCustomPresets()).map(
          (p) => p.name,
        ),
        ['Concept Proposal'],
      );
      expect(
        (await StageDeliverablePresetManager.loadCustomPresets(
          scope: DeliverablePresetScope.pit,
          yearLevel: '1st Year',
        )).map((p) => p.name),
        ['First Year Pitch'],
      );
      expect(
        (await StageDeliverablePresetManager.loadCustomPresets(
          scope: DeliverablePresetScope.pit,
          yearLevel: '2nd Year',
        )).map((p) => p.name),
        ['Second Year Pitch'],
      );
      expect(
        await StageDeliverablePresetManager.loadCustomPresets(
          scope: DeliverablePresetScope.pit,
        ),
        isEmpty,
      );
    });

    test(
      'moves only an exact legacy event checklist into its PIT year',
      () async {
        final eventItems = [
          {'label': 'Concept Paper', 'deliverable_type': 'pre'},
          {'label': 'Pitch Deck', 'deliverable_type': 'pre'},
        ];
        await StageDeliverablePresetManager.saveCustomPreset(
          'System Concept Pitching',
          eventItems,
        );
        await StageDeliverablePresetManager.saveCustomPreset(
          'Concept Proposal',
          eventItems,
        );
        await StageDeliverablePresetManager.adoptMatchingLegacyPitPresets(
          '1st Year',
          [
            {'label': 'System Concept Pitching', 'deliverables': eventItems},
          ],
        );

        expect(
          (await StageDeliverablePresetManager.loadCustomPresets(
            scope: DeliverablePresetScope.pit,
            yearLevel: '1st Year',
          )).map((p) => p.name),
          ['System Concept Pitching'],
        );
        expect(
          (await StageDeliverablePresetManager.loadCustomPresets()).map(
            (p) => p.name,
          ),
          ['Concept Proposal'],
        );
      },
    );

    test('matches explicit PIT ownership and rejects unclassified events', () {
      expect(
        StageDeliverablePresetManager.pitEventMatchesYearLevel(
          '1st Year',
          '1st Year',
        ),
        isTrue,
      );
      expect(
        StageDeliverablePresetManager.pitEventMatchesYearLevel(
          '2nd Year',
          '1st Year',
        ),
        isFalse,
      );
      expect(
        StageDeliverablePresetManager.pitEventMatchesYearLevel('', '1st Year'),
        isFalse,
      );
    });
  });

  group('StageDeliverablePresetsBar widget', () {
    testWidgets('renders preset bar with Load Preset and Copy options', (
      tester,
    ) async {
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

    testWidgets(
      'PIT menu shows only its year presets and PIT event copy sources',
      (tester) async {
        await StageDeliverablePresetManager.saveCustomPreset('Capstone Only', [
          {'label': 'Capstone File', 'deliverable_type': 'pre'},
        ]);
        await StageDeliverablePresetManager.saveCustomPreset(
          'PIT Year One',
          [
            {'label': 'PIT File', 'deliverable_type': 'pre'},
          ],
          scope: DeliverablePresetScope.pit,
          yearLevel: '1st Year',
        );
        await StageDeliverablePresetManager.saveCustomPreset(
          'PIT Year Two',
          [
            {'label': 'Other File', 'deliverable_type': 'pre'},
          ],
          scope: DeliverablePresetScope.pit,
          yearLevel: '2nd Year',
        );
        List<Map<String, dynamic>> applied = [];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StageDeliverablePresetsBar(
                scope: DeliverablePresetScope.pit,
                yearLevel: '1st Year',
                currentSourceId: 1,
                existingStages: [
                  {
                    'id': 1,
                    'scope': 'pit',
                    'year_level': '1st Year',
                    'label': '1st Year PIT Current',
                    'deliverables': [
                      {'label': 'Current'},
                    ],
                  },
                  {
                    'id': 2,
                    'scope': 'pit',
                    'year_level': '1st Year',
                    'label': '1st Year PIT Expo',
                    'deliverables': [
                      {'label': 'Expo'},
                    ],
                  },
                  {
                    'id': 3,
                    'scope': 'pit',
                    'year_level': '2nd Year',
                    'label': '2nd Year PIT Expo',
                    'deliverables': [
                      {'label': 'Wrong Year'},
                    ],
                  },
                  {
                    'id': 4,
                    'label': 'Concept Proposal',
                    'deliverables': [
                      {'label': 'Capstone'},
                    ],
                  },
                ],
                currentDeliverables: const [],
                onApplyDeliverables: (items) => applied = items,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PIT · 1st Year'), findsOneWidget);
        expect(find.text('Copy from Event'), findsOneWidget);
        expect(find.text('Copy from Stage'), findsNothing);
        await tester.tap(find.text('Load Preset'));
        await tester.pumpAndSettle();
        expect(find.text('PIT Year One (1 files)'), findsOneWidget);
        expect(find.text('PIT Year Two (1 files)'), findsNothing);
        expect(find.text('Capstone Only (1 files)'), findsNothing);
        expect(find.text('Concept Proposal / Title Hearing'), findsNothing);
        await tester.tap(find.text('PIT Year One (1 files)'));
        await tester.pumpAndSettle();
        expect(applied.single['label'], 'PIT File');

        await tester.tap(find.text('Copy from Event'));
        await tester.pumpAndSettle();
        expect(find.text('1st Year PIT Expo (1 files)'), findsOneWidget);
        expect(find.text('1st Year PIT Current (1 files)'), findsNothing);
        expect(find.text('2nd Year PIT Expo (1 files)'), findsNothing);
        expect(find.text('Concept Proposal (1 files)'), findsNothing);
        await tester.tap(find.text('1st Year PIT Expo (1 files)'));
        await tester.pumpAndSettle();
        expect(applied.single['label'], 'Expo');
      },
    );
  });
}
