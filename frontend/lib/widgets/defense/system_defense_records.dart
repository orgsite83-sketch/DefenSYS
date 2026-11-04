import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/documenter_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

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
    final completed = widget.items
        .where((item) => item['completed'] == true)
        .length;
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Defense records',
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: DefensysTokens.spacingSm),
              Text(
                '$completed/${widget.items.length} completed',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in widget.items)
            Padding(
              padding: const EdgeInsets.only(bottom: DefensysTokens.spacingMd),
              child: ShadCard(
                width: double.infinity,
                padding: const EdgeInsets.all(DefensysTokens.spacingLg),
                backgroundColor: DefensysTokens.surfaceOf(context),
                rowMainAxisSize: MainAxisSize.max,
                columnCrossAxisAlignment: CrossAxisAlignment.stretch,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: DefensysTokens.surfaceHigherOf(context),
                            borderRadius: BorderRadius.circular(
                              DefensysTokens.radiusMd,
                            ),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            size: 22,
                            color: DefensysTokens.maroonTextOf(context),
                          ),
                        ),
                        const SizedBox(width: DefensysTokens.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['label']}',
                                style: DefensysTokens.body.copyWith(
                                  color: DefensysTokens.textPrimaryOf(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: DefensysTokens.spacingSm),
                              Wrap(
                                spacing: DefensysTokens.spacingSm,
                                runSpacing: DefensysTokens.spacingXs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ShadBadge.outline(
                                    child: Text(
                                      'PDF',
                                      style: DefensysTokens.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: DefensysTokens.textSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Prepared by the assigned documenter',
                                    style: DefensysTokens.caption.copyWith(
                                      color: DefensysTokens.textSecondaryOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DefensysTokens.spacingLg),
                    Divider(height: 1, color: DefensysTokens.borderOf(context)),
                    const SizedBox(height: DefensysTokens.spacingMd),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            item['completed'] == true
                                ? Icons.verified_outlined
                                : Icons.schedule_outlined,
                            size: 16,
                            color: item['completed'] == true
                                ? DefensysTokens.maroonTextOf(context)
                                : DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(width: DefensysTokens.spacingSm),
                        Expanded(
                          child: Text(
                            '${item['session_status'] == 'done' ? 'Session finished · ' : ''}${item['status_label']}',
                            style: DefensysTokens.caption.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item['completed'] == true) ...[
                      const SizedBox(height: DefensysTokens.spacingMd),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ShadButton(
                          size: ShadButtonSize.sm,
                          backgroundColor: DefensysTokens.maroonOf(context),
                          hoverBackgroundColor: DefensysTokens.isDark(context)
                              ? DefensysTokens.maroonLight
                              : DefensysTokens.maroonDark,
                          foregroundColor: Colors.white,
                          onPressed: _opening ? null : () => _open(item),
                          leading: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 16,
                          ),
                          child: Text(
                            _opening ? 'Opening…' : 'View signed PDF',
                            style: const TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                            ),
                          ),
                        ),
                      ),
                    ],
                    for (final record
                        in (item['records'] as List? ?? [])
                            .whereType<Map>()) ...[
                      if (record['completed'] == true &&
                          record['schedule_id'] != item['schedule_id'])
                        _historyAction(
                          context,
                          onPressed: _opening
                              ? null
                              : () => _open(Map<String, dynamic>.from(record)),
                          label: 'View signed minutes · ${record['date']}',
                        ),
                      for (final revision
                          in (record['retained_versions'] as List? ?? [])
                              .whereType<Map>())
                        _historyAction(
                          context,
                          onPressed: _opening
                              ? null
                              : () => _open(
                                  Map<String, dynamic>.from(record),
                                  revisionId: (revision['id'] as num).toInt(),
                                ),
                          label: 'View retained signed version',
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyAction(
    BuildContext context, {
    required VoidCallback? onPressed,
    required String label,
  }) => Padding(
    padding: const EdgeInsets.only(top: DefensysTokens.spacingSm),
    child: ShadButton.ghost(
      height: null,
      padding: const EdgeInsets.symmetric(
        horizontal: DefensysTokens.spacingSm,
        vertical: DefensysTokens.spacingSm,
      ),
      onPressed: onPressed,
      leading: Icon(
        Icons.history,
        size: 16,
        color: DefensysTokens.textSecondaryOf(context),
      ),
      child: Flexible(
        child: Text(
          label,
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.maroonTextOf(context),
          ),
        ),
      ),
    ),
  );
}
