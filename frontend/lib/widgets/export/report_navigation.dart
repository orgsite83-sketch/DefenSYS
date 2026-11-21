import 'package:flutter/material.dart';

import 'report_catalog.dart';

/// Task groups select existing reports; report IDs and endpoints stay stable.
class ReportGroup {
  const ReportGroup(
    this.id,
    this.title,
    this.description,
    this.icon,
    this.reportIds,
  );

  final String id, title, description;
  final IconData icon;
  final List<String> reportIds;

  List<ReportDefinition> reportsFor(Map<String, dynamic>? user) {
    final visible = ReportCatalog.visible(
      user,
    ).map((report) => report.id).toSet();
    return reportIds
        .where(visible.contains)
        .map((id) => ReportCatalog.find(id)!)
        .toList();
  }
}

abstract final class ReportNavigation {
  static const groups = [
    ReportGroup(
      'grades',
      'Grades',
      'Student and team grades, class lists, and report cards.',
      Icons.grading_outlined,
      [
        'student-grade-masterlist',
        'team-grade-masterlist',
        'individual-grade',
        'team-grade',
        'capstone-grade-sheet',
        'pit-grade-sheet',
        'semester-grades',
      ],
    ),
    ReportGroup(
      'projects',
      'Projects & submissions',
      'Concept decisions, submitted files, and defense readiness.',
      Icons.folder_outlined,
      ['concept-projects', 'project-records', 'readiness'],
    ),
    ReportGroup(
      'schedules',
      'Defense schedules',
      'Defense dates, rooms, and panel assignments.',
      Icons.calendar_month_outlined,
      ['defense-schedules'],
    ),
    ReportGroup(
      'people',
      'Teams & people',
      'Team rosters, student enrollment, and staff directories.',
      Icons.groups_outlined,
      [
        'team-roster',
        'student-enrollment',
        'faculty-directory',
        'external-evaluators',
        'user-directory',
      ],
    ),
    ReportGroup(
      'requirements',
      'Rubrics & requirements',
      'Scoring criteria and required defense deliverables.',
      Icons.checklist_outlined,
      ['rubrics', 'rubric-details', 'defense-stage-setup', 'pit-event-setup'],
    ),
    ReportGroup(
      'other',
      'Other reports',
      'Academic summaries, curriculum coverage, and system records.',
      Icons.description_outlined,
      ['overview', 'curriculum-summary', 'academic-periods', 'audit-trail'],
    ),
  ];

  static ReportGroup groupFor(String reportId) =>
      groups.firstWhere((group) => group.reportIds.contains(reportId));

  static String gradeReport({required bool teams, required bool individual}) =>
      individual
      ? (teams ? 'team-grade' : 'individual-grade')
      : (teams ? 'team-grade-masterlist' : 'student-grade-masterlist');

  static String title(ReportDefinition report) =>
      const {
        'student-grade-masterlist': 'Student grade list',
        'team-grade-masterlist': 'Team grade list',
        'individual-grade': 'Student report card',
        'team-grade': 'Team report card',
        'capstone-grade-sheet': 'Capstone stage summary',
        'pit-grade-sheet': 'PIT event summary',
        'semester-grades': 'Semester grade summary',
        'concept-projects': 'Concept decisions & intake roster',
        'project-records': 'Submitted files',
        'readiness': 'Defense readiness',
        'defense-schedules': 'Defense schedule',
        'team-roster': 'Team roster',
        'student-enrollment': 'Student enrollment',
        'faculty-directory': 'Faculty & staff',
        'external-evaluators': 'External evaluators & assignments',
        'user-directory': 'User directory',
        'rubrics': 'Rubric catalog',
        'rubric-details': 'Individual rubric',
        'defense-stage-setup': 'Defense stage requirements',
        'pit-event-setup': 'PIT event requirements',
        'overview': 'Academic overview',
        'curriculum-summary': 'Curriculum coverage',
        'academic-periods': 'Academic periods',
        'audit-trail': 'Logs export',
      }[report.id] ??
      report.title;

  static List<ReportDefinition> search(
    Map<String, dynamic>? user,
    String query,
  ) {
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return ReportCatalog.visible(user).where((report) {
      final text =
          '${title(report)} ${report.title} ${report.description} ${groupFor(report.id).title}'
              .toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  static String description(ReportDefinition report) =>
      const {
        'student-grade-masterlist':
            'Student grades for a class or the whole semester.',
        'team-grade-masterlist':
            'Grade lists and assessment results for multiple teams.',
        'individual-grade':
            'Detailed grades and assessment results for one student.',
        'team-grade': 'Detailed grades and assessment results for one team.',
        'capstone-grade-sheet':
            'Compiled grades for a selected Capstone defense stage.',
        'pit-grade-sheet': 'Compiled grades for a PIT event and year level.',
        'semester-grades':
            'Team grades and outcomes across the selected semester.',
        'concept-projects':
            'Concept titles, decisions, and Capstone intake rosters.',
      }[report.id] ??
      report.description;
}
