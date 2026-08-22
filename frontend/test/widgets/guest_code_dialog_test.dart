import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/dialogs/guest_code_dialog.dart';
import 'package:defensys/screens/web/admin/user_management/components/guest_codes_card.dart';
import 'package:defensys/services/user_management_provider.dart';

import '../helpers/pump_app.dart';

void main() {
  group('GuestPanelistInfo tests', () {
    test('parses full formatted credentials with title, degree, and alma mater', () {
      const raw = 'Engr. Juan Dela Cruz, M.S.IT (DOST Region X · Alma Mater: UP Diliman)';
      final info = GuestPanelistInfo.parse(raw);

      expect(info.displayName, 'Engr. Juan Dela Cruz, M.S.IT');
      expect(info.affiliation, 'DOST Region X · Alma Mater: UP Diliman');
      expect(info.initials, 'JC');
    });

    test('parses plain unformatted name', () {
      const raw = 'Maria Clara';
      final info = GuestPanelistInfo.parse(raw);

      expect(info.displayName, 'Maria Clara');
      expect(info.affiliation, isNull);
      expect(info.initials, 'MC');
    });

    test('formats payload correctly', () {
      final formatted = GuestPanelistInfo.formatPayload(
        prefix: 'Dr.',
        fullName: 'Alan Turing',
        degreeSuffix: 'Ph.D.',
        institution: 'Cambridge University',
        almaMater: 'King\'s College',
      );

      expect(
        formatted,
        'Dr. Alan Turing, Ph.D. (Cambridge University · Alma Mater: King\'s College)',
      );
    });
  });

  group('GuestCodeGenerateDialog widget tests', () {
    final sampleSchedules = [
      {
        'id': 101,
        'label': 'Team Syntax - Capstone 2 Final - 2026-11-24 01:30 PM (Room 302)',
      },
    ];

    testWidgets('renders all fields and updates live pass preview', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Map<String, dynamic>? resultPayload;

      await pumpDefensysWidget(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultPayload = await GuestCodeGenerateDialog.show(
                  context,
                  schedules: sampleSchedules,
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Generate Guest Panelist Pass'), findsOneWidget);
      expect(find.text('HONORIFIC / TITLE'), findsOneWidget);
      expect(find.text('FULL NAME (REQUIRED)'), findsOneWidget);
      expect(find.text('CURRENT INSTITUTION / WORKPLACE (OPTIONAL)'), findsOneWidget);
      expect(find.text('ALMA MATER / EDUCATIONAL BACKGROUND (OPTIONAL)'), findsOneWidget);
      expect(find.text('LIVE EVALUATOR ACCESS PASS PREVIEW'), findsOneWidget);

      // Select 'Dr.' chip
      await tester.tap(find.text('Dr.'));
      await tester.pumpAndSettle();

      // Enter Full Name
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Juan Dela Cruz'), 'Maria Santos');
      // Enter Degree Suffix
      await tester.enterText(find.widgetWithText(TextField, 'e.g. M.S.IT, PECE'), 'Ph.D.');
      // Enter Institution
      await tester.enterText(find.widgetWithText(TextField, 'e.g. DOST Region X / Xavier University - Ateneo'), 'Ateneo de Manila');
      // Enter Alma Mater
      await tester.enterText(find.widgetWithText(TextField, 'e.g. M.S. UP Diliman (USTP Alumnus)'), 'UP Diliman');

      await tester.pumpAndSettle();

      // Verify live preview shows updated credentials
      expect(find.text('Dr. Maria Santos, Ph.D.'), findsOneWidget);
      expect(find.text('Ateneo de Manila · Alma Mater: UP Diliman'), findsOneWidget);
      expect(find.text('MS'), findsOneWidget); // Initials

      // Tap Generate & Save Pass
      await tester.tap(find.text('Generate & Save Pass'));
      await tester.pumpAndSettle();

      expect(resultPayload, isNotNull);
      expect(
        resultPayload!['guest_name'],
        'Dr. Maria Santos, Ph.D. (Ateneo de Manila · Alma Mater: UP Diliman)',
      );
      expect(resultPayload!['defense_schedule'], 101);
    });

    testWidgets('allows generating pass with only required name when optional fields are omitted', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Map<String, dynamic>? resultPayload;

      await pumpDefensysWidget(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultPayload = await GuestCodeGenerateDialog.show(
                  context,
                  schedules: sampleSchedules,
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Select 'None' title chip
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      // Only enter Full Name (leaving degree, institution, alma mater blank)
      await tester.enterText(find.widgetWithText(TextField, 'e.g. Juan Dela Cruz'), 'Alex Rivera');
      await tester.pumpAndSettle();

      expect(find.text('Alex Rivera'), findsWidgets);
      expect(find.text('External Evaluator'), findsOneWidget);

      await tester.tap(find.text('Generate & Save Pass'));
      await tester.pumpAndSettle();

      expect(resultPayload, isNotNull);
      expect(resultPayload!['guest_name'], 'Alex Rivera');
      expect(resultPayload!['defense_schedule'], 101);
    });
  });

  group('GeneratedGuestCodeDialog widget test', () {
    testWidgets('renders code pass card properly', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        const Scaffold(
          body: GeneratedGuestCodeDialog(
            guestCode: {
              'code': 'DEF-99A1B2',
              'guest_name': 'Engr. Juan Dela Cruz (DOST X)',
              'defense_schedule_label': 'Team Syntax - Final Defense',
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Guest Pass Generated!'), findsOneWidget);
      expect(find.text('DEF-99A1B2'), findsOneWidget);
      expect(find.text('Engr. Juan Dela Cruz'), findsOneWidget);
      expect(find.text('DOST X'), findsOneWidget);
      expect(find.text('Copy Access Code'), findsOneWidget);
    });
  });

  group('GuestCodesCard table widget test', () {
    testWidgets('renders evaluator identity cells and badges', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = UserManagementState(
        guestCodes: [
          {
            'id': 1,
            'code': 'DEF-7842AB',
            'guest_name': 'Engr. Juan Dela Cruz, PECE (DOST Region X · Alma Mater: UP Diliman)',
            'defense_schedule_label': 'Team Alpha - Final Defense (Room 302)',
            'created_at': '2026-08-22T08:00:00Z',
            'is_active': true,
          },
        ],
      );

      await pumpDefensysWidget(
        tester,
        Scaffold(
          body: GuestCodesCard(
            state: state,
            onRevokeGuestCode: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Guest Evaluator Access Codes'), findsOneWidget);
      expect(find.text('DEF-7842AB'), findsOneWidget);
      expect(find.text('Engr. Juan Dela Cruz, PECE'), findsOneWidget);
      expect(find.text('DOST Region X · Alma Mater: UP Diliman'), findsOneWidget);
      expect(find.text('Team Alpha - Final Defense (Room 302)'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });
  });
}
