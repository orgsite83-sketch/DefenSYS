import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/l10n/l10n_ext.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/team_bulk_import_draft.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'components/student_teams_bulk_import.dart';
import 'components/student_teams_grid.dart';
import 'components/student_teams_stage_summary.dart';
import 'components/student_teams_toolbar.dart';
import 'dialogs/advisor_assignment_modal.dart';
import 'dialogs/create_team_modal.dart';
import 'dialogs/manage_sections_dialog.dart';
import '../../shared/team_deliverables/team_deliverables_screen.dart';
import '../../faculty/team_roster_screen.dart';

enum TeamListMode { capstoneAdmin, pitLead, pitInstructor }

class StudentTeamsScreen extends ConsumerStatefulWidget {
  const StudentTeamsScreen({
    super.key,
    this.mode = TeamListMode.capstoneAdmin,
    this.onOpenStudentRecords,
    this.initialBulkImport = false,
    this.pitYearLevel,
    this.pitSection,
  });

  final TeamListMode mode;
  final VoidCallback? onOpenStudentRecords;
  final bool initialBulkImport;
  final String? pitYearLevel;
  final String? pitSection;

  @override
  ConsumerState<StudentTeamsScreen> createState() => _StudentTeamsScreenState();
}

class _StudentTeamsScreenState extends ConsumerState<StudentTeamsScreen> {
  late final UnsavedChangesNotifier _unsavedNotifier;
  late final UnsavedChangesSaveDraftNotifier _unsavedDraftNotifier;
  final _searchController = TextEditingController();

  String _conceptFilter = 'all';
  bool? _showBulkImport = false;
  String? _bulkCsv = '';
  String? _bulkAdviserFilter = 'all';
  Map<String, dynamic>? _bulkPreview;
  int _bulkPreviewRevision = 0;
  bool _isBulkPreviewLoading = false;
  String? _fileImportError;
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
      _isPitLeadManager &&
      ref.read(studentTeamsProvider).operatingMode == 'audit';

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

  StudentTeamsState _scopedStateForDisplay(StudentTeamsState state) {
    if (!_isCapstoneAdmin) return state;
    final levelFilter = _teamLevelFilter(state);
    if (levelFilter == 'Capstone') {
      final capstoneTeams = state.teams.where((team) {
        final lvl = team['level']?.toString().toLowerCase() ?? '';
        if (lvl.isEmpty) return true;
        return lvl.contains('capstone');
      }).toList();
      final counts = Map<String, dynamic>.from(state.counts);
      counts['all'] = capstoneTeams.length;
      counts['filtered'] = capstoneTeams.length;
      counts['pending'] = capstoneTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'pending',
          )
          .length;
      counts['approved'] = capstoneTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'approved',
          )
          .length;
      counts['failed'] = capstoneTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'failed',
          )
          .length;
      counts['no_adviser'] = capstoneTeams.where((t) {
        final adv = t['adviser_name'] ?? t['adviser'];
        return adv == null || adv.toString().trim().isEmpty;
      }).length;
      return state.copyWith(teams: capstoneTeams, counts: counts);
    } else if (levelFilter == 'PIT') {
      final pitTeams = state.teams.where((team) {
        final lvl = team['level']?.toString().toLowerCase() ?? '';
        return lvl.contains('pit');
      }).toList();
      final counts = Map<String, dynamic>.from(state.counts);
      counts['all'] = pitTeams.length;
      counts['filtered'] = pitTeams.length;
      counts['pending'] = pitTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'pending',
          )
          .length;
      counts['approved'] = pitTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'approved',
          )
          .length;
      counts['failed'] = pitTeams
          .where(
            (t) => (t['status'] ?? '').toString().toLowerCase() == 'failed',
          )
          .length;
      counts['no_adviser'] = pitTeams.where((t) {
        final adv = t['adviser_name'] ?? t['adviser'];
        return adv == null || adv.toString().trim().isEmpty;
      }).length;
      return state.copyWith(teams: pitTeams, counts: counts);
    }
    return state;
  }

  void _deriveLevelOnRow(Map<String, dynamic> row) {
    applyDerivedLevelToRow(
      row,
      isCapstoneAdmin: _isCapstoneAdmin,
      pitLeadYear: _pitLeadYear ?? widget.pitYearLevel,
    );
  }

  void _deriveLevelsOnRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      _deriveLevelOnRow(row);
    }
  }

  StreamSubscription? _dropSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialBulkImport) {
      _showBulkImport = true;
      if (widget.pitSection != null && widget.pitSection!.isNotEmpty) {
        _section = widget.pitSection;
      }
    }
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);
    _dropSubscription = setupDropzoneListener((files) {
      if (mounted && _isBulkImportVisible) {
        _handleFilesDropped(files);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String? initialEvent;
      try {
        initialEvent = GoRouterState.of(context).uri.queryParameters['event'];
      } catch (_) {}
      _fetchTeamsForCurrentRole(event: initialEvent);
      await _loadBulkDraft();
      if (widget.initialBulkImport && mounted) {
        _openBulkImport(section: widget.pitSection);
      }
    });
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    _draftSaveTimer?.cancel();
    _rowPreviewTimer?.cancel();
    _searchController.dispose();
    releaseUnsavedChangesAfterFrame(_unsavedNotifier, _unsavedDraftNotifier);
    super.dispose();
  }

  void _openTeamDetailRoute(int teamId) {
    final route = (_isPitLeadManager || _isPitInstructor)
        ? FacultyRoutes.teamDetail(teamId)
        : AdminRoutes.teamDetail(teamId);
    context.push(route);
  }

  void _fetchTeamsForCurrentRole({String? scope, String? event}) {
    final initialLevel = _isCapstoneAdmin ? 'Capstone' : '';
    ref
        .read(studentTeamsProvider.notifier)
        .fetchTeams(
          workspace: _isPitInstructor ? 'instructor' : 'operations',
          level: initialLevel,
          scope: (_isPitLeadManager || _isPitInstructor)
              ? (scope ?? _teamListScope)
              : null,
          yearLevel: widget.pitYearLevel,
          section: widget.pitSection,
          eventName: event,
        );
  }

  bool _canCreateCapstoneTeams(StudentTeamsState state) =>
      !_isCapstoneAdmin || state.canCreateCapstoneTeams;

  bool _canManageTeams(StudentTeamsState state) {
    if (_pitTermIsAudit || state.operatingMode == 'audit') return false;
    if (_isPitInstructor) return true;
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
    showManualCreateTeamModal(
      context: context,
      ref: ref,
      state: state,
      isCapstoneAdmin: _isCapstoneAdmin,
      isPitLeadManager: _isPitLeadManager,
      pitLeadYear: _pitLeadYear,
    );
  }

  Future<void> _downloadCsvTemplate() async {
    final isCapstone = _isCapstoneAdmin;
    final bytes = generateOfficialTeamRosterExcelBytes(isCapstone: isCapstone,
      assignedSection: isCapstone ? null : widget.pitSection ?? _section);
    final filename = isCapstone
        ? 'defensys-official-capstone-template.xlsx'
        : 'defensys-official-pit-template.xlsx';
    await downloadBinaryFile(
      filename: filename,
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (mounted) {
      showSuccessToast(
        context,
        'Sample ${isCapstone ? 'Capstone' : 'PIT'} Excel template (.xlsx) downloaded.',
      );
    }
  }

  Future<void> _loadBulkDraft() async {
    final draft = await loadTeamBulkImportDraft();
    if (!mounted || draft == null) return;
    final rows = draft.rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
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
      if (draft.isOpen && rows.isNotEmpty) {
        _showBulkImport = true;
      }
    });
    if (_parsedBulkRows.isNotEmpty) {
      await _refreshBulkPreview();
    }
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
      isOpen: _showBulkImport == true,
    );
    await saveTeamBulkImportDraft(draft);
    if (mounted) {
      setState(() => _savedDraft = draft);
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    }
  }

  Future<bool> _handleSaveDraft({bool showToast = true}) async {
    _draftSaveTimer?.cancel();
    await _persistBulkDraft();
    if (mounted && showToast) {
      showSuccessToast(context, 'Team import draft saved.');
    }
    return true;
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
      setState(() => _showBulkImport = false);
      await _persistBulkDraft();
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    } else {
      _draftSaveTimer?.cancel();
      setState(() => _showBulkImport = false);
      await _persistBulkDraft();
    }
    if (widget.initialBulkImport && mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        try {
          final path = GoRouterState.of(context).uri.path;
          if (path.endsWith('/creation')) {
            context.go(path.replaceFirst('/creation', ''));
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _discardBulkDraftConfirmed() async {
    await clearTeamBulkImportDraft();
    if (!mounted) return;
    setState(() {
      _bulkPreviewRevision++;
      _isBulkPreviewLoading = false;
      _fileImportError = null;
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

  void _openBulkImport({bool resumeDraft = false, String? section}) {
    _bulkImportSessionBaseline = null;
    _bulkImportPersistedSnapshot = null;
    setState(() {
      _templateWarning = null;
      _csvColumns = [];
      final effectiveSec = section ?? widget.pitSection;
      if (effectiveSec != null && effectiveSec.isNotEmpty) {
        _section = effectiveSec;
      }
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
        _csvColumns = bulkImportHeaderFor(
          isCapstoneAdmin: _isCapstoneAdmin,
        ).split(',');
      });
      _captureBulkImportBaseline(persisted: true);
      _refreshBulkPreview();
      return;
    }

    setState(() => _showBulkImport = true);
    _captureBulkImportBaseline();
    if (_parsedBulkRows.isNotEmpty) {
      _refreshBulkPreview();
    }
  }

  void _applyParsedRows(ParsedBulkCsvResult result) {
    final normalized = result.rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    _deriveLevelsOnRows(normalized);
    final isMultiSection = (result.section ?? '').contains(',');
    final singleSection = isMultiSection ? null : result.section?.trim();
    if (singleSection != null && singleSection.isNotEmpty) {
      for (final r in normalized) {
        if ((r['section'] ?? '').toString().trim().isEmpty) {
          r['section'] = singleSection;
        }
      }
    }
    setState(() {
      _parsedBulkRows = normalized;
      _csvColumns = result.csvColumns;
      _section = singleSection;
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
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _handleFilesDropped(files);
    } catch (e) {
      _snack('Could not read file(s): $e');
    }
  }

  Future<void> _handleFilesDropped(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      final csv = readTeamImportFiles(files);
      setState(() => _fileImportError = null);
      _processCsvContent(csv);
    } catch (error, stackTrace) {
      debugPrint('Team roster import failed: $error\n$stackTrace');
      final message = error is FormatException
          ? error.message
          : 'Could not read selected files: $error';
      setState(() => _fileImportError = message);
      _snack(message);
    }
  }

  void _processCsvContent(String csv) {
    if (!mounted) return;

    final result = parseTeamBulkCsvWithContext(
      csv,
      isCapstoneAdmin: _isCapstoneAdmin,
      pitLeadYear: _pitLeadYear ?? widget.pitYearLevel,
    );
    if (result.rows.isEmpty) {
      _snack('Selected file is not a valid DefenSYS team CSV template.');
      return;
    }

    String? warning;
    final recognizedHeaders = {
      'group_key',
      'team_name',
      'project_title',
      'level',
      'year_level',
      'member_ids',
      'leader_id',
      'adviser_id',
      'adviser_name',
      'team name',
      'capstone project',
      'pit project',
      'project',
      'project title',
      'adviser',
      'team members',
      'team_members',
      'members',
      'student name',
      'student_name',
      'student names',
      'student',
      'students',
      'section',
      'class section',
      'class_section',
      'names',
      'modules',
      'module',
      'system name',
      'system_name',
      'project manager',
      'project_manager',
      'pm',
      'instructor',
      'instructor_name',
    };

    final cleanCols = result.csvColumns
        .map(
          (c) => c
              .trim()
              .toLowerCase()
              .replaceAll('*', '')
              .replaceAll(':', '')
              .trim()
              .replaceFirst('\ufeff', ''),
        )
        .where((c) => c.isNotEmpty)
        .toList();

    final unrecognized = cleanCols
        .where((h) => !recognizedHeaders.contains(h))
        .toList();

    final isClientTemplate =
        (cleanCols.contains('team name') || cleanCols.contains('team_name')) &&
        (cleanCols.contains('team members') ||
            cleanCols.contains('team_members') ||
            cleanCols.contains('members') ||
            cleanCols.contains('names') ||
            cleanCols.contains('student name') ||
            cleanCols.contains('student_name') ||
            cleanCols.contains('student names') ||
            cleanCols.contains('student') ||
            cleanCols.contains('students'));
    final isRowTemplate =
        cleanCols.contains('team_name') &&
        cleanCols.contains('member_ids') &&
        cleanCols.contains('leader_id');

    if (unrecognized.isNotEmpty) {
      warning =
          'Wrong template? Unrecognized column(s) detected: ${unrecognized.join(", ")}. Please use the correct CSV template.';
    } else if (!isClientTemplate && !isRowTemplate) {
      warning =
          'Include "Team Name" and "Team Members", or "team_name", "member_ids", and "leader_id" for row-based imports. Project/Module is optional.';
    }

    setState(() {
      _templateWarning = warning;
      _csvColumns = result.csvColumns;
    });

    _applyParsedRows(result);
  }

  Future<void> _refreshBulkPreview() async {
    if (!mounted) return;
    final revision = ++_bulkPreviewRevision;
    setState(() {
      _bulkPreview = null;
      _isBulkPreviewLoading = true;
    });
    if (_parsedBulkRows.isEmpty) {
      final result = parseTeamBulkCsvWithContext(
        _csvDraft,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear ?? widget.pitYearLevel,
      );
      if (result.rows.isEmpty) {
        setState(() => _isBulkPreviewLoading = false);
        return;
      }
      final normalized = result.rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
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
      setState(() => _isBulkPreviewLoading = false);
      return;
    }

    final preview = await ref
        .read(studentTeamsProvider.notifier)
        .bulkImportPreview(
          _parsedBulkRows,
          adviserFilter: _selectedBulkAdviserFilter,
          csvColumns: _csvColumns.isNotEmpty ? _csvColumns : null,
          section: _section,
          systemName: _systemName,
          projectManager: _projectManager,
        );
    if (!mounted || revision != _bulkPreviewRevision) return;
    setState(() {
      _bulkPreview = preview;
      _isBulkPreviewLoading = false;
    });
    _scheduleDraftSave();
  }

  List<int> _readyRowNumbersForImport() {
    if (_isBulkPreviewLoading || _bulkPreview == null) return [];
    final previewRows = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (previewRows.isEmpty) return [];

    final readyNumbers = previewRows
        .where((item) => item['ready'] == true)
        .map((item) => item['row'] as int)
        .toSet();

    if (readyNumbers.isEmpty) return [];

    final ready = <int>[];
    for (var index = 0; index < _parsedBulkRows.length; index++) {
      if (readyNumbers.contains(index + 1)) {
        ready.add(index + 1);
      }
    }
    return ready;
  }

  Future<void> _importBulkTeams() async {
    if (_isBulkPreviewLoading || _templateWarning != null) return;
    if (_parsedBulkRows.isEmpty) {
      _snack('Upload a CSV or add rows to import.');
      return;
    }

    if (_bulkPreview == null) {
      await _refreshBulkPreview();
    }

    if (!mounted || _bulkPreview == null) return;
    final submittedRowNumbers = _readyRowNumbersForImport();
    final rows = [
      for (final rowNumber in submittedRowNumbers)
        Map<String, dynamic>.from(_parsedBulkRows[rowNumber - 1]),
    ];
    if (rows.isEmpty) {
      _snack('No ready rows to import. Fix issues in the table first.');
      return;
    }

    final result = await ref
        .read(studentTeamsProvider.notifier)
        .bulkImport(
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
      submittedRowNumbers: submittedRowNumbers,
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
      if (widget.initialBulkImport && mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          try {
            final path = GoRouterState.of(context).uri.path;
            if (path.endsWith('/creation')) {
              context.go(path.replaceFirst('/creation', ''));
            }
          } catch (_) {}
        }
      }
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
    // Invalidate immediately, including during the debounce interval.
    setState(() {
      _bulkPreviewRevision++;
      _bulkPreview = null;
      _isBulkPreviewLoading = _parsedBulkRows.isNotEmpty;
    });
    _rowPreviewTimer = Timer(const Duration(milliseconds: 500), () {
      _refreshBulkPreview();
    });
  }

  void _addBulkRow() {
    final effectiveYear = _pitLeadYear ?? widget.pitYearLevel ?? '3rd Year';
    final effectiveSection = _section ?? widget.pitSection;
    final row = <String, dynamic>{
      'group_key': 'manual/${DateTime.now().microsecondsSinceEpoch}',
      'team_name': '',
      'project_title': '',
      if (!_isCapstoneAdmin) 'year_level': effectiveYear,
      'member_ids': <String>[],
      'leader_id': '',
      'adviser_name': '',
      if (effectiveSection != null && effectiveSection.isNotEmpty)
        'section': effectiveSection,
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
    final scopedState = _scopedStateForDisplay(state);
    final displayState = scopedState.copyWith(
      teams: scopedState.teams.where((team) {
        if (_isPitContext(scopedState) || _conceptFilter == 'all') return true;
        final context = team['defense_context'] as Map? ?? {};
        final workflow = context['concept_workflow'] as Map? ?? {};
        if (_conceptFilter == 'failed') {
          return ['failed', 'project_rejected'].contains(workflow['status']) ||
              team['status'] == 'Failed';
        }
        if (_conceptFilter == 'redefense_scheduled') {
          return workflow['status'] == 'scheduled' &&
              (workflow['round'] as int? ?? 1) > 1;
        }
        return workflow['status'] == _conceptFilter;
      }).toList(),
    );

    ref.listen<DefensysAdminSection>(activeAdminSectionProvider, (
      previous,
      next,
    ) {
      if (next == DefensysAdminSection.studentTeams &&
          previous != DefensysAdminSection.studentTeams) {
        if (_isBulkImportVisible && _parsedBulkRows.isNotEmpty) {
          _refreshBulkPreview();
        }
      }
    });

    ref.listen(userManagementProvider, (previous, next) {
      if (previous != next &&
          _isBulkImportVisible &&
          _parsedBulkRows.isNotEmpty) {
        _refreshBulkPreview();
      }
    });

    ref.listen(studentAcademicRecordsProvider, (previous, next) {
      if (previous != next &&
          _isBulkImportVisible &&
          _parsedBulkRows.isNotEmpty) {
        _refreshBulkPreview();
      }
    });

    if (_isBulkImportVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !TickerMode.of(context)) return;
        ref
            .read(unsavedChangesSaveDraftProvider.notifier)
            .setCallback(
              _parsedBulkRows.isNotEmpty
                  ? () => _handleSaveDraft(showToast: false)
                  : null,
            );
        ref.read(unsavedChangesProvider.notifier).setDirty(_isBulkImportDirty);
      });

      final activeSemester = ref.watch(academicPeriodProvider).activeSemester;
      return StudentTeamsBulkImportView(
        state: state,
        isPitInstructor: _isPitInstructor,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear ?? widget.pitYearLevel,
        parsedBulkRows: _parsedBulkRows,
        bulkCsvDraft: _csvDraft,
        selectedBulkAdviserFilter: _selectedBulkAdviserFilter,
        bulkPreview: _bulkPreview,
        isPreviewLoading: _isBulkPreviewLoading,
        fileImportError: _fileImportError,
        onRetryPreview: _refreshBulkPreview,
        onOpenExistingTeam: (teamId) async {
          await _persistBulkDraft();
          if (mounted) _openTeamDetailRoute(teamId);
        },
        onEventChanged: (value) async {
          setState(() {
            _bulkPreviewRevision++;
            _bulkPreview = null;
            _isBulkPreviewLoading = true;
          });
          await ref
              .read(studentTeamsProvider.notifier)
              .fetchTeams(
                eventName: value == '' ? null : value,
                clearEventName: value == '',
              );
          if (mounted) await _refreshBulkPreview();
        },
        showIssuesOnly: _showIssuesOnly,
        templateWarning: _templateWarning,
        isBulkImportDirty: _isBulkImportDirty,
        section: _section ?? widget.pitSection,
        systemName: _systemName,
        projectManager: _projectManager,
        activeSemester: activeSemester,
        onRequestClose: _requestCloseBulkImport,
        onDownloadTemplate: _downloadCsvTemplate,
        onPickBulkCsvFile: _pickBulkCsvFile,
        onImportBulkTeams: _importBulkTeams,
        onExportBulkCsv: _exportBulkCsv,
        onSaveDraft: _handleSaveDraft,
        onScheduleRowPreview: _scheduleRowPreview,
        onDeleteBulkRow: _deleteBulkRow,
        onAddBulkRow: _addBulkRow,
        onClearStaged: () {
          setState(() {
            _bulkPreviewRevision++;
            _isBulkPreviewLoading = false;
            _fileImportError = null;
            _parsedBulkRows = [];
            _bulkCsv = '';
            _bulkPreview = null;
            _templateWarning = null;
            _section = null;
            _systemName = null;
            _projectManager = null;
          });
          _scheduleDraftSave();
        },
        onAdviserFilterChanged: (value) {
          if (value == null) return;
          setState(() => _bulkAdviserFilter = value);
          _refreshBulkPreview();
          _scheduleDraftSave();
        },
        onShowIssuesOnlyChanged: (value) =>
            setState(() => _showIssuesOnly = value),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !TickerMode.of(context)) return;
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
    });

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
            actions: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ReportExportMenu(
                  reportId: 'team-roster',
                  params: {
                    'term_context': _teamListScope,
                    if (_section != null) 'section': _section!,
                    'roster_view': 'current',
                    if (displayState.eventName != null)
                      'event_name': displayState.eventName!,
                  },
                ),
                StudentTeamsHeaderActions(
                  isPitInstructor: _isPitInstructor,
                  onRoster: _isCapstoneAdmin ? null : () async {
                    await openTeamRoster(context, year: widget.pitYearLevel,
                      section: _section, event: displayState.eventName, instructor: _isPitInstructor);
                    if (mounted) _fetchTeamsForCurrentRole();
                  },
                  canTapActions: _canTapTeamActions(displayState),
                  importLabel: displayState.eventName == null ? 'Import teams'
                    : displayState.rosterContext.any((r) => r['source'] == 'custom') ? 'Manage event roster' : 'Import different roster',
                  onBulkImport: displayState.eventName != null && displayState.rosterContext.isNotEmpty && displayState.rosterContext.every((r) => r['in_use'] == true)
                    ? null : () => _onBulkImportPressed(displayState),
                  onRefresh: _fetchTeamsForCurrentRole,
                  onCreateTeam: displayState.eventName == null ? () => _onCreateTeamPressed(displayState) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          StudentTeamsSummaryCards(
            state: displayState,
            isPitContext: _isPitContext(displayState),
          ),

          if (displayState.error != null) ...[
            const SizedBox(height: 14),
            _notice(displayState.error!, warning: true),
          ],
          if (displayState.message != null) ...[
            const SizedBox(height: 14),
            _notice(displayState.message!),
          ],
          if (displayState.operatingMessage != null &&
              displayState.operatingMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _notice(displayState.operatingMessage!, warning: _pitTermIsAudit),
          ],
          if (_isPitLeadManager || _isPitInstructor) ...[
            const SizedBox(height: 14),
            PitTeamScopeToggle(
              teamListScope: _teamListScope,
              isSaving: displayState.isSaving,
              onScopeChanged: (value) {
                if (value == null) return;
                setState(() => _teamListScope = value);
                _fetchTeamsForCurrentRole(scope: value);
              },
              onClear: () {
                _searchController.clear();
                setState(() => _teamListScope = 'active');
                ref
                    .read(studentTeamsProvider.notifier)
                    .fetchTeams(
                      level: _isCapstoneAdmin ? 'Capstone' : '',
                      scope: (_isPitLeadManager || _isPitInstructor)
                          ? 'active'
                          : null,
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
            key: const ValueKey('student-teams-list-card'),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: DefensysUi.cardDecoration(context),
            clipBehavior: Clip.none,
            child: Column(
              children: [
                StudentTeamsListToolbar(
                  search: StudentTeamsSearchField(
                    controller: _searchController,
                    isSaving: displayState.isSaving,
                    isPitContext: _isPitContext(displayState),
                    onSubmitted: (value) {
                      ref
                          .read(studentTeamsProvider.notifier)
                          .fetchTeams(search: value);
                    },
                  ),
                  controls: [
                    if (!_isPitContext(displayState))
                      DefensysShadcnScope(
                        child: WorkflowChoice(
                          value: _conceptFilter,
                          options: const {
                            'all': 'All team workflows',
                            'replacement_concepts_needed':
                                'Replacement concepts needed',
                            'concept_review_pending': 'Adviser review pending',
                            'concept_endorsement_pending':
                                'Concept endorsement pending',
                            'module_confirmation_pending':
                                'Confirm module names',
                            'shared_clearance_pending': 'Shared papers pending',
                            'shared_acknowledgment_pending':
                                'Adviser shared review pending',
                            'ready_to_schedule_redefense':
                                'Ready to schedule re-defense',
                            'redefense_scheduled': 'Re-defense scheduled',
                            'failed': 'Failed / rejected',
                          },
                          onChanged: (value) =>
                              setState(() => _conceptFilter = value),
                        ),
                      ),
                    if (_isPitContext(displayState) && !_isPitLeadManager) ...[
                      PitYearLevelDropdownFilter(
                        currentYearLevel: displayState.yearLevel,
                        isSaving: displayState.isSaving,
                        onYearChanged: (year) {
                          ref
                              .read(studentTeamsProvider.notifier)
                              .fetchTeams(
                                yearLevel: year,
                                clearYearLevel: year == null,
                              );
                        },
                      ),
                    ],
                    if (_isPitContext(displayState)) ...[
                      PitEventDropdownFilter(
                        currentEventName: displayState.eventName,
                        pitEvents: displayState.pitEvents,
                        selectedYearLevel:
                            _pitLeadYear ?? displayState.yearLevel,
                        isSaving: displayState.isSaving,
                        onEventChanged: (event) {
                          ref
                              .read(studentTeamsProvider.notifier)
                              .fetchTeams(
                                eventName: event,
                                clearEventName: event == null,
                              );
                        },
                      ),
                    ],
                    if (!_isPitLeadManager && !_isPitInstructor) ...[
                      StudentTeamsLevelFilter(
                        isPitLeadManager: _isPitLeadManager,
                        isPitInstructor: _isPitInstructor,
                        currentLevel: _teamLevelFilter(displayState),
                        isSaving: displayState.isSaving,
                        onLevelChanged: (value) {
                          ref
                              .read(studentTeamsProvider.notifier)
                              .fetchTeams(
                                level: value ?? '',
                                clearEventName: true,
                                clearYearLevel: true,
                              );
                        },
                      ),
                    ],
                    ManageSectionsButton(
                      onPressed:
                          displayState.isLoading ||
                              displayState.isSaving ||
                              _pitTermIsAudit ||
                              _teamListScope != 'active'
                          ? null
                          : () => showManageSectionsDialog(
                              context: context,
                              level: _isPitContext(displayState)
                                  ? 'PIT'
                                  : 'Capstone',
                              scope: _teamListScope,
                              yearLevel: _pitLeadYear ?? displayState.yearLevel,
                              section: displayState.section,
                              onImportSectionRoster: (section) {
                                _openBulkImport(section: section);
                              },
                              onRosterUpdated: () {
                                _fetchTeamsForCurrentRole();
                              },
                            ),
                    ),
                    buildSecondaryButton(
                      icon: Icons.grid_view_rounded,
                      label: 'Deliverables Matrix',
                      context: context,
                      onTap: displayState.isLoading || displayState.isSaving
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => Scaffold(
                                    appBar: AppBar(
                                      backgroundColor: DefensysTokens.surfaceOf(
                                        ctx,
                                      ),
                                      foregroundColor:
                                          DefensysTokens.textPrimaryOf(ctx),
                                      title: Text(
                                        _isPitContext(displayState)
                                            ? 'PIT Cohort Deliverables'
                                            : 'Capstone Cohort Deliverables',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      elevation: 0,
                                      leading: IconButton(
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                      ),
                                    ),
                                    body: TeamDeliverablesScreen(
                                      initialScope: _isPitContext(displayState)
                                          ? 'pit'
                                          : 'capstone',
                                      pitYearLevel:
                                          _pitLeadYear ??
                                          displayState.yearLevel,
                                      pitSection: displayState.section,
                                      initialViewMode:
                                          DeliverablesViewMode.matrix,
                                    ),
                                  ),
                                ),
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                displayState.isLoading
                    ? const SizedBox(
                        height: 150,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: DefensysUi.primaryMaroon,
                          ),
                        ),
                      )
                    : GroupedSectionView(
                        sharedProposalNamesOnly: _isPitLeadManager,
                        state: displayState,
                        isPit: _isPitContext(displayState),
                        canManageTeams: _canManageTeams(displayState),
                        searchQuery: _searchController.text,
                        onOpenTeamDetail: _openTeamDetailRoute,
                      ),
                const SizedBox(height: 18),
                Container(height: 1, color: DefensysTokens.borderOf(context)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Showing ${displayState.teams.length} of ${_count(displayState, 'filtered')} teams',
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
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
