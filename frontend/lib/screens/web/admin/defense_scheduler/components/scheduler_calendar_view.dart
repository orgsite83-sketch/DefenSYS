import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';

class SchedulerCalendarView extends ConsumerWidget {
  const SchedulerCalendarView({
    super.key,
    required this.state,
  });

  final DefenseSchedulerState state;

  Future<void> _cancelSchedule(BuildContext context, WidgetRef ref, int scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Schedule?'),
        content: const Text(
          'This will cancel the defense schedule. Panelists will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(defenseSchedulerProvider.notifier)
          .updateStatus(scheduleId, 'cancelled');
    }
  }

  Future<void> _markScheduleAsDone(BuildContext context, WidgetRef ref, int scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Done?'),
        content: const Text('This will mark the defense as completed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Yes, Mark Done'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(defenseSchedulerProvider.notifier)
          .updateStatus(scheduleId, 'done');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSchedules = state.schedules
        .where((s) => s['status'] == 'scheduled')
        .toList();

    if (activeSchedules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.event_available, color: AppColors.maroon, size: 22),
            SizedBox(width: 8),
            Text(
              'Active Schedules',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.maroon,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeSchedules.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final schedule = activeSchedules[index];
              final rawId = schedule['id'];
              final scheduleId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                leading: CircleAvatar(
                  backgroundColor: AppColors.maroon.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.event,
                    color: AppColors.maroon,
                    size: 20,
                  ),
                ),
                title: Text(
                  schedule['team_name']?.toString() ?? 'Unknown Team',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${schedule['stage_label']} • ${schedule['scheduled_date']} ${schedule['start_time']} • ${schedule['room']}',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.cancel_outlined,
                        color: Colors.orange,
                      ),
                      tooltip: 'Cancel Schedule',
                      onPressed: scheduleId != null
                          ? () => _cancelSchedule(context, ref, scheduleId)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      tooltip: 'Mark as Done',
                      onPressed: scheduleId != null
                          ? () => _markScheduleAsDone(context, ref, scheduleId)
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
