import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/academic_period_provider.dart';
import '../../services/student_teams_provider.dart';
import '../../services/user_management_provider.dart';
import '../../services/grading/rubric_engine_provider.dart';
import '../../services/grading/grade_center_provider.dart';
import '../../services/defense_board_provider.dart';
import '../../services/project_archive_provider.dart';
import '../../services/academic/student_academic_records_provider.dart';
import '../../services/academic/curriculum_analytics_provider.dart';
import '../../services/admin/system_audit_provider.dart';

Map<String, String> reportSourceParams(WidgetRef ref, String reportId) {
  final activeId =
      ref.read(academicPeriodProvider).activeSemester?['id']?.toString() ?? '';
  if (reportId == 'academic-periods' || reportId == 'external-evaluators') {
    return {};
  }
  if (reportId == 'audit-trail') {
    final state = ref.read(systemAuditProvider);
    return {
      'category': state.category,
      'review_status': state.reviewStatus,
      'action': state.action,
      'search': state.search,
      'start_date': state.startDate,
      'end_date': state.endDate,
      'track': state.track,
      'year_level': state.yearLevel,
    };
  }
  if (reportId == 'rubrics' || reportId == 'rubric-details') {
    final state = ref.read(rubricEngineProvider);
    return {
      'scope': state.scope,
      'term_context': state.termContext,
      'search': state.search,
      'status': state.status,
      'evaluation_type': state.evaluationType,
    };
  }
  if (reportId == 'student-enrollment') {
    final state = ref.read(studentAcademicRecordsProvider);
    return {
      'search': state.search,
      'school_year': state.schoolYear,
      'semester': state.semester,
    };
  }
  if (reportId == 'faculty-directory' || reportId == 'user-directory') {
    final state = ref.read(userManagementProvider);
    return {'search': state.search, 'role': state.role};
  }
  if (reportId == 'team-roster') {
    final state = ref.read(studentTeamsProvider);
    return {
      'search': state.search,
      'level': state.level,
      'status': state.status,
      'year_level': state.yearLevel ?? '',
      'section': state.section ?? '',
      'pit_event': state.eventName ?? '',
    };
  }
  if (reportId == 'defense-schedules') {
    final state = ref.read(defenseBoardProvider);
    return {
      'semester_id': state.activeSemester?['id']?.toString() ?? activeId,
      'source_context': 'defense-board',
      'search': state.search,
      'scope': state.scope,
      'stage': state.stage,
      'status': state.status,
      'section': state.section,
      'adviser': state.adviser,
    };
  }
  if ([
    'semester-grades',
    'capstone-grade-sheet',
    'pit-grade-sheet',
    'team-grade',
    'individual-grade',
  ].contains(reportId)) {
    final state = ref.read(gradeCenterProvider);
    return {
      'semester_id': state.activeSemester?['id']?.toString() ?? activeId,
      'scope': state.scope,
      if (reportId == 'semester-grades') 'search': state.search,
      if (reportId == 'semester-grades') 'status': state.status,
      'year_level': state.yearLevel,
    };
  }
  if (reportId == 'project-records') {
    final state = ref.read(repositoryAuditProvider);
    return {
      'search': state.search,
      'type': state.type,
      'year_level': state.yearLevel,
      'academic_year': state.academicYear,
      'status': state.status,
      'semester': state.semester,
      'team_id': state.teamId,
      'stage': state.stage,
      'deliverable_id': state.deliverableId,
      'submission_kind': state.submissionKind,
      'view_mode': state.viewMode,
    };
  }
  if (reportId == 'curriculum-summary') {
    final state = ref.read(curriculumAnalyticsProvider);
    return {
      'academic_year': state.selectedAcademicYear,
      'scope': state.selectedScope,
      'rubric_id': state.selectedRubricId,
      'program': state.selectedProgram,
    };
  }
  return {'semester_id': activeId};
}
