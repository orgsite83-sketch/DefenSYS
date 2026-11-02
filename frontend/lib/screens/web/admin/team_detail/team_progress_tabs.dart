import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../services/team_detail_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import 'academic_progress_card.dart';
import 'team_detail_components.dart';
import 'team_deliverables_browser.dart';

export 'team_detail_components.dart';

class TeamDeliverablesTab extends StatelessWidget {
  const TeamDeliverablesTab({
    super.key,
    required this.teamId,
    required this.state,
    required this.stageLabel,
    required this.stageOptions,
    required this.onStageChanged,
    required this.onRetry,
    required this.onDownloadDocument,
    required this.onViewReport,
  });
  final int teamId;
  final TeamDetailState state;
  final String stageLabel;
  final List<String> stageOptions;
  final ValueChanged<String> onStageChanged;
  final VoidCallback onRetry;
  final ValueChanged<int> onDownloadDocument;
  final ValueChanged<Map<String, dynamic>> onViewReport;

  @override
  Widget build(BuildContext context) {
    final capstone = '${state.team?['level']}'.toUpperCase().contains(
      'CAPSTONE',
    );
    final stage =
        detailRows(
          state.deliverableTeam?['stages'],
        ).where((row) => row['stage_label'] == stageLabel).firstOrNull ??
        <String, dynamic>{};
    return SingleChildScrollView(
      key: PageStorageKey('team-deliverables-$teamId-$stageLabel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (capstone) ...[
            TeamContextSelect(
              labels: stageOptions,
              value: stageLabel,
              label: 'Defense stage',
              onChanged: onStageChanged,
            ),
            const SizedBox(height: 20),
          ],
          if (state.deliverablesError != null)
            TeamDetailNotice(
              message: state.deliverablesError!,
              onRetry: onRetry,
            )
          else if (stage.isEmpty)
            TeamDetailNotice(
              message: capstone
                  ? 'No defense stages configured for this team.'
                  : 'No deliverables configured for this event.',
            ),
          TeamDeliverablesBrowser(
            key: ValueKey('team-file-browser-$teamId-$stageLabel'),
            teamId: teamId,
            state: state,
            stage: stage,
            stageLabel: stageLabel,
            onRetry: onRetry,
            onDownloadDocument: onDownloadDocument,
            onViewReport: onViewReport,
          ),
        ],
      ),
    );
  }
}

class PitEventProgressTab extends StatelessWidget {
  const PitEventProgressTab({
    super.key,
    required this.state,
    required this.eventName,
    required this.onViewDeliverables,
    required this.onViewEvaluation,
    required this.onRetry,
  });
  final TeamDetailState state;
  final String eventName;
  final VoidCallback onViewDeliverables;
  final ValueChanged<Map<String, dynamic>> onViewEvaluation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final event = state.events
        .where((e) => e['event_name'] == eventName)
        .firstOrNull;
    final grades = state.grades
        .where(
          (g) => event != null && g['pit_event_config_id'] != null
              ? '${g['pit_event_config_id']}' == '${event['id']}'
              : g['stage_label'] == eventName,
        )
        .map(
          (grade) => <String, dynamic>{
            ...grade,
            'recorded_stage_label': grade['stage_label'],
            'stage_label': eventName,
          },
        )
        .toList();
    if (eventName.isEmpty) {
      return const TeamDetailNotice(
        message: 'No PIT events assigned for this team in this semester.',
      );
    }
    final workflow = event?['context'] as Map? ?? {};
    final schedule = event?['schedule'] as Map?;
    final readiness = switch (workflow['scheduling_status']) {
      'preparing' => 'Preparing',
      'ready' => 'Ready for scheduling',
      'scheduled' => 'Scheduled',
      'completed' => 'Event participation complete',
      _ => 'Preparation status unavailable',
    };
    return SingleChildScrollView(
      key: PageStorageKey('pit-progress-$eventName'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: DefensysTokens.panelOf(context),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (event?['display_semester'] != null)
                      '${event!['display_semester']}',
                    '${event?['year_level'] ?? state.team?['year_level'] ?? ''}',
                    if (event?['historical'] == true)
                      'Historical participation',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  readiness,
                  style: DefensysTokens.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  schedule == null
                      ? (event == null
                            ? 'Schedule information unavailable'
                            : 'Not scheduled')
                      : '${_date('${schedule['scheduled_date']}')} · ${_time('${schedule['start_time']}')} · ${schedule['room'] ?? ''}',
                ),
                if (schedule != null)
                  Text(
                    'Presentation: ${switch (schedule['status']) {
                      'done' || 'archived' => 'Finished',
                      _ => 'Scheduled',
                    }}',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                const SizedBox(height: 16),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: onViewDeliverables,
                  child: const Text('View deliverables'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final grade in grades) ...[
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                if (grade['panel_evaluators_required'] != null)
                  Text(
                    'Panel evaluations: ${grade['panel_evaluators_submitted'] ?? 0}/${grade['panel_evaluators_required']}',
                  ),
                if ((int.tryParse('${grade['peer_submissions_required']}') ??
                        0) >
                    0)
                  Text(
                    'Peer evaluations: ${grade['peer_submissions_submitted'] ?? 0}/${grade['peer_submissions_required']}',
                  ),
                if (grade['panel_score'] != null)
                  Text('Panel score: ${grade['panel_score']}'),
                if (grade['peer_score'] != null)
                  Text('Peer score: ${grade['peer_score']}'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          AcademicProgressCard(
            grades: grades,
            stageLabels: [eventName],
            isCapstone: false,
            heading: 'EVENT RESULTS',
            isLoading: state.isLoading,
            error: state.gradesError,
            onRetry: onRetry,
            onViewEvaluation: onViewEvaluation,
          ),
        ],
      ),
    );
  }

  static String _date(String raw) {
    final date = DateTime.tryParse(raw);
    return date == null ? raw : DateFormat('d MMM yyyy').format(date);
  }

  static String _time(String raw) {
    final parts = raw.split(':');
    final hour = int.tryParse(parts.first);
    return hour == null || parts.length < 2
        ? raw
        : '${hour % 12 == 0 ? 12 : hour % 12}:${parts[1]} ${hour < 12 ? 'AM' : 'PM'}';
  }
}
