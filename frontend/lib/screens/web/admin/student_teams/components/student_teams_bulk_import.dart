import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_action_menu.dart';
import 'package:defensys/widgets/team_import_format_guide.dart';
import 'package:defensys/widgets/team_import_review.dart';
import 'package:defensys/widgets/team_import_reference_corrections.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/utils/team_bulk_import_draft.dart';

import 'student_teams_toolbar.dart';
import '../../../../../navigation/admin_attention_context.dart';
import '../../../../../widgets/academic/admin_attention_students.dart';

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
    final savedLabel = MaterialLocalizations.of(
      context,
    ).formatShortDate(draft.savedAt);

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
          const Icon(
            Icons.pending_actions_rounded,
            color: DefensysUi.techBlue,
            size: 22,
          ),
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
    this.isPitInstructor = false,
    this.isPreviewLoading = false,
    this.fileImportError,
    this.onRetryPreview,
    this.onEventChanged,
    this.onOpenExistingTeam,
    this.attentionContext,
  });

  final StudentTeamsState state;
  final AdminAttentionContext? attentionContext;
  final bool isPitInstructor;
  final bool isCapstoneAdmin;
  final String? pitLeadYear;
  final List<Map<String, dynamic>> parsedBulkRows;
  final String bulkCsvDraft;
  final String selectedBulkAdviserFilter;
  final Map<String, dynamic>? bulkPreview;
  final bool isPreviewLoading;
  final String? fileImportError;
  final VoidCallback? onRetryPreview;
  final ValueChanged<String?>? onEventChanged;
  final ValueChanged<int>? onOpenExistingTeam;
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
  State<StudentTeamsBulkImportView> createState() =>
      _StudentTeamsBulkImportViewState();
}

class _StudentTeamsBulkImportViewState
    extends State<StudentTeamsBulkImportView> {
  static const Color _muted = DefensysUi.steelGrey;

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedSectionFilter = 'all';
  String _selectedAdviserFilter = 'all';
  String _groupBy = 'none'; // 'none' | 'section' | 'adviser'
  String _reviewFilter = 'all';
  final _reviewTable = GlobalKey<TeamBulkImportReviewTableState>();
  final Set<String> _customSections = {};

  List<Map<String, dynamic>> get _previewRows =>
      (widget.bulkPreview?['rows'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  int get _readyCount =>
      _previewRows.where((row) => row['ready'] == true).length;
  int get _pendingCount => (widget.parsedBulkRows.length - _previewRows.length)
      .clamp(0, widget.parsedBulkRows.length);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _facultyValue(Map<String, dynamic> row) {
    final reference =
        (widget.isCapstoneAdmin
                ? row['adviser_name'] ?? row['adviser_id'] ?? ''
                : row['instructor_name'] ?? '')
            .toString()
            .trim();
    final account = teamImportAccounts(
      widget.state.advisers,
    ).where((a) => teamImportAccountId(a) == reference).firstOrNull;
    return account == null
        ? reference
        : '${teamImportAccountName(account)} ($reference)';
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
    final task = widget.attentionContext;
    if (task != null &&
        (!task.valid ||
            (widget.isCapstoneAdmin &&
                !widget.state.isLoading &&
                !widget.state.canCreateCapstoneTeams) ||
            (widget.activeSemester != null &&
                widget.activeSemester!['id'] != task.semesterId))) {
      return DefensysShadcnScope(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShadButton.outline(
                onPressed: widget.onRequestClose,
                child: const Text('Back to Student Teams'),
              ),
              const SizedBox(height: 16),
              AdminAttentionStudents(context: task),
            ],
          ),
        ),
      );
    }
    return DefensysShadcnScope(
      maroonActions: true,
      neutralActionText: true,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _buildImport(context, constraints.maxWidth),
      ),
    );
  }

  Widget _reviewToolbar() => TeamImportValidationToolbar(
    rows: widget.parsedBulkRows,
    previewRows: _previewRows,
    filter: widget.showIssuesOnly ? 'issues' : _reviewFilter,
    checking: widget.isPreviewLoading,
    showRetainedValidation: true,
    embedded: true,
    onFilter: (value) {
      if (widget.state.isSaving) return;
      widget.onShowIssuesOnlyChanged(false);
      setState(() => _reviewFilter = value);
    },
    onFirstIssue: () {
      widget.onShowIssuesOnlyChanged(false);
      setState(() {
        _reviewFilter = 'all';
        _selectedSectionFilter = 'all';
        _selectedAdviserFilter = 'all';
        _searchCtrl.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reviewTable.currentState?.goToFirstIssue(),
      );
    },
  );

  Widget _buildImport(BuildContext context, double width) {
    final horizontalPadding = width < 720 ? 16.0 : 40.0;

    return PopScope(
      canPop: !widget.isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await widget.onRequestClose();
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('team_import_scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefensysPageHeader(
                    icon: Icons.groups_2_rounded,
                    title: 'Bulk Import Student Teams',
                    actionsBreakpoint: 900,
                    subtitle: widget.isCapstoneAdmin
                        ? 'Upload team spreadsheets, validate member details and advisers inline, then import ready teams into the active capstone term.'
                        : 'Import teams for all sections in your PIT year, including each section\'s instructor. Existing students are linked and blank section assignments are filled from the roster.',
                    actions: ShadButton.outline(
                      enabled: !widget.state.isSaving,
                      onPressed: () => widget.onRequestClose(),
                      leading: const Icon(LucideIcons.arrowLeft, size: 16),
                      child: Text(
                        widget.isPitInstructor
                            ? 'Back to Deliverables'
                            : 'Back to Teams',
                      ),
                    ),
                  ),
                  if (widget.state.error != null &&
                      widget.parsedBulkRows.isEmpty) ...[
                    const SizedBox(height: 14),
                    _notice(widget.state.error!, warning: true),
                  ],
                  if (widget.fileImportError != null &&
                      widget.parsedBulkRows.isEmpty) ...[
                    const SizedBox(height: 12),
                    _notice(widget.fileImportError!, warning: true),
                  ],
                  if (widget.state.message != null) ...[
                    const SizedBox(height: 14),
                    _notice(widget.state.message!),
                  ],
                  const SizedBox(height: 20),

                  if (!widget.isCapstoneAdmin) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'import-event-${widget.state.eventName ?? ''}',
                        ),
                        initialValue: widget.state.eventName ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Import roster for',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Unassigned roster'),
                          ),
                          for (final event in widget.state.pitEvents.where(
                            (e) =>
                                widget.pitLeadYear == null ||
                                e['year_level'] == widget.pitLeadYear,
                          ))
                            DropdownMenuItem(
                              value: '${event['event_name']}',
                              child: Text(
                                '${event['event_name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged:
                            widget.state.isSaving || widget.isPreviewLoading
                            ? null
                            : widget.onEventChanged,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Unassigned rosters are checked against existing PIT teams in this semester. '
                      'Choose a different event explicitly when creating another roster for the same students.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Top 2-Column Section: Left is Smart Format Guide, Right is Primary Upload Action
                  if (widget.attentionContext != null) ...[
                    AdminAttentionStudents(context: widget.attentionContext!),
                    const SizedBox(height: 20),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 960;
                      if (!isWide) {
                        return Column(
                          children: [
                            _buildTeamFormatCard(_getActiveSemLabel()),
                            const SizedBox(height: 18),
                            _buildTeamUploadCard(context),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildTeamFormatCard(_getActiveSemLabel()),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 6,
                            child: _buildTeamUploadCard(context),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildPreflightReviewCard(),
                ],
              ),
            ),
          ),
          if (widget.parsedBulkRows.isNotEmpty) _buildImportActionBar(context),
        ],
      ),
    );
  }

  Widget _headerPill(String text) {
    return ShadBadge.outline(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildToolbarDropdown({
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return ShadSelect<String>(
      key: ValueKey('import_filter_${icon.codePoint}_$value'),
      initialValue: items.any((it) => it.value == value)
          ? value
          : items.first.value,
      enabled: !widget.state.isSaving,
      minWidth: 150,
      maxWidth: 260,
      options: items.map(
        (item) => ShadOption(value: item.value!, child: item.child),
      ),
      selectedOptionBuilder: (context, selected) =>
          items.firstWhere((item) => item.value == selected).child,
      onChanged: onChanged,
    );
  }

  Widget _buildTeamFormatCard(String activeSemLabel) => TeamImportFormatGuide(
    isCapstone: widget.isCapstoneAdmin,
    instructorWorkspace: widget.isPitInstructor,
    contextLabel: activeSemLabel,
    section: widget.isCapstoneAdmin ? null : widget.section,
    onDownload: widget.state.isSaving ? null : widget.onDownloadTemplate,
  );

  Widget _buildTeamUploadCard(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final hasRows = widget.parsedBulkRows.isNotEmpty;
    final readyCount = _readyCount;

    return ShadCard(
      padding: EdgeInsets.zero,
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
                    color: hasRows ? const Color(0xFFDCFCE7) : colors.muted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasRows
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: colors.mutedForeground,
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasRows
                            ? '${widget.parsedBulkRows.length} team(s) staged • $readyCount ready to import'
                            : 'Supports official university CSV and XLSX formats',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (widget.isCapstoneAdmin) ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Adviser filter',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: ShadSelect<String>(
                      key: ValueKey(
                        'adviser-import-${widget.selectedBulkAdviserFilter}',
                      ),
                      initialValue:
                          const [
                            'all',
                            'with_adviser',
                            'without_adviser',
                          ].contains(
                            widget.selectedBulkAdviserFilter.toLowerCase(),
                          )
                          ? widget.selectedBulkAdviserFilter.toLowerCase()
                          : 'all',
                      enabled: !widget.state.isSaving,
                      options: const [
                        ShadOption(value: 'all', child: Text('All teams')),
                        ShadOption(
                          value: 'with_adviser',
                          child: Text('With adviser only'),
                        ),
                        ShadOption(
                          value: 'without_adviser',
                          child: Text('Without adviser only'),
                        ),
                      ],
                      selectedOptionBuilder: (context, value) => Text(
                        const {
                              'all': 'All teams',
                              'with_adviser': 'With adviser only',
                              'without_adviser': 'Without adviser only',
                            }[value] ??
                            'All teams',
                      ),
                      onChanged: widget.onAdviserFilterChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            TeamImportDropArea(
              onPick: widget.state.isSaving ? null : widget.onPickBulkCsvFile,
              teamCount: widget.parsedBulkRows.length,
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
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
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
    final previewRows = _previewRows;
    final totalRows = widget.parsedBulkRows.length;

    final uniqueSections = <String>{};
    for (final r in widget.parsedBulkRows) {
      final s = (r['section'] ?? '').toString().trim();
      if (s.isNotEmpty) uniqueSections.add(s);
    }
    uniqueSections.addAll(_customSections);
    final sortedSections = uniqueSections.toList()..sort();

    final uniqueAdvisers = <String>{};
    for (final r in widget.parsedBulkRows) {
      final a = _facultyValue(r);
      if (a.isNotEmpty) uniqueAdvisers.add(a);
    }
    final sortedAdvisers = uniqueAdvisers.toList()..sort();

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'Review teams',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                if (activeSemLabel.isNotEmpty) _headerPill(activeSemLabel),
              ],
            ),
          ),
          if (totalRows > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _reviewToolbar(),
            ),
          if (((widget.bulkPreview?['summary'] as Map?)?['concept_sections']
                      as Map?)
                  ?.isNotEmpty ==
              true)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (final entry
                      in ((widget.bulkPreview?['summary']
                                  as Map)['concept_sections']
                              as Map)
                          .entries)
                    Text(
                      '${entry.key}: ${entry.value['assigned']} assigned teams · ${entry.value['proposals']} teams requiring proposals',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                ],
              ),
            ),

          // Search + Filter Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ShadInput(
                    key: const ValueKey('team_import_search'),
                    controller: _searchCtrl,
                    enabled: !widget.state.isSaving,
                    onChanged: (_) => setState(() {}),
                    leading: const Icon(LucideIcons.search, size: 16),
                    placeholder: const Text(
                      'Search teams, projects or members',
                    ),
                    trailing: _searchCtrl.text.isEmpty
                        ? null
                        : ShadButton.ghost(
                            width: 24,
                            height: 24,
                            padding: EdgeInsets.zero,
                            onPressed: () => setState(_searchCtrl.clear),
                            child: const Icon(LucideIcons.x, size: 14),
                          ),
                  ),
                ),
                if (sortedSections.isNotEmpty)
                  _buildToolbarDropdown(
                    icon: Icons.meeting_room_outlined,
                    value: _selectedSectionFilter,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Sections'),
                      ),
                      ...sortedSections.map((sec) {
                        final count = widget.parsedBulkRows
                            .where(
                              (r) =>
                                  (r['section'] ?? '').toString().trim() == sec,
                            )
                            .length;
                        return DropdownMenuItem(
                          value: sec,
                          child: Text('Sec: $sec ($count)'),
                        );
                      }),
                      if (widget.parsedBulkRows.any(
                        (r) => (r['section'] ?? '').toString().trim().isEmpty,
                      ))
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
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'All ${widget.isCapstoneAdmin ? 'Advisers' : 'Instructors'}',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'with_adviser',
                        child: Text(
                          'With ${widget.isCapstoneAdmin ? 'Adviser' : 'Instructor'} (${widget.parsedBulkRows.where((r) => _facultyValue(r).isNotEmpty).length})',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'without_adviser',
                        child: Text(
                          'Without ${widget.isCapstoneAdmin ? 'Adviser' : 'Instructor'} (${widget.parsedBulkRows.where((r) => _facultyValue(r).isEmpty).length})',
                        ),
                      ),
                      ...sortedAdvisers.map((adv) {
                        final count = widget.parsedBulkRows
                            .where((r) => _facultyValue(r) == adv)
                            .length;
                        return DropdownMenuItem(
                          value: adv,
                          child: Text(
                            '$adv ($count)',
                            overflow: TextOverflow.ellipsis,
                          ),
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
                  items: [
                    const DropdownMenuItem(
                      value: 'none',
                      child: Text('View: Flat List'),
                    ),
                    DropdownMenuItem(
                      value: 'section',
                      child: Text('Group: By Section'),
                    ),
                    DropdownMenuItem(
                      value: 'adviser',
                      child: Text(
                        'Group: By ${widget.isCapstoneAdmin ? 'Adviser' : 'Instructor'}',
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _groupBy = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),

          // Content body
          if (widget.parsedBulkRows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.groups_2_outlined,
                      size: 38,
                      color: Color(0xFF98A2B3),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No Team Records Staged',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
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
                  TeamBulkImportReviewTable(
                    key: _reviewTable,
                    sectionSummaries: widget.isPreviewLoading
                        ? const []
                        : (widget.bulkPreview?['section_summaries'] as List? ??
                                  const [])
                              .map((s) => Map<String, dynamic>.from(s as Map))
                              .toList(),
                    statusFilter: _reviewFilter,
                    isValidating: widget.isPreviewLoading,
                    showRetainedValidation: true,
                    onOpenExistingTeam: widget.onOpenExistingTeam,
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
                    onSectionAdded: (sec) =>
                        setState(() => _customSections.add(sec)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Lives outside the scroll view so it reserves its own viewport space.
  Widget _buildImportActionBar(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final ready = _readyCount;
    final total = widget.parsedBulkRows.length;
    final failure =
        widget.fileImportError ?? widget.state.error ?? widget.templateWarning;
    final feedback =
        failure ??
        (widget.isPreviewLoading
            ? 'Validating teams\u2026'
            : _pendingCount > 0
            ? '$_pendingCount team${_pendingCount == 1 ? '' : 's'} not checked. Retry validation.'
            : null);
    final canImport =
        !widget.state.isSaving &&
        !widget.isPreviewLoading &&
        widget.fileImportError == null &&
        widget.templateWarning == null &&
        ready > 0;
    return Material(
      key: const ValueKey('team_import_action_bar'),
      color: colors.background,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              final summary = Text(
                '$ready of $total team${total == 1 ? '' : 's'} ready',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              );
              final importButton = ShadButton(
                key: const ValueKey('import_ready_teams_btn'),
                enabled: canImport,
                onPressed: canImport ? widget.onImportBulkTeams : null,
                leading: widget.state.isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.upload, size: 16),
                child: Text(
                  widget.state.isSaving
                      ? 'Importing\u2026'
                      : ready > 0
                      ? 'Import $ready ready team${ready == 1 ? '' : 's'}'
                      : 'Import ready teams',
                ),
              );
              final more = DefensysActionMenu(
                label: 'More import actions',
                enabled: !widget.state.isSaving,
                items: [
                  if (narrow && widget.onSaveDraft != null)
                    DefensysMenuItem(
                      label: 'Save draft',
                      icon: LucideIcons.save,
                      onPressed: widget.onSaveDraft,
                    ),
                  if (widget.templateWarning == null)
                    DefensysMenuItem(
                      label: 'Export CSV',
                      icon: LucideIcons.download,
                      onPressed: widget.onExportBulkCsv,
                    ),
                  DefensysMenuItem(
                    label: 'Cancel import',
                    icon: LucideIcons.x,
                    onPressed: () => widget.onRequestClose(),
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (!narrow && widget.onSaveDraft != null) ...[
                    ShadButton.outline(
                      enabled: !widget.state.isSaving,
                      onPressed: widget.onSaveDraft,
                      child: const Text('Save draft'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  more,
                  const SizedBox(width: 8),
                  if (narrow) Expanded(child: importButton) else importButton,
                ],
              );
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 16 : 40,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (feedback != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          feedback,
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 12,
                            color: failure != null
                                ? colors.destructive
                                : colors.mutedForeground,
                          ),
                        ),
                      ),
                      if (!widget.isPreviewLoading &&
                          widget.onRetryPreview != null &&
                          widget.templateWarning == null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            enabled: !widget.state.isSaving,
                            onPressed: widget.onRetryPreview,
                            child: const Text('Retry validation'),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (narrow) ...[
                      summary,
                      const SizedBox(height: 8),
                      actions,
                    ] else
                      Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 16),
                          actions,
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
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
