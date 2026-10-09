import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    if (!WorkspaceAccess.canDocument(user) ||
        !WorkspaceAccess.canEvaluate(user)) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: 'Switch workspace',
      icon: const Icon(Icons.swap_horiz),
      initialValue: currentRoute,
      onSelected: (route) async {
        if (route == currentRoute) return;
        if (beforeSwitch != null && !await beforeSwitch!()) return;
        if (!context.mounted) return;
        await rememberWorkspace(ref, route);
        if (context.mounted) context.go(route);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: AppRoutes.panelist,
          child: Text('Panelist workspace'),
        ),
        PopupMenuItem(
          value: AppRoutes.documenter,
          child: Text('Documenter workspace'),
        ),
      ],
    );
  }
}
