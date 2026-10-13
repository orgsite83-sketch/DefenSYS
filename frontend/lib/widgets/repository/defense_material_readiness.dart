import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String materialDeadlineLabel(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'After scheduling'
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
      'ready' => 'Ready',
      'overdue' => 'Overdue',
      'awaiting_schedule' => 'Awaiting schedule',
      _ => 'Pending',
    };
    final overdue = status == 'overdue';
    final color = overdue
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final items = (readiness['items'] as List? ?? []).whereType<Map>();
    final deadlineText = items
        .map(
          (item) =>
              '${item['label']}: ${materialDeadlineLabel(item['due_at'])}',
        )
        .join('\n');
    final heading = 'Defense materials · $label · $submitted/$total submitted';
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
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          border: Border.all(color: color.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (status == 'awaiting_schedule')
              const Text(
                'Your deadline appears when the defense is scheduled. You can prepare and upload early.',
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
