import 'package:flutter/material.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/utils/team_bulk_import_csv.dart';
import 'package:defensys/utils/team_bulk_import_draft.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'student_teams_grid.dart';
import 'student_teams_toolbar.dart';

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class DraftResumeBanner extends StatelessWidget {
  const DraftResumeBanner({
    super.key,
    required this.draft,
    required this.onResume,
    required this.onDiscard,
  });

  final TeamBulkImportDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final issueCount = draft.issueCount > 0
        ? draft.issueCount
        : countPreviewIssues(draft.preview);
    final savedLabel = MaterialLocalizations.of(context).formatShortDate(draft.savedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded, color: DefensysUi.techBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              issueCount > 0
                  ? 'Unfinished bulk import — $issueCount row${issueCount == 1 ? '' : 's'} need fixes · Saved $savedLabel'
                  : 'Unfinished bulk import · Saved $savedLabel',
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          buildSecondaryButton(
            icon: Icons.play_arrow_rounded,
            label: 'Resume',
            onTap: onResume,
          ),
          const SizedBox(width: 8),
          buildSecondaryButton(
            icon: Icons.delete_outline_rounded,
            label: 'Discard',
            onTap: onDiscard,
          ),
        ],
      ),
    );
  }
}

class StudentTeamsBulkImportView extends StatelessWidget {
  const StudentTeamsBulkImportView({
    super.key,
    required this.state,
    required this.isCapstoneAdmin,
    required this.pitLeadYear,
    required this.parsedBulkRows,
    required this.bulkCsvDraft,
    required this.selectedBulkAdviserFilter,
    required this.bulkPreview,
    required this.showIssuesOnly,
    required this.templateWarning,
    required this.isBulkImportDirty,
    required this.section,
    required this.systemName,
    required this.projectManager,
    required this.onRequestClose,
    required this.onDownloadTemplate,
    required this.onPickBulkCsvFile,
    required this.onImportBulkTeams,
    required this.onExportBulkCsv,
    required this.onSaveDraft,
    required this.onScheduleRowPreview,
    required this.onDeleteBulkRow,
    required this.onAddBulkRow,
    required this.onAdviserFilterChanged,
    required this.onShowIssuesOnlyChanged,
  });

  final StudentTeamsState state;
  final bool isCapstoneAdmin;
  final String? pitLeadYear;
  final List<Map<String, dynamic>> parsedBulkRows;
  final String bulkCsvDraft;
  final String selectedBulkAdviserFilter;
  final Map<String, dynamic>? bulkPreview;
  final bool showIssuesOnly;
  final String? templateWarning;
  final bool isBulkImportDirty;
  final String? section;
  final String? systemName;
  final String? projectManager;

  final Future<void> Function() onRequestClose;
  final VoidCallback onDownloadTemplate;
  final VoidCallback onPickBulkCsvFile;
  final VoidCallback onImportBulkTeams;
  final VoidCallback onExportBulkCsv;
  final VoidCallback? onSaveDraft;
  final ValueChanged<int> onScheduleRowPreview;
  final ValueChanged<int> onDeleteBulkRow;
  final VoidCallback onAddBulkRow;
  final ValueChanged<String?> onAdviserFilterChanged;
  final ValueChanged<bool> onShowIssuesOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await onRequestClose();
      },
      child: SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.output_rounded,
              title: 'Bulk Import Teams',
              subtitle:
                  'Upload a CSV, review teams in the table, fix issues inline, then import ready rows.',
              actions: buildSecondaryButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back to Teams',
                onTap: state.isSaving ? null : () => onRequestClose(),
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 14),
              _notice(state.error!, warning: true),
            ],
            if (state.message != null) ...[
              const SizedBox(height: 14),
              _notice(state.message!),
            ],
            const SizedBox(height: 28),
            _teamCsvFormatCard(),
            const SizedBox(height: 20),
            _teamUploadCsvCard(context),
          ],
        ),
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning
        ? DefensysUi.warningBorder
        : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _dropdownBox({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: onChanged == null ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _infoBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, color: Color(0xFFB45309), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkSampleMultiRowTable(List<String> columns, List<List<String>> rows) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: columns
                  .map(
                    (column) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          column,
                          style: const TextStyle(
                            color: DefensysUi.textDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          for (final row in rows)
            Container(
              height: 36,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: row
                    .map(
                      (value) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: Color(0xFF536079),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamCsvFormatCard() {
    if (isCapstoneAdmin) {
      final columns = const [
        'Team Name',
        'Capstone Project',
        'Adviser',
        'Team Members',
      ];
      final rows = const [
        ['Team SkyLedger', 'Alumni Career Tracker', 'Ricardo Fontanilla', 'VILLAR, Marcus'],
        ['', '', '', 'ONG, Patricia'],
        ['', '', '', 'SALAZAR, Ethan'],
        ['', '', '', 'CASTILLO, Zoe'],
      ];

      return DefensysCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official Capstone CSV Format',
                    style: TextStyle(
                      color: DefensysUi.textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Each team can span multiple rows. The first member listed is set as the team leader.',
                    style: TextStyle(
                      color: Color(0xFF536079),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bulkSampleMultiRowTable(columns, rows),
                  const SizedBox(height: 14),
                  _infoBanner(
                    'Official format: Team Members must use full names (First Last or Last, First). The adviser and year level will be resolved from student details. Standard DefenSYS format (one-row-per-team with pipe-separated member names) is also accepted automatically.',
                  ),
                  const SizedBox(height: 16),
                  buildSecondaryButton(
                    icon: Icons.file_download_rounded,
                    label: 'Download Sample Template',
                    onTap: onDownloadTemplate,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final columns = const [
      'Team Name',
      'PIT Project',
      'Team Members',
    ];
    final rows = const [
      ['Team CodeLearners', 'Smart Campus Navigator', 'Carlos Reyes'],
      ['', '', 'Maria Santos'],
      ['', '', 'Juan Dela Cruz'],
      ['', '', 'Ana Mendoza'],
      ['Team ByteBridge', 'Library Seat Finder', 'Darren Kim'],
    ];

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Official PIT CSV Format',
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Each team can span multiple rows. The first member listed is set as the team leader.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bulkSampleMultiRowTable(columns, rows),
                const SizedBox(height: 14),
                _infoBanner(
                  'Official format: Team Members must use full names (First Last or Last, First). The year level will be resolved from student details. Standard DefenSYS format (one-row-per-team with pipe-separated member names) is also accepted automatically.',
                ),
                const SizedBox(height: 16),
                buildSecondaryButton(
                  icon: Icons.file_download_rounded,
                  label: 'Download Sample Template',
                  onTap: onDownloadTemplate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamUploadCsvCard(BuildContext context) {
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload CSV',
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Upload a CSV or resume a draft, edit rows in the review table, then import ready teams.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCapstoneAdmin) ...[
                  _fieldLabel('ADVISER IMPORT FILTER'),
                  const SizedBox(height: 8),
                  _dropdownBox(
                    value: selectedBulkAdviserFilter,
                    hint: 'Select filter',
                    onChanged: state.isSaving ? null : onAdviserFilterChanged,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All teams')),
                      DropdownMenuItem(
                        value: 'with_adviser',
                        child: Text('With adviser only'),
                      ),
                      DropdownMenuItem(
                        value: 'without_adviser',
                        child: Text('Without adviser only'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'CSV source (upload / paste)',
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _fieldLabel('CSV FILE'),
                const SizedBox(height: 8),
                _bulkUploadDropZone(),
                if (templateWarning != null) ...[
                  const SizedBox(height: 12),
                  _notice(templateWarning!, warning: true),
                ],
                if (parsedBulkRows.isNotEmpty && templateWarning == null) ...[
                  const SizedBox(height: 20),
                  UnifiedSectionMetadataCard(
                    section: section,
                    systemName: systemName,
                    projectManager: projectManager,
                    bulkPreview: bulkPreview,
                  ),
                  _teamBulkReviewSection(),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    buildPrimaryButton(
                      icon: Icons.system_update_alt_rounded,
                      label: state.isSaving
                          ? 'Importing...'
                          : 'Import ready teams',
                      onTap: state.isSaving || parsedBulkRows.isEmpty || templateWarning != null
                          ? null
                          : onImportBulkTeams,
                    ),
                    const SizedBox(width: 12),
                    if (onSaveDraft != null && parsedBulkRows.isNotEmpty) ...[
                      buildSecondaryButton(
                        icon: Icons.save_as_rounded,
                        label: 'Save draft',
                        onTap: state.isSaving ? null : onSaveDraft,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (parsedBulkRows.isNotEmpty && templateWarning == null) ...[
                      buildSecondaryButton(
                        icon: Icons.file_download_rounded,
                        label: 'Export CSV',
                        onTap: onExportBulkCsv,
                      ),
                      const SizedBox(width: 12),
                    ],
                    buildSecondaryButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: state.isSaving ? null : () => onRequestClose(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamBulkReviewSection() {
    final summary = (bulkPreview?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final previewRows = (bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final readyCount = _asInt(summary['ready']) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, color: DefensysUi.primaryMaroon, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Review & fix teams',
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Issues only'),
                selected: showIssuesOnly,
                onSelected: state.isSaving ? null : onShowIssuesOnlyChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${summary['total'] ?? parsedBulkRows.length} rows · $readyCount ready to import',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TeamBulkImportReviewTable(
            rows: parsedBulkRows,
            previewRows: previewRows,
            isCapstoneAdmin: isCapstoneAdmin,
            pitLeadYear: pitLeadYear,
            showIssuesOnly: showIssuesOnly,
            onRowChanged: onScheduleRowPreview,
            onDeleteRow: onDeleteBulkRow,
            onAddRow: onAddBulkRow,
          ),
        ],
      ),
    );
  }

  Widget _bulkUploadDropZone() {
    final parsedRows = parsedBulkRows.isNotEmpty
        ? parsedBulkRows.length
        : parseTeamBulkCsvWithContext(
            bulkCsvDraft,
            isCapstoneAdmin: isCapstoneAdmin,
            pitLeadYear: pitLeadYear,
          ).rows.length;

    return InkWell(
      onTap: state.isSaving ? null : onPickBulkCsvFile,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 136,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_upload_rounded,
              color: Color(0xFF98A2B3),
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              bulkCsvDraft.trim().isEmpty
                  ? 'Click to choose a CSV file'
                  : 'CSV content ready for preflight',
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              bulkCsvDraft.trim().isEmpty
                  ? 'Only .csv files accepted'
                  : '$parsedRows valid row${parsedRows == 1 ? '' : 's'} detected',
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
