import 'package:flutter/material.dart';

class TemplateBlueprint {
  const TemplateBlueprint({
    required this.id,
    required this.title,
    required this.shortLabel,
    required this.icon,
    required this.filename,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeFg,
    required this.description,
    required this.highlights,
    required this.rawCsv,
    required this.category,
    this.tableHeader = '',
  });

  final String id;
  final String title;
  final String shortLabel;
  final IconData icon;
  final String filename;
  final String badgeText;
  final Color badgeBg;
  final Color badgeFg;
  final String description;
  final List<String> highlights;
  final String rawCsv;
  final String category; // 'student' or 'team'
  final String tableHeader;
}

// ---------------------------------------------------------------------------
// Student Master Intake Blueprints (User Management)
// ---------------------------------------------------------------------------

final List<TemplateBlueprint> studentIntakeBlueprints = [
  const TemplateBlueprint(
    id: 'student_by_year_level',
    title: 'By Year Level (Master Cohort Intake)',
    shortLabel: 'By Year Level',
    icon: Icons.groups_outlined,
    filename: 'official_class_list_year_level.csv',
    badgeText: 'Master Cohort Intake',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Official university registrar export (LIST OF ENROLLMENT). Supports multi-page intervals, summary header, and cohort intake by Year Level directly from the USTP database.',
    highlights: [
      'Direct USTP database export support (no manual reformatting needed)',
      'Multi-page intervals & headers are auto-detected and skipped',
      'Sections automatically bound later via team groupings',
    ],
    category: 'student',
    rawCsv: '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,143,143,,,,,,,,
,TOTAL,,,,,,,,,,
,,143,143,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,2024-00001,"DELA CRUZ, Juan",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,2,2024-00002,"SANTOS, Maria",BSIT,,2nd Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,3,2024-00003,"REYES, Mark",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,4,2024-00004,"GARCIA, Anna",BSIT,,2nd Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,Print Info:,,,Page 2 of,,,,,,4,
,Monday 22 June 2026,,,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,51,2024-00051,"TORRES, Miguel",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,52,2024-00052,"FLORES, Angela",BSIT,,2nd Year,,F,Officially Enrolled,06/22/2026,06/22/2026
''',
  ),
  const TemplateBlueprint(
    id: 'student_by_section',
    title: 'By Section (Class-Specific Intake)',
    shortLabel: 'By Section',
    icon: Icons.class_outlined,
    filename: 'official_class_list_by_section.csv',
    badgeText: 'Class-Specific Intake',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Standard departmental class list for a specific section. Students are directly assigned to the section specified in the header.',
    highlights: [
      'Immediate section assignment from Row 10',
      'Auto-detects instructor and term metadata',
    ],
    category: 'student',
    rawCsv: '''OFFICIAL LIST OF ENROLLED STUDENTS,,,,,,,,
Academic Term,2026-2027 1st Semester,,,,,,,
Subject Code,IT111,Subject Title,Introduction to Computing,,,,
Academic Units,3 (Lab Units: 1),Mode,Lecture and Laboratory,,,,
Instructor,Prof. Alex Santos,,,,,,,
Class Section,BSIT-1A,,,,,,,
Year Level,1st Year,,,,,,,
Schedule(s),M 1:00 PM - 3:00 PM,,,,,,,
,,,,,,,,
#,Student Number,Full Name,Program,Gender,Level,Email,Contact
1,2024-00001,"DELA CRUZ, Juan",BSIT,M,1st Yr.,202400001@university.edu.ph,09170000001
2,2024-00002,"SANTOS, Maria",BSIT,F,1st Yr.,202400002@university.edu.ph,09170000002
3,2024-00003,"REYES, Mark",BSIT,M,1st Yr.,202400003@university.edu.ph,09170000003
4,2024-00004,"GARCIA, Anna",BSIT,F,1st Yr.,202400004@university.edu.ph,09170000004
''',
  ),
];

// ---------------------------------------------------------------------------
// Team Grouping Blueprints (Student Teams) - Single Unified Source of Truth
// ---------------------------------------------------------------------------

final List<TemplateBlueprint> teamGroupingBlueprints = [
  const TemplateBlueprint(
    id: 'official_team_roster_unified',
    title: 'Official Team Roster (Unified Cohort Template)',
    shortLabel: 'Team Roster',
    icon: Icons.hub_outlined,
    filename: 'defensys_team_roster_template.csv',
    badgeText: 'Unified Cohort (Different & Shared)',
    badgeBg: Color(0xFFEFF6FF),
    badgeFg: Color(0xFF1D4ED8),
    description:
        'Official department standard unified template. Formatted side-by-side exactly like the blueprint spreadsheet: Columns A–E for Different Systems (BSIT-4A), Column F blank divider, and Columns G–K for Single Shared System (BSIT-4B) with System Name and PM metadata.',
    highlights: [
      'Side-by-side unified template matching the sheet blueprint layout',
      'Columns A–E: Different Systems (BSIT-4A) with independent projects',
      'Column F: Blank divider column',
      'Columns G–K: Shared System (BSIT-4B) with System Name, PM, and modules',
      'Supports importing both cohorts together in one sheet or separately',
    ],
    category: 'team',
    rawCsv: '''Team Name,Capstone Project,Section,Adviser,Team Members,,System Name,Hospital Management System,,,
Team SkyLedger,Alumni Career Tracker,BSIT-4A,Prof. Alex Santos,Marcus Villar,,Project Manager,Juan Dela Cruz,,,
,,,,Patricia Ong,,Team Name,Module,Section,Adviser,Team Members
,,,,Ethan Salazar,,Team MedRecord,Patient Records,BSIT-4B,Prof. Roberto Gomez,Juan Dela Cruz
,,,,Zoe Castillo,,,,,,Maria Santos
Team BioPulse,AI-Powered Vital Triage & Disease Predictor,BSIT-4A,Prof. Alex Santos,Ryan Torres,,,,,,Mark Reyes
,,,,Nina Villanueva,,,,,,Anna Garcia
,,,,Diego Garcia,,Team MedBilling,Billing,BSIT-4B,Prof. Roberto Gomez,David Aquino
,,,,Patricia Ramos,,,,,,Sarah Ocampo
Team SafeCity,Smart City IoT Infrastructure & Asset Sentinel,BSIT-4A,Prof. Alex Santos,Carlos Bautista,,,,,,Daniel Rivera
,,,,Sophia Santos,,,,,,Jasmine Morales
,,,,Miguel Cruz,,Team MedSchedule,Appointments,BSIT-4B,Prof. Roberto Gomez,Carlo Ramos
,,,,Isabella Alcantara,,,,,,Nicole Bautista
Team CodeLearners,Campus Event Hub,BSIT-4A,Prof. Alex Santos,David Aquino,,,,,,John Mendoza
,,,,Sarah Ocampo,,,,,,Patricia Cruz
,,,,Daniel Rivera,,Team MedPharma,Pharmacy,BSIT-4B,Prof. Roberto Gomez,Kevin Villanueva
,,,,Jasmine Morales,,,,,,Bea Castro
Team CyberGuard,Automated Penetration Testing & Threat Hunter,BSIT-4A,Prof. Elena Ramos,Gabriel Mendoza,,,,,,Christian Lim
,,,,Bea Castro,,,,,,Joshua Navarro
,,,,Christian Lim,,Team MedTriage,Triage,BSIT-4B,Prof. Cynthia Morales,Cedric Valdez
,,,,Joshua Navarro,,,,,,Leila Soriano
Team AgriSense,Smart Agriculture Crop & Soil Monitoring,BSIT-4A,Prof. Elena Ramos,Adrian Valdez,,,,,,Paolo Ramos
,,,,Stephanie Yap,,,,,,Diana Cruz
,,,,Jerome De Leon,,Team MedLab,Laboratory,BSIT-4B,Prof. Cynthia Morales,Anthony Lim
,,,,Camille Roxas,,,,,,Katrina Santos
Team EduTrack,Student Performance Analytics & Early Warning,BSIT-4A,Prof. Elena Ramos,Carlo Ramos,,,,,,Justin Ocampo
,,,,Nicole Bautista,,,,,,Bianca Reyes
,,,,John Mendoza,,Team MedInventory,Inventory,BSIT-4B,Prof. Cynthia Morales,Patrick Mendoza
,,,,Patricia Cruz,,,,,,Christine Torres
Team EcoRoute,Intelligent Fleet Logistics & Route Optimizer,BSIT-4A,Prof. Elena Ramos,Miguel Torres,,,,,,Bea Bautista
,,,,Angela Flores,,,,,,Danica Sotto
,,,,Francis Dizon,,Team MedWards,Wards,BSIT-4B,Prof. Cynthia Morales,Kenneth Salazar
,,,,Rhea Salazar,,,,,,Nicole Dizon
,,,,,,,,,,Jerome Navarro
,,,,,,,,,,Alyssa Castillo
''',
  ),
];

// ---------------------------------------------------------------------------
// PIT Team Grouping Blueprints (Single Unified Source of Truth)
// ---------------------------------------------------------------------------

final List<TemplateBlueprint> pitTeamGroupingBlueprints = [
  const TemplateBlueprint(
    id: 'pit_team_roster_unified',
    title: 'Official PIT Team Roster (Unified Cohort Template)',
    shortLabel: 'PIT Roster',
    icon: Icons.hub_outlined,
    filename: 'defensys_pit_team_roster_template.csv',
    badgeText: 'Unified PIT Cohort',
    badgeBg: Color(0xFFEFF6FF),
    badgeFg: Color(0xFF1D4ED8),
    description:
        'Official PIT standard unified template formatted side-by-side: Columns A–E for Different Systems (BSIT-2A), Column F blank divider, and Columns G–K for Societree Shared System (BSIT-2B).',
    highlights: [
      'Side-by-side unified template matching the sheet blueprint layout',
      'Columns A–E: Different Systems (BSIT-2A) with independent projects',
      'Column F: Blank divider column',
      'Columns G–K: Societree Shared System (BSIT-2B) with modules',
      'Supports importing both cohorts together in one sheet or separately',
    ],
    category: 'team',
    rawCsv: '''Team Name,PIT Project,Section,Instructor,Team Members,,System Name,Societree,,,
Group 1,Smart Campus Navigation System,BSIT-2A,Prof. Alex Santos,Juan Dela Cruz,,Project Manager,Juan Dela Cruz,,,
,,,,Maria Santos,,Team Name,Module,Section,Instructor,Team Members
,,,,Mark Reyes,,Group 1,Site Module,BSIT-2B,Prof. Alex Santos,Juan Dela Cruz
,,,,Anna Garcia,,,,,,Maria Santos
Group 2,Automated Library Portal,BSIT-2A,Prof. Alex Santos,David Aquino,,,,,,Mark Reyes
,,,,Sarah Ocampo,,,,,,Anna Garcia
,,,,Daniel Rivera,,Group 2,Arcu Module,BSIT-2B,Prof. Alex Santos,David Aquino
,,,,Jasmine Morales,,,,,,Sarah Ocampo
Group 3,Alumni Career Tracker,BSIT-2A,Prof. Alex Santos,Carlo Ramos,,,,,,Daniel Rivera
,,,,Nicole Bautista,,,,,,Jasmine Morales
,,,,John Mendoza,,Group 3,Events Module,BSIT-2B,Prof. Alex Santos,Carlo Ramos
,,,,Patricia Cruz,,,,,,Nicole Bautista
Group 4,Event Booking System,BSIT-2A,Prof. Alex Santos,Kevin Villanueva,,,,,,John Mendoza
,,,,Bea Castro,,,,,,Patricia Cruz
,,,,Christian Lim,,Group 4,Membership Module,BSIT-2B,Prof. Alex Santos,Kevin Villanueva
,,,,Joshua Navarro,,,,,,Bea Castro
Group 5,Hostel Reservation Portal,BSIT-2A,Prof. Alex Santos,Cedric Valdez,,,,,,Christian Lim
,,,,Leila Soriano,,,,,,Joshua Navarro
,,,,Paolo Ramos,,Group 5,Finance Module,BSIT-2B,Prof. Alex Santos,Cedric Valdez
,,,,Diana Cruz,,,,,,Leila Soriano
Group 6,Campus Lost & Found Sentinel,BSIT-2A,Prof. Alex Santos,Anthony Lim,,,,,,Paolo Ramos
,,,,Katrina Santos,,,,,,Diana Cruz
,,,,Justin Ocampo,,Group 6,Elections Module,BSIT-2B,Prof. Alex Santos,Anthony Lim
,,,,Bianca Reyes,,,,,,Katrina Santos
Group 7,Student Tutoring Exchange,BSIT-2A,Prof. Alex Santos,Patrick Mendoza,,,,,,Justin Ocampo
,,,,Christine Torres,,,,,,Bianca Reyes
Group 8,Green Campus Energy Tracker,BSIT-2A,Prof. Alex Santos,Kenneth Salazar,,Group 7,Publication Module,BSIT-2B,Prof. Alex Santos,Patrick Mendoza
,,,,Nicole Dizon,,,,,,Christine Torres
,,,,Jerome Navarro,,,,,,Bea Bautista
,,,,Alyssa Castillo,,Group 8,Certificates Module,BSIT-2B,Prof. Alex Santos,Kenneth Salazar
,,,,,,,,,,Nicole Dizon
,,,,,,,,,,Jerome Navarro
,,,,,,,,,,Alyssa Castillo
''',
  ),
];

List<TemplateBlueprint> teamGroupingBlueprintsFor({required bool isCapstone}) =>
    isCapstone ? teamGroupingBlueprints : pitTeamGroupingBlueprints;

class SampleBlueprintTeamItem {
  const SampleBlueprintTeamItem({
    required this.teamName,
    required this.section,
    required this.members,
    required this.independentProject,
    required this.sharedModule,
    this.pitSharedModule = '',
  });

  final String teamName;
  final String section;
  final List<String> members;
  final String independentProject;
  final String sharedModule;
  final String pitSharedModule;

  String effectiveSection({required bool isCapstone}) =>
      isCapstone ? section : section.replaceAll('4', '2');

  String effectiveSharedModule({required bool isCapstone}) =>
      (!isCapstone && pitSharedModule.isNotEmpty) ? pitSharedModule : sharedModule;
}

final List<SampleBlueprintTeamItem> sampleAdviser1Teams = [
  const SampleBlueprintTeamItem(
    teamName: 'Group 1',
    section: 'BSIT-4A',
    members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
    independentProject: 'Smart Campus Navigation System',
    sharedModule: 'Patient Records',
    pitSharedModule: 'Site Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 2',
    section: 'BSIT-4A',
    members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
    independentProject: 'Automated Library Portal',
    sharedModule: 'Billing',
    pitSharedModule: 'Arcu Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 3',
    section: 'BSIT-4A',
    members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
    independentProject: 'Alumni Career Tracker',
    sharedModule: 'Appointments',
    pitSharedModule: 'Events Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 4',
    section: 'BSIT-4A',
    members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
    independentProject: 'Event Booking System',
    sharedModule: 'Triage',
    pitSharedModule: 'Membership Module',
  ),
];

final List<SampleBlueprintTeamItem> sampleAdviser2Teams = [
  const SampleBlueprintTeamItem(
    teamName: 'Group 1',
    section: 'BSIT-4B',
    members: ['Miguel Torres', 'Angela Flores', 'Francis Dizon', 'Rhea Salazar'],
    independentProject: 'Hospital Inventory System',
    sharedModule: 'Pharmacy',
    pitSharedModule: 'Finance Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 2',
    section: 'BSIT-4B',
    members: ['Gabriel Tan', 'Chloe Soriano', 'Pauline Mercado', 'Rafael Pascual'],
    independentProject: 'Laboratory Management Portal',
    sharedModule: 'Laboratory',
    pitSharedModule: 'Elections Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 3',
    section: 'BSIT-4B',
    members: ['Adrian Valdez', 'Stephanie Yap', 'Jerome De Leon', 'Camille Roxas'],
    independentProject: 'Security Clearance System',
    sharedModule: 'Inventory',
    pitSharedModule: 'Publication Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 4',
    section: 'BSIT-4B',
    members: ['Bryan Castillo', 'Karen Tolentino', 'Vincent Miranda', 'Alyssa Fernandez'],
    independentProject: 'Dormitory Management System',
    sharedModule: 'Wards',
    pitSharedModule: 'Certificates Module',
  ),
];

