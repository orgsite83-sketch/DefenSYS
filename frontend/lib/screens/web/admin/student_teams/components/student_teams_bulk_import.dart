import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/screens/web/admin/widgets/template_blueprint_models.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/team_bulk_import_draft.dart';

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
        borderRadius: BorderRadius.circular(10),
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
                fontWeight: FontWeight.w700,
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

class StudentTeamsBulkImportView extends StatefulWidget {
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
    this.activeSemester,
    required this.onRequestClose,
    required this.onDownloadTemplate,
    required this.onPickBulkCsvFile,
    required this.onImportBulkTeams,
    required this.onExportBulkCsv,
    this.onSaveDraft,
    required this.onScheduleRowPreview,
    required this.onDeleteBulkRow,
    required this.onAddBulkRow,
    required this.onAdviserFilterChanged,
    required this.onShowIssuesOnlyChanged,
    this.onClearStaged,
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
  final Map<String, dynamic>? activeSemester;

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
  final VoidCallback? onClearStaged;

  @override
  State<StudentTeamsBulkImportView> createState() => _StudentTeamsBulkImportViewState();
}

class _StudentTeamsBulkImportViewState extends State<StudentTeamsBulkImportView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;
  static const Color _green = Color(0xFF15803D);

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _getActiveSemLabel() {
    final sem = widget.activeSemester;
    if (sem != null) {
      final name = sem['display_name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      final sy = sem['school_year']?.toString().trim();
      final lbl = sem['label']?.toString().trim();
      if (sy != null && lbl != null) return '$sy $lbl';
    }
    return widget.isCapstoneAdmin ? 'Capstone Term' : 'PIT Term';
  }

  @override
  Widget build(BuildContext context) {
    final activeSemLabel = _getActiveSemLabel();

    return PopScope(
      canPop: !widget.isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await widget.onRequestClose();
      },
      child: SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.groups_2_rounded,
              title: 'Bulk Import Student Teams',
              subtitle: widget.isCapstoneAdmin
                  ? 'Upload team spreadsheets, validate member details and advisers inline, then import ready teams into the active capstone term.'
                  : 'Upload PIT team spreadsheets, validate project and member details inline, then import ready teams.',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeSemLabel.isNotEmpty) ...[
                    _headerPill(activeSemLabel),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: widget.state.isSaving ? null : () => widget.onRequestClose(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back to Teams'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.state.error != null) ...[
              const SizedBox(height: 14),
              _notice(widget.state.error!, warning: true),
            ],
            if (widget.state.message != null) ...[
              const SizedBox(height: 14),
              _notice(widget.state.message!),
            ],
            const SizedBox(height: 20),

            // Top 2-Column Section: Left is Smart Format Guide, Right is Primary Upload Action
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                if (!isWide) {
                  return Column(
                    children: [
                      _buildTeamFormatCard(activeSemLabel),
                      const SizedBox(height: 18),
                      _buildTeamUploadCard(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildTeamFormatCard(activeSemLabel),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: _buildTeamUploadCard(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Bottom Full-Width Preflight Review Table Card
            _buildPreflightReviewCard(),
          ],
        ),
      ),
    );
  }

  Widget _headerPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF5D6678),
        ),
      ),
    );
  }

  Widget _buildFormatPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildTemplateSpecTag(
    String label, {
    bool isRequired = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRequired ? Colors.white : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isRequired ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRequired) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: _maroon,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isRequired ? FontWeight.w700 : FontWeight.w600,
              color: isRequired ? _ink : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamStatItem(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTeamStatDivider() {
    return Container(
      height: 14,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _buildTeamFormatCard(String activeSemLabel) {
    final isCapstone = widget.isCapstoneAdmin;

    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_outlined, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCapstone ? 'Official Capstone Team Specification' : 'Official PIT Team Specification',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel • Standard Team Sheet Format',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Document Blueprint Structure Container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tier 1: Registrar Header Preamble
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 14, color: Color(0xFF475569)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'PREAMBLE METADATA (OPTIONAL)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'Auto-Detected',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _buildTemplateSpecTag('Class Section (Header / Column / Matrix)'),
                      _buildTemplateSpecTag('System / Subject'),
                      _buildTemplateSpecTag(isCapstone ? 'Subject Code' : 'Project Manager / Instructor'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  // Tier 2: Required Team Table Columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.table_rows_outlined, size: 14, color: _maroon),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'TEAM ROSTER SPECIFICATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Text(
                          'Core Required',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _maroon,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _buildTemplateSpecTag('Team Name', isRequired: true),
                      _buildTemplateSpecTag(isCapstone ? 'Capstone Project' : 'PIT Project', isRequired: true),
                      _buildTemplateSpecTag('Class Section', isRequired: true),
                      if (isCapstone)
                        _buildTemplateSpecTag('Adviser'),
                      _buildTemplateSpecTag('Team Members (Leader First)', isRequired: true),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tip note
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: _muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Supports standard sheets or multi-column section tables (e.g. 2A, 2B, 2C). Team sections automatically bind to student records.',
                    style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons Row: View Blueprint Modal & Download Template
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showTeamSheetBlueprintModal(context, isCapstone: isCapstone, activeSemLabel: activeSemLabel),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('View Sheet Layout Blueprint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onDownloadTemplate,
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download Sample Template'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamUploadCard() {
    final hasRows = widget.parsedBulkRows.isNotEmpty;
    final summary = (widget.bulkPreview?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final readyCount = _asInt(summary['ready']) ?? 0;
    final totalRows = widget.parsedBulkRows.length;
    final issueCount = totalRows - readyCount;

    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasRows
                        ? const Color(0xFFDCFCE7)
                        : _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasRows
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: hasRows ? _green : _maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasRows
                            ? 'Staged Team Source Records'
                            : 'Upload Team Spreadsheets',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasRows
                            ? '${widget.parsedBulkRows.length} team(s) staged • $readyCount ready to import'
                            : 'Supports official university CSV and XLSX formats',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (widget.isCapstoneAdmin) ...[
              Row(
                children: [
                  const Text(
                    'ADVISER IMPORT FILTER',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: widget.state.isSaving ? const Color(0xFFF1F5F9) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: widget.selectedBulkAdviserFilter,
                        isDense: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                        style: const TextStyle(
                          color: DefensysUi.textDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
                        onChanged: widget.state.isSaving ? null : widget.onAdviserFilterChanged,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            InkWell(
              onTap: widget.state.isSaving ? null : widget.onPickBulkCsvFile,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: hasRows ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasRows ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                    width: hasRows ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasRows
                          ? Icons.inventory_2_outlined
                          : Icons.cloud_upload_outlined,
                      size: 28,
                      color: hasRows ? _green : _maroon,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasRows
                          ? '${widget.parsedBulkRows.length} Team Record(s) Staged (Click to Replace / Stage New)'
                          : 'Click to choose team CSV / spreadsheet (.csv / .xlsx)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: hasRows ? const Color(0xFF15803D) : _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasRows
                          ? '$readyCount ready to import · ${issueCount > 0 ? '$issueCount needing review' : 'all valid'}'
                          : 'Multi-row teams and single-row formats supported',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasRows ? const Color(0xFF166534) : _muted,
                      ),
                    ),
                    if (!hasRows) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFormatPill('CSV'),
                          const SizedBox(width: 6),
                          _buildFormatPill('XLSX'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.templateWarning != null) ...[
              const SizedBox(height: 10),
              _notice(widget.templateWarning!, warning: true),
            ],
            if (hasRows) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    widget.onClearStaged?.call();
                    widget.onScheduleRowPreview(-1);
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 15),
                  label: const Text('Clear all staged teams'),
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightReviewCard() {
    final activeSemLabel = _getActiveSemLabel();
    final summary = (widget.bulkPreview?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final previewRows = (widget.bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final readyCount = _asInt(summary['ready']) ?? 0;
    final totalRows = widget.parsedBulkRows.length;
    final issueCount = totalRows - readyCount;

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header (Unified with Capstone Stages style)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  color: DefensysUi.primaryMaroon,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preflight Team Intake Review',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Verify student team assignments and resolve any roster or leadership issues before importing.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activeSemLabel.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _headerPill(activeSemLabel),
                ],
                const SizedBox(width: 8),
                _headerPill(
                  totalRows == 0
                      ? '0 teams staged'
                      : (readyCount > 0 ? '$readyCount / $totalRows ready' : '$totalRows teams staged'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Team Intake Snapshot Strip
          if (totalRows > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined, size: 15, color: Color(0xFF475569)),
                    const SizedBox(width: 8),
                    const Text(
                      'Validation Snapshot:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 14),
                    _buildTeamStatItem('Ready to Import', readyCount, const Color(0xFF16A34A)),
                    if (issueCount > 0) ...[
                      _buildTeamStatDivider(),
                      _buildTeamStatItem('Needs Fix', issueCount, const Color(0xFFD97706)),
                    ],
                    _buildTeamStatDivider(),
                    _buildTeamStatItem('Total Staged', totalRows, const Color(0xFF64748B)),
                  ],
                ),
              ),
            ),

          // Search + Filter Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16, color: _muted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        hintText: 'Search by team name, project title, adviser, or members...',
                        hintStyle: const TextStyle(fontSize: 12.5, color: _muted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: _maroon),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: Text(issueCount > 0 ? 'Issues only ($issueCount)' : 'Issues only'),
                  selected: widget.showIssuesOnly,
                  onSelected: widget.state.isSaving ? null : widget.onShowIssuesOnlyChanged,
                  selectedColor: const Color(0xFFFEF2F2),
                  checkmarkColor: const Color(0xFFDC2626),
                  side: BorderSide(
                    color: widget.showIssuesOnly ? const Color(0xFFFECACA) : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.showIssuesOnly ? const Color(0xFFDC2626) : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Review team rosters, verify leader designations, and resolve any membership conflicts before importing.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Content body
          if (widget.parsedBulkRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_2_outlined, size: 38, color: Color(0xFF98A2B3)),
                    SizedBox(height: 10),
                    Text(
                      'No Team Records Staged',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose or drop a team CSV / XLSX spreadsheet above to begin preflight review.',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.section != null && widget.section!.isNotEmpty)
                    UnifiedSectionMetadataCard(
                      section: widget.section,
                      systemName: widget.systemName,
                      projectManager: widget.projectManager,
                      bulkPreview: widget.bulkPreview,
                    ),
                  TeamBulkImportReviewTable(
                    rows: widget.parsedBulkRows,
                    previewRows: previewRows,
                    isCapstoneAdmin: widget.isCapstoneAdmin,
                    pitLeadYear: widget.pitLeadYear,
                    showIssuesOnly: widget.showIssuesOnly,
                    searchQuery: _searchCtrl.text,
                    onRowChanged: widget.onScheduleRowPreview,
                    onDeleteRow: widget.onDeleteBulkRow,
                    onAddRow: widget.onAddBulkRow,
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Table Footer Actions Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF667085)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.parsedBulkRows.isNotEmpty
                        ? '$readyCount of $totalRows teams ready to import'
                        : 'Review team details and verify leader designations before confirming import.',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.onSaveDraft != null && widget.parsedBulkRows.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: widget.state.isSaving ? null : widget.onSaveDraft,
                    icon: const Icon(Icons.save_as_rounded, size: 14),
                    label: const Text('Save Draft'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.parsedBulkRows.isNotEmpty && widget.templateWarning == null) ...[
                  OutlinedButton.icon(
                    onPressed: widget.onExportBulkCsv,
                    icon: const Icon(Icons.file_download_rounded, size: 14),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  onPressed: widget.state.isSaving ? null : () => widget.onRequestClose(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFD0D5DD)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: widget.state.isSaving || widget.parsedBulkRows.isEmpty || widget.templateWarning != null || readyCount == 0
                      ? null
                      : widget.onImportBulkTeams,
                  icon: widget.state.isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text(
                    widget.state.isSaving
                        ? 'Importing Teams...'
                        : (readyCount > 0 ? 'Import $readyCount Ready Team${readyCount == 1 ? '' : 's'}' : 'Import Ready Teams'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTeamSheetBlueprintModal(
    BuildContext context, {
    required bool isCapstone,
    required String activeSemLabel,
  }) {
    int selectedTab = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final blueprints = teamGroupingBlueprintsFor(isCapstone: isCapstone);
            final bp = blueprints[selectedTab];

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Modal Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _maroon.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.grid_on_rounded, color: _maroon, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCapstone
                                      ? 'Official Capstone Team Sheet Blueprint'
                                      : 'Official PIT Team Sheet Blueprint',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Target Term: $activeSemLabel • Interactive guide for supported team grouping layouts',
                                  style: const TextStyle(fontSize: 12, color: _muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: _muted),
                            splashRadius: 18,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _line),

                    // Guidance Bar (Single Canonical Standard)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      color: const Color(0xFFF8FAFC),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isCapstone
                                  ? 'Official Department Team Roster. Section declared as header block, with teams grouped under faculty Advisers and projects/modules assigned per team.'
                                  : 'Official PIT Team Roster. Section declared as header block, with instructor declared at top and projects/modules assigned per team.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: const Text(
                              'Auto-Detected',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _line),

                    // Variation Switcher (Independent Projects vs Shared System)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Row(
                        children: [
                          _buildBlueprintVariantTab(
                            title: 'Different Systems (Independent Projects)',
                            icon: Icons.hub_outlined,
                            isSelected: selectedTab == 0,
                            onTap: () => setModalState(() => selectedTab = 0),
                          ),
                          const SizedBox(width: 8),
                          _buildBlueprintVariantTab(
                            title: 'Single Shared System (Modules)',
                            icon: Icons.account_tree_outlined,
                            isSelected: selectedTab == 1,
                            onTap: () => setModalState(() => selectedTab = 1),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _buildSampleTeamSheetPreview(
                          isCapstone: isCapstone,
                          selectedTab: selectedTab,
                        ),
                      ),
                    ),

                    const Divider(height: 1, color: _line),
                    // Modal Footer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await downloadTextFile(
                                    filename: bp.filename,
                                    content: bp.rawCsv,
                                  );
                                  if (context.mounted) {
                                    showSuccessToast(
                                      context,
                                      'Sample ${bp.shortLabel} template downloaded.',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.download_rounded, size: 15),
                                label: Text('Download ${bp.shortLabel} Template (.csv)'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ink,
                                  side: const BorderSide(color: _line),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: csvToTsv(bp.rawCsv)));
                                  if (context.mounted) {
                                    showSuccessToast(
                                      context,
                                      'Copied for Excel/Sheets! Press Ctrl+V in your spreadsheet.',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('Copy for Excel / Sheets'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ink,
                                  side: const BorderSide(color: _line),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _maroon,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                            ),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBlueprintVariantTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF94A3B8) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? _ink : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? _ink : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleTeamSheetPreview({
    required bool isCapstone,
    required int selectedTab,
  }) {
    final blueprints = teamGroupingBlueprintsFor(isCapstone: isCapstone);
    final bp = blueprints[selectedTab];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spreadsheet Window Titlebar & Sheet Tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF475569)),
                      const SizedBox(width: 5),
                      Text(
                        bp.filename,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bp.badgeBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    bp.badgeText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: bp.badgeFg,
                    ),
                  ),
                ),
              ],
            ),
          ),

          _buildOption2CanonicalPreview(
            isCapstone: isCapstone,
            isSharedSystem: selectedTab == 1,
          ),
        ],
      ),
    );
  }

  Widget _buildOption2CanonicalPreview({
    required bool isCapstone,
    required bool isSharedSystem,
  }) {
    var currentRow = 1;
    final rows = <Widget>[];

    void addDivider({bool thick = false}) {
      rows.add(Divider(height: 1, color: thick ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)));
    }

    if (isSharedSystem) {
      rows.add(
        _buildMetadataPreviewRow(
          rowNum: (currentRow++).toString(),
          label: 'System Name:',
          value: isCapstone ? 'Hospital Management System' : 'Societree',
        ),
      );
      addDivider();
    }

    if (!isCapstone) {
      rows.add(
        _buildMetadataPreviewRow(
          rowNum: (currentRow++).toString(),
          label: 'Instructor:',
          value: 'Prof. Alex Santos',
        ),
      );
      addDivider();
    }

    if (isSharedSystem) {
      rows.add(
        _buildMetadataPreviewRow(
          rowNum: (currentRow++).toString(),
          label: 'Project Manager:',
          value: 'Juan Dela Cruz',
        ),
      );
      addDivider();
    }

    if (isSharedSystem || !isCapstone) {
      addDivider(thick: true);
    }

    if (isCapstone) {
      // Adviser 1: Prof. Alex Santos (3 teams in BSIT-4A, 1 team in BSIT-4C)
      rows.add(
        _buildAdviserDividerRow(
          rowNum: (currentRow++).toString(),
          adviserName: 'Prof. Alex Santos',
          badgeText: 'Faculty Adviser (4 Teams)',
        ),
      );
      addDivider(thick: true);

      // Section 4A Sub-Header (3 teams)
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-4A',
        ),
      );
      addDivider();

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      // Teams 0, 1, 2 from sampleAdviser1Teams (Groups 1, 2, 3 in 4A)
      for (var t = 0; t < 3; t++) {
        final team = sampleAdviser1Teams[t];
        final isAlt = t % 2 == 1;
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: isAlt,
            ),
          );
          addDivider();
        }
      }

      // Section 4C Sub-Header (1 team)
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-4C',
        ),
      );
      addDivider();

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      // Team 0 from sampleAdviser2Teams (Group 1 in 4C)
      {
        final team = sampleAdviser2Teams[0];
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: false,
            ),
          );
          addDivider();
        }
      }

      // Adviser 2: Prof. Elena Ramos (1 team in BSIT-4A, 3 teams in BSIT-4B)
      rows.add(
        _buildAdviserDividerRow(
          rowNum: (currentRow++).toString(),
          adviserName: 'Prof. Elena Ramos',
          badgeText: 'Faculty Adviser (4 Teams)',
        ),
      );
      addDivider(thick: true);

      // Section 4A Sub-Header (1 team)
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-4A',
        ),
      );
      addDivider();

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      // Team 3 from sampleAdviser1Teams (Group 4 in 4A)
      {
        final team = sampleAdviser1Teams[3];
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: false,
            ),
          );
          addDivider();
        }
      }

      // Section 4B Sub-Header (3 teams)
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-4B',
        ),
      );
      addDivider();

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      // Teams 1, 2, 3 from sampleAdviser2Teams (Groups 1, 2, 3 in 4B)
      for (var t = 1; t < 4; t++) {
        final team = sampleAdviser2Teams[t];
        final isAlt = (t - 1) % 2 == 1;
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: isAlt,
            ),
          );
          addDivider();
        }
      }
    } else {
      // PIT Mode: 1 Faculty Instructor declared at top. Sections flow as header blocks!
      // --- SECTION 1: BSIT-2A ---
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-2A',
        ),
      );
      addDivider(thick: true);

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      for (var t = 0; t < sampleAdviser1Teams.length; t++) {
        final team = sampleAdviser1Teams[t];
        final isAlt = t % 2 == 1;
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: isAlt,
            ),
          );
          addDivider();
        }
      }

      // --- SECTION 2: BSIT-2B ---
      rows.add(
        _buildSectionDividerRow(
          rowNum: (currentRow++).toString(),
          section: 'BSIT-2B',
        ),
      );
      addDivider(thick: true);

      // Column Headers
      rows.add(
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell((currentRow++).toString(), isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Names', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Project / Module', flex: 4, isRequired: true),
            ],
          ),
        ),
      );
      addDivider(thick: true);

      for (var t = 0; t < sampleAdviser2Teams.length; t++) {
        final team = sampleAdviser2Teams[t];
        final isAlt = t % 2 == 1;
        for (var m = 0; m < team.members.length; m++) {
          rows.add(
            _buildOption2TeamRow(
              rowNum: (currentRow++).toString(),
              teamName: m == 0 ? team.teamName : '',
              member: team.members[m],
              isLeader: m == 0,
              module: m == 0
                  ? (isSharedSystem
                      ? team.effectiveSharedModule(isCapstone: isCapstone)
                      : team.independentProject)
                  : '',
              isAlt: isAlt,
            ),
          );
          addDivider();
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }


  Widget _buildMetadataPreviewRow({
    required String rowNum,
    required String label,
    required String value,
  }) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          _buildGutterCell(rowNum, isHeader: true),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDividerRow({
    required String rowNum,
    required String section,
  }) {
    return Container(
      color: const Color(0xFFE2E8F0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          _buildGutterCell(rowNum, isHeader: true),
          const SizedBox(width: 8),
          const Icon(Icons.school_outlined, size: 15, color: Color(0xFF0F172A)),
          const SizedBox(width: 6),
          Text(
            'SECTION: $section',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdviserDividerRow({
    required String rowNum,
    required String adviserName,
    required String badgeText,
  }) {
    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          _buildGutterCell(rowNum, isHeader: true),
          const SizedBox(width: 8),
          const Icon(Icons.person_pin_circle_outlined, size: 15, color: _maroon),
          const SizedBox(width: 6),
          Text(
            'ADVISER: $adviserName',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _maroon,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption2TeamRow({
    required String rowNum,
    required String teamName,
    required String member,
    required bool isLeader,
    required String module,
    bool isAlt = false,
  }) {
    return Container(
      color: isAlt ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNum),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                teamName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      member,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isLeader ? FontWeight.w800 : FontWeight.w500,
                        color: isLeader ? _maroon : _ink,
                      ),
                    ),
                  ),
                  if (isLeader)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE4E6),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFFDA4AF)),
                      ),
                      child: const Text(
                        'LEADER',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF9F1239),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                module,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildGutterCell(String rowNum, {bool isHeader = false}) {
    return Container(
      width: 26,
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFFCBD5E1) : const Color(0xFFF8FAFC),
        border: const Border(right: BorderSide(color: Color(0xFFCBD5E1))),
      ),
      child: Text(
        rowNum,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? FontWeight.w900 : FontWeight.w600,
          color: isHeader ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildColumnHeaderCell(String title, {required int flex, bool isRequired = false}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isRequired ? FontWeight.w900 : FontWeight.w700,
                  color: isRequired ? _maroon : const Color(0xFF475569),
                ),
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 2),
              const Text(
                '*',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _maroon),
              ),
            ],
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
}
