import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/documenter_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/toasts/feedback_toast.dart';

/// Official minutes have their own signing workflow and no upload/review actions.
class SystemDefenseRecords extends ConsumerStatefulWidget {
  const SystemDefenseRecords({super.key, required this.items});
  final List<Map<String, dynamic>> items;
  @override
  ConsumerState<SystemDefenseRecords> createState() =>
      _SystemDefenseRecordsState();
}

class _SystemDefenseRecordsState extends ConsumerState<SystemDefenseRecords> {
  bool _opening = false;

  Future<void> _open(Map<String, dynamic> record, {int? revisionId}) async {
    final scheduleId = (record['schedule_id'] as num?)?.toInt();
    if (scheduleId == null || _opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await ref
          .read(documenterProvider.notifier)
          .downloadPdf(scheduleId, revisionId: revisionId);
      if (!mounted) return;
      if (bytes == null) {
        showErrorToast(
          context,
          'Could not open the signed minutes. Please try again.',
        );
        return;
      }
      await viewPdfInDialog(
        context: context,
        pdfBytes: bytes,
        fileName: 'signed_minutes_$scheduleId.pdf',
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final completed = widget.items
        .where((item) => item['completed'] == true)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'System-generated Defense Records',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '$completed/${widget.items.length} completed',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final item in widget.items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['id']} · ${item['label']}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'PDF · Prepared by the assigned documenter',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${item['session_status'] == 'done' ? 'Session finished · ' : ''}${item['status_label']}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (item['completed'] == true)
                  TextButton.icon(
                    onPressed: _opening ? null : () => _open(item),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(_opening ? 'Opening…' : 'View signed PDF'),
                  ),
                for (final record
                    in (item['records'] as List? ?? []).whereType<Map>()) ...[
                  if (record['completed'] == true &&
                      record['schedule_id'] != item['schedule_id'])
                    TextButton(
                      onPressed: _opening
                          ? null
                          : () => _open(Map<String, dynamic>.from(record)),
                      child: Text('View signed minutes · ${record['date']}'),
                    ),
                  for (final revision
                      in (record['retained_versions'] as List? ?? [])
                          .whereType<Map>())
                    TextButton(
                      onPressed: _opening
                          ? null
                          : () => _open(
                              Map<String, dynamic>.from(record),
                              revisionId: (revision['id'] as num).toInt(),
                            ),
                      child: const Text('View retained signed version'),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
