import 'package:defensys/screens/web/admin/rubric_engine/rubric_criterion_fields.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final dark in [false, true]) {
    for (final width in [320, 1280]) {
      for (final points in [false, true]) {
        testWidgets(
          '${points ? 'points' : 'standard'} rows fit $width pixels, dark=$dark',
          (tester) async {
            tester.view.physicalSize = Size(width.toDouble(), 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final names = [
              TextEditingController(text: 'Mastery of subject matter'),
              TextEditingController(
                text:
                    'Ability to answer questions, defend ideas, and respond to feedback',
              ),
            ];
            final weights = [
              TextEditingController(text: '60'),
              TextEditingController(text: '40'),
            ];
            final scores = [
              TextEditingController(text: '15'),
              TextEditingController(text: '10'),
            ];
            addTearDown(() {
              for (final controller in [...names, ...weights, ...scores]) {
                controller.dispose();
              }
            });
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: DefensysTokens.fontFamilyInter,
                  scaffoldBackgroundColor: dark
                      ? DefensysTokens.mistSurface
                      : DefensysTokens.surface,
                ),
                home: Scaffold(
                  body: DefensysShadcnScope(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              points
                                  ? 'Oral presentation'
                                  : 'Evaluation criteria',
                              style: DefensysTokens.body.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: dark
                                    ? DefensysTokens.mistTextPrimary
                                    : DefensysTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            RubricCriterionHeader(
                              points: points,
                              showTarget: !points,
                            ),
                            for (var index = 0; index < names.length; index++)
                              RubricCriterionFields(
                                index: index,
                                name: names[index],
                                weight: weights[index],
                                maxScore: scores[index],
                                enabled: true,
                                showTarget: !points,
                                target: index == 0 ? 'team' : 'individual',
                                isPointsScale: points,
                                onTargetChanged: (_) {},
                                onChanged: () {},
                              ),
                          ],
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
              find.byKey(const ValueKey('criterion-name-0')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('criterion-name-1')),
              findsOneWidget,
            );
            expect(find.text('Evaluation guidelines'), findsNothing);
            expect(
              find.byKey(const ValueKey('criterion-toggle-0')),
              findsNothing,
            );
            await capturePreview(
              tester,
              find.byType(Scaffold),
              'rubric-rows-${points ? 'points' : 'standard'}-${dark ? 'dark' : 'light'}-$width',
              viewport: true,
            );
          },
        );
      }
    }
  }
}
