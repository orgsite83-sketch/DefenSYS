import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/web/admin/admin_shell.dart';
import '../academic/academic_period_provider.dart';
import '../grading/adviser_grading_provider.dart';
import '../defense/capstone_deliverables_provider.dart';
import '../academic/curriculum_analytics_provider.dart';
import '../app/dashboard_provider.dart';
import '../defense/defense_board_provider.dart';
import '../defense/defense_scheduler_provider.dart';
import '../defense/defense_stages_provider.dart';
import '../admin/repository_provider.dart';
import '../grading/grade_center_provider.dart';
import '../pit/pit_lead_cohort_provider.dart';
import '../admin/project_archive_provider.dart';
import '../grading/rubrics_provider.dart';
import '../academic/student_academic_records_provider.dart';
import '../academic/student_teams_provider.dart';
import '../admin/user_management_provider.dart';
import '../pit/weekly_progress_provider.dart';
import '../pit/documenter_provider.dart';
import '../app/unsaved_changes_provider.dart';

/// Clears cached API state when the session ends so disposed screens do not rebuild.
void invalidateSessionProviders(Ref ref) {
  ref.invalidate(unsavedChangesProvider);
  ref.invalidate(activeAdminSectionProvider);
  ref.invalidate(gradeCenterProvider);
  ref.invalidate(academicPeriodProvider);
  ref.invalidate(defenseStagesProvider);
  ref.invalidate(defenseBoardProvider);
  ref.invalidate(defenseSchedulerProvider);
  ref.invalidate(projectArchiveProvider);
  ref.invalidate(curriculumAnalyticsProvider);
  ref.invalidate(rubricsProvider);
  ref.invalidate(studentAcademicRecordsProvider);
  ref.invalidate(studentTeamsProvider);
  ref.invalidate(userManagementProvider);
  ref.invalidate(capstoneDeliverablesProvider);
  ref.invalidate(adviserGradingProvider);
  ref.invalidate(pitLeadCohortProvider);
  ref.invalidate(weeklyProgressProvider);
  ref.invalidate(repositoryProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(documenterProvider);
}
