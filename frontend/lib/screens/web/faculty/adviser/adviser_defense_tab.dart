import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/adviser_grading_provider.dart';
import '../../../../services/defense/adviser_defense_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../documenter/minutes_form_screen.dart';

class AdviserDefenseTab extends ConsumerWidget {
  final int teamId;
  final String selectedStage;

  const AdviserDefenseTab({
    super.key,
    required this.teamId,
    required this.selectedStage,
  });

  static int? _id(dynamic value) => int.tryParse(value?.toString() ?? '');

  static String _label(dynamic value) {
    final text = value?.toString().replaceAll('_', ' ').trim() ?? '';
    if (text.isEmpty) return 'Pending';
    if (text == 'for redefense') return 'For re-defense';
    return text[0].toUpperCase() + text.substring(1);
  }

  String _date(BuildContext context, dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'Date to be confirmed'
        : MaterialLocalizations.of(context).formatMediumDate(date);
  }

  String _time(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length < 5) return 'Time to be confirmed';
    final hour = int.tryParse(text.substring(0, 2));
    final minute = text.substring(3, 5);
    if (hour == null) return text;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute ${hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _openMinutes(
    BuildContext context,
    WidgetRef ref,
    int scheduleId,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => MinutesFormScreen(
          scheduleId: scheduleId,
          onBack: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    if (context.mounted) {
      await ref.read(adviserDefenseProvider.notifier).fetch();
    }
  }

  Widget _detail(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 22, bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: DefensysTokens.textSecondary),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: const TextStyle(color: DefensysTokens.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> schedule,
  ) {
    final scheduleId = _id(schedule['id']);
    final stage = schedule['stage_label']?.toString() ?? 'Defense';
    final minutesStatus = schedule['minutes_status']?.toString();
    final grade = ref.watch(adviserGradingProvider).grades.where((record) {
      return _id(record['team_id']) == teamId &&
          record['stage_label']?.toString() == stage;
    }).firstOrNull;
    final gradeScheduleId = _id(grade?['schedule_id']);
    final currentAttempt =
        grade?['status'] == 'published' &&
        (gradeScheduleId == null || gradeScheduleId == scheduleId);
    final pastAttempt = (grade?['attempt_history'] as List? ?? [])
        .whereType<Map>()
        .where((attempt) => _id(attempt['schedule_id']) == scheduleId)
        .firstOrNull;
    final outcome = currentAttempt
        ? (grade?['verdict']?.toString().isNotEmpty == true
              ? grade!['verdict'].toString()
              : grade?['result']?.toString())
        : pastAttempt?['verdict']?.toString();
    final panelists = (schedule['panelists'] as List? ?? [])
        .whereType<Map>()
        .map((person) => person['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    final isSelectedStage = stage == selectedStage;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(
          color: isSelectedStage
              ? DefensysTokens.maroonOf(context).withValues(alpha: 0.45)
              : DefensysTokens.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                stage,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _statusChip(
                context,
                _label(schedule['display_status'] ?? schedule['status']),
              ),
              if (isSelectedStage)
                Text(
                  'Selected stage',
                  style: TextStyle(
                    color: DefensysTokens.maroonOf(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            children: [
              _detail(
                Icons.calendar_today_outlined,
                'Date',
                _date(context, schedule['scheduled_date']),
              ),
              _detail(
                Icons.schedule_outlined,
                'Time',
                _time(schedule['start_time']),
              ),
              _detail(
                Icons.place_outlined,
                'Venue',
                schedule['room']?.toString().isNotEmpty == true
                    ? schedule['room'].toString()
                    : 'To be confirmed',
              ),
            ],
          ),
          if (panelists.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Panel: $panelists',
                style: const TextStyle(color: DefensysTokens.textSecondary),
              ),
            ),
          const Divider(height: 20),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Minutes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _minutesLabel(minutesStatus),
                    style: const TextStyle(color: DefensysTokens.textSecondary),
                  ),
                ],
              ),
              if (scheduleId != null &&
                  const {
                    'submitted',
                    'adviser_signed',
                    'completed',
                  }.contains(minutesStatus))
                OutlinedButton.icon(
                  onPressed: () => _openMinutes(context, ref, scheduleId),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: Text(
                    minutesStatus == 'submitted'
                        ? 'Review and sign minutes'
                        : minutesStatus == 'completed'
                        ? 'View final minutes'
                        : 'View signed minutes',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            outcome != null && outcome.isNotEmpty && outcome != 'pending'
                ? 'Official outcome: ${_label(outcome)}'
                : 'Official outcome pending publication',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color:
                  outcome == 'passed' ||
                      outcome == 'approved' ||
                      outcome == 'approved_with_revisions'
                  ? DefensysTokens.successText
                  : DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  String _minutesLabel(String? status) => switch (status) {
    'draft' => 'Draft in progress',
    'submitted' => 'Awaiting adviser signature',
    'adviser_signed' => 'Signed by adviser; awaiting final signature',
    'completed' => 'Finalized',
    _ => 'Not available yet',
  };

  Widget _statusChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adviserDefenseProvider);
    final schedules =
        state.schedules
            .where(
              (schedule) =>
                  _id(schedule['team_id']) == teamId &&
                  schedule['scope'] == 'capstone',
            )
            .toList()
          ..sort((a, b) {
            final selectedA = a['stage_label']?.toString() == selectedStage;
            final selectedB = b['stage_label']?.toString() == selectedStage;
            if (selectedA != selectedB) return selectedA ? -1 : 1;
            return (b['scheduled_date']?.toString() ?? '').compareTo(
              a['scheduled_date']?.toString() ?? '',
            );
          });

    if (state.isLoading && schedules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && schedules.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.error!,
            style: const TextStyle(color: DefensysTokens.dangerText),
          ),
          TextButton(
            onPressed: () => ref.read(adviserDefenseProvider.notifier).fetch(),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (schedules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 36,
                color: DefensysTokens.steelGrey,
              ),
              SizedBox(height: 12),
              Text(
                'No defense scheduled for this team yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 5),
              Text(
                'The schedule, minutes, and official outcome will appear here as they become available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DefensysTokens.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Defense record',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final schedule in schedules) _scheduleCard(context, ref, schedule),
      ],
    );
  }
}
