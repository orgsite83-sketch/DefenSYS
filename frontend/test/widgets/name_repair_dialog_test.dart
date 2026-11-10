import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/admin/user_management_provider.dart';
import 'package:defensys/screens/web/admin/user_management/dialogs/name_repair_dialog.dart';
import '../helpers/capture_preview.dart';

class RepairService extends UserManagementNotifier {
  Map<String, dynamic>? submitted;
  int applies = 0;
  bool fail = false;
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<Map<String, dynamic>> previewNameRepair(
    Map<String, dynamic> payload,
  ) async {
    submitted = payload;
    return {
      'preview_token': 'reviewed-token',
      'username': '213',
      'source_filename': payload['source_filename'],
      'before': {'first_name': 'RAY AN', 'last_name': 'QUI\ufffdON'},
      'after': {
        'first_name': payload['first_name'],
        'last_name': payload['last_name'],
      },
    };
  }

  @override
  Future<void> applyNameRepair(String token) async {
    if (fail) throw Exception('The account changed. Review again.');
    if (token != 'reviewed-token') throw Exception('Unreviewed change');
    applies++;
  }
}

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('name-only repair is reviewed before apply $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        final service = RepairService();
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [userManagementProvider.overrideWith(() => service)],
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showNameRepairDialog(context, {
                        'username': '213',
                        'role': 'faculty',
                        'first_name': 'RAY AN',
                        'last_name': 'QUI\ufffdON',
                      }),
                      child: const Text('Repair'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Repair'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).at(1), 'QUI\u00d1ON');
        await tester.enterText(
          find.byType(EditableText).at(2),
          'official-faculty.csv',
        );
        await tester.tap(find.text('Review name repair'));
        await tester.pumpAndSettle();
        expect(service.applies, 0);
        expect(service.submitted!.keys.toSet(), {
          'username',
          'expected_role',
          'first_name',
          'last_name',
          'source_filename',
        });
        expect(find.text('Before: RAY AN QUI\ufffdON'), findsOneWidget);
        expect(find.text('After: RAY AN QUI\u00d1ON'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['DEFENSYS_REVIEW_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final captured = await boundary.toImage();
            final bytes = await captured.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../.tmp/name-repair-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            captured.dispose();
          });
        }
        await tester.tap(find.text('Apply reviewed name repair'));
        await tester.pumpAndSettle();
        expect(service.applies, 1);
        expect(find.text('Repair account name'), findsNothing);
      });
    }
  }
  testWidgets('stale repair keeps typed values for another review', (
    tester,
  ) async {
    final service = RepairService()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userManagementProvider.overrideWith(() => service)],
        child: MaterialApp(
          home: Scaffold(
            body: NameRepairDialog(
              user: const {
                'username': '213',
                'role': 'faculty',
                'first_name': 'RAY AN',
                'last_name': 'QUI\ufffdON',
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText).at(1), 'QUI\u00d1ON');
    await tester.enterText(find.byType(EditableText).at(2), 'verified.csv');
    await tester.tap(find.text('Review name repair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply reviewed name repair'));
    await tester.pumpAndSettle();
    expect(find.text('The account changed. Review again.'), findsOneWidget);
    expect(find.text('QUI\u00d1ON'), findsOneWidget);
    expect(find.text('verified.csv'), findsOneWidget);
    expect(service.applies, 0);
  });
}
