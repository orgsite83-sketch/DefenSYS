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
        'Official university registrar export organized by Year Level. Class section is omitted and automatically assigned when team groupings are uploaded.',
    highlights: [
      'Enrolls the entire cohort at once',
      'Sections automatically bound via team groupings',
    ],
    category: 'student',
    rawCsv: '''OFFICIAL LIST OF ENROLLED STUDENTS,,,,,,,,
Academic Term,2026-2027 1st Semester,,,,,,,
Subject Code,IT211,Subject Title,Data Structures and Algorithms,,,,
Academic Units,3 (Lab Units: 1),Mode,Lecture and Laboratory,,,,
Year Level,2nd Year,,,,,,,
Schedule(s),M/Th 1:00 PM - 3:00 PM,,,,,,,
,,,,,,,,
#,Student Number,Full Name,Program,Gender,Level,Email,Contact
1,2024-00001,"DELA CRUZ, Juan",BSIT,M,2nd Yr.,202400001@university.edu.ph,09170000001
2,2024-00002,"SANTOS, Maria",BSIT,F,2nd Yr.,202400002@university.edu.ph,09170000002
3,2024-00003,"REYES, Mark",BSIT,M,2nd Yr.,202400003@university.edu.ph,09170000003
4,2024-00004,"GARCIA, Anna",BSIT,F,2nd Yr.,202400004@university.edu.ph,09170000004
5,2024-00005,"TORRES, Miguel",BSIT,M,2nd Yr.,202400005@university.edu.ph,09170000005
6,2024-00006,"FLORES, Angela",BSIT,F,2nd Yr.,202400006@university.edu.ph,09170000006
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
        'Official department standard grouped by Faculty Adviser with Section sub-headers (e.g. 3 teams in 4A, 1 team in 4C). Clean 3-column table with 4 members per team.',
    highlights: [
      'Grouped by Faculty Adviser (instantly verify 4-team cap)',
      'Section sub-headers allow advisees from multiple sections',
      'Clean 3-column format (Team Name, Names, Project)',
      '4 members per team (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''ADVISER: Prof. Alex Santos

Section,BSIT-4A
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

Section,BSIT-4C
Team Name,Names,Project / Module
Group 1,Miguel Torres,Hospital Inventory System
,,Angela Flores,
,,Francis Dizon,
,,Rhea Salazar,

ADVISER: Prof. Elena Ramos

Section,BSIT-4A
Team Name,Names,Project / Module
Group 4,Kevin Villanueva,Event Booking System
,,Bea Castro,
,,Christian Lim,
,,Joshua Navarro,

Section,BSIT-4B
Team Name,Names,Project / Module
Group 1,Gabriel Tan,Laboratory Management Portal
,,Chloe Soriano,
,,Pauline Mercado,
,,Rafael Pascual,
Group 2,Adrian Valdez,Security Clearance System
,,Stephanie Yap,
,,Jerome De Leon,
,,Camille Roxas,
Group 3,Bryan Castillo,Dormitory Management System
,,Karen Tolentino,
,,Vincent Miranda,
,,Alyssa Fernandez,
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
        'Official department standard where sections collaborate on a shared system. System Name and PM at top, grouped by Faculty Adviser with Section sub-headers.',
    highlights: [
      'One overarching system divided into modules',
      'Grouped by Faculty Adviser (instantly verify 4-team cap)',
      'Section sub-headers allow advisees from multiple sections',
      '4 members per team (1st member = Leader)',
    ],
    category: 'team',
    rawCsv: '''System Name,Hospital Management System
Project Manager,Juan Dela Cruz

ADVISER: Prof. Alex Santos

Section,BSIT-4A
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Patient Records
,,Maria Santos,
,,Mark Reyes,
,,Anna Garcia,
Group 2,David Aquino,Billing
,,Sarah Ocampo,
,,Daniel Rivera,
,,Jasmine Morales,
Group 3,Carlo Ramos,Appointments
,,Nicole Bautista,
,,John Mendoza,
,,Patricia Cruz,

Section,BSIT-4C
Team Name,Names,Project / Module
Group 1,Miguel Torres,Pharmacy
,,Angela Flores,
,,Francis Dizon,
,,Rhea Salazar,

ADVISER: Prof. Elena Ramos

Section,BSIT-4A
Team Name,Names,Project / Module
Group 4,Kevin Villanueva,Triage
,,Bea Castro,
,,Christian Lim,
,,Joshua Navarro,

Section,BSIT-4B
Team Name,Names,Project / Module
Group 1,Gabriel Tan,Laboratory
,,Chloe Soriano,
,,Pauline Mercado,
,,Rafael Pascual,
Group 2,Adrian Valdez,Inventory
,,Stephanie Yap,
,,Jerome De Leon,
,,Camille Roxas,
Group 3,Bryan Castillo,Wards
,,Karen Tolentino,
,,Vincent Miranda,
,,Alyssa Fernandez,
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

