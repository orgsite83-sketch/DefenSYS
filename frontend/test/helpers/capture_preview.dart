import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadPreviewFonts({bool force = false}) async {
  if (!force && Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] != '1') return;
  for (final entry in {
    'Inter': 'assets/fonts/Inter-Regular.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'packages/lucide_icons_flutter/Lucide':
        'packages/lucide_icons_flutter/assets/lucide.ttf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

Future<void> capturePreview(
  WidgetTester tester,
  Finder finder,
  String name,
) async {
  if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../.tmp/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
