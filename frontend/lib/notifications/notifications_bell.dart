import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/defensys_tokens.dart';
import '../widgets/shadcn/defensys_shadcn_scope.dart';
import 'notifications_modal.dart';
import 'notifications_provider.dart';

/// All workspaces use the same top-anchored panel and independent role badge.
class NotificationsBell extends ConsumerStatefulWidget {
  const NotificationsBell({
    super.key,
    required this.workspace,
    required this.workspaceLabel,
    this.color,
  });

  final String workspace;
  final String workspaceLabel;
  final Color? color;

  @override
  ConsumerState<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends ConsumerState<NotificationsBell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant NotificationsBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  void _refresh() {
    for (final workspace in [widget.workspace, 'account']) {
      final state = ref.read(notificationsProvider(workspace));
      if (!state.isLoading && !state.isLoadingMore && !state.isSaving) {
        ref
            .read(notificationsProvider(workspace).notifier)
            .fetchNotifications();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider(widget.workspace));
    final account = ref.watch(notificationsProvider('account'));
    return DefensysShadcnScope(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Tooltip(
            message:
                '${widget.workspaceLabel}: ${state.unreadCount} unread. Account: ${account.unreadCount} unread.',
            child: ShadButton.ghost(
              width: 40,
              height: 40,
              padding: EdgeInsets.zero,
              child: Icon(
                Icons.notifications_outlined,
                size: 23,
                color: widget.color ?? DefensysTokens.textSecondaryOf(context),
              ),
              onPressed: () => showNotificationsPanel(
                context,
                workspace: widget.workspace,
                workspaceLabel: widget.workspaceLabel,
                initiallyAccount:
                    state.unreadCount == 0 && account.unreadCount > 0,
              ),
            ),
          ),
          if (state.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: ShadBadge(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  backgroundColor: widget.color == null
                      ? DefensysTokens.maroonOf(context)
                      : Colors.white,
                  foregroundColor: widget.color == null
                      ? Colors.white
                      : DefensysTokens.maroon,
                  child: Text(
                    state.unreadCount > 99 ? '99+' : '${state.unreadCount}',
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
          if (account.unreadCount > 0)
            Positioned(
              left: 9,
              bottom: 9,
              child: IgnorePointer(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: DefensysTokens.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
