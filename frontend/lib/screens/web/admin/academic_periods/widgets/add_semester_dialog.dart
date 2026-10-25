import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/academic_period_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import 'semester_calendar_fields.dart';
import 'semester_transition_dialog.dart';

class AddSemesterDialog extends ConsumerStatefulWidget {
  const AddSemesterDialog({super.key, required this.year});
  final Map<String, dynamic> year;

  @override
  ConsumerState<AddSemesterDialog> createState() => _AddSemesterDialogState();
}

class _AddSemesterDialogState extends ConsumerState<AddSemesterDialog> {
  String? _term, _error;
  DateTime? _start, _end;
  bool _active = false, _busy = false;
  late final _requestId =
      'create-${widget.year['id']}-${DateTime.now().microsecondsSinceEpoch}';

  bool get _valid =>
      !_busy &&
      _term != null &&
      _start != null &&
      _end != null &&
      _end!.isAfter(_start!);

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final yearId = int.parse(widget.year['id'].toString());
    final notifier = ref.read(academicPeriodProvider.notifier);
    final draft = {
      'label': _term!,
      'starts_on': semesterDateValue(_start!),
      'ends_on': semesterDateValue(_end!),
    };
    bool ok = false;
    if (_active) {
      final preview = await notifier.fetchCreateTransitionPreview(
        yearId,
        draft,
      );
      if (!mounted) return;
      if (preview != null) {
        if (preview['current_semester'] == null) {
          ok = await notifier.addSemester(
            yearId,
            _term!,
            startsOn: draft['starts_on'],
            endsOn: draft['ends_on'],
            setActive: true,
            activation: {
              'request_id': _requestId,
              'preview_revision': preview['preview_revision'],
            },
          );
        } else {
          ok =
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => SemesterTransitionDialog(
                  semesterId: 0,
                  preview: preview,
                  schoolYearId: yearId,
                  creationDraft: draft,
                ),
              ) ==
              true;
        }
      }
    } else {
      ok = await notifier.addSemester(
        yearId,
        _term!,
        startsOn: draft['starts_on'],
        endsOn: draft['ends_on'],
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = ref.read(academicPeriodProvider).error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final existing = (widget.year['semesters'] as List? ?? [])
        .whereType<Map>()
        .map((term) => term['label'])
        .toSet();
    final options = {
      for (final term in ['1st Semester', '2nd Semester', 'Summer'])
        if (!existing.contains(term)) term: term,
    };
    return DefensysShadcnScope(
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: const Text('Add Term'),
        description: Text('A.Y. ${widget.year['label']}'),
        actions: [
          ShadButton.outline(
            enabled: !_busy,
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ShadButton(
            enabled: _valid,
            onPressed: _valid ? _submit : null,
            backgroundColor: _valid
                ? DefensysTokens.maroon
                : DefensysTokens.borderOf(context),
            hoverBackgroundColor: DefensysTokens.maroonDark,
            foregroundColor: _valid
                ? Colors.white
                : DefensysTokens.textSecondaryOf(context),
            child: Text(
              _busy
                  ? 'Saving…'
                  : _active
                  ? 'Add & Activate'
                  : 'Add Term',
            ),
          ),
        ],
        child: SizedBox(
          width: 472,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkflowSelect(
                  label: 'Term *',
                  value: _term,
                  options: options,
                  placeholder: 'Select term',
                  searchable: false,
                  enabled: !_busy,
                  onChanged: (value) => setState(() => _term = value),
                ),
                const SizedBox(height: 8),
                SemesterCalendarFields(
                  start: _start,
                  end: _end,
                  enabled: !_busy,
                  onChanged: (start, end) => setState(() {
                    _start = start;
                    _end = end;
                  }),
                ),
                const SizedBox(height: 8),
                ShadSwitch(
                  value: _active,
                  enabled: !_busy,
                  checkedTrackColor: DefensysTokens.maroon,
                  onChanged: (value) => setState(() => _active = value),
                  label: const Text('Set as active'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
