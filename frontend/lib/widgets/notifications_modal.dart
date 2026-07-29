import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notifications_provider.dart';
import '../theme/defensys_tokens.dart';

class NotificationsModal extends ConsumerStatefulWidget {
  const NotificationsModal({super.key});

  @override
  ConsumerState<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends ConsumerState<NotificationsModal> {
  int? _expandedNotificationId;

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    return Container(
      constraints: const BoxConstraints(maxWidth: 450),
      decoration: BoxDecoration(
        color: DefensysTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DefensysTokens.radiusXl)),
        border: Border.all(color: DefensysTokens.border, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  style: DefensysTokens.dialogTitle,
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
                      '${state.unreadCount} new',
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
          const Divider(height: 1.0),

          // Notification List
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 500),
              child: state.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: DefensysTokens.maroon),
                      ),
                    )
                  : state.notifications.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: state.notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1.0),
                          itemBuilder: (context, index) {
                            final notification = state.notifications[index];
                            final id = notification['id'] as int;
                            final isRead = notification['is_read'] as bool? ?? false;
                            final isExpanded = _expandedNotificationId == id;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedNotificationId = null;
                                  } else {
                                    _expandedNotificationId = id;
                                  }
                                });
                                if (!isRead) {
                                  ref.read(notificationsProvider.notifier).markAsRead(id);
                                }
                              },
                              child: Container(
                                color: isRead ? Colors.transparent : DefensysTokens.dangerBg.withValues(alpha: 0.5),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Status marker
                                    Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: isRead ? Colors.transparent : DefensysTokens.maroon,
                                          shape: BoxShape.circle,
                                        ),
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
                                                  notification['title']?.toString() ?? '',
                                                  style: DefensysTokens.body.copyWith(
                                                    fontWeight: isRead
                                                        ? FontWeight.w500
                                                        : FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _formatTime(notification['created_at']?.toString()),
                                                style: DefensysTokens.caption.copyWith(
                                                  fontSize: 11.5,
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
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                          ),
                                          if (isExpanded) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'From: ${notification['sender_name'] ?? 'System'}',
                                                  style: DefensysTokens.caption.copyWith(
                                                    fontSize: 11.5,
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

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DefensysTokens.neutralBg,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
              border: Border.all(color: DefensysTokens.border, width: 1.0),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: DefensysTokens.steelGrey,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "All caught up!",
            style: DefensysTokens.sectionTitle.copyWith(
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "You don't have any notifications at the moment.",
            textAlign: TextAlign.center,
            style: DefensysTokens.subtitle,
          ),
        ],
      ),
    );
  }
}
