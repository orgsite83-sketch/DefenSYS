import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_outcome_settings.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/grading/grading_setup_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

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
