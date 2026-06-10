import '../screens/web/admin/widgets/defensys_admin_shell.dart';

/// Admin web URL paths (go_router).
abstract final class AdminRoutes {
  static const overview = '/admin/overview';
  static const academicPeriods = '/admin/academic-periods';
  static const users = '/admin/users';
  static const usersBulkImport = '/admin/users/bulk-import';
  static const studentTeams = '/admin/student-teams';
  static const studentTeamsBulkImport = '/admin/student-teams/bulk-import';
  static const studentRecords = '/admin/student-records';
  static const gradeCenter = '/admin/grade-center';
  static const rubrics = '/admin/rubrics';
  static const repositoryAudit = '/admin/repository-audit';
  static const curriculumAnalytics = '/admin/curriculum-analytics';
  static const auditCompliance = '/admin/audit-compliance';
  static const defenseScheduler = '/admin/defense-scheduler';
  static const defenseBoard = '/admin/defense-board';
  static const defenseStages = '/admin/defense-stages';

  static String teamDetail(int teamId) => '/admin/student-teams/$teamId';

  static String gradeDetail(int gradeId) =>
      '/admin/grade-center/grades/$gradeId';

  static String gradeEventTeams(
    String groupKey, {
    required String scope,
    required String stageLabel,
    required String title,
  }) {
    final params = Uri(
      queryParameters: {
        'scope': scope,
        'stageLabel': stageLabel,
        'title': title,
      },
    );
    return '/admin/grade-center/events/$groupKey?${params.query}';
  }

  static String rubricEdit(int rubricId) => '/admin/rubrics/$rubricId/edit';

  static const rubricCreate = '/admin/rubrics/new/edit';

  static String defenseStageEdit(int stageId) =>
      '/admin/defense-stages/$stageId/edit';

  static DefensysAdminSection? sectionForLocation(String location) {
    if (location.startsWith('/admin/overview')) {
      return DefensysAdminSection.overview;
    }
    if (location.startsWith('/admin/academic-periods')) {
      return DefensysAdminSection.academicPeriods;
    }
    if (location.startsWith('/admin/users')) {
      return DefensysAdminSection.userManagement;
    }
    if (location.startsWith('/admin/student-teams')) {
      return DefensysAdminSection.studentTeams;
    }
    if (location.startsWith('/admin/student-records')) {
      return DefensysAdminSection.studentAcademicRecords;
    }
    if (location.startsWith('/admin/grade-center')) {
      return DefensysAdminSection.gradeCenter;
    }
    if (location.startsWith('/admin/rubrics')) {
      return DefensysAdminSection.rubricEngine;
    }
    if (location.startsWith('/admin/repository-audit')) {
      return DefensysAdminSection.repositoryAudit;
    }
    if (location.startsWith('/admin/curriculum-analytics')) {
      return DefensysAdminSection.curriculumAnalytics;
    }
    if (location.startsWith('/admin/audit-compliance')) {
      return DefensysAdminSection.auditCompliance;
    }
    if (location.startsWith('/admin/defense-scheduler')) {
      return DefensysAdminSection.scheduling;
    }
    if (location.startsWith('/admin/defense-board')) {
      return DefensysAdminSection.defenseBoard;
    }
    if (location.startsWith('/admin/defense-stages')) {
      return DefensysAdminSection.defenseStages;
    }
    return null;
  }

  static String pathForSection(DefensysAdminSection section) {
    return switch (section) {
      DefensysAdminSection.overview => overview,
      DefensysAdminSection.academicPeriods => academicPeriods,
      DefensysAdminSection.userManagement => users,
      DefensysAdminSection.studentTeams => studentTeams,
      DefensysAdminSection.studentAcademicRecords => studentRecords,
      DefensysAdminSection.gradeCenter => gradeCenter,
      DefensysAdminSection.rubricEngine => rubrics,
      DefensysAdminSection.repositoryAudit => repositoryAudit,
      DefensysAdminSection.curriculumAnalytics => curriculumAnalytics,
      DefensysAdminSection.auditCompliance => auditCompliance,
      DefensysAdminSection.scheduling => defenseScheduler,
      DefensysAdminSection.defenseBoard => defenseBoard,
      DefensysAdminSection.defenseStages => defenseStages,
    };
  }
}

/// Faculty web URL paths (go_router).
abstract final class FacultyRoutes {
  static const dashboard = '/faculty/dashboard';
  static const cohort = '/faculty/cohort';
  static const pitStudentImport = '/faculty/pit-student-import';
  static const studentTeams = '/faculty/student-teams';
  static const pitInstructors = '/faculty/pit-instructors';
  static const defenseScheduler = '/faculty/defense-scheduler';
  static const defenseBoard = '/faculty/defense-board';
  static const gradeCenter = '/faculty/grade-center';
  static const rubrics = '/faculty/rubrics';
  static const repositoryAudit = '/faculty/repository-audit';
  static const auditCompliance = '/faculty/audit-compliance';
  static const deliverables = '/faculty/deliverables';
  static const weeklyReports = '/faculty/weekly-reports';
  static const adviserGrading = '/faculty/adviser-grading';
  static const uploader = '/faculty/uploader';
  static const pitEvents = '/faculty/pit-events';

  static String teamDetail(int teamId) => '/faculty/student-teams/$teamId';

  static String? sectionForLocation(String location) {
    if (location.startsWith('/faculty/dashboard')) return 'dashboard';
    if (location.startsWith('/faculty/cohort')) return 'cohort';
    if (location.startsWith('/faculty/pit-student-import')) {
      return 'pit_student_import';
    }
    if (location.startsWith('/faculty/student-teams')) return 'student_teams';
    if (location.startsWith('/faculty/pit-instructors')) {
      return 'pit_instructors';
    }
    if (location.startsWith('/faculty/defense-scheduler')) {
      return 'defense_scheduler';
    }
    if (location.startsWith('/faculty/defense-board')) return 'defense_board';
    if (location.startsWith('/faculty/grade-center')) return 'grade_center';
    if (location.startsWith('/faculty/rubrics')) return 'rubric_engine';
    if (location.startsWith('/faculty/repository-audit')) {
      return 'repository_audit';
    }
    if (location.startsWith('/faculty/audit-compliance')) {
      return 'audit_compliance';
    }
    if (location.startsWith('/faculty/deliverables')) return 'deliverables';
    if (location.startsWith('/faculty/weekly-reports')) {
      return 'weekly_reports';
    }
    if (location.startsWith('/faculty/adviser-grading')) {
      return 'adviser_grading';
    }
    if (location.startsWith('/faculty/uploader')) return 'uploader';
    if (location.startsWith('/faculty/pit-events')) return 'pit_events';
    return null;
  }

  static String pathForSection(String section) {
    return switch (section) {
      'dashboard' => dashboard,
      'cohort' => cohort,
      'pit_student_import' => pitStudentImport,
      'student_teams' => studentTeams,
      'pit_instructors' => pitInstructors,
      'defense_scheduler' => defenseScheduler,
      'defense_board' => defenseBoard,
      'grade_center' => gradeCenter,
      'rubric_engine' => rubrics,
      'repository_audit' => repositoryAudit,
      'audit_compliance' => auditCompliance,
      'deliverables' => deliverables,
      'weekly_reports' => weeklyReports,
      'adviser_grading' => adviserGrading,
      'uploader' => uploader,
      'pit_events' => pitEvents,
      _ => dashboard,
    };
  }
}

abstract final class AppRoutes {
  static const login = '/login';
  static const student = '/student';
  static const panelist = '/panelist';
  static const terms = '/terms';
}
