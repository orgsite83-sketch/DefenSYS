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
// Team Grouping Blueprints (Student Teams) - Streamlined to 2 Primary Choices
// ---------------------------------------------------------------------------

final List<TemplateBlueprint> teamGroupingBlueprints = [
  const TemplateBlueprint(
    id: 'official_team_roster_independent',
    title: 'Different Systems (Independent Projects)',
    shortLabel: 'Independent Systems',
    icon: Icons.hub_outlined,
    filename: 'defensys_team_roster_independent_projects.csv',
    badgeText: 'Different Systems per Team',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Official department standard 5-column matrix format (Team Name, Capstone Project, Section, Adviser, Team Members). Team Name sits in a single cell per team, with Section & Adviser vertically merged across advisee teams.',
    highlights: [
      '5-column matrix format (Team Name, Capstone Project, Section, Adviser, Team Members)',
      'Team Name & Project occupy single top cell per team (rows 2-4 unmerged blank)',
      'Section & Adviser vertically merged across advisee teams',
      '4 members per team stacked vertically (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''Team Name,Capstone Project,Section,Adviser,Team Members
Team SkyLedger,Alumni Career Tracker,BSIT 4A,Prof. Alex Santos,Marcus Villar
,,,,Patricia Ong
,,,,Ethan Salazar
,,,,Zoe Castillo
Team BioPulse,AI-Powered Patient Vital Triage & Disease Predictor,,,Ryan Torres
,,,,Nina Villanueva
,,,,Diego Garcia
,,,,Patricia Ramos
Team SafeCity,Smart City IoT Infrastructure & Asset Sentinel,,,Carlos Bautista
,,,,Sophia Santos
,,,,Miguel Cruz
,,,,Isabella Alcantara
Team CodeLearners,Campus Event Hub,BSIT 4B,,Kevin Villanueva
,,,,Bea Castro
,,,,Christian Lim
,,,,Joshua Navarro
''',
  ),
  const TemplateBlueprint(
    id: 'official_team_roster_shared',
    title: 'Single Shared System (Modules)',
    shortLabel: 'Shared System',
    icon: Icons.account_tree_outlined,
    filename: 'defensys_team_roster_shared_system.csv',
    badgeText: 'Single Shared System',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Official department standard where sections collaborate on a shared system. Grouped by Section (BSIT-4A & BSIT-4B) with faculty advisers, meaningful team names, and 4 students per team.',
    highlights: [
      'One overarching system divided into modules per section',
      'Structured by Section (BSIT-4A, BSIT-4B) with dedicated faculty advisers',
      'Team Name sits in a single unmerged cell per team',
      'Exactly 4 members per team (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''System Name,Hospital Management System
Project Manager,Juan Dela Cruz

Section,BSIT-4A
ADVISER: Prof. Alex Santos
Team Name,Names,Project / Module
Team MedRecord,Juan Dela Cruz,Patient Records
,,Maria Santos,
,,Mark Reyes,
,,Anna Garcia,
Team MedBilling,David Aquino,Billing
,,Sarah Ocampo,
,,Daniel Rivera,
,,Jasmine Morales,
Team MedSchedule,Carlo Ramos,Appointments
,,Nicole Bautista,
,,John Mendoza,
,,Patricia Cruz,
Team MedPharma,Miguel Torres,Pharmacy
,,Angela Flores,
,,Francis Dizon,
,,Rhea Salazar,

ADVISER: Prof. Elena Ramos
Team Name,Names,Project / Module
Team MedTriage,Kevin Villanueva,Triage
,,Bea Castro,
,,Christian Lim,
,,Joshua Navarro,
Team MedLab,Gabriel Tan,Laboratory
,,Chloe Soriano,
,,Pauline Mercado,
,,Rafael Pascual,
Team MedInventory,Adrian Valdez,Inventory
,,Stephanie Yap,
,,Jerome De Leon,
,,Camille Roxas,
Team MedWards,Bryan Castillo,Wards
,,Karen Tolentino,
,,Vincent Miranda,
,,Alyssa Fernandez,

System Name,Campus Logistics & Supply Chain Platform
Project Manager,Patricia Ramos

Section,BSIT-4B
ADVISER: Prof. Roberto Gomez
Team Name,Names,Project / Module
Team FleetTrack,Lucas Hernandez,Fleet & Route Monitoring
,,Camille Bernardo,
,,Danilo Gutierrez,
,,Andrea Salazar,
Team WarehouseHub,Enzo Morales,Central Storage & Stock
,,Valerie Cruz,
,,Paolo Mendoza,
,,Bianca Reyes,
Team OrderDispatch,Giancarlo Diaz,Package Dispatching
,,Rachelle Santos,
,,Marco Villanueva,
,,Hannah Flores,
Team SupplierLink,Leandro Garcia,Vendor Procurement
,,Kirsten Gomez,
,,Jerome Pineda,
,,Monica Castro,

ADVISER: Prof. Cynthia Morales
Team Name,Names,Project / Module
Team AssetTag,Timothy Aguilar,RFID & Asset Tracking
,,Clarisse Domingo,
,,Nathaniel Ramos,
,,Fiona Soriano,
Team FreightGuard,Oliver Tan,Cold-Chain & Security
,,Kaye Tolentino,
,,Derrick Miranda,
,,Althea Pascual,
Team AuditPulse,Justin Valenzuela,Compliance & Audits
,,Giselle David,
,,Patrick Ocampo,
,,Denise Rivera,
Team CargoAnalytics,Aaron Mercado,KPI & Fuel Analytics
,,Jocelyn Aquino,
,,Raymond Dizon,
,,Erika Yap,
''',
  ),
];

// ---------------------------------------------------------------------------
// PIT Team Grouping Blueprints (Single Faculty Instructor at Top)
// ---------------------------------------------------------------------------

final List<TemplateBlueprint> pitTeamGroupingBlueprints = [
  const TemplateBlueprint(
    id: 'pit_team_roster_independent',
    title: 'Different Systems (Independent Projects)',
    shortLabel: 'Independent Systems',
    icon: Icons.hub_outlined,
    filename: 'defensys_pit_team_roster_independent.csv',
    badgeText: 'PIT Independent Projects',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Official PIT standard with Section header blocks supporting multiple sections (BSIT-2A & BSIT-2B). Faculty Instructor declared at top, with 4 members per team.',
    highlights: [
      'Section header blocks support multiple sections in one sheet',
      '1 faculty Instructor declared at top',
      'Each team has its own independent system/project',
      '4 members per team (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''Instructor,Prof. Alex Santos

Section,BSIT-2A
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus Navigation System
,,Maria Santos,
,,Mark Reyes,
,,Anna Garcia,
Group 2,David Aquino,Automated Library Portal
,,Sarah Ocampo,
,,Daniel Rivera,
,,Jasmine Morales,
Group 3,Carlo Ramos,Alumni Career Tracker
,,Nicole Bautista,
,,John Mendoza,
,,Patricia Cruz,
Group 4,Kevin Villanueva,Event Booking System
,,Bea Castro,
,,Christian Lim,
,,Joshua Navarro,

Section,BSIT-2B
Team Name,Names,Project / Module
Group 1,Miguel Torres,Hospital Inventory System
,,Angela Flores,
,,Francis Dizon,
,,Rhea Salazar,
Group 2,Gabriel Tan,Laboratory Management Portal
,,Chloe Soriano,
,,Pauline Mercado,
,,Rafael Pascual,
Group 3,Adrian Valdez,Security Clearance System
,,Stephanie Yap,
,,Jerome De Leon,
,,Camille Roxas,
Group 4,Bryan Castillo,Dormitory Management System
,,Karen Tolentino,
,,Vincent Miranda,
,,Alyssa Fernandez,
''',
  ),
  const TemplateBlueprint(
    id: 'pit_team_roster_shared',
    title: 'Single Shared System (Modules)',
    shortLabel: 'Shared System',
    icon: Icons.account_tree_outlined,
    filename: 'defensys_pit_team_roster_shared_system.csv',
    badgeText: 'PIT Shared System',
    badgeBg: Color(0xFFF1F5F9),
    badgeFg: Color(0xFF475569),
    description:
        'Official PIT standard where sections collaborate on a shared system (e.g. Societree). System Name, Instructor, and PM at top, Section header blocks, with modules assigned per team.',
    highlights: [
      'Section header blocks support multiple sections in one sheet',
      '1 faculty Instructor declared at top',
      'Single shared system divided into modules per team',
      '4 members per team (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''System Name,Societree
Instructor,Prof. Alex Santos
Project Manager,Juan Dela Cruz

Section,BSIT-2A
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Site Module
,,Maria Santos,
,,Mark Reyes,
,,Anna Garcia,
Group 2,David Aquino,Arcu Module
,,Sarah Ocampo,
,,Daniel Rivera,
,,Jasmine Morales,
Group 3,Carlo Ramos,Events Module
,,Nicole Bautista,
,,John Mendoza,
,,Patricia Cruz,
Group 4,Kevin Villanueva,Membership Module
,,Bea Castro,
,,Christian Lim,
,,Joshua Navarro,

Section,BSIT-2B
Team Name,Names,Project / Module
Group 1,Miguel Torres,Finance Module
,,Angela Flores,
,,Francis Dizon,
,,Rhea Salazar,
Group 2,Gabriel Tan,Elections Module
,,Chloe Soriano,
,,Pauline Mercado,
,,Rafael Pascual,
Group 3,Adrian Valdez,Publication Module
,,Stephanie Yap,
,,Jerome De Leon,
,,Camille Roxas,
Group 4,Bryan Castillo,Certificates Module
,,Karen Tolentino,
,,Vincent Miranda,
,,Alyssa Fernandez,
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

