import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/defensys_tokens.dart';

String materialDeadlineLabel(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Deadline set when scheduled'
      : DateFormat('MMM d, y · h:mm a').format(date.toLocal());
}

class DefenseMaterialReadiness extends StatelessWidget {
  const DefenseMaterialReadiness({
    super.key,
    required this.readiness,
    this.compact = false,
    this.onEditDeadline,
    this.editDeadlineLabel,
  });
  final Map<String, dynamic> readiness;
  final bool compact;
  final VoidCallback? onEditDeadline;
  final String? editDeadlineLabel;

  @override
  Widget build(BuildContext context) {
    final total = readiness['required_total'] as num? ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final submitted = readiness['submitted_total'] as num? ?? 0;
    final isComplete = submitted >= total && total > 0;

    // When all defense materials are submitted, hide the reminder banner completely.
    if (isComplete) {
      return const SizedBox.shrink();
    }

    final status = readiness['status']?.toString();
    final lateWindow =
        status == 'late_window' || readiness['late_window_active'] == true;
    final label = switch (status) {
      'ready' => 'Uploaded',
      'late_window' => 'Late-upload window active',
      'overdue' => 'Deadline passed',
      'awaiting_schedule' => 'No defense date yet',
      _ => lateWindow ? 'Late-upload window active' : 'Due before defense',
    };
    final overdue = status == 'overdue';
    final awaitingSchedule = status == 'awaiting_schedule';
    final color = overdue
        ? Theme.of(context).colorScheme.error
        : lateWindow
        ? const Color(0xFFD97706)
        : awaitingSchedule
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.primary;
    final items = (readiness['items'] as List? ?? []).whereType<Map>();
    final deadlineText = items
        .map(
          (item) =>
              '${item['label']}: ${materialDeadlineLabel(item['due_at'])}',
        )
        .join('\n');
    final heading = 'Defense files · $submitted/$total uploaded · $label';

    if (compact) {
      final microText = lateWindow
          ? '$submitted/$total slides · Late window'
          : overdue
          ? '$submitted/$total slides · Overdue'
          : awaitingSchedule
          ? '$submitted/$total slides · Awaiting schedule'
          : '$submitted/$total slides · Due before defense';
      final tooltipMessage = lateWindow && readiness['late_upload_until'] != null
          ? 'Oral presentation slides (late-upload window closes ${materialDeadlineLabel(readiness['late_upload_until'])})'
          : overdue
          ? 'Oral presentation slides missed deadline'
          : awaitingSchedule
          ? 'Oral presentation slides (deadline set when scheduled)'
          : (deadlineText.isNotEmpty ? deadlineText : 'Oral presentation slides');

      return Tooltip(
        message: tooltipMessage,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              lateWindow
                  ? Icons.schedule_rounded
                  : overdue
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              microText,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (awaitingSchedule && !lateWindow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'These files do not block endorsement or scheduling. The upload deadline appears once the defense is scheduled.',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: awaitingSchedule
              ? Theme.of(context).colorScheme.surfaceContainerLowest
              : color.withValues(alpha: .06),
          border: Border.all(
            color: awaitingSchedule
                ? Theme.of(context).dividerColor
                : color.withValues(alpha: .25),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  lateWindow
                      ? Icons.schedule_rounded
                      : overdue
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    heading,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onEditDeadline != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: onEditDeadline,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 14),
                    label: Text(editDeadlineLabel ?? 'Edit deadline'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (lateWindow && readiness['late_upload_until'] != null)
              Text(
                'Late-upload window open until ${materialDeadlineLabel(readiness['late_upload_until'])}. Missing materials may be submitted.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            if (overdue && !lateWindow) ...[
              const SizedBox(height: 4),
              const Text(
                'Required materials missed their deadline. An administrator can extend it or reschedule.',
              ),
            ],
            if (readiness['deadline_reason']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.format_quote_rounded, size: 14, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Coordinator note: "${readiness['deadline_reason']}"',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
