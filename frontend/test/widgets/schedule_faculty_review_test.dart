import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_faculty_review_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter');
    loader.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    await loader.load();
  });
  for (final width in [320.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'faculty correction fits $width dark=$dark and returns a registered ID',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ({int id, bool equivalent})? result;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('capture'),
              child: MaterialApp(
                theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showScheduleFacultyReview(
                          context,
                          original: 'Mernel A. Catada',
                          reason: 'Middle-name details need confirmation.',
                          duty: 'chair',
                          equivalentCount: 12,
                          accounts: const [
                            {
                              'id': 42,
                              'username': '213',
                              'name': 'Mernel Antio Catada',
                            },
                          ],
                        );
                      },
                      child: const Text('Review'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Review'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.widget<ShadCheckbox>(find.byType(ShadCheckbox)).value,
            false,
          );
          if (width == 1280) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('../.tmp').create(recursive: true);
              await File(
                '../.tmp/schedule_faculty_${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.byType(ShadCheckbox));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(EditableText), '213');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Mernel Antio Catada · 213'));
          await tester.pumpAndSettle();
          expect(result, (id: 42, equivalent: true));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
