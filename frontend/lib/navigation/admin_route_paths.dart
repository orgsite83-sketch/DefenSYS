import '../screens/web/admin/widgets/defensys_admin_shell.dart';

/// Explicit cross-section evaluation links retain only known board context.
abstract final class BoardEvaluationRoutes {
  static String detail({
    required bool faculty,
    required int gradeId,
    required bool locked,
    required Uri boardUri,
    required String program,
  }) => Uri(
    path: faculty
        ? FacultyRoutes.gradeDetail(gradeId)
        : AdminRoutes.gradeDetail(gradeId),
    queryParameters: {
      'locked': locked ? '1' : '0',
      'fromBoard': '1',
      if (program == 'capstone' || program == 'pit') 'boardScope': program,
      if (DateTime.tryParse(boardUri.queryParameters['date'] ?? '') != null)
        'boardDate': boardUri.queryParameters['date']!,
      if (boardUri.queryParameters['session']?.isNotEmpty == true)
        'boardSession': boardUri.queryParameters['session']!,
      // A mixed-program planner link must remain mixed on return.
      if (boardUri.queryParameters['date'] != null &&
          boardUri.queryParameters['scope'] == null)
        'boardMixed': '1',
    },
  ).toString();

  static String board(Uri evaluationUri) {
    final query = evaluationUri.queryParameters;
    final date = DateTime.tryParse(query['boardDate'] ?? '') != null
        ? query['boardDate']
        : null;
    final scope = query['boardScope'];
    return Uri(
      path: evaluationUri.path.startsWith('/faculty/')
          ? FacultyRoutes.defenseBoard
          : AdminRoutes.defenseBoard,
      queryParameters: {
        if (date != null) 'date': date,
        if (date != null && query['boardSession']?.isNotEmpty == true)
          'session': query['boardSession']!,
        if ((scope == 'capstone' || scope == 'pit') &&
            !(date != null && query['boardMixed'] == '1'))
          'scope': scope!,
      },
    ).toString();
  }
}

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
  static const projectArchive = '/admin/project-archive';
  static const repositoryAudit = projectArchive;
  static const curriculumAnalytics = '/admin/curriculum-analytics';
  static const auditCompliance = '/admin/audit-compliance';
  static const defenseScheduler = '/admin/defense-scheduler';
  static const defenseBoard = '/admin/defense-board';
  static const defenseScheduleBulkImport = '/admin/defense-board/import';
  static const defenseStages = '/admin/defense-stages';

  static String academicPeriodDetail(int semesterId) =>
      '/admin/academic-periods/$semesterId';

  static String teamDetail(int teamId) => '/admin/student-teams/$teamId';

  static String gradeDetail(int gradeId) =>
      '/admin/grade-center/grades/$gradeId';

  static String gradeEventTeams(
    String groupKey, {
    required String scope,
    required String stageLabel,
    required String title,
    Map<String, String> contextParameters = const {},
  }) {
    final params = Uri(
      queryParameters: {
        'scope': scope,
        'stageLabel': stageLabel,
        'title': title,
        ...contextParameters,
      },
    );
    return '/admin/grade-center/events/$groupKey?${params.query}';
  }

  static String rubricEdit(int rubricId) => '/admin/rubrics/$rubricId/edit';

  static const rubricCreate = '/admin/rubrics/new/edit';

  static String defenseStageEdit(int stageId, {int? initialTab}) {
    if (initialTab != null) {
      return '/admin/defense-stages/$stageId/edit?tab=$initialTab';
    }
    return '/admin/defense-stages/$stageId/edit';
  }

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
      return DefensysAdminSection.rubrics;
    }
    if (location.startsWith('/admin/project-archive') ||
        location.startsWith('/admin/repository-audit')) {
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
      DefensysAdminSection.rubrics => rubrics,
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
  static const documenterRecords = '/faculty/documenter-records';
  static const profile = '/faculty/profile';
  static const cohort = '/faculty/cohort';
  static const pitStudentImport = '/faculty/pit-student-import';
  static const studentTeams = '/faculty/student-teams';
  static const pitInstructors = '/faculty/pit-instructors';
  static const defenseScheduler = '/faculty/defense-scheduler';
  static const defenseBoard = '/faculty/defense-board';
  static const defenseScheduleBulkImport = '/faculty/defense-board/import';
  static const gradeCenter = '/faculty/grade-center';
  static const rubrics = '/faculty/rubrics';
  static const projectArchive = '/faculty/project-archive';
  static const repositoryAudit = projectArchive;
  static const auditCompliance = '/faculty/audit-compliance';
  static const deliverables = '/faculty/deliverables';
  static const weeklyReports = '/faculty/weekly-reports';
  static const adviserGrading = '/faculty/adviser-grading';
  static const uploader = '/faculty/uploader';
  static const pitEvents = '/faculty/pit-events';
  static const curriculumAnalytics = '/faculty/curriculum-analytics';

  static String teamDetail(int teamId) => '/faculty/student-teams/$teamId';

  static String gradeDetail(int gradeId) =>
      '/faculty/grade-center/grades/$gradeId';

  static String gradeEventTeams(
    String groupKey, {
    required String scope,
    required String stageLabel,
    required String title,
    Map<String, String> contextParameters = const {},
  }) {
    final params = Uri(
      queryParameters: {
        'scope': scope,
        'stageLabel': stageLabel,
        'title': title,
        ...contextParameters,
      },
    );
    return '/faculty/grade-center/events/$groupKey?${params.query}';
  }

  static String cohortDetail(String sectionName) =>
      '/faculty/cohort/${Uri.encodeComponent(sectionName)}';

  static String? sectionForLocation(String location) {
    if (location.startsWith('/faculty/dashboard')) return 'dashboard';
    if (location.startsWith(documenterRecords)) return 'documenter_records';
    if (location == profile) return 'profile';
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
    if (location.startsWith('/faculty/rubrics')) return 'rubrics';
    if (location.startsWith('/faculty/project-archive') ||
        location.startsWith('/faculty/repository-audit')) {
      return 'project_archive';
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
    if (location.startsWith(curriculumAnalytics)) return 'curriculum_analytics';
    return null;
  }

  static String pathForSection(String section) {
    return switch (section) {
      'profile' => profile,
      'dashboard' => dashboard,
      'documenter_records' => documenterRecords,
      'cohort' => cohort,
      'pit_student_import' => pitStudentImport,
      'student_teams' => studentTeams,
      'pit_instructors' => pitInstructors,
      'defense_scheduler' => defenseScheduler,
      'defense_board' => defenseBoard,
      'grade_center' => gradeCenter,
      'rubrics' => rubrics,
      'project_archive' => projectArchive,
      'repository_audit' => projectArchive,
      'audit_compliance' => auditCompliance,
      'deliverables' => deliverables,
      'weekly_reports' => weeklyReports,
      'adviser_grading' => adviserGrading,
      'uploader' => uploader,
      'pit_events' => pitEvents,
      'curriculum_analytics' => curriculumAnalytics,
      _ => dashboard,
    };
  }
}

abstract final class AppRoutes {
  static const guestEntry = '/guest/evaluate';
  static const guestDefenses = '/guest/defenses';
  static const login = '/login';
  static const student = '/student';
  static const panelist = '/panelist';
  static const documenter = '/documenter';
  static const settings = '/settings';
  static const webWorkspaceOnly = '/web-workspace';
  static const terms = '/terms';
  static const passwordResetConfirm = '/password-reset/confirm/:uid/:token';
}
