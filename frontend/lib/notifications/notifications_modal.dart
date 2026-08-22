import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../navigation/admin_route_paths.dart';
import '../services/app_navigator.dart';
import '../services/auth_provider.dart';
import '../theme/defensys_tokens.dart';
import '../widgets/feedback/empty_state.dart';
import 'notifications_provider.dart';

enum NotificationFilter { all, unread }

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({super.key});

  @override
  ConsumerState<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  int? _expandedNotificationId;
  NotificationFilter _currentFilter = NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final parsed = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(parsed);

      if (diff.inSeconds < 60) {
        return 'Just now';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (_) {
      return '';
    }
  }

  IconData _getCategoryIcon(String? category, String title) {
    final cat = (category ?? '').toUpperCase();
    final lowerTitle = title.toLowerCase();

    if (cat == 'SECURITY' || lowerTitle.contains('password') || lowerTitle.contains('security')) {
      return Icons.shield_rounded;
    } else if (cat == 'MINUTES' || lowerTitle.contains('minute') || lowerTitle.contains('signature')) {
      return Icons.draw_rounded;
    } else if (cat == 'DEFENSE' || lowerTitle.contains('defense') || lowerTitle.contains('schedule')) {
      return Icons.calendar_month_rounded;
    } else if (cat == 'PEER_EVAL' || lowerTitle.contains('peer') || lowerTitle.contains('evaluation')) {
      return Icons.rate_review_rounded;
    } else if (cat == 'ANNOUNCEMENT' || lowerTitle.contains('announcement')) {
      return Icons.campaign_rounded;
    }
    return Icons.notifications_rounded;
  }

  Color _getCategoryColor(String? category, String title) {
    final cat = (category ?? '').toUpperCase();
    final lowerTitle = title.toLowerCase();

    if (cat == 'SECURITY' || lowerTitle.contains('password') || lowerTitle.contains('security')) {
      return const Color(0xFF0284C7); // Tech Sky Blue
    } else if (cat == 'MINUTES' || lowerTitle.contains('minute') || lowerTitle.contains('signature')) {
      return DefensysTokens.maroon;
    } else if (cat == 'DEFENSE' || lowerTitle.contains('defense') || lowerTitle.contains('schedule')) {
      return const Color(0xFF4F46E5); // Indigo
    } else if (cat == 'PEER_EVAL' || lowerTitle.contains('peer') || lowerTitle.contains('evaluation')) {
      return const Color(0xFF059669); // Emerald
    } else if (cat == 'ANNOUNCEMENT' || lowerTitle.contains('announcement')) {
      return const Color(0xFFD97706); // Amber
    }
    return const Color(0xFF6B7280); // Slate
  }

  String? _resolveActionRoute(Map<String, dynamic> notification) {
    final user = ref.read(authProvider).user;
    final role = user?['role']?.toString().toLowerCase() ?? '';

    var explicitRoute = notification['action_route'] as String?;
    if (explicitRoute != null && explicitRoute.trim().isNotEmpty) {
      var route = explicitRoute.trim();
      if (role == 'admin' && route.startsWith('/faculty/')) {
        route = route.replaceAll('/faculty/', '/admin/');
      }
      return route.replaceAll('_', '-');
    }

    final title = (notification['title']?.toString() ?? '').toLowerCase();
    final category = (notification['category']?.toString() ?? '').toUpperCase();

    if (category == 'MINUTES' || title.contains('minute') || title.contains('signature')) {
      return role == 'admin' ? AdminRoutes.defenseBoard : FacultyRoutes.defenseBoard;
    } else if (category == 'DEFENSE' || title.contains('defense') || title.contains('schedule')) {
      return role == 'admin' ? AdminRoutes.defenseScheduler : FacultyRoutes.defenseScheduler;
    } else if (category == 'PEER_EVAL' || title.contains('peer') || title.contains('eval')) {
      return AppRoutes.student;
    }
    return null;
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final id = notification['id'] as int;
    final isRead = notification['is_read'] as bool? ?? false;
    final actionRoute = _resolveActionRoute(notification);

    if (!isRead) {
      ref.read(notificationsProvider.notifier).markAsRead(id);
    }

    if (actionRoute != null && actionRoute.isNotEmpty) {
      if (mounted) Navigator.of(context).pop();
      Future.microtask(() {
        final targetContext = rootNavigatorKey.currentContext;
        if (targetContext != null && targetContext.mounted) {
          try {
            GoRouter.of(targetContext).go(actionRoute);
          } catch (e) {
            debugPrint('Notification route navigation error: $e');
          }
        }
      });
    } else {
      setState(() {
        if (_expandedNotificationId == id) {
          _expandedNotificationId = null;
        } else {
          _expandedNotificationId = id;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    final filteredList = _currentFilter == NotificationFilter.unread
        ? state.notifications.where((n) => n['is_read'] != true).toList()
        : state.notifications;

    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: DefensysTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DefensysTokens.radiusXl)),
        border: Border.all(color: DefensysTokens.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: DefensysTokens.maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Notifications',
                  style: DefensysTokens.dialogTitle.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (state.unreadCount > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    ),
                    child: Text(
                      '${state.unreadCount} unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (state.unreadCount > 0)
                  TextButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () => ref.read(notificationsProvider.notifier).markAllAsRead(),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Mark all read'),
                    style: TextButton.styleFrom(
                      foregroundColor: DefensysTokens.maroon,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Filter Pills Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'All (${state.notifications.length})',
                  isSelected: _currentFilter == NotificationFilter.all,
                  onTap: () => setState(() => _currentFilter = NotificationFilter.all),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Unread (${state.unreadCount})',
                  isSelected: _currentFilter == NotificationFilter.unread,
                  onTap: () => setState(() => _currentFilter = NotificationFilter.unread),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1.0),

          // Notification List
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 480),
              child: state.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: DefensysTokens.maroon),
                      ),
                    )
                  : filteredList.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: filteredList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1.0),
                          itemBuilder: (context, index) {
                            final notification = filteredList[index];
                            final id = notification['id'] as int;
                            final isRead = notification['is_read'] as bool? ?? false;
                            final title = notification['title']?.toString() ?? '';
                            final category = notification['category']?.toString();
                            final actionRoute = _resolveActionRoute(notification);
                            final isExpanded = _expandedNotificationId == id;

                            final iconData = _getCategoryIcon(category, title);
                            final accentColor = _getCategoryColor(category, title);

                            return InkWell(
                              onTap: () => _handleNotificationTap(notification),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  color: isRead
                                      ? Colors.transparent
                                      : DefensysTokens.maroon.withValues(alpha: 0.03),
                                  border: Border(
                                    left: BorderSide(
                                      color: isRead ? Colors.transparent : DefensysTokens.maroon,
                                      width: 3.5,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Category icon badge
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                      ),
                                      child: Icon(
                                        iconData,
                                        color: accentColor,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  style: DefensysTokens.body.copyWith(
                                                    fontWeight: isRead
                                                        ? FontWeight.w500
                                                        : FontWeight.w700,
                                                    fontSize: 13.5,
                                                    color: isRead ? Colors.black87 : Colors.black,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _formatTime(notification['created_at']?.toString()),
                                                style: DefensysTokens.caption.copyWith(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            notification['message']?.toString() ?? '',
                                            maxLines: isExpanded ? null : 2,
                                            overflow: isExpanded
                                                ? TextOverflow.visible
                                                : TextOverflow.ellipsis,
                                            style: DefensysTokens.subtitle.copyWith(
                                              fontSize: 12.5,
                                              height: 1.4,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          if (actionRoute != null && actionRoute.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Text(
                                                  'Tap to open view',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: accentColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 13,
                                                  color: accentColor,
                                                ),
                                              ],
                                            ),
                                          ] else if (isExpanded) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'From: ${notification['sender_name'] ?? 'System'}',
                                                  style: DefensysTokens.caption.copyWith(
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? DefensysTokens.maroon : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
          border: Border.all(
            color: isSelected ? DefensysTokens.maroon : Colors.grey.shade300,
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade800,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFilteredUnread = _currentFilter == NotificationFilter.unread;

    return DefensysEmptyState(
      icon: isFilteredUnread
          ? Icons.mark_email_read_rounded
          : Icons.notifications_none_rounded,
      title: isFilteredUnread ? 'No unread notifications' : 'All caught up!',
      description: isFilteredUnread
          ? "You've read all your notifications."
          : "You don't have any notifications at the moment.",
      size: DefensysEmptyStateSize.compact,
    );
  }
}
