import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/faculty/faculty_base_dashboard_content.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('FacultyBaseDashboardContent renders institutional portal with hearings and status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockData = {
      'active_semester': '1st Semester, A.Y. 2024-2025',
      'has_e_signature': true,
      'roles': {
        'panelist': true,
        'pit_lead': false,
        'adviser': false,
        'documenter': false,
      },
      'advised_teams': [],
      'panelist_assignments': [
        {
          'id': 101,
          'schedule_id': 42,
          'scheduled_date': '2026-09-15',
          'start_time': '10:00 AM',
          'room': 'Room 402',
          'scope': 'CAPSTONE',
          'stage_label': 'Title Defense',
          'is_chair': true,
          'team_name': 'Team Alpha',
          'project_title': 'IoT Flood Warning System',
        },
      ],
    };

    var boardOpened = false;
    var archiveOpened = false;
    var rubricsOpened = false;
    var signatureOpened = false;

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: FacultyBaseDashboardContent(
          data: mockData,
          facultyName: 'Prof. Maricel Suarez',
          onOpenDefenseBoard: () => boardOpened = true,
          onOpenProjectArchive: () => archiveOpened = true,
          onOpenRubrics: () => rubricsOpened = true,
          onOpenSignatureUpload: () => signatureOpened = true,
        ),
      ),
    );

    // Verify header
    expect(find.text('Welcome, Prof. Maricel Suarez'), findsOneWidget);
    expect(
      find.text('Faculty Member Portal · 1st Semester, A.Y. 2024-2025'),
      findsOneWidget,
    );

    // Verify readiness cards
    expect(find.text('Digital Signature Verified'), findsOneWidget);
    expect(find.text('Defense Deliberation Pool'), findsOneWidget);
    expect(find.text('Department Roles & Load'), findsOneWidget);
    expect(find.text('Assigned Hearing'), findsOneWidget);

    // Verify hearing details
    expect(find.text('Team Alpha'), findsOneWidget);
    expect(find.text('IoT Flood Warning System'), findsOneWidget);
    expect(find.text('Title Defense'), findsOneWidget);
    expect(find.text('Panel Chair'), findsOneWidget);
    expect(find.text('Room: Room 402'), findsOneWidget);

    // Verify archive and rubrics cards
    expect(find.text('Institutional Project Repository'), findsOneWidget);
    expect(find.text('Scoring Rubrics & Guidelines'), findsOneWidget);

    // Test callback buttons
    await tester.tap(find.text('Open Defense Board'));
    await tester.pump();
    expect(boardOpened, isTrue);

    await tester.tap(find.text('Search Project Archive'));
    await tester.pump();
    expect(archiveOpened, isTrue);

    await tester.tap(find.text('View Rubrics'));
    await tester.pump();
    expect(rubricsOpened, isTrue);

    await tester.tap(find.text('Update Signature'));
    await tester.pump();
    expect(signatureOpened, isTrue);
  });

  testWidgets('FacultyBaseDashboardContent renders signature required when signature is missing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockData = {
      'active_semester': '1st Semester, A.Y. 2024-2025',
      'has_e_signature': false,
      'roles': {},
      'advised_teams': [],
      'panelist_assignments': [],
    };

    var signatureOpened = false;

    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: FacultyBaseDashboardContent(
          data: mockData,
          facultyName: 'Prof. Jonathan Beltran',
          onOpenDefenseBoard: () {},
          onOpenProjectArchive: () {},
          onOpenRubrics: () {},
          onOpenSignatureUpload: () => signatureOpened = true,
        ),
      ),
    );

    expect(find.text('E-Signature Required'), findsOneWidget);
    expect(find.text('No Defense Hearings Currently Scheduled'), findsOneWidget);

    await tester.tap(find.text('Upload Digital Signature'));
    await tester.pump();
    expect(signatureOpened, isTrue);
  });
}
