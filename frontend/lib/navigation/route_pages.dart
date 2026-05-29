import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/web/admin/defense_stage_editor_screen.dart';
import '../screens/web/admin/grade_center_event_teams_screen.dart';
import '../screens/web/admin/grade_center_team_detail_screen.dart';
import '../screens/web/admin/rubric_full_page_editor.dart';
import '../screens/web/admin/team_detail_page.dart';
import '../services/dashboard_provider.dart';
import '../services/rubric_engine_provider.dart';
import 'admin_route_paths.dart';

class AdminTeamDetailRoute extends ConsumerWidget {
  const AdminTeamDetailRoute({
    super.key,
    required this.teamId,
    this.pitLeadMode = false,
  });

  final int teamId;
  final bool pitLeadMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TeamDetailPage(
      teamId: teamId,
      canManage: true,
      isPitLead: pitLeadMode,
      pitLeadYear: pitLeadMode
          ? (ref.watch(dashboardProvider('faculty')).data?['pit_lead_year'])
              ?.toString()
          : null,
      onBack: () => context.pop(),
      onDeleted: () {
        if (pitLeadMode) {
          context.go(FacultyRoutes.studentTeams);
        } else {
          context.go(AdminRoutes.studentTeams);
        }
      },
    );
  }
}

class AdminGradeTeamDetailRoute extends StatelessWidget {
  const AdminGradeTeamDetailRoute({
    super.key,
    required this.gradeId,
  });

  final int gradeId;

  @override
  Widget build(BuildContext context) {
    final locked =
        GoRouterState.of(context).uri.queryParameters['locked'] == '1';
    return GradeCenterTeamDetailScreen(
      gradeId: gradeId,
      isLocked: locked,
      onBack: () => context.pop(),
    );
  }
}

class AdminGradeEventTeamsRoute extends StatelessWidget {
  const AdminGradeEventTeamsRoute({
    super.key,
    required this.groupKey,
  });

  final String groupKey;

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final scope = params['scope'] ?? 'capstone';
    final stageLabel = params['stageLabel'] ?? '';
    final title = params['title'] ?? '';
    return GradeCenterEventTeamsScreen(
      groupKey: groupKey,
      scope: scope,
      stageLabel: stageLabel,
      title: title,
      onBack: () => context.pop(),
      onOpenTeamDetail: (gradeId, isLocked) {
        final locked = isLocked ? '1' : '0';
        context.push('${AdminRoutes.gradeDetail(gradeId)}?locked=$locked');
      },
    );
  }
}

class AdminRubricEditorRoute extends ConsumerWidget {
  const AdminRubricEditorRoute({
    super.key,
    required this.rubricIdParam,
  });

  final String rubricIdParam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNew = rubricIdParam == 'new';
    Map<String, dynamic>? rubric;
    if (!isNew) {
      final id = int.tryParse(rubricIdParam);
      final rubrics = ref.watch(rubricEngineProvider).rubrics;
      for (final item in rubrics) {
        if (int.tryParse(item['id']?.toString() ?? '') == id) {
          rubric = Map<String, dynamic>.from(item);
          break;
        }
      }
    }
    return RubricFullPageEditor(
      rubric: rubric,
      readOnly: rubric?['status']?.toString() == 'published',
      onBack: () => context.pop(),
    );
  }
}

class AdminDefenseStageEditorRoute extends ConsumerWidget {
  const AdminDefenseStageEditorRoute({
    super.key,
    required this.stageId,
  });

  final int stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefenseStageEditorScreen(
      stageId: stageId,
      onBack: () => context.pop(),
    );
  }
}

