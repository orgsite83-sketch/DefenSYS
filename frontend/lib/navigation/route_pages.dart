import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../toasts/feedback_toast.dart';

import '../screens/web/admin/academic_periods/semester_detail_screen.dart';
import '../screens/web/admin/defense_stage_editor_screen.dart';
import '../screens/web/admin/grade_center_event_teams_screen.dart';
import '../screens/web/admin/grade_center_shared.dart';
import '../screens/web/admin/grade_center_team_detail_screen.dart';
import '../screens/web/admin/rubric_full_page_editor.dart';
import '../screens/web/admin/team_detail_page.dart';
import '../screens/web/faculty/pit_lead_cohort_section_detail_screen.dart';
import '../services/dashboard_provider.dart';
import '../services/rubric_engine_provider.dart';
import '../services/unsaved_changes_provider.dart';
import 'admin_route_paths.dart';

class AdminTeamDetailRoute extends ConsumerWidget {
  const AdminTeamDetailRoute({
    super.key,
    required this.teamId,
    this.pitLeadMode = false,
    this.initialDeliverableStage,
  });

  final int teamId;
  final bool pitLeadMode;
  final String? initialDeliverableStage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TeamDetailPage(
      teamId: teamId,
      initialDeliverableStage: initialDeliverableStage,
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
    final uri = GoRouterState.of(context).uri;
    final locked = uri.queryParameters['locked'] == '1';
    final originTeamId = int.tryParse(uri.queryParameters['fromTeam'] ?? '');
    final returnTeamId = originTeamId != null && originTeamId > 0
        ? originTeamId
        : null;
    final isFaculty = uri.path.startsWith('/faculty/');
    return GradeCenterTeamDetailScreen(
      gradeId: gradeId,
      isLocked: locked,
      returnToTeam: returnTeamId != null,
      onBack: () {
        if (returnTeamId != null) {
          context.go(
            isFaculty
                ? FacultyRoutes.teamDetail(returnTeamId)
                : AdminRoutes.teamDetail(returnTeamId),
          );
          return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          if (isFaculty) {
            context.go(FacultyRoutes.gradeCenter);
          } else {
            context.go(AdminRoutes.gradeCenter);
          }
        }
      },
    );
  }
}

class AdminGradeEventTeamsRoute extends StatelessWidget {
  const AdminGradeEventTeamsRoute({super.key, required this.groupKey});

  final String groupKey;

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final isFaculty = GoRouterState.of(
      context,
    ).uri.path.startsWith('/faculty/');
    final rootPath = isFaculty
        ? FacultyRoutes.gradeCenter
        : AdminRoutes.gradeCenter;
    final routeScope = _validGradeScope(params['scope']);
    final groupScope = _validGradeScope(_scopeFromGroupKey(groupKey));
    if (routeScope != null && groupScope != null && routeScope != groupScope) {
      return _GradeCenterRouteError(
        message:
            'This Evaluation & Grades link has conflicting scope values. Open it again from Evaluation & Grades.',
        onBack: () => context.go(rootPath),
      );
    }

    final scope = routeScope ?? groupScope;
    if (scope == null) {
      return _GradeCenterRouteError(
        message:
            'This Evaluation & Grades link is missing a valid scope. Open it again from Evaluation & Grades.',
        onBack: () => context.go(rootPath),
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
      onBack: () => context.canPop() ? context.pop() : context.go(rootPath),
      onOpenTeamDetail: (gradeId, isLocked) {
        final locked = isLocked ? '1' : '0';
        final path = isFaculty
            ? FacultyRoutes.gradeDetail(gradeId)
            : AdminRoutes.gradeDetail(gradeId);
        context.push('$path?locked=$locked');
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
                        'Invalid Evaluation & Grades Link',
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
                  label: const Text('Back to Evaluation & Grades'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminRubricEditorRoute extends ConsumerStatefulWidget {
  const AdminRubricEditorRoute({super.key, required this.rubricIdParam});

  final String rubricIdParam;

  @override
  ConsumerState<AdminRubricEditorRoute> createState() => _AdminRubricEditorRouteState();
}

class _AdminRubricEditorRouteState extends ConsumerState<AdminRubricEditorRoute> {
  bool _isFetching = false;
  bool _fetchAttempted = false;

  @override
  void initState() {
    super.initState();
    _checkAndFetch();
  }

  @override
  void didUpdateWidget(AdminRubricEditorRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rubricIdParam != oldWidget.rubricIdParam) {
      _fetchAttempted = false;
      _checkAndFetch();
    }
  }

  void _checkAndFetch() {
    if (widget.rubricIdParam == 'new') return;
    final id = int.tryParse(widget.rubricIdParam);
    if (id == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final rubrics = ref.read(rubricEngineProvider).rubrics;
      final exists = rubrics.any((item) => int.tryParse(item['id']?.toString() ?? '') == id);
      if (!exists && !_isFetching) {
        setState(() => _isFetching = true);
        await ref.read(rubricEngineProvider.notifier).fetchSingleRubric(id);
        if (mounted) {
          setState(() {
            _isFetching = false;
            _fetchAttempted = true;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.rubricIdParam == 'new';
    if (isNew) {
      return RubricFullPageEditor(
        key: const ValueKey('rubric-new'),
        rubric: null,
        readOnly: false,
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AdminRoutes.rubrics);
          }
        },
      );
    }

    final id = int.tryParse(widget.rubricIdParam);
    if (id == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              const Text('Invalid Rubric ID'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AdminRoutes.rubrics);
                  }
                },
                child: const Text('Back to Rubrics'),
              ),
            ],
          ),
        ),
      );
    }

    final rubrics = ref.watch(rubricEngineProvider).rubrics;
    Map<String, dynamic>? rubric;
    for (final item in rubrics) {
      if (int.tryParse(item['id']?.toString() ?? '') == id) {
        rubric = Map<String, dynamic>.from(item);
        break;
      }
    }

    if (rubric == null) {
      if (_isFetching || !_fetchAttempted) {
        return const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
              const SizedBox(height: 16),
              Text(
                'Rubric #$id not found',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AdminRoutes.rubrics);
                  }
                },
                child: const Text('Back to Rubrics'),
              ),
            ],
          ),
        ),
      );
    }

    final rubricId = id;

    Future<void> handleDelete() async {
      final rubricName = rubric?['name']?.toString() ?? 'rubric';
      final canDelete = rubric?['can_delete'] != false;
      final lockReason = rubric?['lock_reason']?.toString();
      final isAssigned = rubric?['is_assigned'] == true;
      final assignedContext = rubric?['assigned_context_name']?.toString();

      if (!canDelete) {
        showErrorToast(
          context,
          lockReason ?? 'This rubric is assigned to active defenses or evaluations and cannot be deleted.',
        );
        return;
      }

      String dialogMessage = 'Delete $rubricName? This removes its criteria too.';
      if (isAssigned && assignedContext != null && assignedContext.isNotEmpty) {
        dialogMessage =
            'This rubric is currently assigned to Defense Stage "$assignedContext". '
            'Deleting it will remove the assignment from the stage configuration. Are you sure you want to proceed?';
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Rubric'),
          content: Text(dialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      final success = await ref.read(rubricEngineProvider.notifier).deleteRubric(rubricId);
      if (!context.mounted) return;
      if (success) {
        showSuccessToast(context, 'Rubric deleted.');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AdminRoutes.rubrics);
        }
      } else {
        final error = ref.read(rubricEngineProvider).error ?? 'Could not delete rubric.';
        showErrorToast(context, error);
      }
    }

    return RubricFullPageEditor(
      key: ValueKey('rubric-$rubricId'),
      rubric: rubric,
      readOnly: rubric['is_locked'] == true,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AdminRoutes.rubrics);
        }
      },
      onDelete: handleDelete,
    );
  }
}

class AdminDefenseStageEditorRoute extends ConsumerWidget {
  const AdminDefenseStageEditorRoute({
    super.key,
    required this.stageId,
    this.initialTab = 0,
  });

  final int stageId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefenseStageEditorScreen(
      stageId: stageId,
      initialTab: initialTab,
      onBack: () {
        ref.read(unsavedChangesProvider.notifier).setDirty(false);
        context.pop();
      },
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

class AdminSemesterDetailRoute extends StatelessWidget {
  const AdminSemesterDetailRoute({super.key, required this.semesterId});

  final int? semesterId;

  @override
  Widget build(BuildContext context) {
    return SemesterDetailScreen(
      semesterId: semesterId,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AdminRoutes.academicPeriods);
        }
      },
    );
  }
}
