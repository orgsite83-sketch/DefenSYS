import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/screens/web/admin/widgets/template_blueprint_models.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
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
  String _selectedSectionFilter = 'all';
  String _selectedAdviserFilter = 'all';
  String _groupBy = 'none'; // 'none' | 'section' | 'adviser'
  final Set<String> _customSections = {};

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

  Widget _buildToolbarDropdown({
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((it) => it.value == value) ? value : items.first.value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _muted),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: DefensysUi.textDark,
          ),
          items: items,
          onChanged: widget.state.isSaving ? null : onChanged,
        ),
      ),
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
                        value: ['all', 'with_adviser', 'without_adviser']
                                .contains(widget.selectedBulkAdviserFilter.toLowerCase())
                            ? widget.selectedBulkAdviserFilter.toLowerCase()
                            : 'all',
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

    final uniqueSections = <String>{};
    for (final r in widget.parsedBulkRows) {
      final s = (r['section'] ?? '').toString().trim();
      if (s.isNotEmpty) uniqueSections.add(s);
    }
    uniqueSections.addAll(_customSections);
    final sortedSections = uniqueSections.toList()..sort();

    final uniqueAdvisers = <String>{};
    for (final r in widget.parsedBulkRows) {
      final a = (r['adviser_name'] ?? r['adviser_id'] ?? '').toString().trim();
      if (a.isNotEmpty) uniqueAdvisers.add(a);
    }
    final sortedAdvisers = uniqueAdvisers.toList()..sort();

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
                if (widget.parsedBulkRows.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    key: const ValueKey('top_import_ready_teams_btn'),
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
                        : const Icon(Icons.cloud_upload_rounded, size: 15),
                    label: Text(
                      readyCount > 0 ? 'Import $readyCount Ready' : 'Import Ready',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
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
                      if (sortedSections.isNotEmpty) ...[
                        _buildTeamStatDivider(),
                        _buildTeamStatItem(
                          sortedSections.length == 1 ? 'Section' : 'Sections',
                          sortedSections.length,
                          const Color(0xFF0284C7),
                        ),
                      ],
                      if (widget.isCapstoneAdmin && sortedAdvisers.isNotEmpty) ...[
                        _buildTeamStatDivider(),
                        _buildTeamStatItem(
                          sortedAdvisers.length == 1 ? 'Adviser' : 'Advisers',
                          sortedAdvisers.length,
                          const Color(0xFF7C3AED),
                        ),
                      ],
                      _buildTeamStatDivider(),
                      _buildTeamStatItem('Total Staged', totalRows, const Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
            ),

          // Search + Filter Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
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
                        hintText: 'Search by team, project, section, adviser...',
                        hintStyle: const TextStyle(fontSize: 12, color: _muted),
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
                if (sortedSections.isNotEmpty)
                  _buildToolbarDropdown(
                    icon: Icons.meeting_room_outlined,
                    value: _selectedSectionFilter,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Sections')),
                      ...sortedSections.map((sec) {
                        final count = widget.parsedBulkRows
                            .where((r) => (r['section'] ?? '').toString().trim() == sec)
                            .length;
                        return DropdownMenuItem(value: sec, child: Text('Sec: $sec ($count)'));
                      }),
                      if (widget.parsedBulkRows.any((r) => (r['section'] ?? '').toString().trim().isEmpty))
                        DropdownMenuItem(
                          value: '_none_',
                          child: Text(
                            'No Section (${widget.parsedBulkRows.where((r) => (r['section'] ?? '').toString().trim().isEmpty).length})',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedSectionFilter = v);
                    },
                  ),
                if (widget.isCapstoneAdmin || sortedAdvisers.isNotEmpty)
                  _buildToolbarDropdown(
                    icon: Icons.supervisor_account_outlined,
                    value: _selectedAdviserFilter,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Advisers')),
                      DropdownMenuItem(
                        value: 'with_adviser',
                        child: Text(
                          'With Adviser (${widget.parsedBulkRows.where((r) => (r['adviser_name'] ?? r['adviser_id'] ?? '').toString().trim().isNotEmpty).length})',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'without_adviser',
                        child: Text(
                          'Without Adviser (${widget.parsedBulkRows.where((r) => (r['adviser_name'] ?? r['adviser_id'] ?? '').toString().trim().isEmpty).length})',
                        ),
                      ),
                      ...sortedAdvisers.map((adv) {
                        final count = widget.parsedBulkRows
                            .where((r) => (r['adviser_name'] ?? r['adviser_id'] ?? '').toString().trim() == adv)
                            .length;
                        return DropdownMenuItem(
                          value: adv,
                          child: Text('$adv ($count)', overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedAdviserFilter = v);
                    },
                  ),
                _buildToolbarDropdown(
                  icon: Icons.view_agenda_outlined,
                  value: _groupBy,
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('View: Flat List')),
                    DropdownMenuItem(value: 'section', child: Text('Group: By Section')),
                    DropdownMenuItem(value: 'adviser', child: Text('Group: By Adviser')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _groupBy = v);
                  },
                ),
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
                    sectionFilter: _selectedSectionFilter,
                    adviserFilter: _selectedAdviserFilter,
                    groupBy: _groupBy,
                    onRowChanged: widget.onScheduleRowPreview,
                    onDeleteRow: widget.onDeleteBulkRow,
                    onAddRow: widget.onAddBulkRow,
                    adviserOptions: widget.state.advisers,
                    sectionOptions: sortedSections,
                    studentOptions: widget.state.students,
                    onSectionAdded: (sec) => setState(() => _customSections.add(sec)),
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
    showDialog(
      context: context,
      builder: (ctx) {
        final blueprints = teamGroupingBlueprintsFor(isCapstone: isCapstone);
        final bp = blueprints.first;

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1350, maxHeight: 850),
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
                              'Target Term: $activeSemLabel • Standardized unified team roster blueprint',
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
                              ? 'Official Unified Team Roster. Supports both Different Systems (Independent Projects) and Single Shared Systems (Modules) under one standardized 5-column schema.'
                              : 'Official Unified PIT Team Roster. Supports both Different Systems (Independent Projects) and Single Shared Systems (Modules) under one standardized 5-column schema.',
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
                          'Unified Standard',
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

                // Scrollable Content (Unified Side-by-Side: Different & Shared System)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildSampleTeamSheetPreview(
                      isCapstone: isCapstone,
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
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () async {
                                final xlsxBytes = generateOfficialTeamRosterExcelBytes(
                                  isCapstone: widget.isCapstoneAdmin,
                                );
                                final xlsxFilename = bp.filename.replaceAll('.csv', '.xlsx');
                                await downloadBinaryFile(
                                  filename: xlsxFilename,
                                  bytes: xlsxBytes,
                                  mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                );
                                if (context.mounted) {
                                  showSuccessToast(
                                    context,
                                    'Sample ${bp.shortLabel} Excel template (.xlsx) downloaded.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.table_chart_rounded, size: 15),
                              label: const Text('Download Excel Template (.xlsx)'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF15803D),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
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
                      ),
                      const SizedBox(width: 12),
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
  }

  Widget _buildSampleTeamSheetPreview({
    required bool isCapstone,
  }) {
    final blueprints = teamGroupingBlueprintsFor(isCapstone: isCapstone);
    final bp = blueprints.first;

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

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1285,
              child: _buildUnifiedSingleSpreadsheetPreview(isCapstone: isCapstone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndependent5ColumnPreview() {
    const rowH = 32.0;
    const teamH = rowH * 4 + 3.0; // 131.0
    const sec4AH = teamH * 3 + 2.0; // 395.0 (3 teams: SkyLedger, BioPulse, SafeCity)
    const sec4BH = teamH; // 131.0 (1 team: CodeLearners)
    const totalH = sec4AH + 1.0 + sec4BH; // 527.0 (all 16 student rows)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row (Row 1)
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell('1', isHeader: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Capstone Project', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Section', flex: 2, isRequired: true),
              _buildColumnHeaderCell('Adviser', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Team Members', flex: 4, isRequired: true),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFCBD5E1)),

        // 16-Row Data Matrix matching Picture 2
        SizedBox(
          height: totalH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gutter Column (Rows 2 to 17)
              SizedBox(
                width: 26,
                height: totalH,
                child: Column(
                  children: List.generate(16, (index) {
                    final rowNum = (index + 2).toString();
                    return SizedBox(
                      height: index < 15 ? rowH + 1.0 : rowH,
                      child: Column(
                        children: [
                          SizedBox(height: rowH, child: _buildGutterCell(rowNum)),
                          if (index < 15) const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        ],
                      ),
                    );
                  }),
                ),
              ),

              // Columns A & B: Team Name & Capstone Project (flex: 3 + 4 = 7)
              // Each team occupies 1 single top cell, with rows 2-4 blank unmerged!
              Expanded(
                flex: 7,
                child: SizedBox(
                  height: totalH,
                  child: Column(
                    children: [
                      // Team 1: Team SkyLedger (Rows 2 to 5)
                      SizedBox(
                        height: teamH,
                        child: _buildUnmergedTeamAndProject4Rows(
                          teamName: 'Team SkyLedger',
                          projectName: 'Alumni Career Tracker',
                          rowH: rowH,
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 2: Team BioPulse (Rows 6 to 9)
                      SizedBox(
                        height: teamH,
                        child: _buildUnmergedTeamAndProject4Rows(
                          teamName: 'Team BioPulse',
                          projectName: 'AI-Powered Patient Vital Triage & Disease Predictor',
                          rowH: rowH,
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 3: Team SafeCity (Rows 10 to 13)
                      SizedBox(
                        height: teamH,
                        child: _buildUnmergedTeamAndProject4Rows(
                          teamName: 'Team SafeCity',
                          projectName: 'Smart City IoT Infrastructure & Asset Sentinel',
                          rowH: rowH,
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 4: Team CodeLearners (Rows 14 to 17)
                      SizedBox(
                        height: teamH,
                        child: _buildUnmergedTeamAndProject4Rows(
                          teamName: 'Team CodeLearners',
                          projectName: 'Campus Event Hub',
                          rowH: rowH,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Column C: Section (flex: 2)
              // BSIT 4A spans 12 rows (Teams 1, 2, 3), BSIT 4B spans 4 rows (Team 4)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: totalH,
                  child: Column(
                    children: [
                      // BSIT 4A (1 big merged cell spanning rows 2 to 13)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: const Text(
                            'BSIT 4A',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // BSIT 4B (1 big merged cell spanning rows 14 to 17)
                      SizedBox(
                        height: sec4BH,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: const Text(
                            'BSIT 4B',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Column D: Adviser (flex: 3) -> 1 BIG MERGED CELL spanning all 16 rows!
              Expanded(
                flex: 3,
                child: Container(
                  height: totalH,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  child: const Text(
                    'Prof. Alex Santos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),

              // Column E: Team Members (flex: 4) -> 16 member rows matching Picture 2
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: totalH,
                  child: Column(
                    children: [
                      // Team 1 members
                      ..._buildMemberRows([
                        'Marcus Villar',
                        'Patricia Ong',
                        'Ethan Salazar',
                        'Zoe Castillo',
                      ], rowHeight: rowH),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 2 members
                      ..._buildMemberRows([
                        'Ryan Torres',
                        'Nina Villanueva',
                        'Diego Garcia',
                        'Patricia Ramos',
                      ], rowHeight: rowH),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 3 members
                      ..._buildMemberRows([
                        'Carlos Bautista',
                        'Sophia Santos',
                        'Miguel Cruz',
                        'Isabella Alcantara',
                      ], rowHeight: rowH),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      // Team 4 members
                      ..._buildMemberRows([
                        'Kevin Villanueva',
                        'Bea Castro',
                        'Christian Lim',
                        'Joshua Navarro',
                      ], rowHeight: rowH),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnmergedTeamAndProject4Rows({
    required String teamName,
    required String projectName,
    double rowH = 32.0,
  }) {
    return Column(
      children: [
        // Row 1: Values
        SizedBox(
          height: rowH,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: const Color(0xFFE2E8F0)),
              Expanded(
                flex: 4,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        // Rows 2, 3, 4: Blank cells with cell dividers
        for (var r = 0; r < 3; r++) ...[
          SizedBox(
            height: rowH,
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox.shrink()),
                Container(width: 1, color: const Color(0xFFE2E8F0)),
                const Expanded(flex: 4, child: SizedBox.shrink()),
              ],
            ),
          ),
          if (r < 2) const Divider(height: 1, color: Color(0xFFE2E8F0)),
        ],
      ],
    );
  }

  List<Widget> _buildMemberRows(List<String> members, {double rowHeight = 32.0}) {
    final list = <Widget>[];
    for (var i = 0; i < members.length; i++) {
      final isLeader = i == 0;
      final name = members[i];
      list.add(
        SizedBox(
          height: rowHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 10.5,
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
                    ),
                    child: const Text(
                      'LEADER',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: _maroon,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (i < members.length - 1) {
        list.add(const Divider(height: 1, color: Color(0xFFF1F5F9)));
      }
    }
    return list;
  }

  static const _capstone4ATeams = [
    (
      team: 'Team SkyLedger',
      item: 'Alumni Career Tracker',
      members: ['Marcus Villar', 'Patricia Ong', 'Ethan Salazar', 'Zoe Castillo'],
    ),
    (
      team: 'Team BioPulse',
      item: 'AI-Powered Vital Triage & Disease Predictor',
      members: ['Ryan Torres', 'Nina Villanueva', 'Diego Garcia', 'Patricia Ramos'],
    ),
    (
      team: 'Team SafeCity',
      item: 'Smart City IoT Infrastructure & Asset Sentinel',
      members: ['Carlos Bautista', 'Sophia Santos', 'Miguel Cruz', 'Isabella Alcantara'],
    ),
    (
      team: 'Team CodeLearners',
      item: 'Campus Event Hub',
      members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
    ),
    (
      team: 'Team CyberGuard',
      item: 'Automated Penetration Testing & Threat Hunter',
      members: ['Gabriel Mendoza', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
    ),
    (
      team: 'Team AgriSense',
      item: 'Smart Agriculture Crop & Soil Monitoring',
      members: ['Adrian Valdez', 'Stephanie Yap', 'Jerome De Leon', 'Camille Roxas'],
    ),
    (
      team: 'Team EduTrack',
      item: 'Student Performance Analytics & Early Warning',
      members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
    ),
    (
      team: 'Team EcoRoute',
      item: 'Intelligent Fleet Logistics & Route Optimizer',
      members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
    ),
  ];

  static const _capstone4BTeams = [
    (
      team: 'Team MedRecord',
      item: 'Patient Records',
      members: ['Lucas Hernandez', 'Camille Bernardo', 'Danilo Gutierrez', 'Andrea Salazar'],
    ),
    (
      team: 'Team MedBilling',
      item: 'Billing',
      members: ['Enzo Morales', 'Valerie Cruz', 'Paolo Mercado', 'Bianca Reyes'],
    ),
    (
      team: 'Team MedSchedule',
      item: 'Appointments',
      members: ['Giancarlo Diaz', 'Rachelle Santos', 'Marco Dela Cruz', 'Hannah Ocampo'],
    ),
    (
      team: 'Team MedPharma',
      item: 'Pharmacy',
      members: ['Leandro Garcia', 'Kirsten Gomez', 'Jerome Pineda', 'Monica Castro'],
    ),
    (
      team: 'Team MedTriage',
      item: 'Triage',
      members: ['Timothy Aguilar', 'Clarisse Domingo', 'Nathaniel Pascual', 'Fiona Soriano'],
    ),
    (
      team: 'Team MedLab',
      item: 'Laboratory',
      members: ['Oliver Tan', 'Kaye Tolentino', 'Derrick Miranda', 'Althea Fernandez'],
    ),
    (
      team: 'Team MedInventory',
      item: 'Inventory',
      members: ['Justin Valenzuela', 'Alyssa Romero', 'Vincent Marquez', 'Danica Sotto'],
    ),
    (
      team: 'Team MedWards',
      item: 'Wards',
      members: ['Gabriel Tan', 'Chloe Soriano', 'Pauline Mercado', 'Rafael Pascual'],
    ),
  ];

  static const _pit2ATeams = [
    (
      team: 'Group 1',
      item: 'Smart Campus Navigation System',
      members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
    ),
    (
      team: 'Group 2',
      item: 'Automated Library Portal',
      members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
    ),
    (
      team: 'Group 3',
      item: 'Alumni Career Tracker',
      members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
    ),
    (
      team: 'Group 4',
      item: 'Event Booking System',
      members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
    ),
    (
      team: 'Group 5',
      item: 'Hostel Reservation Portal',
      members: ['Cedric Valdez', 'Leila Soriano', 'Paolo Ramos', 'Diana Cruz'],
    ),
    (
      team: 'Group 6',
      item: 'Campus Lost & Found Sentinel',
      members: ['Anthony Lim', 'Katrina Santos', 'Justin Ocampo', 'Bianca Reyes'],
    ),
    (
      team: 'Group 7',
      item: 'Student Tutoring Exchange',
      members: ['Patrick Mendoza', 'Christine Torres', 'Lorenzo Garcia', 'Bea Bautista'],
    ),
    (
      team: 'Group 8',
      item: 'Green Campus Energy Tracker',
      members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
    ),
  ];

  static const _pit2BTeams = [
    (
      team: 'Group 1',
      item: 'Site Module',
      members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
    ),
    (
      team: 'Group 2',
      item: 'Arcu Module',
      members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
    ),
    (
      team: 'Group 3',
      item: 'Events Module',
      members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
    ),
    (
      team: 'Group 4',
      item: 'Membership Module',
      members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
    ),
    (
      team: 'Group 5',
      item: 'Finance Module',
      members: ['Cedric Valdez', 'Leila Soriano', 'Paolo Ramos', 'Diana Cruz'],
    ),
    (
      team: 'Group 6',
      item: 'Elections Module',
      members: ['Anthony Lim', 'Katrina Santos', 'Justin Ocampo', 'Bianca Reyes'],
    ),
    (
      team: 'Group 7',
      item: 'Publication Module',
      members: ['Patrick Mendoza', 'Christine Torres', 'Lorenzo Garcia', 'Bea Bautista'],
    ),
    (
      team: 'Group 8',
      item: 'Certificates Module',
      members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
    ),
  ];

  Widget _buildUnifiedSingleSpreadsheetPreview({required bool isCapstone}) {
    const rowH = 26.0;
    const colLettersH = 22.0;

    const gutterW = 34.0;
    const colAW = 115.0; // Team Name
    const colBW = 180.0; // Capstone Project
    const colCW = 68.0;  // Section
    const colDW = 125.0; // Adviser
    const colEW = 140.0; // Team Members
    const colFW = 28.0;  // Empty Column F Separator
    const colGW = 115.0; // Team Name
    const colHW = 140.0; // Module
    const colIW = 68.0;  // Section
    const colJW = 130.0; // Adviser
    const colKW = 140.0; // Team Members

    const totalTableWidth = gutterW +
        colAW +
        colBW +
        colCW +
        colDW +
        colEW +
        colFW +
        colGW +
        colHW +
        colIW +
        colJW +
        colKW; // 1285.0

    final leftTeams = isCapstone ? _capstone4ATeams : _pit2ATeams;
    final rightTeams = isCapstone ? _capstone4BTeams : _pit2BTeams;

    final leftSectionName = isCapstone ? 'BSIT-4A' : 'BSIT-2A';
    final rightSectionName = isCapstone ? 'BSIT-4B' : 'BSIT-2B';
    final systemName = isCapstone ? 'Hospital Management System' : 'Societree';
    final projectManager = 'Juan Dela Cruz';
    final projectColTitle = isCapstone ? 'Capstone Project *' : 'PIT Project *';
    final adviserColTitle = isCapstone ? 'Adviser *' : 'Instructor *';

    return Container(
      width: totalTableWidth + 2,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Excel Column Letter Header Row (A to K)
          Container(
            color: const Color(0xFFF1F5F9),
            child: Row(
              children: [
                _buildExcelHeaderCell('', width: gutterW, height: colLettersH),
                _buildExcelHeaderCell('A', width: colAW, height: colLettersH),
                _buildExcelHeaderCell('B', width: colBW, height: colLettersH),
                _buildExcelHeaderCell('C', width: colCW, height: colLettersH),
                _buildExcelHeaderCell('D', width: colDW, height: colLettersH),
                _buildExcelHeaderCell('E', width: colEW, height: colLettersH),
                _buildExcelHeaderCell('F', width: colFW, height: colLettersH),
                _buildExcelHeaderCell('G', width: colGW, height: colLettersH),
                _buildExcelHeaderCell('H', width: colHW, height: colLettersH),
                _buildExcelHeaderCell('I', width: colIW, height: colLettersH),
                _buildExcelHeaderCell('J', width: colJW, height: colLettersH),
                _buildExcelHeaderCell('K', width: colKW, height: colLettersH),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // 35 Data Rows
          SizedBox(
            height: rowH * 35,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gutter Column: Row numbers 1 to 35
                SizedBox(
                  width: gutterW,
                  child: Column(
                    children: List.generate(35, (index) {
                      return _buildExcelGutterCell('${index + 1}', width: gutterW, height: rowH);
                    }),
                  ),
                ),

                // Columns A & B: Left Teams (Team Name & Project)
                SizedBox(
                  width: colAW + colBW,
                  child: Column(
                    children: [
                      // Row 1: Header
                      SizedBox(
                        height: rowH,
                        child: Row(
                          children: [
                            _buildExcelTableHeadCell('Team Name *', width: colAW, height: rowH),
                            _buildExcelTableHeadCell(projectColTitle, width: colBW, height: rowH),
                          ],
                        ),
                      ),
                      // Rows 2 to 33: 8 Teams (4 rows per team)
                      for (var t = 0; t < leftTeams.length; t++)
                        _buildTeamAndProjectUnmergedCells(
                          teamName: leftTeams[t].team,
                          projectName: leftTeams[t].item,
                          colAW: colAW,
                          colBW: colBW,
                          rowH: rowH,
                        ),
                      // Rows 34 & 35: Empty padding rows
                      for (var r = 0; r < 2; r++)
                        SizedBox(
                          height: rowH,
                          child: Row(
                            children: [
                              _buildExcelEmptyCell(width: colAW, height: rowH),
                              _buildExcelEmptyCell(width: colBW, height: rowH),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Column C: Section (BSIT-4A merged across rows 2 to 33)
                SizedBox(
                  width: colCW,
                  child: Column(
                    children: [
                      _buildExcelTableHeadCell('Section *', width: colCW, height: rowH),
                      _buildExcelMergedCell(
                        text: leftSectionName,
                        width: colCW,
                        height: rowH * 32,
                      ),
                      _buildExcelEmptyCell(width: colCW, height: rowH * 2),
                    ],
                  ),
                ),

                // Column D: Adviser (Prof. Alex Santos [rows 2-17], Prof. Elena Ramos [rows 18-33])
                SizedBox(
                  width: colDW,
                  child: Column(
                    children: [
                      _buildExcelTableHeadCell(adviserColTitle, width: colDW, height: rowH),
                      if (isCapstone) ...[
                        _buildExcelMergedCell(
                          text: 'Prof. Alex Santos',
                          width: colDW,
                          height: rowH * 16,
                        ),
                        _buildExcelMergedCell(
                          text: 'Prof. Elena Ramos',
                          width: colDW,
                          height: rowH * 16,
                        ),
                      ] else ...[
                        _buildExcelMergedCell(
                          text: 'Prof. Alex Santos',
                          width: colDW,
                          height: rowH * 32,
                        ),
                      ],
                      _buildExcelEmptyCell(width: colDW, height: rowH * 2),
                    ],
                  ),
                ),

                // Column E: Left Team Members (32 rows, 4 per team)
                SizedBox(
                  width: colEW,
                  child: Column(
                    children: [
                      _buildExcelTableHeadCell('Team Members *', width: colEW, height: rowH),
                      for (var t = 0; t < leftTeams.length; t++)
                        for (var m = 0; m < leftTeams[t].members.length; m++)
                          _buildExcelMemberCell(
                            name: leftTeams[t].members[m],
                            isLeader: m == 0,
                            width: colEW,
                            height: rowH,
                          ),
                      _buildExcelEmptyCell(width: colEW, height: rowH * 2),
                    ],
                  ),
                ),

                // Column F: Empty Separator Column
                SizedBox(
                  width: colFW,
                  child: Column(
                    children: List.generate(35, (index) {
                      return _buildExcelEmptyCell(width: colFW, height: rowH, isSeparator: true);
                    }),
                  ),
                ),

                // Columns G & H: Right Teams (System Name/PM metadata, Header, Teams & Modules)
                SizedBox(
                  width: colGW + colHW,
                  child: Column(
                    children: [
                      // Row 1: System Name
                      SizedBox(
                        height: rowH,
                        child: Row(
                          children: [
                            _buildExcelLabelCell('System Name', width: colGW, height: rowH),
                            _buildExcelValueCell(systemName, width: colHW, height: rowH),
                          ],
                        ),
                      ),
                      // Row 2: Project Manager
                      SizedBox(
                        height: rowH,
                        child: Row(
                          children: [
                            _buildExcelLabelCell('Project Manager', width: colGW, height: rowH),
                            _buildExcelValueCell(projectManager, width: colHW, height: rowH),
                          ],
                        ),
                      ),
                      // Row 3: Header Row
                      SizedBox(
                        height: rowH,
                        child: Row(
                          children: [
                            _buildExcelTableHeadCell('Team Name *', width: colGW, height: rowH),
                            _buildExcelTableHeadCell('Module *', width: colHW, height: rowH),
                          ],
                        ),
                      ),
                      // Rows 4 to 35: 8 Teams (4 rows per team)
                      for (var t = 0; t < rightTeams.length; t++)
                        _buildTeamAndProjectUnmergedCells(
                          teamName: rightTeams[t].team,
                          projectName: rightTeams[t].item,
                          colAW: colGW,
                          colBW: colHW,
                          rowH: rowH,
                        ),
                    ],
                  ),
                ),

                // Column I: Section (BSIT-4B merged across rows 4 to 35)
                SizedBox(
                  width: colIW,
                  child: Column(
                    children: [
                      _buildExcelEmptyCell(width: colIW, height: rowH * 2),
                      _buildExcelTableHeadCell('Section *', width: colIW, height: rowH),
                      _buildExcelMergedCell(
                        text: rightSectionName,
                        width: colIW,
                        height: rowH * 32,
                      ),
                    ],
                  ),
                ),

                // Column J: Adviser (Prof. Roberto Gomez [rows 4-19], Prof. Cynthia Morales [rows 20-35])
                SizedBox(
                  width: colJW,
                  child: Column(
                    children: [
                      _buildExcelEmptyCell(width: colJW, height: rowH * 2),
                      _buildExcelTableHeadCell(adviserColTitle, width: colJW, height: rowH),
                      if (isCapstone) ...[
                        _buildExcelMergedCell(
                          text: 'Prof. Roberto Gomez',
                          width: colJW,
                          height: rowH * 16,
                        ),
                        _buildExcelMergedCell(
                          text: 'Prof. Cynthia Morales',
                          width: colJW,
                          height: rowH * 16,
                        ),
                      ] else ...[
                        _buildExcelMergedCell(
                          text: 'Prof. Alex Santos',
                          width: colJW,
                          height: rowH * 32,
                        ),
                      ],
                    ],
                  ),
                ),

                // Column K: Right Team Members (32 rows, 4 per team)
                SizedBox(
                  width: colKW,
                  child: Column(
                    children: [
                      _buildExcelEmptyCell(width: colKW, height: rowH * 2),
                      _buildExcelTableHeadCell('Team Members *', width: colKW, height: rowH),
                      for (var t = 0; t < rightTeams.length; t++)
                        for (var m = 0; m < rightTeams[t].members.length; m++)
                          _buildExcelMemberCell(
                            name: rightTeams[t].members[m],
                            isLeader: m == 0,
                            width: colKW,
                            height: rowH,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Bottom Excel Sheet Tab Bar
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          left: BorderSide(color: Color(0xFFCBD5E1)),
                          right: BorderSide(color: Color(0xFFCBD5E1)),
                          top: BorderSide(color: Color(0xFF16A34A), width: 2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.table_chart_outlined, size: 12, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text(
                            isCapstone ? 'defensys_team_roster_template' : 'defensys_pit_team_roster_template',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.add, size: 15, color: Color(0xFF64748B)),
                  ],
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ready',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                    SizedBox(width: 16),
                    Text(
                      '100%',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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

  Widget _buildExcelHeaderCell(String text, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildExcelGutterCell(String text, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildExcelTableHeadCell(String text, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildExcelLabelCell(String text, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _buildExcelValueCell(String text, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildExcelEmptyCell(
      {required double width, required double height, bool isSeparator = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isSeparator ? const Color(0xFFF8FAFC) : Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
      ),
    );
  }

  Widget _buildExcelMergedCell({
    required String text,
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildExcelMemberCell({
    required String name,
    required bool isLeader,
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isLeader ? FontWeight.w800 : FontWeight.w500,
                color: isLeader ? _maroon : _ink,
              ),
            ),
          ),
          if (isLeader)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4E6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'LEADER',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: _maroon,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamAndProjectUnmergedCells({
    required String teamName,
    required String projectName,
    required double colAW,
    required double colBW,
    required double rowH,
  }) {
    return Column(
      children: [
        // Row 1 of team: values
        SizedBox(
          height: rowH,
          child: Row(
            children: [
              Container(
                width: colAW,
                height: rowH,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
                ),
                child: Text(
                  teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                width: colBW,
                height: rowH,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
                ),
                child: Text(
                  projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Rows 2, 3, 4 of team: empty unmerged cells
        for (var r = 0; r < 3; r++)
          SizedBox(
            height: rowH,
            child: Row(
              children: [
                _buildExcelEmptyCell(width: colAW, height: rowH),
                _buildExcelEmptyCell(width: colBW, height: rowH),
              ],
            ),
          ),
      ],
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
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
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
          Flexible(
            child: Text(
              'ADVISER: $adviserName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _maroon,
              ),
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
