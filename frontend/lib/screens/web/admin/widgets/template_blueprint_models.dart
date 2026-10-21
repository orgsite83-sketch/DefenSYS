import 'package:flutter/material.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';

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

TemplateBlueprint _teamBlueprint(bool capstone) => TemplateBlueprint(
  id: capstone ? 'official_team_roster_unified' : 'pit_team_roster_unified',
  title: capstone ? 'Official Capstone Team Sheet' : 'Official PIT Team Sheet',
  shortLabel: capstone ? 'Team Roster' : 'PIT Roster',
  icon: Icons.hub_outlined,
  filename: capstone
      ? 'defensys_team_roster_template.csv'
      : 'defensys_pit_team_roster_template.csv',
  badgeText: 'Different & Shared Systems',
  badgeBg: const Color(0xFFEFF6FF),
  badgeFg: const Color(0xFF1D4ED8),
  description:
      'Different systems in B–F; shared system in H–L. System Name and Project Manager values begin in column I.',
  highlights: const [
    'Separate teams with a blank row.',
    'List the leader first in Team Members.',
  ],
  rawCsv: officialTeamRosterCsv(isCapstone: capstone),
  category: 'team',
);

final List<TemplateBlueprint> teamGroupingBlueprints = [_teamBlueprint(true)];
final List<TemplateBlueprint> pitTeamGroupingBlueprints = [
  _teamBlueprint(false),
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
      (!isCapstone && pitSharedModule.isNotEmpty)
      ? pitSharedModule
      : sharedModule;
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
    members: [
      'David Aquino',
      'Sarah Ocampo',
      'Daniel Rivera',
      'Jasmine Morales',
    ],
    independentProject: 'Automated Library Portal',
    sharedModule: 'Billing',
    pitSharedModule: 'Arcu Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 3',
    section: 'BSIT-4A',
    members: [
      'Carlo Ramos',
      'Nicole Bautista',
      'John Mendoza',
      'Patricia Cruz',
    ],
    independentProject: 'Alumni Career Tracker',
    sharedModule: 'Appointments',
    pitSharedModule: 'Events Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 4',
    section: 'BSIT-4A',
    members: [
      'Kevin Villanueva',
      'Bea Castro',
      'Christian Lim',
      'Joshua Navarro',
    ],
    independentProject: 'Event Booking System',
    sharedModule: 'Triage',
    pitSharedModule: 'Membership Module',
  ),
];

final List<SampleBlueprintTeamItem> sampleAdviser2Teams = [
  const SampleBlueprintTeamItem(
    teamName: 'Group 1',
    section: 'BSIT-4B',
    members: [
      'Miguel Torres',
      'Angela Flores',
      'Francis Dizon',
      'Rhea Salazar',
    ],
    independentProject: 'Hospital Inventory System',
    sharedModule: 'Pharmacy',
    pitSharedModule: 'Finance Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 2',
    section: 'BSIT-4B',
    members: [
      'Gabriel Tan',
      'Chloe Soriano',
      'Pauline Mercado',
      'Rafael Pascual',
    ],
    independentProject: 'Laboratory Management Portal',
    sharedModule: 'Laboratory',
    pitSharedModule: 'Elections Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 3',
    section: 'BSIT-4B',
    members: [
      'Adrian Valdez',
      'Stephanie Yap',
      'Jerome De Leon',
      'Camille Roxas',
    ],
    independentProject: 'Security Clearance System',
    sharedModule: 'Inventory',
    pitSharedModule: 'Publication Module',
  ),
  const SampleBlueprintTeamItem(
    teamName: 'Group 4',
    section: 'BSIT-4B',
    members: [
      'Bryan Castillo',
      'Karen Tolentino',
      'Vincent Miranda',
      'Alyssa Fernandez',
    ],
    independentProject: 'Dormitory Management System',
    sharedModule: 'Wards',
    pitSharedModule: 'Certificates Module',
  ),
];
