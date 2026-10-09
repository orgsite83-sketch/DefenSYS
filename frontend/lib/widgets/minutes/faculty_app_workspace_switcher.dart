import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_action_menu.dart';
import '../../navigation/admin_route_paths.dart';
import '../../navigation/workspace_access.dart';
import '../../navigation/workspace_preference.dart';
import '../../services/auth_provider.dart';

class FacultyAppWorkspaceSwitcher extends ConsumerWidget {
  const FacultyAppWorkspaceSwitcher({
    super.key,
    required this.currentRoute,
    this.beforeSwitch,
  });
  final String currentRoute;
  final Future<bool> Function()? beforeSwitch;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user ?? {};
    final options = [
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
      if (kIsWeb && WorkspaceAccess.hasStaffWorkspace(user))
        (
          route: FacultyRoutes.dashboard,
          label: 'Staff web workspace',
          icon: Icons.desktop_windows_outlined,
        ),
    ];
    if (options.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: DefensysActionMenu(
        label: 'Switch workspace',
        triggerLabel: 'Workspace',
        triggerIcon: LucideIcons.chevronDown,
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
                      await rememberWorkspace(ref, option.route);
                      if (context.mounted) context.go(option.route);
                    },
            ),
        ],
      ),
    );
  }
}
