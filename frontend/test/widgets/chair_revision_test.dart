import 'dart:convert';

import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';
import 'panel_deliberation_test.dart' as fixtures;

class _Client extends Mock implements AuthenticatedHttpClient {}

Map<String, dynamic> grade({bool chair = true}) {
  final data = fixtures.grade(chair: chair);
  final policy = (data['workflow'] as Map)['deliberation'] as Map;
  policy['revision_mode'] = 'chair';
  policy['revision_areas'] = [];
  return data;
}

Finder control(String prefix, {int index = 0}) => find
    .byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith(prefix),
    )
    .at(index);

Future<void> addCorrection(
  WidgetTester tester, {
  String label = 'Access controls',
  int index = 0,
}) async {
  await tester.ensureVisible(find.text('Add revision area'));
  await tester.tap(find.text('Add revision area'));
  await tester.pumpAndSettle();
  await tester.enterText(control('chair-area-', index: index), label);
  await tester.ensureVisible(control('chair-severity-', index: index));
  await tester.tap(control('chair-severity-', index: index));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Minor revision').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    control('chair-instructions-', index: index),
    'Restrict report exports to the coordinator.',
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  testWidgets(
    'chair authors corrections without stage categories and submits one decision',
    (tester) async {
      final client = _Client();
      Map? sent;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        sent = jsonDecode(call.namedArguments[#body] as String) as Map;
        return http.Response(jsonEncode({'grade': grade()}), 200);
      });
      await pumpDefensysWidget(
        tester,
        fixtures.host(grade()),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      expect(find.text('System'), findsNothing);
      await addCorrection(tester);
      await tester.ensureVisible(
        find.text('Re-demo required · Verification only'),
      );
      await tester.tap(find.text('Re-demo required · Verification only'));
      await tester.pumpAndSettle();
      final demoInput = find.byWidgetPredicate(
        (widget) => widget is ShadInput && widget.maxLength == 1000,
      );
      await tester.enterText(demoInput, 'Demonstrate the export restrictions.');
      await tester.ensureVisible(find.text('Confirm panel decision'));
      await tester.tap(find.text('Confirm panel decision'));
      await tester.pumpAndSettle();
      final entry = (sent?['revision_entries'] as List).single as Map;
      expect(entry['label'], 'Access controls');
      expect(entry['severity'], 'minor');
      expect(
        entry['instructions'],
        'Restrict report exports to the coordinator.',
      );
      expect((sent?['demo_requirements'] as List).single, {
        'area_id': entry['area_id'],
        'text': 'Demonstrate the export restrictions.',
      });
      expect(sent?['re_demo_required'], true);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'approval and re-defense hide correction drafts and omit them from submissions',
    (tester) async {
      final client = _Client();
      final sent = <Map>[];
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        sent.add(jsonDecode(call.namedArguments[#body] as String) as Map);
        return http.Response(jsonEncode({'grade': grade()}), 200);
      });
      await pumpDefensysWidget(
        tester,
        fixtures.host(grade()),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await addCorrection(tester);
      for (final verdict in ['Approved', 'For Re-defense']) {
        await tester.ensureVisible(find.text(verdict));
        await tester.tap(find.text(verdict));
        await tester.pumpAndSettle();
        expect(find.text('Add revision area'), findsNothing);
        expect(find.text('Re-demo required · Verification only'), findsNothing);
        await tester.ensureVisible(find.text('Confirm panel decision'));
        await tester.tap(find.text('Confirm panel decision'));
        await tester.pumpAndSettle();
        expect(sent.last['revision_entries'], isEmpty);
        expect(sent.last['demo_requirements'], isEmpty);
        expect(sent.last['re_demo_required'], false);
      }
      await tester.ensureVisible(find.text('Approved with Revisions'));
      await tester.tap(find.text('Approved with Revisions'));
      await tester.pumpAndSettle();
      expect(find.text('Access controls'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'missing corrections are explained and a server rejection retains the form',
    (tester) async {
      final client = _Client();
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'detail': 'The assessment changed. Refresh before confirming.',
          }),
          400,
        ),
      );
      await pumpDefensysWidget(
        tester,
        fixtures.host(grade()),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.ensureVisible(find.text('Confirm panel decision'));
      await tester.tap(find.text('Confirm panel decision'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add each revision area'), findsOneWidget);
      verifyNever(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
      await addCorrection(tester);
      await tester.ensureVisible(find.text('Confirm panel decision'));
      await tester.tap(find.text('Confirm panel decision'));
      await tester.pumpAndSettle();
      expect(find.text('Access controls'), findsOneWidget);
      expect(
        find.text('Restrict report exports to the coordinator.'),
        findsOneWidget,
      );
      expect(find.textContaining('The assessment changed.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('removing the last correction removes its demonstration draft', (
    tester,
  ) async {
    await pumpDefensysWidget(tester, fixtures.host(grade()));
    await addCorrection(tester);
    await tester.ensureVisible(
      find.text('Re-demo required · Verification only'),
    );
    await tester.tap(find.text('Re-demo required · Verification only'));
    await tester.pumpAndSettle();
    expect(find.text('Required demonstration'), findsOneWidget);
    await tester.ensureVisible(find.text('Remove revision area'));
    await tester.tap(find.text('Remove revision area'));
    await tester.pumpAndSettle();
    expect(find.text('Required demonstration'), findsNothing);
    expect(find.text('Re-demo required · Verification only'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary panel members cannot author correction areas', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      fixtures.host(grade(chair: false), chair: false),
    );
    expect(find.text('Add revision area'), findsNothing);
    expect(find.text('Confirm panel decision'), findsNothing);
  });

  testWidgets(
    'confirmed correction text is read-only and an amendment retains identities',
    (tester) async {
      final data = grade();
      final policy = (data['workflow'] as Map)['deliberation'] as Map;
      policy['can_request_correction'] = true;
      policy['decision'] = {
        'revision': 1,
        'verdict': 'approved_with_revisions',
        'instructions': '',
        'revision_entries': [
          {
            'area_id': 'existing-area',
            'label': 'Access controls',
            'severity': 'major',
            'instructions': 'Restrict all exports to the coordinator.',
          },
        ],
        're_demo_required': false,
      };
      final client = _Client();
      Map? sent;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        sent = jsonDecode(call.namedArguments[#body] as String) as Map;
        expect(
          (call.positionalArguments.single as Uri).path,
          endsWith('/panel-decision/correction/'),
        );
        return http.Response(jsonEncode({'grade': data}), 200);
      });
      await pumpDefensysWidget(
        tester,
        fixtures.host(data),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      expect(
        find.text('Restrict all exports to the coordinator.'),
        findsOneWidget,
      );
      expect(find.text('Add revision area'), findsNothing);
      await tester.tap(find.text('Request decision amendment'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chair-area-existing-area')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chair-instructions-existing-area')),
        'Restrict spreadsheet and PDF exports.',
      );
      await tester.ensureVisible(find.text('Request decision amendment'));
      await tester.tap(find.text('Request decision amendment'));
      await tester.pumpAndSettle();
      final decision = ((sent?['changes'] as Map)['panel_decision'] as Map);
      expect((decision['revision_entries'] as List).single, {
        'area_id': 'existing-area',
        'label': 'Access controls',
        'severity': 'major',
        'instructions': 'Restrict spreadsheet and PDF exports.',
      });
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('chair-authored corrections fit $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          fixtures.host(grade()),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        await addCorrection(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Panel decision'));
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'chair-corrections-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
