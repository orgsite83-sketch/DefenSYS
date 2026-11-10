import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/student_teams/dialogs/adviser_limits_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> fixture({bool approved = false}) => {
  'active_semester': {'id': 10, 'display_name': '1st Semester, A.Y. 2026-2027'},
  'advisers': [
    {
      'id': 2,
      'name': 'Faculty Rivera',
      'capacity': {
        'active_count': approved ? 5 : 4,
        'effective_limit': approved ? 5 : 4,
        'has_exception': approved,
        'is_overloaded': false,
      },
    },
  ],
  'exceptions': [
    if (approved)
      {
        'id': 1,
        'adviser_id': 2,
        'semester_id': 10,
        'approved_limit': 5,
        'authorization': 'Department chair decision',
        'reason': 'Additional solo project',
        'reference': 'DEP-001',
      },
  ],
};

Future<void> pumpDialog(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function() load,
  required Future<void> Function(Map<String, dynamic>, bool) save,
  Size size = const Size(1024, 900),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts();
  await tester.pumpWidget(
    MaterialApp(
      theme: dark
          ? ThemeData.dark().copyWith(textTheme: AppTheme.theme.textTheme)
          : AppTheme.theme,
      home: Scaffold(
        body: DefensysShadcnScope(
          maroonActions: true,
          child: AdviserLimitsDialog(load: load, save: save),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder input(String label) => find.descendant(
  of: find.byKey(ValueKey(label)),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('requires department authorization and reason before saving', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await pumpDialog(
      tester,
      load: () async => fixture(),
      save: (data, revoke) async {
        sent = data;
      },
    );
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Save exception'))
          .enabled,
      isFalse,
    );
    await tester.enterText(
      input('Department authorization'),
      'Department chair decision',
    );
    await tester.enterText(
      input('Reason for this change'),
      'Additional solo project',
    );
    await tester.pump();
    await tester.tap(find.text('Save exception'));
    await tester.pumpAndSettle();
    expect(sent, containsPair('approved_limit', 5));
    expect(sent, containsPair('adviser_id', 2));
    expect(sent, containsPair('semester_id', 10));
    expect(
      find.text('Exception saved. You can now assign teams within this limit.'),
      findsOneWidget,
    );
    expect(input('Reason for this change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'revocation needs a new reason and preserves current assignment message',
    (tester) async {
      bool? revoked;
      Map<String, dynamic>? sent;
      await pumpDialog(
        tester,
        load: () async => fixture(approved: true),
        save: (data, revoke) async {
          sent = data;
          revoked = revoke;
        },
      );
      expect(find.text('5 active teams · Approved limit: 5'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Revoke exception'),
            )
            .enabled,
        isFalse,
      );
      await tester.enterText(
        input('Reason for this change'),
        'Permission withdrawn',
      );
      await tester.pump();
      await tester.tap(find.text('Revoke exception'));
      await tester.pumpAndSettle();
      expect(revoked, isTrue);
      expect(sent, isNot(contains('approved_limit')));
      expect(
        find.text('Exception revoked. Existing teams keep their adviser.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'stale server rejection remains visible without success message',
    (tester) async {
      await pumpDialog(
        tester,
        load: () async => fixture(),
        save: (_, _) async {
          throw Exception('Refresh and choose the active academic period.');
        },
      );
      await tester.enterText(input('Department authorization'), 'Department');
      await tester.enterText(input('Reason for this change'), 'Approved');
      await tester.pump();
      await tester.tap(find.text('Save exception'));
      await tester.pumpAndSettle();
      expect(
        find.text('Refresh and choose the active academic period.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception saved.'), findsNothing);
    },
  );

  testWidgets('failed load can be retried', (tester) async {
    var calls = 0;
    await pumpDialog(
      tester,
      load: () async {
        if (calls++ == 0) throw Exception('Service unavailable');
        return fixture();
      },
      save: (_, _) async {},
    );
    expect(find.text('Service unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('4 active teams · Limit: 4'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('responsive ${dark ? 'narrow dark' : 'desktop light'} dialog', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        load: () async => fixture(approved: true),
        save: (_, _) async {},
        size: dark ? const Size(360, 740) : const Size(1024, 900),
        dark: dark,
      );
      expect(find.text('Adviser limits'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(Scaffold),
        'adviser-limits-${dark ? 'narrow-dark' : 'desktop-light'}',
        viewport: true,
      );
    });
  }
}
