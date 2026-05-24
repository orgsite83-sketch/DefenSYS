import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/web/admin/admin_shell.dart';
import 'academic_period_provider.dart';
import 'adviser_grading_provider.dart';
import 'capstone_deliverables_provider.dart';
import 'curriculum_analytics_provider.dart';
import 'dashboard_provider.dart';
import 'defense_board_provider.dart';
import 'defense_scheduler_provider.dart';
import 'defense_stages_provider.dart';
import 'digital_vault_provider.dart';
import 'grade_center_provider.dart';
import 'pit_lead_cohort_provider.dart';
import 'pit_repository_assistant_provider.dart';
import 'repository_audit_provider.dart';
import 'rubric_engine_provider.dart';
import 'student_academic_records_provider.dart';
import 'student_teams_provider.dart';
import 'user_management_provider.dart';
import 'weekly_progress_provider.dart';

/// Clears cached API state when the session ends so disposed screens do not rebuild.
void invalidateSessionProviders(Ref ref) {
  ref.invalidate(activeAdminSectionProvider);
  ref.invalidate(gradeCenterProvider);
  ref.invalidate(academicPeriodProvider);
  ref.invalidate(defenseStagesProvider);
  ref.invalidate(defenseBoardProvider);
  ref.invalidate(defenseSchedulerProvider);
  ref.invalidate(repositoryAuditProvider);
  ref.invalidate(curriculumAnalyticsProvider);
  ref.invalidate(rubricEngineProvider);
  ref.invalidate(studentAcademicRecordsProvider);
  ref.invalidate(studentTeamsProvider);
  ref.invalidate(userManagementProvider);
  ref.invalidate(capstoneDeliverablesProvider);
  ref.invalidate(adviserGradingProvider);
  ref.invalidate(pitLeadCohortProvider);
  ref.invalidate(pitRepositoryAssistantProvider);
  ref.invalidate(weeklyProgressProvider);
  ref.invalidate(digitalVaultProvider);
  ref.invalidate(dashboardProvider);
}
