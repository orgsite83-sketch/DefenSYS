import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/branding/status_badge.dart';

class ArchiveFileDetailsDialog extends StatelessWidget {
  const ArchiveFileDetailsDialog({
    super.key,
    required this.entry,
    this.onViewPdf,
    this.onDownloadFile,
    this.onOverrideStatus,
  });

  final Map<String, dynamic> entry;
  final void Function(String url, String name)? onViewPdf;
  final void Function(String url, String name)? onDownloadFile;
  final void Function(Map<String, dynamic> entry)? onOverrideStatus;

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> entry,
    void Function(String url, String name)? onViewPdf,
    void Function(String url, String name)? onDownloadFile,
    void Function(Map<String, dynamic> entry)? onOverrideStatus,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => ArchiveFileDetailsDialog(
        entry: entry,
        onViewPdf: onViewPdf,
        onDownloadFile: onDownloadFile,
        onOverrideStatus: onOverrideStatus,
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return 'Not available';
    final raw = value.toString().trim();
    if (raw.isEmpty) return 'Not available';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y · h:mm a').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final fileName = (entry['file_name']?.toString() ?? '').trim();
    final deliverableId = (entry['deliverable_id']?.toString() ?? '').trim();
    final deliverableLabel = (entry['deliverable_label']?.toString() ?? '').trim();
    final displayTitle = deliverableLabel.isNotEmpty
        ? (deliverableId.isNotEmpty ? '$deliverableId · $deliverableLabel' : deliverableLabel)
        : (fileName.isNotEmpty ? fileName : 'Document Details');

    final status = (entry['status']?.toString() ?? 'Approved').trim();
    final fileUrl = (entry['file_url']?.toString() ?? '').trim();
    final uploadedBy = (entry['uploaded_by']?.toString() ?? '').trim();
    final uploadedAt = _formatDateTime(entry['uploaded_at']);
    final teamName = (entry['team_name']?.toString() ?? entry['team']?.toString() ?? '').trim();
    final projectTitle = (entry['project_title']?.toString() ?? '').trim();
    final stage = (entry['stage']?.toString() ?? '').trim();
    final academicYear = (entry['academic_year']?.toString() ?? '').trim();
    final semester = (entry['semester']?.toString() ?? '').trim();
    final yearLevel = (entry['year_level']?.toString() ?? '').trim();
    final fileSize = (entry['file_size']?.toString() ?? '').trim();
    final feedback = (entry['feedback']?.toString() ?? entry['remarks']?.toString() ?? '').trim();
    final archiveNote = (entry['archive_note']?.toString() ?? '').trim();
    final canOverride = entry['can_override'] == true;

    final format = DeliverableFormatInfo.fromFileName(fileName);
    final isApproved = status == 'Approved' || status == 'Accepted' || status == 'Post-Defense' || status == 'Uploaded';
    final isNeedsRevision = status == 'Needs Revision' || status == 'Rejected' || status == 'Needs Re-upload';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: DefensysTokens.dialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: format.color.withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: format.color.withValues(alpha: isDark ? 0.45 : 0.25)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(format.icon, size: 20, color: format.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          format.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isApproved
                            ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFF0FDF4))
                            : isNeedsRevision
                                ? (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.3) : const Color(0xFFFEF2F2))
                                : (isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isApproved
                              ? (isDark ? const Color(0xFF047857) : const Color(0xFFBBF7D0))
                              : isNeedsRevision
                                  ? (isDark ? const Color(0xFFDC2626) : const Color(0xFFFECACA))
                                  : (isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isApproved
                                ? Icons.verified_rounded
                                : isNeedsRevision
                                    ? Icons.warning_amber_rounded
                                    : Icons.info_outline_rounded,
                            size: 18,
                            color: isApproved
                                ? const Color(0xFF16A34A)
                                : isNeedsRevision
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status: $status',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isApproved
                                        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF15803D))
                                        : isNeedsRevision
                                            ? (isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C))
                                            : (isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155)),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isApproved
                                      ? 'Verified and permanently archived in the project repository.'
                                      : isNeedsRevision
                                          ? 'Committee requested revisions. Awaiting updated submission.'
                                          : 'Registered in the institutional archive system.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isApproved
                                        ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534))
                                        : isNeedsRevision
                                            ? (isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B))
                                            : (isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // File Identity Card with Copy Button
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(format.icon, size: 20, color: format.color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FILE NAME',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fileName.isNotEmpty ? fileName : 'No file name recorded',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (fileName.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              tooltip: 'Copy filename',
                              color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: fileName));
                                showSuccessToast(context, 'Filename copied to clipboard');
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section: Document Properties
                    _sectionHeader(context, 'DOCUMENT PROPERTIES'),
                    const SizedBox(height: 8),
                    _propertyCard(context, [
                      _propRow(context, 'Format', format.label),
                      if (fileSize.isNotEmpty) _propRow(context, 'File Size', fileSize),
                      if (deliverableId.isNotEmpty) _propRow(context, 'Deliverable ID', deliverableId),
                      if (stage.isNotEmpty) _propRow(context, 'Stage / Event', stage),
                    ]),
                    const SizedBox(height: 18),

                    // Section: Academic & Team Context
                    _sectionHeader(context, 'ACADEMIC & TEAM CONTEXT'),
                    const SizedBox(height: 8),
                    _propertyCard(context, [
                      if (teamName.isNotEmpty) _propRow(context, 'Team Name', teamName),
                      if (projectTitle.isNotEmpty && projectTitle != teamName)
                        _propRow(context, 'Project Title', projectTitle),
                      if (academicYear.isNotEmpty) _propRow(context, 'Academic Year', academicYear),
                      if (semester.isNotEmpty) _propRow(context, 'Semester', semester),
                      if (yearLevel.isNotEmpty) _propRow(context, 'Year Level', yearLevel),
                    ]),
                    const SizedBox(height: 18),

                    // Section: Submission & Audit Trail
                    _sectionHeader(context, 'SUBMISSION & AUDIT TRAIL'),
                    const SizedBox(height: 8),
                    _propertyCard(context, [
                      _propRow(context, 'Uploaded By', uploadedBy.isNotEmpty ? uploadedBy : 'System / Not Recorded'),
                      _propRow(context, 'Date Submitted', uploadedAt),
                      if (archiveNote.isNotEmpty) _propRow(context, 'Archive Note', archiveNote),
                    ]),

                    // Review Remarks (if present)
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _sectionHeader(context, 'COMMITTEE REMARKS'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFFEFCE8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          feedback,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF78350F),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (fileUrl.isNotEmpty && onDownloadFile != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onDownloadFile!(fileUrl, fileName);
                      },
                      icon: const Icon(Icons.download_rounded, size: 15),
                      label: const Text('Download'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (fileUrl.isNotEmpty && onViewPdf != null)
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onViewPdf!(fileUrl, fileName);
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 15),
                      label: const Text('View Document'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroonOf(context),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final isDark = DefensysTokens.isDark(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
      ),
    );
  }

  Widget _propertyCard(BuildContext context, List<Widget> rows) {
    final isDark = DefensysTokens.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistPanel : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                height: 1,
                color: isDark ? DefensysTokens.mistBorder : const Color(0xFFF1F5F9),
              ),
          ],
        ],
      ),
    );
  }

  Widget _propRow(BuildContext context, String label, String value) {
    final isDark = DefensysTokens.isDark(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '—',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
