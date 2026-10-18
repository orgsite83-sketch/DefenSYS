import 'package:flutter/material.dart';

class ReportDefinition {
  const ReportDefinition(
    this.id,
    this.title,
    this.description,
    this.category, {
    String? endpoint,
    this.scope = '',
    this.adminOnly = false,
    this.managerOnly = false,
    this.legacy = false,
    this.filters = const [],
    this.icon = Icons.description_outlined,
  }) : endpoint = endpoint ?? id;

  final String id, title, description, category, endpoint, scope;
  final bool adminOnly, managerOnly, legacy;
  final List<String> filters;
  final IconData icon;

  String endpointFor(Map<String, String> params) {
    final selector = id == 'rubric-details'
        ? 'rubric_id'
        : id == 'team-grade'
        ? 'team_id'
        : id == 'individual-grade'
        ? 'student_id'
        : null;
    return selector == null ? '$endpoint/' : '$endpoint/${params[selector]}/';
  }

  String? missingSelection(Map<String, String> params) {
    final selector = id == 'rubric-details'
        ? 'rubric_id'
        : id == 'team-grade'
        ? 'team_id'
        : id == 'individual-grade'
        ? 'student_id'
        : null;
    return selector != null && (params[selector] ?? '').isEmpty
        ? 'Choose a ${selector == 'rubric_id'
              ? 'rubric'
              : selector == 'team_id'
              ? 'team'
              : 'student'}.'
        : null;
  }

  Map<String, dynamic> toCatalogEntry() => {
    'id': id,
    'title': title,
    'desc': description,
    'endpoint': endpoint,
    'icon': icon,
    'tag': category,
    'meta': 'PDF · Excel',
    'paramHint': filters.contains('rubric_id')
        ? 'Select a rubric'
        : 'Current filters or custom scope',
    if (scope.isNotEmpty) 'scope': scope,
  };
}

abstract final class ReportCatalog {
  static const reports = [
    ReportDefinition(
      'concept-projects',
      'Concept Project Register',
      'Concept titles and recorded decisions across PIT and Capstone. Export a 3rd Year PIT roster for fresh Capstone intake.',
      'projects',
      managerOnly: true,
      filters: [
        'semester_id',
        'scope',
        'year_level',
        'section',
        'pit_event_config_id',
        'stage_id',
        'concept_status',
        'include_history',
        'layout',
        'search',
      ],
      icon: Icons.topic_outlined,
    ),
    ReportDefinition(
      'team-grade',
      'Team Grade Report Card',
      'Full recorded assessment and criterion breakdown for a team.',
      'grading',
      legacy: true,
      filters: ['semester_id', 'scope', 'team_id', 'coverage'],
      icon: Icons.badge_outlined,
    ),
    ReportDefinition(
      'individual-grade',
      'Individual Student Grade Audit Card',
      'Recorded individual assessments and peer contributions.',
      'grading',
      legacy: true,
      filters: ['semester_id', 'scope', 'student_id', 'coverage'],
      icon: Icons.person_outline,
    ),
    ReportDefinition(
      'capstone-grade-sheet',
      'Capstone Stage Grade Sheet',
      'Compiled grades for a Capstone defense stage.',
      'grading',
      endpoint: 'semester-grades',
      scope: 'capstone',
      legacy: true,
      filters: ['semester_id', 'stage', 'year_level', 'section'],
      icon: Icons.school_outlined,
    ),
    ReportDefinition(
      'pit-grade-sheet',
      'PIT Event Grade Sheet',
      'Compiled grades for a PIT event and cohort.',
      'grading',
      endpoint: 'semester-grades',
      scope: 'pit',
      legacy: true,
      filters: ['semester_id', 'pit_event', 'year_level', 'section'],
      icon: Icons.event_available_outlined,
    ),
    ReportDefinition(
      'semester-grades',
      'Semester Grade Summary',
      'Recorded grades and outcomes across stages and events.',
      'grading',
      legacy: true,
      filters: [
        'semester_id',
        'scope',
        'stage',
        'search',
        'status',
        'year_level',
        'section',
      ],
      icon: Icons.grade_outlined,
    ),
    ReportDefinition(
      'rubrics',
      'Rubric Catalog',
      'Rubric inventory with evaluator types, status and complete criteria in Excel.',
      'grading',
      filters: [
        'semester_id',
        'scope',
        'term_context',
        'search',
        'status',
        'evaluation_type',
      ],
      icon: Icons.rule_outlined,
    ),
    ReportDefinition(
      'rubric-details',
      'Individual Rubric Details',
      'Complete scoring guide with criterion descriptions, scales, maximum scores and weights.',
      'grading',
      endpoint: 'rubrics',
      filters: ['rubric_id', 'semester_id', 'scope'],
      icon: Icons.fact_check_outlined,
    ),
    ReportDefinition(
      'defense-schedules',
      'Defense Schedule Summary',
      'Defense dates, rooms, teams, panels and workflow status.',
      'operations',
      legacy: true,
      filters: [
        'semester_id',
        'scope',
        'stage',
        'search',
        'status',
        'section',
        'adviser',
        'start_date',
        'end_date',
      ],
      icon: Icons.calendar_month_outlined,
    ),
    ReportDefinition(
      'team-roster',
      'Team Roster Report',
      'Teams, project titles, members, leaders and advisers.',
      'operations',
      legacy: true,
      filters: [
        'semester_id',
        'scope',
        'term_context',
        'search',
        'year_level',
        'section',
        'status',
      ],
      icon: Icons.groups_outlined,
    ),
    ReportDefinition(
      'readiness',
      'Pre-Defense Readiness Register',
      'Readiness and outstanding requirements for the selected stage or PIT event.',
      'operations',
      managerOnly: true,
      filters: [
        'semester_id',
        'scope',
        'stage',
        'search',
        'year_level',
        'section',
        'status',
      ],
      icon: Icons.checklist_outlined,
    ),
    ReportDefinition(
      'project-records',
      'Project Archive Register',
      'Recorded files, deliverables, teams, uploaders and upload dates.',
      'operations',
      managerOnly: true,
      filters: [
        'type',
        'academic_year',
        'semester',
        'year_level',
        'stage',
        'status',
        'search',
        'deliverable_id',
      ],
      icon: Icons.inventory_2_outlined,
    ),
    ReportDefinition(
      'external-evaluators',
      'External Evaluators & Defense Assignments',
      'Evaluator directory and assigned defenses, without access credentials.',
      'operations',
      managerOnly: true,
      filters: ['view', 'search', 'status'],
      icon: Icons.person_pin_outlined,
    ),
    ReportDefinition(
      'academic-periods',
      'School Year & Semester Register',
      'School years, semesters and program configuration.',
      'setup',
      adminOnly: true,
      filters: ['school_year', 'semester_id'],
      icon: Icons.date_range_outlined,
    ),
    ReportDefinition(
      'defense-stage-setup',
      'Defense Stage Configuration & Requirements',
      'Stage grading configuration, assigned rubrics and deliverable requirements.',
      'setup',
      adminOnly: true,
      filters: ['semester_id', 'stage', 'search'],
      icon: Icons.layers_outlined,
    ),
    ReportDefinition(
      'pit-event-setup',
      'PIT Event Configuration & Requirements',
      'PIT event grade distribution, rubrics and requirements.',
      'setup',
      scope: 'pit',
      managerOnly: true,
      filters: ['semester_id', 'stage', 'search'],
      icon: Icons.event_note_outlined,
    ),
    ReportDefinition(
      'student-enrollment',
      'Student Enrollment Register',
      'Student academic records by school year, semester, year and section.',
      'governance',
      adminOnly: true,
      filters: ['school_year', 'semester', 'year_level', 'section', 'search'],
      icon: Icons.school_outlined,
    ),
    ReportDefinition(
      'faculty-directory',
      'Faculty & Staff Directory',
      'Faculty accounts and assigned staff responsibilities.',
      'governance',
      adminOnly: true,
      filters: ['search', 'role', 'status'],
      icon: Icons.badge_outlined,
    ),
    ReportDefinition(
      'user-directory',
      'User Directory',
      'Registered portal accounts, filtered by role and active status.',
      'governance',
      adminOnly: true,
      legacy: true,
      filters: ['role', 'status', 'search'],
      icon: Icons.person_search_outlined,
    ),
    ReportDefinition(
      'audit-trail',
      'Audit Trail Export',
      'Recorded system events, evidence and review history.',
      'governance',
      managerOnly: true,
      legacy: true,
      filters: [
        'track',
        'year_level',
        'category',
        'action',
        'review_status',
        'search',
        'start_date',
        'end_date',
      ],
      icon: Icons.receipt_long_outlined,
    ),
    ReportDefinition(
      'overview',
      'Academic Overview Summary',
      'Recorded team, defense and assessment counts.',
      'governance',
      managerOnly: true,
      filters: ['semester_id', 'scope', 'year_level', 'section'],
      icon: Icons.dashboard_outlined,
    ),
    ReportDefinition(
      'curriculum-summary',
      'Curriculum Summary & Criterion Coverage',
      'Recorded competency measures and criterion evaluation coverage.',
      'governance',
      adminOnly: true,
      filters: ['academic_year', 'scope', 'rubric_id', 'stage_id'],
      icon: Icons.insights_outlined,
    ),
  ];

  static ReportDefinition? find(String id) {
    for (final report in reports) {
      if (report.id == id) return report;
    }
    return null;
  }

  static List<ReportDefinition> visible(Map<String, dynamic>? user) {
    if (user == null) return [];
    final admin = user['role'] == 'admin' || user['is_superuser'] == true;
    final lead = user['is_pit_lead'] == true;
    return reports
        .where(
          (report) =>
              (!report.adminOnly || admin) &&
              (!report.managerOnly || admin || lead) &&
              (!lead || admin || report.scope != 'capstone'),
        )
        .toList();
  }

  static String filterLabel(String key) =>
      const {
        'semester_id': 'Academic period',
        'scope': 'Scope',
        'rubric_id': 'Rubric',
        'team_id': 'Team',
        'student_id': 'Student',
        'stage_id': 'Stage',
        'stage': 'Stage / event',
        'pit_event': 'PIT event',
        'pit_event_config_id': 'PIT concept event',
        'concept_status': 'Concept decision',
        'include_history': 'Round coverage',
        'layout': 'Export layout',
        'type': 'Scope',
        'term_context': 'Term coverage',
        'year_level': 'Year level',
        'section': 'Section',
        'academic_year': 'School year',
        'school_year': 'School year',
        'semester': 'Semester',
        'evaluation_type': 'Evaluator type',
        'coverage': 'Assessment coverage',
        'review_status': 'Review status',
      }[key] ??
      key
          .replaceAll('_', ' ')
          .replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match[0]!.toUpperCase(),
          );
}
