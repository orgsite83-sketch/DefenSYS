import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../screens/app/student/profile_edit_screen.dart';
import '../services/app_navigator.dart';
import '../theme/defensys_tokens.dart';
import '../widgets/defensys_skeleton.dart';
import '../widgets/shadcn/defensys_shadcn_scope.dart';
import 'notifications_provider.dart';

Future<void> showNotificationsPanel(
  BuildContext context, {
  required String workspace,
  required String workspaceLabel,
  bool initiallyAccount = false,
}) {
  final size = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  final box = context.findRenderObject();
  final anchor = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final width = math.min(460.0, size.width - 24);
  final top =
      (anchor == null || anchor.height > 80
              ? padding.top + 76
              : anchor.bottom + 8)
          .clamp(
            padding.top + 12,
            math.max(padding.top + 12, size.height - padding.bottom - 260),
          )
          .toDouble();
  final right = anchor == null || size.width < 600
      ? 12.0
      : (size.width - anchor.right)
            .clamp(12.0, math.max(12.0, size.width - width - 12))
            .toDouble();
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black.withValues(alpha: .12),
    builder: (_) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: top,
          right: right,
          bottom: padding.bottom + 12,
        ),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(620, size.height - top - padding.bottom - 12),
            ),
            child: NotificationsModal(
              workspace: workspace,
              workspaceLabel: workspaceLabel,
              initiallyAccount: initiallyAccount,
            ),
          ),
        ),
      ),
    ),
  );
}

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({
    super.key,
    required this.workspace,
    required this.workspaceLabel,
    this.initiallyAccount = false,
  });

  final String workspace;
  final String workspaceLabel;
  final bool initiallyAccount;

  @override
  ConsumerState<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  late bool _account = widget.initiallyAccount;
  int? _expandedId;
  String get _workspace => _account ? 'account' : widget.workspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(notificationsProvider(widget.workspace).notifier)
          .fetchNotifications(unreadOnly: false);
      ref
          .read(notificationsProvider('account').notifier)
          .fetchNotifications(unreadOnly: false);
    });
  }

  DateTime? _date(Map<String, dynamic> n) =>
      DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal();

  String _time(Map<String, dynamic> n) {
    final date = _date(n);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  String _group(Map<String, dynamic> n) {
    final date = _date(n);
    if (date == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(today)) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return 'Earlier';
  }

  IconData _icon(Map<String, dynamic> n) => switch (n['category']) {
    'SECURITY' => Icons.lock_outline_rounded,
    'MINUTES' => Icons.draw_outlined,
    'DEFENSE' => Icons.event_outlined,
    'PEER_EVAL' => Icons.rate_review_outlined,
    'ANNOUNCEMENT' => Icons.campaign_outlined,
    _ => Icons.notifications_outlined,
  };

  String _actionLabel(Map<String, dynamic> n) {
    final action = n['action'];
    if (action is Map && action['cta'] is String) return action['cta'];
    final payload = n['action_payload'];
    if (payload is Map && payload['panelist_eligibility'] == true) {
      return 'Review panelist request';
    }
    if (n['category'] == 'SECURITY') return 'View account';
    if (n['category'] == 'MINUTES') return 'Open minutes';
    if (payload is Map && payload['stage_label'] != null) {
      return 'View deliverables';
    }
    if (n['category'] == 'DEFENSE') return 'View defense';
    return 'Open details';
  }

  String? _route(Map<String, dynamic> n) {
    final action = n['action'];
    final raw = (action is Map ? action['route'] : n['action_route'])
        ?.toString()
        .trim();
    if (raw == null ||
        raw.isEmpty ||
        !raw.startsWith('/') ||
        raw.startsWith('//')) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    var path = uri.path.replaceAll('_', '-');
    if (widget.workspace == 'admin' && path.startsWith('/faculty/')) {
      path = path.replaceFirst('/faculty/', '/admin/');
    }
    if (widget.workspace == 'documenter' && path == '/faculty/defense-board') {
      path = '/documenter';
    }
    return uri.replace(path: path).toString();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final scope = _workspace;
    // Old informational alerts retain their destination. Workflow alerts are
    // checked again in case someone else has completed the action meanwhile.
    final current = n['action'] is Map
        ? await ref
              .read(notificationsProvider(scope).notifier)
              .refreshNotification(n['id'] as int)
        : n;
    if (current == null || !mounted || scope != _workspace) return;
    if (_route(current) == null) return;
    if (current['is_read'] != true) {
      final ok = await ref
          .read(notificationsProvider(scope).notifier)
          .markAsRead(n['id'] as int);
      if (!ok || !mounted || scope != _workspace) return;
    }
    if (!mounted) return;
    final route = _route(current);
    if (route == null) return;
    final target = rootNavigatorKey.currentContext;
    final router =
        GoRouter.maybeOf(context) ??
        (target == null || !target.mounted ? null : GoRouter.maybeOf(target));
    if (route != '/me/profile' && router == null) return;
    Navigator.of(context).pop();
    if (route == '/me/profile') {
      if (target != null && target.mounted) {
        Navigator.of(
          target,
        ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
      }
    } else {
      router!.go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider(_workspace));
    final role = ref.watch(notificationsProvider(widget.workspace));
    final account = ref.watch(notificationsProvider('account'));
    final accent = DefensysTokens.maroonTextOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final label = _account ? 'Account & security' : widget.workspaceLabel;
    return DefensysShadcnScope(
      child: ShadCard(
        key: const ValueKey('notifications-panel'),
        padding: EdgeInsets.zero,
        backgroundColor: DefensysTokens.surfaceOf(context),
        radius: BorderRadius.circular(12),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined, size: 21, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: DefensysTokens.dialogTitle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  _iconAction(
                    'Refresh notifications',
                    Icons.refresh_rounded,
                    state.isLoading || state.isSaving
                        ? null
                        : () => ref
                              .read(notificationsProvider(_workspace).notifier)
                              .fetchNotifications(),
                  ),
                  _iconAction(
                    'Close notifications',
                    Icons.close_rounded,
                    () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                label,
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) => ShadTabs<bool>(
                  value: _account,
                  gap: 0,
                  onChanged: (value) => setState(() {
                    _account = value;
                    _expandedId = null;
                  }),
                  tabBarConstraints: BoxConstraints.tightFor(
                    width: constraints.maxWidth,
                  ),
                  tabs: [
                    ShadTab(
                      value: false,
                      child: SizedBox(
                        width: (constraints.maxWidth - 64) / 2,
                        child: Text(
                          'Workspace${role.unreadCount > 0 ? ' (${role.unreadCount})' : ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    ShadTab(
                      value: true,
                      child: SizedBox(
                        width: (constraints.maxWidth - 64) / 2,
                        child: Text(
                          'Account${account.unreadCount > 0 ? ' (${account.unreadCount})' : ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Text(
                _account
                    ? 'Shared account alerts across your workspaces.'
                    : 'Only alerts for this role. Other inboxes stay unread.',
                style: TextStyle(fontSize: 11, color: secondary, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  _filter(
                    'All (${state.totalCount})',
                    !state.unreadOnly,
                    false,
                    state,
                  ),
                  const SizedBox(width: 6),
                  _filter(
                    'Unread (${state.unreadCount})',
                    state.unreadOnly,
                    true,
                    state,
                  ),
                  const Spacer(),
                  _iconAction(
                    'Mark all read in $label',
                    Icons.done_all_rounded,
                    state.unreadCount == 0 || state.isSaving || state.isLoading
                        ? null
                        : () => ref
                              .read(notificationsProvider(_workspace).notifier)
                              .markAllAsRead(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            Flexible(
              child: state.isLoading || state.notifications.isEmpty
                  ? SingleChildScrollView(child: _body(state))
                  : _body(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(String label, IconData icon, VoidCallback? onPressed) =>
      Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: ShadButton.ghost(
            width: 36,
            height: 36,
            padding: EdgeInsets.zero,
            enabled: onPressed != null,
            onPressed: onPressed,
            child: Icon(
              icon,
              size: 18,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      );

  Widget _filter(
    String label,
    bool selected,
    bool unread,
    NotificationsState state,
  ) => Semantics(
    selected: selected,
    child: ShadButton.raw(
      variant: selected ? ShadButtonVariant.secondary : ShadButtonVariant.ghost,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      enabled: !state.isSaving,
      onPressed: state.isSaving
          ? null
          : () {
              setState(() => _expandedId = null);
              ref
                  .read(notificationsProvider(_workspace).notifier)
                  .fetchNotifications(unreadOnly: unread);
            },
      child: Text(label, style: const TextStyle(fontSize: 11)),
    ),
  );

  Widget _body(NotificationsState state) {
    final content = _content(state);
    if (!state.isLoading && state.notifications.isNotEmpty) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [if (state.error != null) _feedback(state.error!), content],
    );
  }

  Widget _feedback(String error) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
    child: Row(
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: DefensysTokens.danger,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error,
            style: TextStyle(
              color: DefensysTokens.textSecondaryOf(context),
              fontSize: 12,
            ),
          ),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: () => ref
              .read(notificationsProvider(_workspace).notifier)
              .fetchNotifications(),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _content(NotificationsState state) {
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    DefensysSkeleton.box(
                      width: 34,
                      height: 34,
                      color: DefensysTokens.borderOf(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefensysSkeleton.box(
                            height: 12,
                            color: DefensysTokens.borderOf(context),
                          ),
                          const SizedBox(height: 10),
                          DefensysSkeleton.box(
                            width: 170,
                            height: 10,
                            color: DefensysTokens.borderOf(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (state.notifications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.error != null
                  ? Icons.cloud_off_outlined
                  : Icons.notifications_none_rounded,
              size: 34,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(height: 12),
            Text(
              state.error != null
                  ? 'Notifications unavailable'
                  : state.unreadOnly
                  ? 'No unread notifications'
                  : 'No notifications yet',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state.error != null
                  ? 'Try refreshing this inbox.'
                  : 'New ${_account ? 'account' : 'workspace'} alerts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      );
    }
    final rows = <Widget>[if (state.error != null) _feedback(state.error!)];
    String? lastGroup;
    for (final n in state.notifications) {
      final group = _group(n);
      if (group != lastGroup) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              group,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
        );
        lastGroup = group;
      }
      rows.add(_notification(n, state.isSaving));
    }
    if (state.nextPage != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: state.isLoadingMore || state.isSaving
                ? null
                : () => ref
                      .read(notificationsProvider(_workspace).notifier)
                      .fetchNotifications(loadMore: true),
            child: Text(
              state.isLoadingMore
                  ? 'Loading older notifications...'
                  : 'Load older notifications',
            ),
          ),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: rows,
    );
  }

  Widget _notification(Map<String, dynamic> n, bool saving) {
    final id = n['id'] as int;
    final unread = n['is_read'] != true;
    final expanded = _expandedId == id;
    final accent = DefensysTokens.maroonTextOf(context);
    final priority = n['priority']?.toString();
    final route = _route(n);
    final date = _date(n);
    final action = n['action'];
    final actionLabel = action is Map ? action['label']?.toString() : null;
    final completed = action is Map && action['is_complete'] == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expandedId = expanded ? null : id),
        child: Container(
          decoration: BoxDecoration(
            color: unread
                ? DefensysTokens.maroonOf(context).withValues(alpha: .045)
                : null,
            border: Border(
              left: BorderSide(
                width: 3,
                color: unread ? accent : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DefensysTokens.backgroundOf(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _icon(n),
                  size: 18,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n['title']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: date == null
                              ? ''
                              : DateFormat('MMM d, y · h:mm a').format(date),
                          child: Text(
                            _time(n),
                            style: TextStyle(
                              fontSize: 10,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 6),
                      ShadBadge.outline(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              completed
                                  ? LucideIcons.circleCheck
                                  : action['status'] == 'pending'
                                  ? LucideIcons.clock
                                  : LucideIcons.circleMinus,
                              size: 12,
                              color: completed
                                  ? (DefensysTokens.isDark(context)
                                        ? Colors.tealAccent
                                        : DefensysTokens.successText)
                                  : DefensysTokens.textSecondaryOf(context),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              actionLabel,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!completed &&
                        actionLabel == null &&
                        (priority == 'HIGH' || priority == 'URGENT')) ...[
                      const SizedBox(height: 4),
                      Text(
                        priority == 'URGENT' ? 'Urgent' : 'Needs attention',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: priority == 'URGENT'
                              ? DefensysTokens.danger
                              : accent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      n['message']?.toString() ?? '',
                      maxLines: expanded ? null : 3,
                      overflow: expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    if (expanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'From ${n['sender_name'] ?? 'System'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (route != null)
                          ShadButton.ghost(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            foregroundColor: accent,
                            enabled: !saving,
                            onPressed: saving ? null : () => _open(n),
                            trailing: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                            ),
                            child: Text(
                              _actionLabel(n),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (unread)
                          ShadButton.ghost(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            enabled: !saving,
                            onPressed: saving
                                ? null
                                : () => ref
                                      .read(
                                        notificationsProvider(
                                          _workspace,
                                        ).notifier,
                                      )
                                      .markAsRead(id),
                            child: const Text(
                              'Mark read',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
