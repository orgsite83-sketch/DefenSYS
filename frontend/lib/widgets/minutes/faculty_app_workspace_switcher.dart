import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_action_menu.dart';
import '../../navigation/admin_route_paths.dart';
import '../../navigation/workspace_access.dart';
import '../../navigation/workspace_preference.dart';
import '../../navigation/staff_workspaces.dart';
import 'staff_workspace_switcher.dart';
import '../../services/auth_provider.dart';
import '../../theme/defensys_tokens.dart';

class FacultyAppWorkspaceSwitcher extends ConsumerWidget {
  const FacultyAppWorkspaceSwitcher({
    super.key,
    required this.currentRoute,
    this.beforeSwitch,
    this.isWeb = kIsWeb,
  });
  final String currentRoute;
  final Future<bool> Function()? beforeSwitch;
  final bool isWeb;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    watchStaffWorkspaceAssignments(ref);
    final user = ref.watch(authProvider).user ?? {};
    final options = [
      if (isWeb)
        for (final option in StaffWorkspace.available(user))
          if (option.hasWebWorkspace)
            (
              route: option.locationFor(isWeb: isWeb),
              label: switch (option.key) {
                'admin' => 'Admin workspace',
                'documenter' => 'Documenter web workspace',
                _ => option.label,
              },
              icon: Icons.desktop_windows_outlined,
            ),
      if (WorkspaceAccess.canEvaluate(user))
        (
          route: AppRoutes.panelist,
          label: 'Panel workspace',
          icon: Icons.rate_review_outlined,
        ),
      if (WorkspaceAccess.canDocument(user))
        (
          route: AppRoutes.documenter,
          label: 'Documenter workspace',
          icon: Icons.edit_note_rounded,
        ),
    ];
    if (options.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: DefensysActionMenu(
        label: 'Switch workspace',
        triggerLabel: MediaQuery.sizeOf(context).width < 360
            ? 'Switch'
            : 'Workspace',
        triggerIcon: LucideIcons.chevronDown,
        triggerForegroundColor: DefensysTokens.textPrimaryOf(context),
        items: [
          for (final option in options)
            DefensysMenuItem(
              label: option.label,
              icon: option.route == currentRoute
                  ? Icons.check_rounded
                  : option.icon,
              onPressed: option.route == currentRoute
                  ? null
                  : () async {
                      if (beforeSwitch != null && !await beforeSwitch!()) {
                        return;
                      }
                      if (!context.mounted) return;
                      if (!await prepareStaffWorkspaceSwitch(context, ref)) {
                        return;
                      }
                      if (!context.mounted) return;
                      await rememberWorkspace(ref, option.route);
                      if (context.mounted) {
                        clearStaffWorkspaceData(ref);
                        context.go(option.route);
                      }
                    },
            ),
        ],
      ),
    );
  }
}
