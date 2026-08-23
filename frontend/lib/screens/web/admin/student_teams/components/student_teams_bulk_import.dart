import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/services/student_teams_provider.dart';
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
              actions: OutlinedButton.icon(
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

  Widget _buildSpecChip(String label, Color bg, Color fg, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildSummaryBadge(String label, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamFormatCard(String activeSemLabel) {
    final isCapstone = widget.isCapstoneAdmin;

    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
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
                  child: const Icon(Icons.fact_check_outlined, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCapstone ? 'Official Capstone CSV & XLSX Format' : 'Official PIT CSV & XLSX Format',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Smart Spec Badges Group
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Detected Preamble Headers
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.auto_awesome_rounded, size: 14, color: _maroon),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auto-Detected Preamble Headers (Optional):',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildSpecChip('Class Section', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                                _buildSpecChip('System / Subject', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                                _buildSpecChip('Project Manager', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: _line),
                  const SizedBox(height: 10),

                  // Row 2: Required Team Table Columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.table_chart_outlined, size: 14, color: Color(0xFF475569)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Required Team Table Columns:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildSpecChip('Team Name *', const Color(0xFFF1F5F9), _ink, isBold: true),
                                _buildSpecChip(
                                  isCapstone ? 'Capstone Project *' : 'PIT Project *',
                                  const Color(0xFFF1F5F9),
                                  _ink,
                                  isBold: true,
                                ),
                                if (isCapstone)
                                  _buildSpecChip('Adviser', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                                _buildSpecChip('Team Members * (Leader First)', const Color(0xFFFEE2E2), _maroon, isBold: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Tip note
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: _muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Multi-row (1 team spanning rows) or pipe-separated member format accepted.',
                    style: TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons Row: View Blueprint Modal & Download Template
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showTeamSheetBlueprintModal(context, isCapstone: isCapstone, activeSemLabel: activeSemLabel),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('View Sheet Layout Blueprint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: BorderSide(color: _maroon.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
        constraints: const BoxConstraints(minHeight: 240),
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
                      border: Border.all(color: _line),
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
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
                          _buildSpecChip('CSV', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                          const SizedBox(width: 6),
                          _buildSpecChip('XLSX', const Color(0xFFF1F5F9), const Color(0xFF475569)),
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
    final summary = (widget.bulkPreview?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final previewRows = (widget.bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final readyCount = _asInt(summary['ready']) ?? 0;
    final totalRows = widget.parsedBulkRows.length;
    final issueCount = totalRows - readyCount;

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Toolbar Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _maroon.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(Icons.checklist_rtl_rounded, color: _maroon, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preflight Team Intake Review',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Verify student team assignments and resolve any roster or leadership issues before importing.',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildSummaryBadge(
                      'Ready: $readyCount',
                      const Color(0xFFDCFCE7),
                      _green,
                      icon: Icons.check_circle_rounded,
                    ),
                    const SizedBox(width: 8),
                    if (issueCount > 0) ...[
                      _buildSummaryBadge(
                        'Needs Fix: $issueCount',
                        const Color(0xFFFEF3C7),
                        const Color(0xFF92400E),
                        icon: Icons.warning_amber_rounded,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildSummaryBadge(
                      'Total: $totalRows',
                      const Color(0xFFEFF6FF),
                      const Color(0xFF1D4ED8),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _maroon, width: 1.5),
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
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: widget.showIssuesOnly ? const Color(0xFFDC2626) : _ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),

          // Content body
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

                if (widget.parsedBulkRows.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.groups_2_outlined, size: 38, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No Team Records Staged',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose or drop a team CSV / XLSX spreadsheet above to begin preflight review.',
                          style: TextStyle(fontSize: 12.5, color: _muted),
                        ),
                      ],
                    ),
                  )
                else
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
          const Divider(height: 1, color: _line),

          // Table Footer Actions Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text(
                  widget.parsedBulkRows.isNotEmpty
                      ? '$readyCount of $totalRows teams ready to import'
                      : '0 teams staged',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                buildPrimaryButton(
                  icon: Icons.system_update_alt_rounded,
                  label: widget.state.isSaving
                      ? 'Importing...'
                      : (readyCount > 0 ? 'Import $readyCount Ready Team${readyCount == 1 ? '' : 's'}' : 'Import Ready Teams'),
                  onTap: widget.state.isSaving || widget.parsedBulkRows.isEmpty || widget.templateWarning != null || readyCount == 0
                      ? null
                      : widget.onImportBulkTeams,
                ),
                const SizedBox(width: 10),
                if (widget.onSaveDraft != null && widget.parsedBulkRows.isNotEmpty) ...[
                  buildSecondaryButton(
                    icon: Icons.save_as_rounded,
                    label: 'Save draft',
                    onTap: widget.state.isSaving ? null : widget.onSaveDraft,
                  ),
                  const SizedBox(width: 10),
                ],
                if (widget.parsedBulkRows.isNotEmpty && widget.templateWarning == null) ...[
                  buildSecondaryButton(
                    icon: Icons.file_download_rounded,
                    label: 'Export CSV',
                    onTap: widget.onExportBulkCsv,
                  ),
                  const SizedBox(width: 10),
                ],
                buildSecondaryButton(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: widget.state.isSaving ? null : () => widget.onRequestClose(),
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
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
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
                              'Target Term: $activeSemLabel • Visual guide for multi-row and single-row formats',
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

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preamble Info Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                                    children: [
                                      TextSpan(
                                        text: 'Multi-Row & Leader Linking: ',
                                        style: TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      TextSpan(
                                        text: 'Each team can span multiple rows. The ',
                                      ),
                                      TextSpan(
                                        text: 'first member listed in each team ',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF78350F)),
                                      ),
                                      TextSpan(
                                        text: 'is automatically designated as Team Leader. Full names (Last, First or First Last) are resolved to student records automatically.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Spreadsheet Preview
                        _buildSampleTeamSheetPreview(isCapstone: isCapstone),
                      ],
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
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onDownloadTemplate();
                        },
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Download Sample Template (.csv)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _line),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
  }

  Widget _buildSampleTeamSheetPreview({required bool isCapstone}) {
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
                      const Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF16A34A)),
                      const SizedBox(width: 5),
                      Text(
                        isCapstone ? 'capstone_teams_template.csv' : 'pit_teams_template.csv',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildSpecChip('⭐ Multi-Row Linking & Leader Designation', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
              ],
            ),
          ),

          // Row 1: Column Headers
          Container(
            color: const Color(0xFFE2E8F0),
            child: Row(
              children: [
                _buildGutterCell('1', isHeader: true),
                _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
                _buildColumnHeaderCell(isCapstone ? 'Capstone Project' : 'PIT Project', flex: 4, isRequired: true),
                if (isCapstone)
                  _buildColumnHeaderCell('Adviser', flex: 3),
                _buildColumnHeaderCell('Team Members', flex: 4, isRequired: true),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Sample Rows for Team 1
          _buildSampleTeamRow(
            rowNum: '2',
            teamName: 'Team SkyLedger',
            project: 'Alumni Career Tracker',
            adviser: isCapstone ? 'Ricardo Fontanilla' : null,
            member: 'VILLAR, Marcus',
            isLeader: true,
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSampleTeamRow(
            rowNum: '3',
            teamName: '',
            project: '',
            adviser: isCapstone ? '' : null,
            member: 'ONG, Patricia',
            isLeader: false,
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSampleTeamRow(
            rowNum: '4',
            teamName: '',
            project: '',
            adviser: isCapstone ? '' : null,
            member: 'SALAZAR, Ethan',
            isLeader: false,
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSampleTeamRow(
            rowNum: '5',
            teamName: '',
            project: '',
            adviser: isCapstone ? '' : null,
            member: 'CASTILLO, Zoe',
            isLeader: false,
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Sample Rows for Team 2
          _buildSampleTeamRow(
            rowNum: '6',
            teamName: 'Team ByteBridge',
            project: 'Smart Campus Navigator',
            adviser: isCapstone ? 'Dr. Evelyn Morales' : null,
            member: 'REYES, Carlos',
            isLeader: true,
            isAlt: true,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSampleTeamRow(
            rowNum: '7',
            teamName: '',
            project: '',
            adviser: isCapstone ? '' : null,
            member: 'SANTOS, Maria',
            isLeader: false,
            isAlt: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSampleTeamRow({
    required String rowNum,
    required String teamName,
    required String project,
    String? adviser,
    required String member,
    required bool isLeader,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                project,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ),
          if (adviser != null)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  adviser,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LEADER',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: _maroon,
                        ),
                      ),
                    ),
                ],
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
