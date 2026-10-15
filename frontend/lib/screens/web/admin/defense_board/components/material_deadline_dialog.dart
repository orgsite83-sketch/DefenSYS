import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense_board_provider.dart';
import '../../../../../widgets/repository/defense_material_readiness.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';

Future<void> showMaterialDeadlineDialog(
  BuildContext context,
  Map<String, dynamic> schedule,
) => showDialog<void>(
  context: context,
  builder: (_) => MaterialDeadlineDialog(schedule: schedule),
);

class MaterialDeadlineDialog extends ConsumerStatefulWidget {
  const MaterialDeadlineDialog({super.key, required this.schedule});
  final Map<String, dynamic> schedule;

  @override
  ConsumerState<MaterialDeadlineDialog> createState() =>
      _MaterialDeadlineDialogState();
}

class _MaterialDeadlineDialogState
    extends ConsumerState<MaterialDeadlineDialog> {
  final _reason = TextEditingController();
  late DateTime _deadline;
  late DateTime _defenseStart;
  late String _mode;
  late bool _isLocked;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final readiness = widget.schedule['materials_readiness'] as Map?;
    _defenseStart =
        DateTime.tryParse(
          readiness?['defense_starts_at']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.parse(
          '${widget.schedule['scheduled_date']}T${widget.schedule['start_time']}',
        );

    final isPast = DateTime.now().isAfter(_defenseStart);
    final hasEvals = readiness?['has_evaluations'] == true;
    final canExtend = readiness?['can_extend_deadline'] == true ||
        (readiness?['can_extend_deadline'] == null && !isPast && !hasEvals && widget.schedule['status'] != 'archived');
    _isLocked =
        readiness?['is_locked_historical'] == true ||
        widget.schedule['status'] == 'archived';

    if (canExtend && !isPast && !hasEvals) {
      _mode = 'extend';
      _deadline = _defenseStart;
    } else {
      _mode = 'late_upload';
      final existingLate = DateTime.tryParse(
        readiness?['late_upload_until']?.toString() ?? '',
      )?.toLocal();
      _deadline =
          (existingLate != null && existingLate.isAfter(DateTime.now()))
              ? existingLate
              : DateTime.now().add(const Duration(hours: 24));
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isLocked) return;
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Enter a reason of at least 5 characters.');
      return;
    }
    if (_mode == 'extend') {
      if (!_deadline.isAfter(DateTime.now()) ||
          _deadline.isAfter(_defenseStart)) {
        setState(
          () => _error =
              'Choose a future deadline at or before the defense starts.',
        );
        return;
      }
    } else {
      if (!_deadline.isAfter(DateTime.now())) {
        setState(
          () => _error =
              'Choose a future deadline for the late-upload window.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(defenseBoardProvider.notifier)
          .extendMaterialDeadline(
            scheduleId: int.parse(widget.schedule['id'].toString()),
            revision:
                int.tryParse(widget.schedule['revision']?.toString() ?? '') ??
                1,
            deadline: _deadline,
            reason: reason,
            mode: _mode,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLocked
        ? 'Submission deadlines (Locked)'
        : _mode == 'extend'
            ? 'Extend material deadline'
            : 'Open late-upload window';
    final buttonLabel = _saving
        ? 'Saving…'
        : _mode == 'extend'
            ? 'Extend deadline'
            : 'Open late-upload window';

    return DefensysShadcnScope(
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.schedule['team_name']} · ${widget.schedule['stage_label']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DefenseMaterialReadiness(
                  readiness: Map<String, dynamic>.from(
                    widget.schedule['materials_readiness'] as Map? ?? const {},
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Defense time: ${DateFormat('MMM d, y · h:mm a').format(_defenseStart)}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (_isLocked)
                  const WorkflowNotice(
                    title: 'Defense record is protected',
                    message:
                        'This defense is archived or has finalized grades. Submission deadlines cannot be modified.',
                  )
                else if (_mode == 'late_upload')
                  const WorkflowNotice(
                    title: 'Late-upload window for missing files',
                    message:
                        'Defense evaluations and grades are protected. The team may upload missing defense materials only; existing submissions cannot be modified.',
                  )
                else
                  WorkflowNotice(
                    title: 'Pre-defense deadline extension',
                    message:
                        'Extend submission deadline up to defense start (${DateFormat('MMM d, y · h:mm a').format(_defenseStart)}).',
                  ),
                const SizedBox(height: 14),
                Text(
                  _mode == 'extend'
                      ? 'New submission deadline'
                      : 'Late-upload window open until',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      enabled: !_saving && !_isLocked,
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _deadline,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: _mode == 'extend'
                              ? _defenseStart
                              : DateTime.now().add(const Duration(days: 90)),
                        );
                        if (date != null && mounted) {
                          setState(
                            () => _deadline = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              _deadline.hour,
                              _deadline.minute,
                            ),
                          );
                        }
                      },
                      child: Text(DateFormat('MMM d, y').format(_deadline)),
                    ),
                    ShadButton.outline(
                      enabled: !_saving && !_isLocked,
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_deadline),
                        );
                        if (time != null && mounted) {
                          setState(
                            () => _deadline = DateTime(
                              _deadline.year,
                              _deadline.month,
                              _deadline.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
                      child: Text(DateFormat('h:mm a').format(_deadline)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reason',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_saving && !_isLocked,
                  placeholder: Text(
                    _mode == 'extend'
                        ? 'Explain why the team needs more preparation time.'
                        : 'Explain why a late-upload window is being granted.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _mode == 'extend'
                      ? 'Applies to this team’s defense materials. Students receive the new deadline; the reason is recorded in the audit trail.'
                      : 'Team members receive notification to upload missing materials. Completed evaluations and existing files remain untouched.',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ShadButton.ghost(
            enabled: !_saving,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ShadButton(
            enabled: !_saving && !_isLocked,
            onPressed: _save,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
