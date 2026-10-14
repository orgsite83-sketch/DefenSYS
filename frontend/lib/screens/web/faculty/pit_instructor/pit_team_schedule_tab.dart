import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/defense/team_defense_provider.dart';
import '../../../../theme/app_theme.dart';

/// PIT schedule visibility only. PIT events have no minutes workflow.
class PitTeamScheduleTab extends ConsumerWidget {
  const PitTeamScheduleTab({
    super.key,
    required this.teamId,
    required this.selectedStage,
    this.projectVersion,
  });

  final int teamId;
  final String selectedStage;
  final int? projectVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pitInstructorDefenseProvider);
    final schedules = state.schedules.where((schedule) {
      final id = int.tryParse('${schedule['team_id']}');
      final version = int.tryParse('${schedule['project_version']}');
      return id == teamId && schedule['scope'] == 'pit' &&
          (projectVersion == null || version == projectVersion) &&
          schedule['stage_label']?.toString() == selectedStage &&
          schedule['status'] != 'cancelled' && schedule['status'] != 'archived';
    }).toList()
      ..sort((a, b) => '${a['scheduled_date']} ${a['start_time']}'
          .compareTo('${b['scheduled_date']} ${b['start_time']}'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Event schedule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Read only schedule for this team and PIT event.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        if (state.isLoading && schedules.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.error != null && schedules.isEmpty)
          Row(children: [
            const Expanded(child: Text('Schedule could not be loaded.')),
            OutlinedButton(onPressed: () => ref.read(pitInstructorDefenseProvider.notifier).fetch(),
                child: const Text('Retry')),
          ])
        else if (schedules.isEmpty)
          const Text('No event is scheduled for this team yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
        else
          ...schedules.map((schedule) {
            final date = DateTime.tryParse(schedule['scheduled_date']?.toString() ?? '');
            final rawTime = schedule['start_time']?.toString().split(':') ?? [];
            final hour = rawTime.isNotEmpty ? int.tryParse(rawTime[0]) : null;
            final minute = rawTime.length > 1 ? int.tryParse(rawTime[1]) : null;
            final time = hour != null && minute != null
                ? MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: hour, minute: minute))
                : 'Time pending';
            final panelists = (schedule['panelists'] as List? ?? [])
                .whereType<Map>()
                .map((panelist) => panelist['panelist_name']?.toString() ??
                    panelist['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(date == null ? 'Date pending' :
                      '${MaterialLocalizations.of(context).formatMediumDate(date)} · $time',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 5),
                  Text('Room: ${schedule['room'] ?? 'To be assigned'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('Status: ${schedule['display_status'] ?? schedule['status'] ?? 'Scheduled'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (panelists.isNotEmpty)
                    Text('Panel: $panelists',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}
