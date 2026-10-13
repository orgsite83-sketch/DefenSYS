import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense_board_provider.dart';
import '../../../../../widgets/repository/defense_material_readiness.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

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
    _deadline = _defenseStart;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Enter a reason of at least 5 characters.');
      return;
    }
    if (!_deadline.isAfter(DateTime.now()) ||
        _deadline.isAfter(_defenseStart)) {
      setState(
        () => _error =
            'Choose a future deadline at or before the defense starts.',
      );
      return;
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
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: AlertDialog(
      title: const Text('Extend material deadline'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.schedule['team_name']} · ${widget.schedule['stage_label']}',
              ),
              DefenseMaterialReadiness(
                readiness: Map<String, dynamic>.from(
                  widget.schedule['materials_readiness'] as Map? ?? const {},
                ),
              ),
              Text(
                'Defense starts: ${DateFormat('MMM d, y · h:mm a').format(_defenseStart)}',
              ),
              const SizedBox(height: 12),
              const Text(
                'New submission deadline',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShadButton.outline(
                    enabled: !_saving,
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _deadline,
                        firstDate: DateTime.now(),
                        lastDate: _defenseStart,
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
                    enabled: !_saving,
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
                enabled: !_saving,
                placeholder: const Text(
                  'Explain why the team needs more time.',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Applies to this team’s defense materials. Students receive the new deadline; the reason is saved in the audit trail.',
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
          enabled: !_saving,
          onPressed: _save,
          child: Text(_saving ? 'Saving…' : 'Extend deadline'),
        ),
      ],
    ),
  );
}
