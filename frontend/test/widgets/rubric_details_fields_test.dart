import 'package:defensys/screens/web/admin/rubric_engine/rubric_details_fields.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final dark in [false, true]) {
    for (final width in [320, 390, 1280]) {
      testWidgets('rubric details fit $width pixels, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width.toDouble(), 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final name = TextEditingController(text: '2nd Year PIT — Panel Rubric');
        final points = TextEditingController(text: '25');
        addTearDown(name.dispose);
        addTearDown(points.dispose);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Inter',
              scaffoldBackgroundColor: dark
                  ? DefensysTokens.mistSurface
                  : DefensysTokens.surface,
            ),
            home: Scaffold(
              body: DefensysShadcnScope(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: RubricDetailsFields(
                      semesterLabel: '1st Semester, A.Y. 2026–2027',
                      semesterActive: true,
                      hasSemester: true,
                      nameController: name,
                      customName: true,
                      onNameChanged: (_) {},
                      onResetName: () {},
                      isPit: true,
                      evaluationType: 'panel',
                      onEvaluationChanged: (_) {},
                      scale: 'Custom Scale',
                      scales: const [
                        '5-Point Scale',
                        '10-Point Scale',
                        '100-Point Scale',
                        'Custom Scale',
                      ],
                      customPoints: points,
                      onScaleChanged: (_) {},
                      onCustomPointsChanged: (_) {},
                      target: 'both',
                      onTargetChanged: (_) {},
                      assignment: LayoutBuilder(
                        builder: (context, constraints) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'PIT event (optional)',
                              style: DefensysTokens.tableCell.copyWith(
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ShadSelect<int>(
                              initialValue: 0,
                              minWidth: constraints.maxWidth,
                              maxWidth: constraints.maxWidth,
                              selectedOptionBuilder: (_, value) =>
                                  const Text('Unassigned template'),
                              options: const [
                                ShadOption(
                                  value: 0,
                                  child: Text('Unassigned template'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      enabled: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Use the suggested name or enter your own.'),
          findsOneWidget,
        );
        await capturePreview(
          tester,
          find.byType(RubricDetailsFields),
          'rubric-details-${dark ? 'dark' : 'light'}-$width',
          viewport: true,
        );
      });
    }
  }
}
