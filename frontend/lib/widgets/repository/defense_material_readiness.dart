import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  });
  final Map<String, dynamic> readiness;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final total = readiness['required_total'] as num? ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final submitted = readiness['submitted_total'] as num? ?? 0;
    final status = readiness['status']?.toString();
    final label = switch (status) {
      'ready' => 'Uploaded',
      'overdue' => 'Deadline passed',
      'awaiting_schedule' => 'No defense date yet',
      _ => 'Due before defense',
    };
    final overdue = status == 'overdue';
    final awaitingSchedule = status == 'awaiting_schedule';
    final color = overdue
        ? Theme.of(context).colorScheme.error
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
      return Tooltip(
        message: deadlineText,
        child: Text(
          heading,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
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
                : color.withValues(alpha: .2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (awaitingSchedule)
              const Text(
                'These files do not block endorsement or scheduling. Students can upload now or after endorsement; the deadline appears when the defense is scheduled.',
              )
            else if (deadlineText.isNotEmpty)
              Text(deadlineText),
            if (overdue) ...[
              const SizedBox(height: 6),
              const Text(
                'Required materials missed their deadline. An administrator can extend it or reschedule.',
              ),
            ],
            if (readiness['deadline_reason']?.toString().isNotEmpty ==
                true) ...[
              const SizedBox(height: 6),
              Text('Deadline extension: ${readiness['deadline_reason']}'),
            ],
          ],
        ),
      ),
    );
  }
}
