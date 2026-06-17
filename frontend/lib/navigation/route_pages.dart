import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/web/admin/defense_stage_editor_screen.dart';
import '../screens/web/admin/grade_center_event_teams_screen.dart';
import '../screens/web/admin/grade_center_shared.dart';
import '../screens/web/admin/grade_center_team_detail_screen.dart';
import '../screens/web/admin/rubric_full_page_editor.dart';
import '../screens/web/admin/team_detail_page.dart';
import '../screens/web/faculty/pit_lead_cohort_section_detail_screen.dart';
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
  const AdminGradeTeamDetailRoute({super.key, required this.gradeId});

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
  const AdminGradeEventTeamsRoute({super.key, required this.groupKey});

  final String groupKey;

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final routeScope = _validGradeScope(params['scope']);
    final groupScope = _validGradeScope(_scopeFromGroupKey(groupKey));
    if (routeScope != null && groupScope != null && routeScope != groupScope) {
      return _GradeCenterRouteError(
        message:
            'This Grade Center event link has conflicting scope values. Open the event again from Grade Center.',
        onBack: () => context.go(AdminRoutes.gradeCenter),
      );
    }

    final scope = routeScope ?? groupScope;
    if (scope == null) {
      return _GradeCenterRouteError(
        message:
            'This Grade Center event link is missing a valid scope. Open the event again from Grade Center.',
        onBack: () => context.go(AdminRoutes.gradeCenter),
      );
    }

    final stageLabel =
        params['stageLabel'] ?? _stageLabelFromGroupKey(groupKey);
    final title =
        params['title'] ?? gradeGroupTitle(gradeGroupKey(scope, stageLabel));
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

  String? _validGradeScope(String? value) {
    final scope = value?.trim();
    if (scope == 'capstone' || scope == 'pit') {
      return scope;
    }
    return null;
  }

  String _scopeFromGroupKey(String key) {
    return key.split('|').first.trim();
  }

  String _stageLabelFromGroupKey(String key) {
    if (!key.contains('|')) {
      return '';
    }
    return key.split('|').sublist(1).join('|').trim();
  }
}

class _GradeCenterRouteError extends StatelessWidget {
  const _GradeCenterRouteError({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Invalid Grade Center Link',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(color: Color(0xFF4B5563), height: 1.4),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Grade Center'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminRubricEditorRoute extends ConsumerWidget {
  const AdminRubricEditorRoute({super.key, required this.rubricIdParam});

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
  const AdminDefenseStageEditorRoute({super.key, required this.stageId});

  final int stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefenseStageEditorScreen(
      stageId: stageId,
      onBack: () => context.pop(),
    );
  }
}

class PitLeadCohortSectionDetailRoute extends StatelessWidget {
  const PitLeadCohortSectionDetailRoute({super.key, required this.sectionName});

  final String sectionName;

  @override
  Widget build(BuildContext context) {
    return PitLeadCohortSectionDetailScreen(
      sectionName: Uri.decodeComponent(sectionName),
      onBack: () => context.go(FacultyRoutes.cohort),
    );
  }
}
