import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/defensys_tokens.dart';
import '../../theme/program_colors.dart';
import '../../utils/universal_file_viewer.dart';
import '../../models/team_workflow_status.dart';
import 'workflow_status_style.dart';

/// Single-file policies still use the original requirement card. Named slots,
/// concepts and attachment groups need their own per-file upload/review targets.
bool usesGroupedDocumentCard(Map<String, dynamic> item) {
  final policy = item['file_policy'] as Map? ?? const {};
  return policy.isNotEmpty && (policy['mode'] ?? 'single') != 'single';
}

bool hasSubmittedDeliverable(Map<String, dynamic> item) {
  final submission = item['submission'] as Map? ?? const {};
  return item['uploaded'] == true ||
      (submission['files'] as List? ?? const []).isNotEmpty ||
      '${submission['file_url'] ?? ''}'.isNotEmpty ||
      '${submission['file_name'] ?? ''}'.isNotEmpty;
}

class DeliverableFileTypeBadge extends StatelessWidget {
  const DeliverableFileTypeBadge({
    super.key,
    required this.format,
    this.fileName,
  });

  final DeliverableFormatInfo format;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final name = fileName?.trim() ?? '';
    final actual = name.isEmpty
        ? format
        : DeliverableFormatInfo.fromFileName(name);
    final dot = name.lastIndexOf('.');
    final extension = dot >= 0 ? name.substring(dot + 1).toUpperCase() : '';
    final label = extension.isNotEmpty
        ? extension
        : format.extensions.length == 1
        ? format.extensions.single.toUpperCase()
        : switch (format.badgeCode) {
            'W' => 'DOC',
            'P' => 'PPT',
            'X' => 'XLS',
            'DOC' => 'FILE',
            _ => format.badgeCode,
          };
    final color = DefensysTokens.isDark(context)
        ? Color.lerp(actual.color, Colors.white, .35)!
        : actual.color;
    return Tooltip(
      message: name.isEmpty ? format.description : actual.label,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// The existing upload-row spacing with neutral chrome shared by all file slots.
class DeliverableUploadTile extends StatelessWidget {
  const DeliverableUploadTile({
    super.key,
    required this.title,
    required this.format,
    required this.onUpload,
    this.status,
    this.enabled = true,
    this.maxFileSizeMb = 50,
  });

  final String title;
  final DeliverableFormatInfo format;
  final VoidCallback onUpload;
  final String? status;
  final bool enabled;
  final int maxFileSizeMb;

  @override
  Widget build(BuildContext context) {
    final formats = format.label == 'Any File Format'
        ? format.label
        : format.extensions
              .map((extension) => extension.toUpperCase())
              .join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Row(
        children: [
          DeliverableFileTypeBadge(format: format),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      if (status != null)
                        TextSpan(
                          text: '$status · ',
                          style: TextStyle(
                            color: status == 'Missing'
                                ? Theme.of(context).colorScheme.error
                                : DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      TextSpan(
                        text:
                            '${status == null ? 'Accepted: ' : ''}$formats · Max $maxFileSizeMb MB',
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: enabled ? onUpload : null,
            icon: const Icon(Icons.add_rounded, size: 14),
            label: const Text('Upload'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.textPrimaryOf(context),
              side: BorderSide(color: DefensysTokens.borderOf(context)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same compact, document-first row for single and grouped requirements.
class DeliverableUploadedFileTile extends StatelessWidget {
  const DeliverableUploadedFileTile({
    super.key,
    required this.fileName,
    required this.onDetails,
    this.onRevision,
    this.revisionEnabled = true,
    this.trailing,
  });

  final String fileName;
  final VoidCallback onDetails;
  final VoidCallback? onRevision;
  final bool revisionEnabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final format = DeliverableFormatInfo.fromFileName(fileName);
    final surface = Color.alphaBlend(
      DefensysTokens.surfaceHigherOf(context).withValues(alpha: .5),
      DefensysTokens.surfaceOf(context),
    );
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final document = Row(
                children: [
                  DeliverableFileTypeBadge(format: format, fileName: fileName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: '$fileName\nView file details',
                          child: Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          format.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onRevision == null
                        ? onDetails
                        : revisionEnabled
                        ? onRevision
                        : null,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: DefensysTokens.surfaceHigherOf(context),
                      foregroundColor: DefensysTokens.textPrimaryOf(context),
                      side: BorderSide(color: DefensysTokens.borderOf(context)),
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      textStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          onRevision == null ? 'Details' : 'Upload revision',
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          onRevision == null
                              ? Icons.chevron_right_rounded
                              : Icons.upload_file_outlined,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              );
              if (onRevision != null && constraints.maxWidth < 250) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    document,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: document),
                  const SizedBox(width: 8),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class DeliverableStatusBadge extends StatelessWidget {
  const DeliverableStatusBadge({
    super.key,
    required this.label,
    required this.tone,
  });
  final String label;
  final WorkflowStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final style = WorkflowStatusStyle.of(context, tone);
    final action = label == 'Action Required';
    final icon = tone == WorkflowStatusTone.success
        ? Icons.check_circle_outline_rounded
        : tone == WorkflowStatusTone.attention
        ? Icons.schedule_rounded
        : Icons.circle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        border: Border.all(color: style.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            action ? Icons.circle : icon,
            size: action || tone == WorkflowStatusTone.neutral ? 5 : 11,
            color: style.foreground,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: style.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DeliverableUploadAttribution extends StatelessWidget {
  const DeliverableUploadAttribution({
    super.key,
    this.uploader,
    this.uploadedAt,
  });
  final String? uploader;
  final String? uploadedAt;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(uploadedAt ?? '');
    final author = uploader?.trim() ?? '';
    final text =
        '${author.isEmpty ? 'Uploaded' : 'Uploaded by $author'}${date == null ? '' : ' · ${DateFormat('MMM d, y').format(date.toLocal())}'}';
    return Row(
      children: [
        Icon(
          Icons.person_outline_rounded,
          size: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: DefensysTokens.textSecondaryOf(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class DeliverableDetailsActions extends StatelessWidget {
  const DeliverableDetailsActions({
    super.key,
    required this.onView,
    this.onReplace,
    this.onRemove,
    this.replacementLabel = 'Replace File',
  });

  final VoidCallback? onView;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;
  final String replacementLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: DefensysTokens.textPrimaryOf(context),
      side: BorderSide(color: DefensysTokens.borderOf(context)),
      shape: shape,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      visualDensity: VisualDensity.standard,
      textStyle: labelStyle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 28, color: DefensysTokens.borderOf(context)),
        FilledButton.icon(
          onPressed: onView,
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('View Document'),
          style: FilledButton.styleFrom(
            backgroundColor: DefensysTokens.maroonOf(context),
            foregroundColor: Colors.white,
            shape: shape,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            visualDensity: VisualDensity.standard,
            textStyle: labelStyle,
          ),
        ),
        if (onReplace != null || onRemove != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (onReplace != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReplace,
                    icon: Icon(
                      replacementLabel == 'Upload revision'
                          ? Icons.upload_file_outlined
                          : Icons.swap_horiz_rounded,
                      size: 16,
                    ),
                    label: Text(replacementLabel),
                    style: secondary,
                  ),
                ),
              if (onReplace != null && onRemove != null)
                const SizedBox(width: 10),
              if (onRemove != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: secondary.copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.error,
                      ),
                      side: WidgetStatePropertyAll(
                        BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: .3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> showDeliverableFileDetails({
  required BuildContext context,
  required String label,
  required String stageLabel,
  required Map<String, dynamic> file,
  required String status,
  String? uploader,
  Future<void> Function()? onReplace,
  Future<void> Function()? onRemove,
  String? programScope,
}) async {
  final name = '${file['file_name'] ?? 'Document'}';
  final format = DeliverableFormatInfo.fromFileName(name);
  final submitted = DateTime.tryParse('${file['uploaded_at'] ?? ''}');
  final properties = <String, String>{
    'Type': format.label,
    programTrack(scope: programScope) == ProgramTrack.pit ? 'Event' : 'Stage':
        stageLabel,
    'Size': '${file['file_size'] ?? 'Not available'}',
    'Uploaded by': uploader?.isNotEmpty == true ? uploader! : 'Not available',
    'Submitted': submitted == null
        ? 'Not available'
        : DateFormat('MMM d, y · h:mm a').format(submitted.toLocal()),
    'Revision': '${file['revision'] ?? 1}',
    'File name': name,
  };
  Widget content(BuildContext sheetContext) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DeliverableFileTypeBadge(format: format, fileName: name),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textPrimaryOf(sheetContext),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close details',
              onPressed: () => Navigator.pop(sheetContext),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textSecondaryOf(sheetContext),
          ),
        ),
        const SizedBox(height: 14),
        for (final property in properties.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    property.key,
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(sheetContext),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    property.value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.textPrimaryOf(sheetContext),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if ('${file['feedback'] ?? ''}'.isNotEmpty) ...[
          const Divider(height: 24),
          Text(
            'Feedback: ${file['feedback']}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textPrimaryOf(sheetContext),
            ),
          ),
        ],
        DeliverableDetailsActions(
          onView: '${file['file_url'] ?? ''}'.isEmpty
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  viewFileInDialog(
                    context: context,
                    fileUrl: '${file['file_url']}',
                    fileName: name,
                  );
                },
          replacementLabel:
              file['status'] == 'rejected' || file['status'] == 'Needs Revision'
              ? 'Upload revision'
              : 'Replace File',
          onReplace: onReplace == null
              ? null
              : () async {
                  Navigator.pop(sheetContext);
                  await onReplace();
                },
          onRemove: onRemove == null
              ? null
              : () async {
                  Navigator.pop(sheetContext);
                  await onRemove();
                },
        ),
      ],
    ),
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DefensysTokens.surfaceOf(context),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      builder: content,
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: DefensysTokens.surfaceOf(dialogContext),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: content(dialogContext),
        ),
      ),
    );
  }
}
