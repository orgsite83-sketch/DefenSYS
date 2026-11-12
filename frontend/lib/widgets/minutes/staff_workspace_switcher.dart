import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    this.currentLocation,
  });
  final bool isWeb;
  final String? currentLocation;
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
          (option) => isWeb
              ? option.hasWebWorkspace
              : const {'panelist', 'documenter'}.contains(option.key),
        )
        .toList();
    if (options.length < 2) return const SizedBox.shrink();
    final uri = currentLocation == null
        ? GoRouterState.of(context).uri
        : Uri.parse(currentLocation!);
    final current =
        StaffWorkspace.resolve(user, uri.toString()) ?? options.first;
    String locationOf(StaffWorkspace option) =>
        option.locationFor(isWeb: isWeb);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF0F172A);

    Future<void> select(String location) async {
      final option = options.firstWhere((item) => locationOf(item) == location);
      if (option.matches(uri)) return;
      if (beforeSwitch != null && !await beforeSwitch!()) return;
      if (!context.mounted ||
          !await prepareStaffWorkspaceSwitch(context, ref)) {
        return;
      }
      if (!context.mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await rememberWorkspace(ref, locationOf(option));
      if (!context.mounted) return;
      clearStaffWorkspaceData(ref);
      onSwitched?.call();
      if (context.mounted) context.go(locationOf(option));
    }

    // Preserve the established faculty sidebar switcher for every staff duty.
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: PopupMenuButton<String>(
          tooltip: 'Switch workspace',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
          ),
          color: DefensysTokens.panelOf(context),
          elevation: 4,
          offset: const Offset(50, 0),
          onSelected: select,
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem(
                value: locationOf(option),
                height: 36,
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12.5,
                    fontWeight: locationOf(option) == locationOf(current)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: locationOf(option) == locationOf(current)
                        ? DefensysTokens.maroonOf(context)
                        : textColor,
                  ),
                ),
              ),
          ],
          child: Container(
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF28272D) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Center(
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: isDark
                    ? const Color(0xFFA1A1AA)
                    : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysTokens.borderOf(context), width: 1),
      ),
      child: Tooltip(
        message: 'Switch workspace',
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: locationOf(current),
            dropdownColor: DefensysTokens.panelOf(context),
            iconEnabledColor: isDark
                ? const Color(0xFFA1A1AA)
                : const Color(0xFF64748B),
            icon: const Icon(Icons.unfold_more_rounded, size: 18),
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: locationOf(option),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            onChanged: (location) {
              if (location != null) select(location);
            },
          ),
        ),
      ),
    );
  }
}
