import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_outcome_settings.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/grading/grading_setup_section.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final dark in [false, true]) {
    for (final width in [390.0, 1100.0]) {
      testWidgets(
        'concept evaluation preserves ordinary draft inputs $dark $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controllers = [
            for (final value in ['50', '30', '20'])
              TextEditingController(text: value),
          ];
          final cutoff = TextEditingController(text: '75');
          addTearDown(() {
            for (final controller in controllers) {
              controller.dispose();
            }
            cutoff.dispose();
          });
          var concept = true;
          await pumpDefensysWidget(
            tester,
            StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: const ValueKey('panel-only-preview'),
                      child: ColoredBox(
                        color: dark
                            ? DefensysTokens.mistSurface
                            : DefensysTokens.surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConceptSettings(
                              value: {'enabled': concept, 'required_count': 3},
                              onChanged: (value) => setState(
                                () => concept = value['enabled'] == true,
                              ),
                            ),
                            const SizedBox(height: 24),
                            GradingSetupSection(
                              panelOnly: concept,
                              roles: [
                                for (final (index, label) in [
                                  'Panel',
                                  'Adviser',
                                  'Peer',
                                ].indexed)
                                  GradingRoleSetup(
                                    role: label.toLowerCase(),
                                    label: label,
                                    weightController: controllers[index],
                                    rubricId: index + 1,
                                    rubrics: [
                                      {
                                        'id': index + 1,
                                        'name': '$label evaluation rubric',
                                      },
                                    ],
                                    onWeightChanged: (_) {},
                                    onRubricChanged: (_) {},
                                  ),
                              ],
                              resetLabel: 'Reset to 50 / 30 / 20',
                              onReset: () {},
                              onManageRubrics: () {},
                            ),
                            const SizedBox(height: 24),
                            StageOutcomeSettings(
                              scoreController: cutoff,
                              scoreCarryover: 'reassess',
                              conceptSelection: concept,
                              onCarryoverChanged: (_) {},
                              onChanged: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          expect(
            find.byKey(const ValueKey('panel-fixed-weight')),
            findsOneWidget,
          );
          expect(find.byType(ShadSelect<int>), findsOneWidget);
          expect(find.text('Adviser'), findsNothing);
          expect(find.text('Peer'), findsNothing);
          expect(find.text('Reset to 50 / 30 / 20'), findsNothing);
          expect(
            find.text('Adviser and peer scores on re-defense'),
            findsNothing,
          );
          expect(find.text('Total 100%'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('panel-only-preview')),
            'panel-only-concepts/setup-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.ensureVisible(find.text('Concept selection'));
          await tester.tap(find.text('Concept selection'));
          await tester.pumpAndSettle();
          expect(find.byType(ShadSelect<int>), findsNWidgets(3));
          expect(controllers.map((controller) => controller.text), [
            '50',
            '30',
            '20',
          ]);
          expect(
            find.text('Adviser and peer scores on re-defense'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('rubrics can be cleared and refreshed without stale selections', (
    tester,
  ) async {
    final weight = TextEditingController(text: '100');
    addTearDown(weight.dispose);
    int? selected = 10;
    late StateSetter update;
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return GradingSetupSection(
            roles: [
              GradingRoleSetup(
                role: 'panel',
                label: 'Panel',
                weightController: weight,
                rubricId: selected,
                rubrics: const [
                  {'id': 10, 'name': 'Current rubric'},
                  {'id': 11, 'name': 'Updated rubric'},
                ],
                onWeightChanged: (_) {},
                onRubricChanged: (value) => setState(() => selected = value),
              ),
            ],
            resetLabel: 'Reset',
            onReset: () {},
            onManageRubrics: () {},
          );
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('panel-rubric-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select later').last);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(
      tester.widget<ShadSelect<int>>(find.byType(ShadSelect<int>)).initialValue,
      0,
    );
    update(() => selected = 11);
    await tester.pumpAndSettle();
    expect(find.text('Updated rubric'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable assignments remain visible without becoming options',
    (tester) async {
      final weight = TextEditingController(text: '100');
      addTearDown(weight.dispose);
      await pumpDefensysWidget(
        tester,
        GradingSetupSection(
          roles: [
            GradingRoleSetup(
              role: 'panel',
              label: 'Panel',
              weightController: weight,
              rubricId: 99,
              rubricName: 'Previous assignment',
              rubrics: const [],
              onWeightChanged: (_) {},
              onRubricChanged: (_) {},
            ),
          ],
          enabled: false,
          resetLabel: 'Reset',
          onReset: () {},
          onManageRubrics: () {},
        ),
      );
      final select = tester.widget<ShadSelect<int>>(
        find.byType(ShadSelect<int>),
      );
      expect(
        select.options!.whereType<ShadOption<int>>().map(
          (option) => option.value,
        ),
        [0],
      );
      expect(find.text('Previous assignment'), findsOneWidget);
      expect(select.enabled, isFalse);
      expect(tester.widget<ShadInput>(find.byType(ShadInput)).enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final pit in [false, true]) {
    for (final width in [320.0, 760.0]) {
      for (final dark in [false, true]) {
        testWidgets('grading setup fits $width pit=$pit dark=$dark', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controllers = [
            TextEditingController(text: pit ? '80' : '50'),
            if (!pit) TextEditingController(text: '30'),
            TextEditingController(text: '20'),
          ];
          final score = TextEditingController(text: '75');
          addTearDown(() {
            for (final controller in [...controllers, score]) {
              controller.dispose();
            }
          });
          final labels = ['Panel', if (!pit) 'Adviser', 'Peer'];
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: const ValueKey('grading-setup-preview'),
                  child: ColoredBox(
                    color: dark
                        ? DefensysTokens.mistSurface
                        : DefensysTokens.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GradingSetupSection(
                          roles: [
                            for (var i = 0; i < labels.length; i++)
                              GradingRoleSetup(
                                role: labels[i].toLowerCase(),
                                label: labels[i],
                                weightController: controllers[i],
                                rubricId: i + 1,
                                rubrics: [
                                  {
                                    'id': i + 1,
                                    'name': '${labels[i]} evaluation rubric',
                                  },
                                ],
                                onWeightChanged: (_) {},
                                onRubricChanged: (_) {},
                              ),
                          ],
                          resetLabel: pit
                              ? 'Reset to 80 / 20'
                              : 'Reset to 50 / 30 / 20',
                          onReset: () {},
                          onManageRubrics: () {},
                        ),
                        if (!pit) ...[
                          const Divider(height: 48),
                          StageOutcomeSettings(
                            scoreController: score,
                            scoreCarryover: 'reassess',
                            onCarryoverChanged: (_) {},
                            onChanged: () {},
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          expect(find.text('Total 100%'), findsOneWidget);
          expect(find.byType(ShadSelect<int>), findsNWidgets(labels.length));
          if (!pit) {
            expect(find.text('Below 75% requires re-defense.'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('grading-setup-preview')),
            'grading-setup-${pit ? 'pit' : 'capstone'}-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
        });
      }
    }
  }
}
