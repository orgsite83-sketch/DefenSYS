import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/academic_period_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';

String semesterDateValue(DateTime date) =>
    DateFormat('yyyy-MM-dd').format(date);

String semesterDateRange(Map<String, dynamic> semester) {
  final start = DateTime.tryParse(semester['starts_on']?.toString() ?? '');
  final end = DateTime.tryParse(semester['ends_on']?.toString() ?? '');
  if (start == null || end == null) return 'Dates not set';
  return '${DateFormat.yMMMd().format(start)} – ${DateFormat.yMMMd().format(end)}';
}

class SemesterCalendarFields extends StatelessWidget {
  const SemesterCalendarFields({
    super.key,
    this.start,
    this.end,
    this.enabled = true,
    required this.onChanged,
  });
  final DateTime? start, end;
  final bool enabled;
  final void Function(DateTime?, DateTime?) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(bool isStart) => WorkflowField(
      label: isStart ? 'Start date *' : 'End date *',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadDatePicker(
            key: ValueKey(
              isStart ? 'semester-start-date' : 'semester-end-date',
            ),
            selected: isStart ? start : end,
            enabled: enabled,
            closeOnSelection: true,
            allowDeselection: false,
            placeholder: const Text('Select date'),
            formatDate: (date) => DateFormat.yMMMd().format(date),
            onChanged: (date) {
              if (date != null) {
                onChanged(isStart ? date : start, isStart ? end : date);
              }
            },
          ),
          if (!isStart && start != null && end != null && !end!.isAfter(start!))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'End date must be after start date.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 400
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [field(true), field(false)],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field(true)),
                const SizedBox(width: 16),
                Expanded(child: field(false)),
              ],
            ),
    );
  }
}

class SemesterCalendarSummary extends StatelessWidget {
  const SemesterCalendarSummary({
    super.key,
    required this.semester,
    this.onEdit,
  });
  final Map<String, dynamic> semester;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadCard(
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Semester dates',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(semesterDateRange(semester)),
            ],
          ),
          ShadButton.outline(
            enabled: onEdit != null,
            onPressed: onEdit,
            leading: const Icon(Icons.edit_calendar_outlined, size: 16),
            child: const Text('Edit dates'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showSemesterCalendarEditor(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> semester,
) async {
  var start = DateTime.tryParse(semester['starts_on']?.toString() ?? '');
  var end = DateTime.tryParse(semester['ends_on']?.toString() ?? '');
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => DefensysShadcnScope(
        child: ShadDialog(
          constraints: const BoxConstraints(maxWidth: 520),
          title: const Text('Semester dates'),
          description: Text(
            semester['display_name']?.toString() ??
                semester['label'].toString(),
          ),
          actions: [
            ShadButton.outline(
              enabled: !busy,
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ShadButton(
              enabled:
                  !busy && start != null && end != null && end!.isAfter(start!),
              backgroundColor: DefensysTokens.maroon,
              hoverBackgroundColor: DefensysTokens.maroonDark,
              foregroundColor: Colors.white,
              onPressed: () async {
                if (busy ||
                    start == null ||
                    end == null ||
                    !end!.isAfter(start!)) {
                  return;
                }
                setDialogState(() {
                  busy = true;
                  error = null;
                });
                final ok = await ref
                    .read(academicPeriodProvider.notifier)
                    .updateSemesterCalendar(
                      int.parse(semester['id'].toString()),
                      semesterDateValue(start!),
                      semesterDateValue(end!),
                    );
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(dialogContext);
                  return;
                }
                setDialogState(() {
                  busy = false;
                  error = ref.read(academicPeriodProvider).error;
                });
              },
              child: Text(busy ? 'Saving…' : 'Save dates'),
            ),
          ],
          child: SizedBox(
            width: 472,
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SemesterCalendarFields(
                    start: start,
                    end: end,
                    enabled: !busy,
                    onChanged: (s, e) => setDialogState(() {
                      start = s;
                      end = e;
                    }),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
