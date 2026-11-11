import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../navigation/staff_workspaces.dart';
import '../../navigation/workspace_preference.dart';
import '../../services/auth_provider.dart';
import '../../services/app/data_refresh_provider.dart';
import '../../services/unsaved_changes_provider.dart';
import '../../utils/unsaved_changes.dart';
import '../../services/academic/student_teams_provider.dart';
import '../../services/academic/curriculum_explorer_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../services/defense/defense_board_provider.dart';
import '../../services/defense/defense_scheduler_provider.dart';
import '../../services/defense/adviser_defense_provider.dart';
import '../../services/grading/grade_center_provider.dart';
import '../../services/adviser_grading_provider.dart';
import '../../services/weekly_progress_provider.dart';
import '../../services/documenter_provider.dart';
import '../../services/defense/team_defense_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_action_menu.dart';

void watchStaffWorkspaceAssignments(WidgetRef ref) {
  ref.listen(dataRefreshProvider, (previous, next) {
    if (!const [
      DataArea.users,
      DataArea.teams,
      DataArea.academicPeriods,
    ].any((area) => previous?[area] != next[area])) {
      return;
    }
    final auth = ref.read(authProvider);
    if (auth.token != null &&
        const {'admin', 'faculty'}.contains(auth.user?['role'])) {
      ref.read(authProvider.notifier).fetchCurrentUser(auth.token!);
    }
  });
}

void clearStaffWorkspaceData(WidgetRef ref) {
  ref.invalidate(studentTeamsProvider);
  ref.invalidate(capstoneDeliverablesProvider);
  ref.invalidate(defenseBoardProvider);
  ref.invalidate(defenseSchedulerProvider);
  ref.invalidate(gradeCenterProvider);
  ref.invalidate(curriculumExplorerProvider);
  ref.invalidate(adviserDefenseProvider);
  ref.invalidate(pitInstructorDefenseProvider);
  ref.invalidate(adviserGradingProvider);
  ref.invalidate(weeklyProgressProvider);
  ref.invalidate(documenterProvider);
  ref.read(authenticatedHttpClientProvider).clearFileCache();
}

Future<bool> prepareStaffWorkspaceSwitch(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(unsavedChangesProvider)) {
    final save = ref.read(unsavedChangesSaveDraftProvider);
    final action = await showDiscardUnsavedChangesDialog(
      context,
      onSaveDraft: save,
    );
    if (!context.mounted || action == UnsavedChangesAction.cancel) {
      return false;
    }
    if (action == UnsavedChangesAction.saveDraft &&
        save != null &&
        !await save()) {
      return false;
    }
    if (!context.mounted) return false;
  }
  ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
  ref.read(unsavedChangesProvider.notifier).setDirty(false);
  return true;
}

Future<void> switchStaffWorkspace(
  BuildContext context,
  WidgetRef ref,
  String location,
) async {
  if (!await prepareStaffWorkspaceSwitch(context, ref) || !context.mounted) {
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await rememberWorkspace(ref, location);
  if (!context.mounted) return;
  clearStaffWorkspaceData(ref);
  context.go(location);
}

class StaffWorkspaceSwitcher extends ConsumerWidget {
  const StaffWorkspaceSwitcher({
    super.key,
    this.collapsed = false,
    this.beforeSwitch,
    this.userOverride,
    this.onSwitched,
    this.isWeb = kIsWeb,
  });
  final bool isWeb;
  final bool collapsed;
  final Future<bool> Function()? beforeSwitch;
  final Map<String, dynamic>? userOverride;
  final VoidCallback? onSwitched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    watchStaffWorkspaceAssignments(ref);
    final user = userOverride ?? ref.watch(authProvider).user ?? {};
    final options = StaffWorkspace.available(user)
        .where(
          (option) =>
              isWeb || const {'panelist', 'documenter'}.contains(option.key),
        )
        .toList();
    if (options.length < 2) return const SizedBox.shrink();
    final uri = GoRouterState.of(context).uri;
    final current = StaffWorkspace.resolve(user, uri.toString());
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 8 : 10,
        vertical: 6,
      ),
      child: DefensysActionMenu(
        label: 'Switch workspace',
        wrapLabel: true,
        triggerLabel: collapsed
            ? null
            : current?.key == 'instructor'
            ? 'PIT Instructor · ${current?.section ?? current?.year}'
            : current?.label ?? 'Workspace',
        triggerIcon: LucideIcons.chevronsUpDown,
        triggerForegroundColor: DefensysTokens.textPrimaryOf(context),
        items: [
          for (final option in options)
            DefensysMenuItem(
              label: option.label,
              icon: option.matches(uri)
                  ? Icons.check_rounded
                  : Icons.workspaces_outline,
              onPressed: option.matches(uri)
                  ? null
                  : () async {
                      if (beforeSwitch != null && !await beforeSwitch!()) {
                        return;
                      }
                      if (!context.mounted ||
                          !await prepareStaffWorkspaceSwitch(context, ref)) {
                        return;
                      }
                      if (!context.mounted) return;
                      FocusManager.instance.primaryFocus?.unfocus();
                      await rememberWorkspace(ref, option.location);
                      if (!context.mounted) return;
                      clearStaffWorkspaceData(ref);
                      onSwitched?.call();
                      if (context.mounted) context.go(option.location);
                    },
            ),
        ],
      ),
    );
  }
}
