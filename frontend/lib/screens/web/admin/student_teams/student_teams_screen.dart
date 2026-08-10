import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/l10n/l10n_ext.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/team_bulk_import_csv.dart';
import 'package:defensys/utils/team_bulk_import_draft.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'components/student_teams_bulk_import.dart';
import 'components/student_teams_grid.dart';
import 'components/student_teams_toolbar.dart';
import 'dialogs/advisor_assignment_modal.dart';
import 'dialogs/create_team_modal.dart';

enum TeamListMode {
  capstoneAdmin,
  pitLead,
  pitInstructor,
}

class StudentTeamsScreen extends ConsumerStatefulWidget {
  const StudentTeamsScreen({
    super.key,
    this.mode = TeamListMode.capstoneAdmin,
    this.onOpenStudentRecords,
    this.initialBulkImport = false,
    this.pitYearLevel,
  });

  final TeamListMode mode;
  final VoidCallback? onOpenStudentRecords;
  final bool initialBulkImport;
  final String? pitYearLevel;

  @override
  ConsumerState<StudentTeamsScreen> createState() => _StudentTeamsScreenState();
}

class _StudentTeamsScreenState extends ConsumerState<StudentTeamsScreen> {
  final _searchController = TextEditingController();

  bool? _showBulkImport = false;
  String? _bulkCsv = '';
  String? _bulkAdviserFilter = 'all';
  Map<String, dynamic>? _bulkPreview;
  List<Map<String, dynamic>> _parsedBulkRows = [];
  bool _showIssuesOnly = false;
  TeamBulkImportDraft? _savedDraft;
  Timer? _draftSaveTimer;
  Timer? _rowPreviewTimer;
  String? _bulkImportSessionBaseline;
  String? _bulkImportPersistedSnapshot;
  String? _templateWarning;
  List<String> _csvColumns = [];
  String? _section;
  String? _systemName;
  String? _projectManager;

  bool get _isBulkImportVisible => _showBulkImport == true;
  String get _selectedBulkAdviserFilter => _bulkAdviserFilter ?? 'all';
  String get _csvDraft => _bulkCsv ?? '';

  bool get _isCapstoneAdmin => widget.mode == TeamListMode.capstoneAdmin;
  bool get _isPitLeadManager => widget.mode == TeamListMode.pitLead;
  bool get _isPitInstructor => widget.mode == TeamListMode.pitInstructor;

  bool get _pitTermIsAudit =>
      _isPitLeadManager && ref.read(studentTeamsProvider).operatingMode == 'audit';

  String _teamListScope = 'active';

  String? get _pitLeadYear {
    if (!_isPitLeadManager) return null;
    final faculty = ref.read(dashboardProvider('faculty')).data;
    final topLevel = faculty?['pit_lead_year']?.toString().trim();
    if (topLevel != null && topLevel.isNotEmpty) return topLevel;
    final roles = (faculty?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    final year = roles['pit_lead_year']?.toString().trim();
    return year != null && year.isNotEmpty ? year : null;
  }

  String _teamLevelFilter(StudentTeamsState state) {
    if (!_isCapstoneAdmin) return state.level;
    final level = state.level.trim();
    if (level.isEmpty || level == 'Capstone') return 'Capstone';
    return level;
  }

  bool _isPitContext(StudentTeamsState state) =>
      _isPitLeadManager ||
      _isPitInstructor ||
      (_isCapstoneAdmin && _teamLevelFilter(state) == 'PIT');

  void _deriveLevelOnRow(Map<String, dynamic> row) {
    applyDerivedLevelToRow(
      row,
      isCapstoneAdmin: _isCapstoneAdmin,
      pitLeadYear: _pitLeadYear,
    );
  }

  void _deriveLevelsOnRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      _deriveLevelOnRow(row);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBulkDraft();
      _fetchTeamsForCurrentRole();
      if (widget.initialBulkImport && mounted) {
        _openBulkImport();
      }
    });
  }

  void _openTeamDetailRoute(int teamId) {
    final route = (_isPitLeadManager || _isPitInstructor)
        ? FacultyRoutes.teamDetail(teamId)
        : AdminRoutes.teamDetail(teamId);
    context.push(route);
  }

  void _fetchTeamsForCurrentRole({String? scope}) {
    final initialLevel = _isCapstoneAdmin ? 'Capstone' : '';
    ref.read(studentTeamsProvider.notifier).fetchTeams(
          level: initialLevel,
          scope: (_isPitLeadManager || _isPitInstructor) ? (scope ?? _teamListScope) : null,
          yearLevel: widget.pitYearLevel,
        );
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _rowPreviewTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _canCreateCapstoneTeams(StudentTeamsState state) =>
      !_isCapstoneAdmin || state.canCreateCapstoneTeams;

  bool _canManageTeams(StudentTeamsState state) {
    if (_isPitInstructor) return false;
    if (_pitTermIsAudit || state.operatingMode == 'audit') return false;
    return _isPitLeadManager ||
        (_isCapstoneAdmin && _teamLevelFilter(state) == 'PIT') ||
        _canCreateCapstoneTeams(state);
  }

  bool _shouldBlockCapstoneCreate(StudentTeamsState state) =>
      _isCapstoneAdmin &&
      _teamLevelFilter(state) == 'Capstone' &&
      !state.canCreateCapstoneTeams;

  bool _canTapTeamActions(StudentTeamsState state) =>
      !state.isSaving &&
      (_canManageTeams(state) ||
          (_isCapstoneAdmin && _teamLevelFilter(state) == 'Capstone'));

  void _onBulkImportPressed(StudentTeamsState state) {
    if (_shouldBlockCapstoneCreate(state)) {
      showCapstoneCreationBlockedDialog(
        context: context,
        state: state,
        onOpenStudentRecords: widget.onOpenStudentRecords,
      );
      return;
    }
    if (!_canManageTeams(state) || state.isSaving) return;
    _openBulkImport();
  }

  void _onCreateTeamPressed(StudentTeamsState state) {
    if (_shouldBlockCapstoneCreate(state)) {
      showCapstoneCreationBlockedDialog(
        context: context,
        state: state,
        onOpenStudentRecords: widget.onOpenStudentRecords,
      );
      return;
    }
    if (!_canManageTeams(state) || state.isSaving) return;
    showCreateTeamModal(
      context: context,
      ref: ref,
      state: state,
      isCapstoneAdmin: _isCapstoneAdmin,
      isPitLeadManager: _isPitLeadManager,
      pitLeadYear: _pitLeadYear,
    );
  }

  Future<void> _downloadCsvTemplate() async {
    if (_isPitLeadManager) {
      final year = _pitLeadYear ?? '3rd Year';
      final content = sampleTeamCsvForYear(year, isCapstoneAdmin: false);
      final sectionPrefix = year.contains('2')
          ? 'Section,BSIT-2A\n'
          : year.contains('3')
              ? 'Section,BSIT-3A\n'
              : year.contains('4')
                  ? 'Section,BSIT-4A\n'
                  : 'Section,BSIT-1A\n';
      await downloadTextFile(
        filename: sampleTeamCsvFilenameForYear(year),
        content: '$sectionPrefix$content',
      );
      return;
    }

    await downloadTextFile(
      filename: 'defensys-official-capstone-template.csv',
      content: 'Section,BSIT-4A\n'
          'Team Name,Capstone Project,Adviser,Team Members\n'
          'Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,"VILLAR, Marcus"\n'
          ',,,"ONG, Patricia"\n'
          ',,,"SALAZAR, Ethan"\n'
          ',,,"CASTILLO, Zoe"\n',
    );
  }

  Future<void> _loadBulkDraft() async {
    final draft = await loadTeamBulkImportDraft();
    if (!mounted || draft == null) return;
    final rows = draft.rows.map((row) => Map<String, dynamic>.from(row)).toList();
    _deriveLevelsOnRows(rows);
    setState(() {
      _savedDraft = draft;
      _parsedBulkRows = rows;
      _bulkAdviserFilter = draft.adviserFilter;
      _bulkPreview = draft.preview;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
  }

  Future<void> _persistBulkDraft() async {
    if (_parsedBulkRows.isEmpty) {
      await clearTeamBulkImportDraft();
      if (mounted) setState(() => _savedDraft = null);
      return;
    }

    final draft = TeamBulkImportDraft(
      rows: _parsedBulkRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      preview: _bulkPreview,
      adviserFilter: _selectedBulkAdviserFilter,
      savedAt: DateTime.now(),
      issueCount: countPreviewIssues(_bulkPreview),
    );
    await saveTeamBulkImportDraft(draft);
    if (mounted) {
      setState(() => _savedDraft = draft);
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    }
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _persistBulkDraft();
    });
  }

  String _bulkImportSnapshot() {
    return jsonEncode({
      'rows': _parsedBulkRows,
      'filter': _selectedBulkAdviserFilter,
    });
  }

  void _captureBulkImportBaseline({bool persisted = false}) {
    final snap = _bulkImportSnapshot();
    _bulkImportSessionBaseline ??= snap;
    if (persisted) _bulkImportPersistedSnapshot = snap;
  }

  bool get _isBulkImportDirty {
    if (!_isBulkImportVisible || _parsedBulkRows.isEmpty) return false;
    if (_draftSaveTimer?.isActive ?? false) return true;
    final current = _bulkImportSnapshot();
    final baseline = _bulkImportPersistedSnapshot ?? _bulkImportSessionBaseline;
    return baseline != null && current != baseline;
  }

  Future<void> _requestCloseBulkImport() async {
    if (_isBulkImportDirty) {
      final leave = await showConfirmDialog(
        context,
        title: context.l10n.leaveBulkImportTitle,
        message: context.l10n.leaveBulkImportMessage,
        confirmLabel: context.l10n.saveAndLeave,
        cancelLabel: context.l10n.stay,
      );
      if (!leave || !mounted) return;
      _draftSaveTimer?.cancel();
      await _persistBulkDraft();
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    } else {
      _scheduleDraftSave();
    }
    if (!mounted) return;
    setState(() => _showBulkImport = false);
  }

  Future<void> _discardBulkDraftConfirmed() async {
    await clearTeamBulkImportDraft();
    if (!mounted) return;
    setState(() {
      _savedDraft = null;
      _parsedBulkRows = [];
      _bulkCsv = '';
      _bulkPreview = null;
      _templateWarning = null;
      _csvColumns = [];
      _section = null;
      _systemName = null;
      _projectManager = null;
    });
  }

  Future<void> _discardBulkDraft() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Discard draft?',
      message: 'Your saved bulk import draft will be permanently deleted.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    await _discardBulkDraftConfirmed();
  }

  void _openBulkImport({bool resumeDraft = false}) {
    _bulkImportSessionBaseline = null;
    _bulkImportPersistedSnapshot = null;
    setState(() {
      _templateWarning = null;
      _csvColumns = [];
    });
    if (resumeDraft && _savedDraft != null) {
      setState(() {
        _showBulkImport = true;
        _parsedBulkRows = _savedDraft!.rows
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _bulkAdviserFilter = _savedDraft!.adviserFilter;
        _bulkPreview = _savedDraft!.preview;
        _bulkCsv = rowsToTeamCsv(
          _parsedBulkRows,
          isCapstoneAdmin: _isCapstoneAdmin,
        );
        _csvColumns = bulkImportHeaderFor(isCapstoneAdmin: _isCapstoneAdmin).split(',');
      });
      _captureBulkImportBaseline(persisted: true);
      _refreshBulkPreview();
      return;
    }

    setState(() => _showBulkImport = true);
    _captureBulkImportBaseline();
  }

  void _applyParsedRows(ParsedBulkCsvResult result) {
    final normalized = result.rows.map((row) => Map<String, dynamic>.from(row)).toList();
    _deriveLevelsOnRows(normalized);
    setState(() {
      _parsedBulkRows = normalized;
      _section = result.section;
      _systemName = result.systemName;
      _projectManager = result.projectManager;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _scheduleDraftSave();
    _refreshBulkPreview();
  }

  Future<void> _pickBulkCsvFile() async {
    try {
      final csv = await pickCsvTextFile();
      if (!mounted || csv == null) return;

      final lines = csv
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      List<String> headers = [];
      if (lines.isNotEmpty) {
        headers = lines.first
            .split(',')
            .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
            .toList();

        String? warning;
        final isClientTemplate = (headers.contains('team name') || headers.contains('team_name')) &&
            (headers.contains('team members') || headers.contains('team_members') || headers.contains('members'));
        final recognizedHeaders = {
          'team_name', 'project_title', 'level', 'year_level', 'member_ids',
          'leader_id', 'adviser_id', 'adviser_name', 'team name', 'capstone project',
          'pit project', 'project', 'project title', 'adviser', 'team members', 'members',
        };
        final unrecognized = headers.where((h) => !recognizedHeaders.contains(h)).toList();

        if (unrecognized.isNotEmpty) {
          warning = 'Wrong template? Unrecognized column(s) detected: ${unrecognized.join(", ")}. Please use the correct CSV template.';
        } else if (!_isCapstoneAdmin) {
          if (!isClientTemplate) {
            if (headers.contains('adviser_id') || headers.contains('adviser_name') || headers.contains('year_level')) {
              warning = 'Wrong template? PIT import templates should not contain "adviser_name" or "year_level" columns. These will be ignored or cleared.';
            } else if (!headers.contains('member_ids') || !headers.contains('leader_id')) {
              warning = 'Wrong template? PIT import templates must contain "team_name", "project_title", "member_ids", and "leader_id" columns (or "Team Name" and "Team Members" for multi-row format).';
            }
          }
        } else {
          if (!isClientTemplate) {
            if ((!headers.contains('adviser_id') && !headers.contains('adviser_name')) || !headers.contains('year_level')) {
              warning = 'Wrong template? Capstone import templates should contain "year_level" and "adviser_name" columns (or "Team Name" and "Team Members" for client format).';
            }
          }
        }
        setState(() {
          _templateWarning = warning;
          _csvColumns = headers;
        });
      }

      final result = parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
      );
      if (result.rows.isEmpty) {
        _snack('Selected file is not a valid DefenSYS team CSV template.');
        return;
      }

      _applyParsedRows(result);
    } catch (e) {
      _snack('Could not read CSV file: $e');
    }
  }

  Future<void> _refreshBulkPreview() async {
    if (_parsedBulkRows.isEmpty) {
      final result = parseTeamBulkCsvWithContext(
        _csvDraft,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
      );
      if (result.rows.isEmpty) {
        setState(() => _bulkPreview = null);
        return;
      }
      final normalized = result.rows.map((row) => Map<String, dynamic>.from(row)).toList();
      _deriveLevelsOnRows(normalized);
      setState(() {
        _parsedBulkRows = normalized;
        _csvColumns = result.csvColumns;
        _section = result.section;
        _systemName = result.systemName;
        _projectManager = result.projectManager;
      });
    }

    _deriveLevelsOnRows(_parsedBulkRows);

    if (_parsedBulkRows.isEmpty) {
      setState(() => _bulkPreview = null);
      return;
    }

    final preview = await ref.read(studentTeamsProvider.notifier).bulkImportPreview(
      _parsedBulkRows,
      adviserFilter: _selectedBulkAdviserFilter,
      csvColumns: _csvColumns.isNotEmpty ? _csvColumns : null,
      section: _section,
      systemName: _systemName,
      projectManager: _projectManager,
    );
    if (!mounted) return;
    setState(() => _bulkPreview = preview);
    _scheduleDraftSave();
  }

  List<Map<String, dynamic>> _readyRowsForImport() {
    final previewRows = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (previewRows.isEmpty) return _parsedBulkRows;

    final readyNumbers = previewRows
        .where((item) => item['ready'] == true)
        .map((item) => item['row'] as int)
        .toSet();

    if (readyNumbers.isEmpty) return [];

    final ready = <Map<String, dynamic>>[];
    for (var index = 0; index < _parsedBulkRows.length; index++) {
      if (readyNumbers.contains(index + 1)) {
        ready.add(Map<String, dynamic>.from(_parsedBulkRows[index]));
      }
    }
    return ready;
  }

  Future<void> _importBulkTeams() async {
    if (_parsedBulkRows.isEmpty) {
      _snack('Upload a CSV or add rows to import.');
      return;
    }

    if (_bulkPreview == null) {
      await _refreshBulkPreview();
    }

    final rows = _readyRowsForImport();
    if (rows.isEmpty) {
      _snack('No ready rows to import. Fix issues in the table first.');
      return;
    }

    final result = await ref.read(studentTeamsProvider.notifier).bulkImport(
      rows,
      adviserFilter: _selectedBulkAdviserFilter,
      csvColumns: _csvColumns.isNotEmpty ? _csvColumns : null,
      section: _section,
      systemName: _systemName,
      projectManager: _projectManager,
    );

    if (!mounted || result == null) return;

    final created = _asInt(result['created_count']) ?? 0;
    final errorCount = _asInt(result['error_count']) ?? 0;
    final importedRows = result['imported_rows'] as List? ?? const [];

    if (errorCount > 0) {
      showImportResultDialog(context: context, result: result);
    }

    final remaining = trimRowsAfterImport(
      rows: _parsedBulkRows,
      importedRows: importedRows,
    );

    if (remaining.isEmpty) {
      await _discardBulkDraftConfirmed();
      if (!mounted) return;
      setState(() {
        _showBulkImport = false;
        _parsedBulkRows = [];
        _bulkCsv = '';
        _bulkPreview = null;
      });
      _snack('$created team${created == 1 ? '' : 's'} imported.');
      return;
    }

    setState(() {
      _parsedBulkRows = remaining;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    await _refreshBulkPreview();
    _snack(
      'Imported $created team${created == 1 ? '' : 's'}. '
      '${remaining.length} row${remaining.length == 1 ? '' : 's'} still need fixes — draft saved.',
    );
  }

  void _scheduleRowPreview(int index) {
    _scheduleDraftSave();
    _rowPreviewTimer?.cancel();
    _rowPreviewTimer = Timer(const Duration(milliseconds: 500), () {
      _preflightSingleRow(index);
    });
  }

  Future<void> _preflightSingleRow(int index) async {
    if (index < 0 || index >= _parsedBulkRows.length) return;
    final row = Map<String, dynamic>.from(_parsedBulkRows[index]);
    if (!_isCapstoneAdmin) _deriveLevelOnRow(row);
    _parsedBulkRows[index] = row;
    final preview = await ref.read(studentTeamsProvider.notifier).bulkImportPreview(
      [row],
      adviserFilter: _selectedBulkAdviserFilter,
    );
    if (!mounted || preview == null) return;
    final previewRows = (preview['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (previewRows.isEmpty) return;

    final previewRow = previewRows.first;
    if (_isCapstoneAdmin) {
      final inferredYear = previewRow['year_level']?.toString();
      final inferredLevel = previewRow['level']?.toString();
      if (inferredYear != null && inferredYear.isNotEmpty) row['year_level'] = inferredYear;
      if (inferredLevel != null && inferredLevel.isNotEmpty) row['level'] = inferredLevel;
      _parsedBulkRows[index] = row;
    }

    final existing = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final rowNumber = index + 1;
    final updated = [
      for (final item in existing)
        if (item['row'] != rowNumber) item,
      {...previewRows.first, 'row': rowNumber, 'sheet_row': rowNumber + 1},
    ];
    updated.sort((a, b) => (a['row'] as int).compareTo(b['row'] as int));

    final ready = updated.where((item) => item['ready'] == true).length;
    setState(() {
      _bulkPreview = {
        'rows': updated,
        'summary': {
          'total': _parsedBulkRows.length,
          'ready': ready,
          'with_adviser': updated.where((item) => item['adviser_status'] == 'valid').length,
          'without_adviser': updated.where((item) => item['adviser_status'] == 'none').length,
          'adviser_invalid': updated.where((item) {
            final status = item['adviser_status']?.toString() ?? '';
            return status != 'valid' && status != 'none';
          }).length,
        },
      };
    });
    _scheduleDraftSave();
  }

  void _addBulkRow() {
    final row = <String, dynamic>{
      'team_name': '',
      'project_title': '',
      if (!_isCapstoneAdmin) 'year_level': _pitLeadYear ?? '3rd Year',
      'member_ids': <String>[],
      'leader_id': '',
      'adviser_name': '',
    };
    _deriveLevelOnRow(row);
    setState(() {
      _parsedBulkRows = [..._parsedBulkRows, row];
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _refreshBulkPreview();
  }

  void _deleteBulkRow(int index) {
    setState(() {
      _parsedBulkRows = [
        for (var i = 0; i < _parsedBulkRows.length; i++)
          if (i != index) _parsedBulkRows[i],
      ];
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _refreshBulkPreview();
  }

  Future<void> _exportBulkCsv() async {
    if (_parsedBulkRows.isEmpty) return;
    await downloadTextFile(
      filename: 'defensys-team-import-draft.csv',
      content: rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    showInfoToast(context, message);
  }

  int _count(StudentTeamsState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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

  @override
  Widget build(BuildContext context) {
    if (_isPitLeadManager || _isPitInstructor) {
      ref.watch(dashboardProvider('faculty'));
    }
    final state = ref.watch(studentTeamsProvider);

    if (_isBulkImportVisible) {
      return StudentTeamsBulkImportView(
        state: state,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
        parsedBulkRows: _parsedBulkRows,
        bulkCsvDraft: _csvDraft,
        selectedBulkAdviserFilter: _selectedBulkAdviserFilter,
        bulkPreview: _bulkPreview,
        showIssuesOnly: _showIssuesOnly,
        templateWarning: _templateWarning,
        isBulkImportDirty: _isBulkImportDirty,
        section: _section,
        systemName: _systemName,
        projectManager: _projectManager,
        onRequestClose: _requestCloseBulkImport,
        onDownloadTemplate: _downloadCsvTemplate,
        onPickBulkCsvFile: _pickBulkCsvFile,
        onImportBulkTeams: _importBulkTeams,
        onExportBulkCsv: _exportBulkCsv,
        onScheduleRowPreview: _scheduleRowPreview,
        onDeleteBulkRow: _deleteBulkRow,
        onAddBulkRow: _addBulkRow,
        onAdviserFilterChanged: (value) {
          if (value == null) return;
          setState(() => _bulkAdviserFilter = value);
          _refreshBulkPreview();
          _scheduleDraftSave();
        },
        onShowIssuesOnlyChanged: (value) => setState(() => _showIssuesOnly = value),
      );
    }

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.groups_2_rounded,
            title: 'Student Teams',
            subtitle: _isCapstoneAdmin
                ? 'Manage capstone project teams, assign advisers, and review defense context.'
                : 'Manage PIT teams and PIT events setup for your assigned year level.',
            actions: StudentTeamsHeaderActions(
              isPitInstructor: _isPitInstructor,
              canTapActions: _canTapTeamActions(state),
              onDownloadTemplate: _downloadCsvTemplate,
              onBulkImport: () => _onBulkImportPressed(state),
              onCreateTeam: () => _onCreateTeamPressed(state),
            ),
          ),
          const SizedBox(height: 26),
          StudentTeamsSummaryCards(
            state: state,
            isPitContext: _isPitContext(state),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          if (state.operatingMessage != null &&
              state.operatingMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _notice(state.operatingMessage!, warning: _pitTermIsAudit),
          ],
          if (_isPitLeadManager || _isPitInstructor) ...[
            const SizedBox(height: 14),
            PitTeamScopeToggle(
              teamListScope: _teamListScope,
              isSaving: state.isSaving,
              onScopeChanged: (value) {
                if (value == null) return;
                setState(() => _teamListScope = value);
                _fetchTeamsForCurrentRole(scope: value);
              },
              onClear: () {
                _searchController.clear();
                setState(() => _teamListScope = 'active');
                ref.read(studentTeamsProvider.notifier).fetchTeams(
                      level: _isCapstoneAdmin ? 'Capstone' : '',
                      scope: (_isPitLeadManager || _isPitInstructor) ? 'active' : null,
                      search: '',
                    );
              },
            ),
          ],
          if (_savedDraft != null && !_isBulkImportVisible) ...[
            const SizedBox(height: 14),
            DraftResumeBanner(
              draft: _savedDraft!,
              onResume: () => _openBulkImport(resumeDraft: true),
              onDiscard: _discardBulkDraft,
            ),
          ],
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: DefensysUi.cardDecoration(),
            clipBehavior: Clip.none,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StudentTeamsSearchField(
                        controller: _searchController,
                        isSaving: state.isSaving,
                        isPitContext: _isPitContext(state),
                        onSubmitted: (value) {
                          ref.read(studentTeamsProvider.notifier).fetchTeams(search: value);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    StudentTeamsLevelFilter(
                      isPitLeadManager: _isPitLeadManager,
                      isPitInstructor: _isPitInstructor,
                      currentLevel: _teamLevelFilter(state),
                      isSaving: state.isSaving,
                      onLevelChanged: (value) {
                        ref.read(studentTeamsProvider.notifier).fetchTeams(level: value ?? '');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                state.isLoading
                    ? const SizedBox(
                        height: 150,
                        child: Center(child: CircularProgressIndicator(color: DefensysUi.primaryMaroon)),
                      )
                    : GroupedSectionView(
                        state: state,
                        isPit: _isPitContext(state),
                        searchQuery: _searchController.text,
                        onOpenTeamDetail: _openTeamDetailRoute,
                      ),
                const SizedBox(height: 18),
                Container(height: 1, color: const Color(0xFFE5E7EB)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Showing ${state.teams.length} of ${_count(state, 'filtered')} teams',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
}
