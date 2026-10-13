import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/defense_workflow_labels.dart';
import '../../models/team_defense_record.dart';
import '../../models/adviser_workflow.dart';
import '../adviser/workflow_reminder.dart';
import '../../services/defense/team_defense_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../minutes/minutes_pdf_dialog.dart';

/// A scheduled defense exists independently of its assessment and minutes.
class TeamDefenseRecordsView extends ConsumerWidget {
  const TeamDefenseRecordsView({
    super.key,
    required this.teamId,
    required this.selectedStage,
    this.grades = const [],
    this.adviserName,
    this.projectVersion,
    this.semesterId,
    this.allowAdviserReview = false,
  });

  final int teamId;
  final String selectedStage;
  final List<Map<String, dynamic>> grades;
  final String? adviserName;
  final int? projectVersion, semesterId;
  final bool allowAdviserReview;

  Future<void> _openMinutes(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> schedule,
  ) async {
    final id = defenseRecordId(schedule['id']);
    if (id == null) return;
    final signed = await MinutesPdfDialog.show(
      context,
      scheduleId: id,
      finalized: schedule['minutes_status'] == 'completed',
      allowAdviserSigning:
          allowAdviserReview &&
          schedule['status'] != 'cancelled' &&
          schedule['minutes_status'] == 'submitted',
      teamName:
          '${schedule['team_name'] ?? 'Defense'} · ${schedule['stage_label'] ?? 'Minutes'}',
    );
    if (!context.mounted) return;
    if (signed == true) {
      showSuccessToast(context, 'Signed as project adviser successfully.');
    }
    await ref.read(teamDefenseProvider.notifier).fetch();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(teamDefenseProvider);
    final records = TeamDefenseRecords.fromSchedules(
      state.schedules,
      teamId: teamId,
      selectedStage: selectedStage,
      projectVersion: projectVersion,
      semesterId: semesterId,
    );
    Widget card(Map<String, dynamic> schedule, {bool historical = false}) =>
        DefenseRecordCard(
          key: ValueKey('defense-record-${schedule['id']}'),
          schedule: schedule,
          grade: gradeForDefense(schedule, grades),
          adviserName: adviserName,
          historical: historical,
          allowAdviserReview: allowAdviserReview,
          onOpenMinutes: () => _openMinutes(context, ref, schedule),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(color: DefensysTokens.surfaceOf(context), child: Row(
          children: [
            const Expanded(
              child: Text(
                'Defense record',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh defense records',
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(teamDefenseProvider.notifier).fetch(),
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        )),
        if (state.isLoading) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
        ],
        if (state.error != null) ...[
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.read(teamDefenseProvider.notifier).fetch(),
              child: const Text('Retry'),
            ),
          ),
        ],
        if (records.current != null)
          card(records.current!)
        else if (!state.isLoading && state.error == null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _decoration(context),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 30,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No defense scheduled yet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'The $selectedStage schedule will appear here once assigned.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        if (records.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            key: PageStorageKey('defense-history-$teamId-$selectedStage'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'Previous defenses (${records.history.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Earlier attempts and cancelled schedules for $selectedStage',
            ),
            children: [
              for (final schedule in records.history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: card(schedule, historical: true),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

BoxDecoration _decoration(BuildContext context) => BoxDecoration(
  color: DefensysTokens.surfaceOf(context),
  borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
  border: Border.all(color: DefensysTokens.borderOf(context)),
);

class DefenseRecordCard extends StatelessWidget {
  const DefenseRecordCard({
    super.key,
    required this.schedule,
    this.grade,
    this.adviserName,
    this.historical = false,
    this.allowAdviserReview = false,
    required this.onOpenMinutes,
  });

  final Map<String, dynamic> schedule;
  final Map<String, dynamic>? grade;
  final String? adviserName;
  final bool historical, allowAdviserReview;
  final VoidCallback onOpenMinutes;

  String _date(BuildContext context, dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'To be confirmed'
        : '${MaterialLocalizations.of(context).formatMediumDate(date)}, ${date.year}';
  }

  TimeOfDay? get _start {
    final parts = schedule['start_time']?.toString().split(':') ?? [];
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _time(BuildContext context) {
    final start = _start;
    if (start == null) return 'To be confirmed';
    final duration = defenseRecordId(schedule['slot_duration']);
    if (duration == null || duration <= 0) return start.format(context);
    final total = start.hour * 60 + start.minute + duration;
    final end = TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
    return '${start.format(context)} – ${end.format(context)}${total >= 1440 ? ' (next day)' : ''}';
  }

  Widget _detail(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: DefensysTokens.textSecondaryOf(context)),
        const SizedBox(width: 9),
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  Widget _detailsGrid(List<Widget> details, int columns) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Column(children: details);
      }
      final width = (constraints.maxWidth - 24 * (columns - 1)) / columns;
      return Wrap(
        spacing: 24,
        children: [
          for (final detail in details) SizedBox(width: width, child: detail),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final assessment = (schedule['assessment'] as Map?) ?? const {};
    final status =
        schedule['display_status']?.toString() ??
        schedule['status']?.toString() ??
        'scheduled';
    final minutes = schedule['minutes_status']?.toString();
    final verdict = (assessment['verdict'] ?? grade?['verdict'])?.toString();
    final hasVerdict =
        verdict != null && verdict.isNotEmpty && verdict != 'pending';
    final published =
        assessment['grade_status'] == 'published' ||
        grade?['status'] == 'published';
    final result = published
        ? (assessment['published_result'] ?? grade?['result'])?.toString()
        : null;
    final completed =
        assessment['is_completed'] == true || (published && result == 'passed');
    final date = DateTime.tryParse(
      schedule['scheduled_date']?.toString() ?? '',
    );
    final start = _start;
    final scheduledAt = date == null
        ? null
        : DateTime(
            date.year,
            date.month,
            date.day,
            start?.hour ?? 0,
            start?.minute ?? 0,
          );
    final upcoming =
        status == 'scheduled' &&
        scheduledAt != null &&
        scheduledAt.isAfter(DateTime.now());
    final display = upcoming ? 'Upcoming' : defenseProgressLabel(status);
    final panel = (schedule['panelists'] as List? ?? []).whereType<Map>().map((
      p,
    ) {
      final name =
          p['name']?.toString() ?? p['username']?.toString() ?? 'Panelist';
      return p['is_chair'] == true ? '$name · Chair' : name;
    }).toList();
    final external = (schedule['external_evaluators'] as List? ?? [])
        .whereType<Map>()
        .map((p) => '${p['name'] ?? 'External panelist'} · External panelist')
        .toList();
    final attempt =
        grade?['attempt_number'] ??
        assessment['attempt_count'] ??
        grade?['attempt_count'];
    final canOpen =
        defenseRecordId(schedule['id']) != null &&
        (minutes == 'completed' ||
            (allowAdviserReview &&
                schedule['status'] != 'cancelled' &&
                {'submitted', 'adviser_signed'}.contains(minutes)));
    final minutesLabel = switch (minutes) {
      'draft' => 'Draft in progress',
      'submitted' => 'Awaiting adviser signature',
      'adviser_signed' => 'Signed by adviser; awaiting final signature',
      'completed' => 'Finalized',
      _ =>
        schedule['minutes_required'] == false
            ? 'Not required for this defense'
            : 'Not started',
    };
    final minutesGuidance = AdviserMinutesStatus.fromSchedule(schedule);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final deadline =
        assessment['revision_deadline'] ?? grade?['revision_deadline'];
    final remarks =
        (assessment['verdict_remarks'] ?? grade?['verdict_remarks'])
            ?.toString()
            .trim() ??
        '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _decoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allowAdviserReview) ...[
            AdviserWorkflowReminder(
              key: ValueKey('adviser-minutes-reminder-${schedule['id']}'),
              title: minutesGuidance.title, detail: minutesGuidance.detail,
              tone: minutesGuidance.tone,
              actionLabel: 'Review and sign minutes',
              onAction: minutesGuidance.needsSignature ? onOpenMinutes : null,
            ),
            const SizedBox(height: 18),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                schedule['stage_label']?.toString() ?? 'Defense',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  display,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (attempt != null) 'Attempt $attempt',
              if (historical) 'Previous defense',
              if (historical && schedule['project_version'] != null)
                'Project ${schedule['project_version']}',
              if (schedule['display_semester'] != null)
                schedule['display_semester'].toString(),
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          if (historical &&
              schedule['project_title']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              schedule['project_title'].toString(),
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          ],
          const SizedBox(height: 20),
          _section('Schedule and participants'),
          _detailsGrid([
            _detail(
              context,
              Icons.calendar_today_outlined,
              'Date',
              _date(context, schedule['scheduled_date']),
            ),
            _detail(context, Icons.schedule_outlined, 'Time', _time(context)),
            _detail(
              context,
              Icons.place_outlined,
              'Venue',
              _nonEmpty(schedule['room'], 'To be confirmed'),
            ),
          ], 3),
          _detail(
            context,
            Icons.people_outline_rounded,
            'Panel',
            [...panel, ...external].join('\n').isEmpty
                ? 'To be assigned'
                : [...panel, ...external].join('\n'),
          ),
          _detailsGrid([
            _detail(
              context,
              Icons.school_outlined,
              'Adviser',
              _nonEmpty(
                schedule['adviser_name'],
                adviserName ?? 'To be assigned',
              ),
            ),
            _detail(
              context,
              Icons.edit_note_outlined,
              'Documenter',
              _nonEmpty(schedule['documenter_name'], 'To be assigned'),
            ),
          ], 2),
          if (schedule['operation_reason']?.toString().trim().isNotEmpty ==
              true)
            Text(
              schedule['operation_reason'].toString(),
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          if (upcoming) ...[
            const SizedBox(height: 2),
            Text(
              _countdown(scheduledAt),
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
          const Divider(height: 30),
          _section('Verdict and completion'),
          Text(
            hasVerdict
                ? 'Defense verdict: ${defenseVerdictLabel(verdict)}'
                : (result != null && result != 'pending'
                      ? 'Published result: ${_resultLabel(result)}'
                      : 'Awaiting verdict'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Stage completion: ${completed
                ? 'Completed'
                : {'scheduled', 'awaiting_evaluation', 'evaluating', 'awaiting_verdict', 'done'}.contains(status)
                ? 'Pending'
                : defenseProgressLabel(status)}',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          const SizedBox(height: 6),
          Text(
            published
                ? (grade?['final_grade'] != null
                      ? 'Team average: ${_score(grade!['final_grade'])} · Published'
                      : 'Grade publication: Published')
                : 'Grade publication: Pending',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          if (hasVerdict && verdict == 'approved_with_revisions') ...[
            const SizedBox(height: 8),
            Text(
              grade?['revisions_cleared_at'] != null ||
                      assessment['revisions_cleared_at'] != null
                  ? 'Revisions cleared'
                  : 'Revisions pending',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (deadline != null)
              Text(
                'Revision deadline: ${_date(context, deadline)}',
                style: TextStyle(fontSize: 13, color: secondary),
              ),
          ],
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              remarks,
              style: TextStyle(fontSize: 13, color: secondary, height: 1.45),
            ),
          ],
          const Divider(height: 30),
          _section('Minutes'),
          Text(minutesLabel, style: TextStyle(fontSize: 13, color: secondary)),
          if (canOpen && !minutesGuidance.needsSignature) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenMinutes,
                icon: const Icon(Icons.description_outlined, size: 16),
                label: Text(
                  minutes == 'submitted'
                      ? 'Review and sign minutes'
                      : minutes == 'completed'
                      ? 'View final minutes'
                      : 'View signed minutes',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _nonEmpty(dynamic value, String fallback) =>
      value?.toString().trim().isNotEmpty == true ? value.toString() : fallback;
  static String _resultLabel(String value) => value.isEmpty
      ? 'Pending'
      : '${value[0].toUpperCase()}${value.substring(1)}';
  static String _score(dynamic value) =>
      double.tryParse(value.toString())?.toStringAsFixed(2) ?? value.toString();
  static String _countdown(DateTime scheduledAt) {
    final left = scheduledAt.difference(DateTime.now());
    if (left.inDays > 0) {
      return 'Starts in ${left.inDays} ${left.inDays == 1 ? 'day' : 'days'}';
    }
    if (left.inHours > 0) {
      return 'Starts in ${left.inHours} ${left.inHours == 1 ? 'hour' : 'hours'}';
    }
    return 'Starts in ${left.inMinutes < 1 ? 1 : left.inMinutes} minutes';
  }
}
