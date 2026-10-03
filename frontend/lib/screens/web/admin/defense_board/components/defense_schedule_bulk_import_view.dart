import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'schedule_import_review_widgets.dart';
import 'schedule_import_settings_dialog.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/export/defense_schedule_excel_generator.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/import/schedule_import_workspace.dart';
import 'package:defensys/utils/state/unsaved_changes.dart';
import 'package:defensys/utils/string_matching_utils.dart';

import '../../defense_scheduler/models/schedule_import_models.dart';
import '../../defense_scheduler/dialogs/panelist_pool_dialog.dart';

class DefenseScheduleBulkImportView extends ConsumerStatefulWidget {
  const DefenseScheduleBulkImportView({
    super.key,
    required this.scope,
    required this.onBack,
    this.initialStageId,
    this.initialEventName,
    this.initialDate = '',
    this.initialRoom = '',
    this.initialDuration = '60',
    this.initialPanelWeight = '80',
    this.initialPeerWeight = '20',
  });

  final String scope;
  final VoidCallback onBack;
  final int? initialStageId;
  final String? initialEventName;
  final String initialDate;
  final String initialRoom;
  final String initialDuration;
  final String initialPanelWeight;
  final String initialPeerWeight;

  @override
  ConsumerState<DefenseScheduleBulkImportView> createState() =>
      _DefenseScheduleBulkImportViewState();
}

class _DefenseScheduleBulkImportViewState
    extends ConsumerState<DefenseScheduleBulkImportView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  ParsedScheduleImport? _parsed;
  List<ScheduleImportSourceFile> _sourceFiles = [];
  String? _selectedFileId;
  bool _fileBusy = false;
  String? _fileName;
  int? _importStageId;
  String _importEventName = '';
  MatchResult<dynamic>? _headerMatch;
  String? _mismatchWarning;

  int? _panelRubricId;
  int? _adviserRubricId;
  int? _peerRubricId;
  String? _panelRubricName;
  String? _adviserRubricName;
  String? _peerRubricName;
  int _panelWeight = 80;
  int _peerWeight = 20;

  bool _rubricLoading = false;
  bool _importBusy = false;
  bool _awaitingImportConfirmation = false;
  List<String> _importErrors = [];

  Timer? _draftDebounce;
  DateTime? _draftSavedAt;
  String? _lastSavedSnapshot;
  bool _showIssuesOnly = false;
  bool _showDraftRestoredNotice = false;
  bool _reflowStartTimes = true;
  List<Map<String, dynamic>>? _conflictSchedules;
  bool _conflictLoading = false;
  String? _conflictCheckError;
  String? _filterDate;
  String? _filterRoom;
  String? _importResultMessage;
  final Set<String> _collapsedSessions = {};
  final ScrollController _reviewScrollController = ScrollController();

  int? get _semesterId =>
      asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);

  bool get _isPit => widget.scope == 'pit';
  bool get _busy => _importBusy || _fileBusy;

  @override
  void initState() {
    super.initState();
    _importStageId = _isPit ? null : widget.initialStageId;
    _importEventName = _isPit ? (widget.initialEventName ?? '').trim() : '';
    _dateController.text = widget.initialDate;
    _roomController.text = widget.initialRoom;
    _durationController.text = widget.initialDuration;
    _panelWeight = int.tryParse(widget.initialPanelWeight) ?? 80;
    _peerWeight = int.tryParse(widget.initialPeerWeight) ?? 20;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDraftAndConfig();
    });
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _reviewScrollController.dispose();
    _searchCtrl.dispose();
    _dateController.dispose();
    _roomController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  String _currentDraftSnapshot() {
    if (_parsed == null || _parsed!.rows.isEmpty) return '';
    return jsonEncode({
      'files': _sourceFiles.map((file) => file.toJson()).toList(),
      'parsed': _parsed!.toJson(),
      'stage': _importStageId,
      'event': _importEventName,
      'date': _dateController.text,
      'room': _roomController.text,
      'duration': _durationController.text,
      'rubrics': [_panelRubricId, _adviserRubricId, _peerRubricId],
      'weights': [_panelWeight, _peerWeight],
      'selected_file': _selectedFileId,
    });
  }

  bool _isDirty() {
    if (_parsed == null || _parsed!.rows.isEmpty) return false;
    if (_draftDebounce?.isActive ?? false) return true;
    final current = _currentDraftSnapshot();
    return _lastSavedSnapshot == null || current != _lastSavedSnapshot;
  }

  Future<void> _initDraftAndConfig() async {
    final schedState = ref.read(defenseSchedulerProvider);
    final existingDraft = await loadScheduleImportDraft(
      scope: widget.scope,
      semesterId: _semesterId,
    );
    if (!mounted) return;

    if (existingDraft != null && existingDraft.parsed.rows.isNotEmpty) {
      _parsed = existingDraft.parsed;
      _fileName = existingDraft.fileName;
      _importStageId = existingDraft.stageId ?? _importStageId;
      if (existingDraft.eventName.isNotEmpty) {
        _importEventName = existingDraft.eventName;
      }
      if (existingDraft.date.isNotEmpty) {
        _dateController.text = existingDraft.date;
      }
      if (existingDraft.room.isNotEmpty) {
        _roomController.text = existingDraft.room;
      }
      if (existingDraft.duration.isNotEmpty) {
        _durationController.text = existingDraft.duration;
      }
      _panelRubricId = existingDraft.panelRubricId ?? _panelRubricId;
      _adviserRubricId = existingDraft.adviserRubricId ?? _adviserRubricId;
      _peerRubricId = existingDraft.peerRubricId ?? _peerRubricId;
      _reflowStartTimes = existingDraft.reflowStartTimes;
      _panelWeight = existingDraft.panelWeight;
      _peerWeight = existingDraft.peerWeight;
      if (existingDraft.files.isNotEmpty) {
        _sourceFiles = existingDraft.files;
        _parsed = combineScheduleImportSources(_sourceFiles);
      } else {
        // Materialize the previous duration editor's plan before migrating it.
        final legacy = buildScheduleImportPreviewRows(
          _parsed!,
          schedState,
          scope: widget.scope,
          stageId: _importStageId,
          eventName: _importEventName,
          date: _dateController.text,
          room: _roomController.text,
          slotDuration: int.tryParse(_durationController.text),
          reflowStartTimes: _reflowStartTimes,
          fallbackDuration: int.tryParse(_durationController.text) ?? 60,
          panelRubricId: _panelRubricId,
          adviserRubricId: _adviserRubricId,
          peerRubricId: _peerRubricId,
          panelWeight: _panelWeight,
          peerWeight: _peerWeight,
        );
        _sourceFiles = [
          attachScheduleImportSource(
            _parsed!.copyWith(
              rows: legacy
                  .map(
                    (row) => row.source.copyWith(
                      startTime: row.effectiveStartTime,
                      endTime: row.effectiveEndTime,
                      slotDuration: row.duration,
                    ),
                  )
                  .toList(),
            ),
            'legacy',
            existingDraft.fileName ?? 'Timetable',
          ),
        ];
        _parsed = combineScheduleImportSources(_sourceFiles);
      }
      _selectedFileId = existingDraft.selectedFileId;
      _reflowStartTimes = false;

      _evaluateStageMatching(parsed: _parsed!, schedState: schedState);

      if (existingDraft.stageId != null) {
        _importStageId = existingDraft.stageId;
        if (_headerMatch != null && _headerMatch!.isMatched) {
          final matchedId = asInt(_headerMatch!.item?['id']);
          if (matchedId == _importStageId) {
            _mismatchWarning = null;
          }
        }
      }
      if (existingDraft.eventName.isNotEmpty) {
        _importEventName = existingDraft.eventName;
        if (_headerMatch != null && _headerMatch!.isMatched) {
          if (_headerMatch!.label.toLowerCase() ==
              _importEventName.toLowerCase()) {
            _mismatchWarning = null;
          }
        }
      }

      _showDraftRestoredNotice = true;
      _draftSavedAt = existingDraft.savedAt;
      _lastSavedSnapshot = _currentDraftSnapshot();
    }

    if (!_isPit && _importStageId != null) {
      await _loadStageRubrics(_importStageId);
    } else if (_isPit && _importEventName.isNotEmpty) {
      await _loadPitEventConfig(_importEventName);
    }

    if (_parsed != null) await _refreshConflictSchedules();
    if (mounted) setState(() {});
  }

  Future<bool> _refreshConflictSchedules() async {
    if (!mounted) return false;
    setState(() {
      _conflictLoading = true;
      _conflictCheckError = null;
    });
    try {
      final schedules = await ref
          .read(defenseSchedulerProvider.notifier)
          .fetchImportConflictSchedules();
      if (!mounted) return false;
      setState(() => _conflictSchedules = schedules);
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _conflictCheckError =
              'Could not check existing schedules. Retry validation before importing.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _conflictLoading = false);
    }
  }

  Future<void> _persistDraft({bool showToast = false}) async {
    _draftDebounce?.cancel();
    if (_parsed == null || _parsed!.rows.isEmpty) {
      await clearScheduleImportDraft(
        scope: widget.scope,
        semesterId: _semesterId,
      );
      _lastSavedSnapshot = null;
      return;
    }
    _syncSourceFiles();
    final snapshot = _currentDraftSnapshot();
    final preview = _buildPreviewRows(ref.read(defenseSchedulerProvider));
    final draft = ScheduleImportDraft(
      parsed: _parsed!,
      scope: widget.scope,
      fileName: _fileName,
      stageId: _importStageId,
      eventName: _importEventName,
      date: _dateController.text,
      room: _roomController.text,
      duration: _durationController.text,
      reflowStartTimes: _reflowStartTimes,
      panelRubricId: _panelRubricId,
      adviserRubricId: _adviserRubricId,
      peerRubricId: _peerRubricId,
      panelWeight: _panelWeight,
      peerWeight: _peerWeight,
      savedAt: DateTime.now(),
      rowCount: _parsed!.rows.length,
      readyCount: preview.where((row) => row.ready).length,
      issueCount: preview.where((row) => !row.ready).length,
      files: _sourceFiles,
      semesterId: asInt(
        ref.read(defenseSchedulerProvider).activeSemester?['id'],
      ),
      selectedFileId: _selectedFileId,
    );
    await saveScheduleImportDraft(draft);
    if (mounted) setState(() => _draftSavedAt = draft.savedAt);
    _lastSavedSnapshot = snapshot;
    if (showToast && mounted) {
      showSuccessToast(context, 'Schedule import draft saved.');
    }
  }

  void _scheduleDraftSave() {
    _syncSourceFiles();
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), () {
      _persistDraft();
    });
  }

  Future<void> _discardDraft() async {
    _draftDebounce?.cancel();
    await clearScheduleImportDraft(
      scope: widget.scope,
      semesterId: _semesterId,
    );
    _lastSavedSnapshot = null;
    setState(() {
      _parsed = null;
      _sourceFiles = [];
      _selectedFileId = null;
      _fileName = null;
      _showDraftRestoredNotice = false;
      _reflowStartTimes = true;
      _filterDate = null;
      _filterRoom = null;
      _searchCtrl.clear();
      _showIssuesOnly = false;
      _collapsedSessions.clear();
      _importResultMessage = null;
      _draftSavedAt = null;
      _headerMatch = null;
      _mismatchWarning = null;
      _dateController.text = widget.initialDate;
      _roomController.text = widget.initialRoom;
      _durationController.text = widget.initialDuration;
      _importStageId = _isPit ? null : widget.initialStageId;
      _importEventName = _isPit ? (widget.initialEventName ?? '').trim() : '';
      _panelRubricId = null;
      _adviserRubricId = null;
      _peerRubricId = null;
      _panelRubricName = null;
      _adviserRubricName = null;
      _peerRubricName = null;
      _panelWeight = int.tryParse(widget.initialPanelWeight) ?? 80;
      _peerWeight = int.tryParse(widget.initialPeerWeight) ?? 20;
      _importErrors = [];
    });
    if (mounted) {
      showInfoToast(context, 'Schedule import draft discarded.');
    }
  }

  Future<void> _loadStageRubrics(int? stageId) async {
    if (stageId == null) {
      setState(() {
        _panelRubricId = null;
        _adviserRubricId = null;
        _peerRubricId = null;
        _panelRubricName = null;
        _adviserRubricName = null;
        _peerRubricName = null;
        _rubricLoading = false;
      });
      return;
    }

    setState(() => _rubricLoading = true);
    final schedState = ref.read(defenseSchedulerProvider);
    final semesterId = asInt(schedState.activeSemester?['id']);
    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(stageId, semesterId: semesterId);
    final grading = detail?['grading_config'];

    if (!mounted) return;
    setState(() {
      if (grading is Map) {
        _panelRubricId = asInt(grading['panel_rubric_id']);
        _adviserRubricId = asInt(grading['adviser_rubric_id']);
        _peerRubricId = asInt(grading['peer_rubric_id']);
        _panelRubricName = grading['panel_rubric_name']?.toString();
        _adviserRubricName = grading['adviser_rubric_name']?.toString();
        _peerRubricName = grading['peer_rubric_name']?.toString();
      } else {
        _panelRubricId = null;
        _adviserRubricId = null;
        _peerRubricId = null;
        _panelRubricName = null;
        _adviserRubricName = null;
        _peerRubricName = null;
      }
      _rubricLoading = false;
    });
    _scheduleDraftSave();
  }

  Future<void> _loadPitEventConfig(String eventName) async {
    if (eventName.trim().isEmpty) {
      setState(() {
        _panelRubricId = null;
        _peerRubricId = null;
        _panelRubricName = null;
        _peerRubricName = null;
        _rubricLoading = false;
      });
      return;
    }

    setState(() => _rubricLoading = true);
    final schedState = ref.read(defenseSchedulerProvider);
    final semesterId = asInt(schedState.activeSemester?['id']);
    final config = await ref
        .read(defenseSchedulerProvider.notifier)
        .fetchPitEventConfig(eventName: eventName, semesterId: semesterId);

    if (!mounted) return;
    setState(() {
      if (config != null) {
        _panelRubricId = asInt(config['panel_rubric_id']);
        _peerRubricId = asInt(config['peer_rubric_id']);
        _panelRubricName = config['panel_rubric_name']?.toString();
        _peerRubricName = config['peer_rubric_name']?.toString();
        _panelWeight =
            int.tryParse(config['panel_weight']?.toString() ?? '') ??
            _panelWeight;
        _peerWeight =
            int.tryParse(config['peer_weight']?.toString() ?? '') ??
            _peerWeight;
      } else {
        _panelRubricId = null;
        _peerRubricId = null;
        _panelRubricName = null;
        _peerRubricName = null;
      }
      _rubricLoading = false;
    });
    _scheduleDraftSave();
  }

  void _evaluateStageMatching({
    required ParsedScheduleImport parsed,
    required DefenseSchedulerState schedState,
  }) {
    final rawStage = parsed.stage?.trim() ?? '';
    MatchResult<dynamic>? resolvedMatch;
    String? warning;

    if (_isPit) {
      final activeEventName = (widget.initialEventName ?? '').trim();
      if (rawStage.isNotEmpty) {
        resolvedMatch = findBestMatch<Map<String, dynamic>>(
          source: rawStage,
          items: schedState.pitEvents,
          labelGetter: (e) => e['event_name']?.toString() ?? '',
        );
        if (resolvedMatch.isMatched) {
          final matchedName = resolvedMatch.label;
          if (activeEventName.isNotEmpty &&
              matchedName.toLowerCase() != activeEventName.toLowerCase()) {
            warning =
                'File header specifies "$rawStage" (matched to "$matchedName"), while active PIT event is "$activeEventName".';
          }
          _importEventName = matchedName;
        } else {
          warning =
              'File header specifies event "$rawStage", which does not match active event "$activeEventName" (or any registered PIT event for this semester).';
          if (_importEventName.isEmpty) _importEventName = activeEventName;
        }
      } else {
        if (_importEventName.isEmpty) _importEventName = activeEventName;
      }
    } else {
      final activeStageId = widget.initialStageId;
      final activeStageObj = schedState.defenseStages.firstWhere(
        (s) => asInt(s['id']) == activeStageId,
        orElse: () => schedState.defenseStages.isNotEmpty
            ? schedState.defenseStages.first
            : <String, dynamic>{},
      );
      final activeStageLabel = activeStageObj['label']?.toString() ?? '';

      if (rawStage.isNotEmpty) {
        resolvedMatch = findBestMatch<Map<String, dynamic>>(
          source: rawStage,
          items: schedState.defenseStages,
          labelGetter: (s) => s['label']?.toString() ?? '',
        );
        if (resolvedMatch.isMatched) {
          final matchedStageId = asInt(resolvedMatch.item?['id']);
          if (activeStageId != null && matchedStageId != activeStageId) {
            warning =
                'File header specifies "$rawStage" (matched to "${resolvedMatch.label}"), while active defense stage is "$activeStageLabel".';
          }
          _importStageId = matchedStageId;
        } else {
          warning =
              'File header specifies stage "$rawStage", which does not match active stage "$activeStageLabel" (or any stage in your Academic Stage Chain).';
          _importStageId ??= activeStageId ?? asInt(activeStageObj['id']);
        }
      } else {
        _importStageId ??= activeStageId ?? asInt(activeStageObj['id']);
      }
    }

    _headerMatch = resolvedMatch;
    _mismatchWarning = warning;
  }

  void _syncSourceFiles() {
    if (_parsed == null) return;
    _sourceFiles = [
      for (final file in _sourceFiles)
        file.withRows(
          _parsed!.rows.where((row) => row.sourceFileId == file.id).toList(),
        ),
    ].where((file) => file.parsed.rows.isNotEmpty).toList();
    if (!_sourceFiles.any((file) => file.id == _selectedFileId)) {
      _selectedFileId = null;
    }
    _fileName = _sourceFiles.isEmpty
        ? null
        : _sourceFiles.length == 1
        ? _sourceFiles.single.name
        : '${_sourceFiles.length} files';
  }

  Future<void> _removeSource(ScheduleImportSourceFile file) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove ${file.name}?',
      message:
          'This removes ${file.parsed.rows.length} staged slots from this file. Other files keep their edits.',
      confirmLabel: 'Remove file',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _parsed = _parsed!.copyWith(
        rows: _parsed!.rows
            .where((row) => row.sourceFileId != file.id)
            .toList(),
      );
      _syncSourceFiles();
      if (_sourceFiles.isEmpty) {
        _parsed = null;
        _fileName = null;
      }
    });
    await _persistDraft();
  }

  Future<void> _pickFile({
    String? replaceFileId,
    bool replaceAll = false,
  }) async {
    if (_busy) return;
    if (replaceAll || replaceFileId != null) {
      final file = _sourceFiles
          .where((file) => file.id == replaceFileId)
          .firstOrNull;
      final confirmed = await confirmDestructive(
        context,
        title: file == null ? 'Replace all files?' : 'Replace ${file.name}?',
        message: file == null
            ? 'The selected files will replace the entire staged draft.'
            : 'Changes to this file’s staged rows will be replaced. Other files keep their edits.',
        confirmLabel: 'Choose replacement',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _fileBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
        allowMultiple: replaceFileId == null,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final state = ref.read(defenseSchedulerProvider);
      final targets = _isPit ? state.pitEvents : state.defenseStages;
      final configured = targets
          .map(
            (target) =>
                (_isPit ? target['event_name'] : target['label'])?.toString() ??
                '',
          )
          .toList();
      final incoming = <ScheduleImportSourceFile>[];
      String? batchTarget;
      for (final file in result.files) {
        if (file.bytes == null) {
          throw FormatException('Unable to read ${file.name}.');
        }
        final parsed = parseScheduleImportFile(
          bytes: file.bytes!,
          filename: file.name,
          configuredStages: configured,
        );
        if (parsed.rows.isEmpty) {
          throw FormatException('${file.name} has no timetable slots.');
        }
        if (!scheduleImportSemesterMatches(
          parsed.semester,
          _getActiveSemLabel(state),
        )) {
          throw FormatException(
            '${file.name} targets another academic term. Add files for ${_getActiveSemLabel(state)}.',
          );
        }
        final raw = parsed.stage?.trim() ?? '';
        if (raw.isNotEmpty) {
          final match = findBestMatch<Map<String, dynamic>>(
            source: raw,
            items: targets,
            labelGetter: (target) =>
                (_isPit ? target['event_name'] : target['label'])?.toString() ??
                '',
          );
          if (match.isMatched) {
            final target = _isPit
                ? match.label.toLowerCase()
                : asInt(match.item?['id']).toString();
            final current = _isPit
                ? _importEventName.toLowerCase()
                : _importStageId?.toString();
            if ((batchTarget != null && target != batchTarget) ||
                (_sourceFiles.isNotEmpty &&
                    !replaceAll &&
                    current != null &&
                    current.isNotEmpty &&
                    target != current)) {
              throw FormatException(
                '${file.name} targets a different ${_isPit ? 'event' : 'stage'}. Combine files for the same target.',
              );
            }
            batchTarget = target;
          }
        }
        incoming.add(
          attachScheduleImportSource(
            parsed,
            'file-${DateTime.now().microsecondsSinceEpoch}-${incoming.length}',
            file.name,
          ),
        );
      }
      if (_sourceFiles.isEmpty || replaceAll) {
        _evaluateStageMatching(
          parsed:
              incoming
                  .where((file) => file.parsed.stage?.trim().isNotEmpty == true)
                  .firstOrNull
                  ?.parsed ??
              incoming.first.parsed,
          schedState: state,
        );
      }
      setState(() {
        _syncSourceFiles();
        if (replaceAll) {
          _sourceFiles = incoming;
        } else if (replaceFileId != null) {
          final index = _sourceFiles.indexWhere(
            (file) => file.id == replaceFileId,
          );
          if (index >= 0) {
            _sourceFiles.replaceRange(index, index + 1, incoming);
          } else {
            _sourceFiles.addAll(incoming);
          }
          if (_selectedFileId == replaceFileId) {
            _selectedFileId = incoming.first.id;
          }
        } else {
          _sourceFiles.addAll(incoming);
        }
        _parsed = combineScheduleImportSources(_sourceFiles);
        _fileName = _sourceFiles.length == 1
            ? _sourceFiles.first.name
            : '${_sourceFiles.length} files';
        _reflowStartTimes = false;
        _importErrors = [];
        _showDraftRestoredNotice = false;
        _collapsedSessions.clear();
        _importResultMessage = null;
      });
      if (!_isPit && _importStageId != null) {
        await _loadStageRubrics(_importStageId);
      } else if (_isPit && _importEventName.isNotEmpty) {
        await _loadPitEventConfig(_importEventName);
      }
      await _refreshConflictSchedules();
      _scheduleDraftSave();
    } catch (error) {
      if (mounted) showErrorToast(context, 'Unable to add timetable: $error');
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<bool> _handleAttemptClose() async {
    _draftDebounce?.cancel();
    if (!_isDirty()) {
      return true;
    }
    final action = await showDiscardUnsavedChangesDialog(
      context,
      onSaveDraft: () async {
        await _persistDraft(showToast: true);
        return true;
      },
    );
    if (action == UnsavedChangesAction.discard) {
      await clearScheduleImportDraft(
        scope: widget.scope,
        semesterId: _semesterId,
      );
      return true;
    }
    if (action == UnsavedChangesAction.saveDraft) {
      return true;
    }
    return false;
  }

  String _getActiveSemLabel(DefenseSchedulerState state) {
    final sem = state.activeSemester;
    if (sem != null) {
      final name = sem['display_name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      final sy = sem['school_year']?.toString().trim();
      final lbl = sem['label']?.toString().trim();
      if (sy != null && lbl != null) return '$sy $lbl';
    }
    return _isPit ? 'PIT Term' : 'Capstone Term';
  }

  List<ScheduleImportPreviewRow> _previewForRows(
    List<ParsedScheduleImportRow> rows,
    DefenseSchedulerState state,
  ) => buildScheduleImportPreviewRows(
    ParsedScheduleImport(rows: rows),
    state.copyWith(schedules: _conflictSchedules ?? state.schedules),
    scope: widget.scope,
    stageId: _importStageId,
    eventName: _importEventName,
    date: _dateController.text,
    room: _roomController.text,
    reflowStartTimes: false,
    fallbackDuration: int.tryParse(_durationController.text) ?? 60,
    panelRubricId: _panelRubricId,
    adviserRubricId: _adviserRubricId,
    peerRubricId: _peerRubricId,
    panelWeight: _panelWeight,
    peerWeight: _peerWeight,
  );

  List<ScheduleImportPreviewRow> _buildPreviewRows(
    DefenseSchedulerState state,
  ) => _parsed == null ? [] : _previewForRows(_parsed!.rows, state);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider),
        semester = _getActiveSemLabel(state);
    final rows = _buildPreviewRows(state);
    return PopScope(
      canPop: !_busy && !_isDirty(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (await _handleAttemptClose() && mounted) widget.onBack();
      },
      child: SingleChildScrollView(
        controller: _reviewScrollController,
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildReviewPageHeader(semester, _parsed != null),
            const SizedBox(height: 20),
            Text(
              'Upload spreadsheet  /  Review & resolve  /  Import',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final format = _buildScheduleFormatCard(semester),
                    upload = _buildScheduleUploadCard(
                      rows.length,
                      rows.where((row) => row.ready).length,
                    );
                return constraints.maxWidth < 960
                    ? Column(
                        children: [format, const SizedBox(height: 18), upload],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: format),
                          const SizedBox(width: 20),
                          Expanded(flex: 6, child: upload),
                        ],
                      );
              },
            ),
            if (_mismatchWarning != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildMismatchBanner(
                  message: _mismatchWarning!,
                  onDismiss: () => setState(() => _mismatchWarning = null),
                ),
              ),
            if (_parsed?.isRedefense == true)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildRedefenseBanner(),
              ),
            const SizedBox(height: 26),
            if (_parsed != null)
              _buildPreflightReviewCard(schedState: state, previewRows: rows)
            else
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Upload a spreadsheet above to review its schedule here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscardDraft() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Discard schedule draft?',
      message:
          'This removes the staged spreadsheet and your unsaved schedule changes.',
      confirmLabel: 'Discard draft',
    );
    if (confirmed && mounted) await _discardDraft();
  }

  Widget _buildReviewPageHeader(String semester, bool hasFile) {
    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _headerPill(semester),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final canClose = await _handleAttemptClose();
                  if (canClose && mounted) widget.onBack();
                },
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back to Defense Board'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1000;
        final heading = DefensysPageHeader(
          icon: Icons.schedule_send_rounded,
          title: 'Import defense schedule',
          subtitle:
              'Upload a ${_isPit ? 'PIT' : 'Capstone'} timetable to review and schedule defense slots.',
          actions: narrow ? null : actions,
        );
        return narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 16), actions],
              )
            : heading;
      },
    );
  }

  Future<void> _importReadySlots(
    List<ScheduleImportPreviewRow> previewRows,
  ) async {
    if (_busy ||
        _awaitingImportConfirmation ||
        _rubricLoading ||
        _conflictLoading ||
        _conflictCheckError != null) {
      return;
    }
    final readyRows = previewRows.where((row) => row.ready).toList();
    if (readyRows.isEmpty) return;
    final excluded = previewRows.length - readyRows.length;
    try {
      if (excluded > 0) {
        _awaitingImportConfirmation = true;
        final confirmed = await showConfirmDialog(
          context,
          title: 'Import ${readyRows.length} ready slots?',
          message:
              '$excluded ${excluded == 1 ? 'slot needs' : 'slots need'} attention and will be excluded from this import. These slots will remain in your draft.',
          confirmLabel: 'Import ${readyRows.length} slots',
        );
        if (!confirmed || !mounted) return;
      }
      if (!mounted) return;
      setState(() {
        _importBusy = true;
        _importErrors = [];
        _importResultMessage = null;
      });
      if (!await _refreshConflictSchedules() || !mounted) return;
      final latestRows = _buildPreviewRows(ref.read(defenseSchedulerProvider));
      final latestReadySources = latestRows
          .where((row) => row.ready)
          .map((row) => row.source)
          .toSet();
      if (readyRows.any((row) => !latestReadySources.contains(row.source))) {
        setState(
          () => _importErrors = [
            'The schedule changed during review. Resolve the new conflicts before importing.',
          ],
        );
        return;
      }
      final result = await ref
          .read(defenseSchedulerProvider.notifier)
          .importSchedules(readyRows.map((row) => row.toPayload()).toList());
      if (!mounted) return;
      final created = result['created'] as int? ?? 0;
      final errors =
          (result['errors'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
      final importedIndices =
          (result['imported_indices'] as List?)?.whereType<int>().toList() ??
          <int>[];
      // Remove only confirmed successes so retrying does not recreate imported slots.
      final importedSources = importedIndices
          .where((index) => index >= 0 && index < readyRows.length)
          .map((index) => readyRows[index].source)
          .toSet();
      if (_parsed != null && importedSources.isNotEmpty) {
        final planned = {for (final row in previewRows) row.source: row};
        _parsed = _parsed!.copyWith(
          rows: _parsed!.rows
              .where((row) => !importedSources.contains(row))
              .map((source) {
                final row = planned[source]!;
                return source.copyWith(
                  startTime: row.effectiveStartTime,
                  endTime: row.effectiveEndTime,
                  time: row.timeLabel,
                  slotDuration: row.duration,
                  date: row.date,
                  room: row.room,
                );
              })
              .toList(),
        );
        // Gaps left by imported slots are fixed appointments on subsequent edits.
        _reflowStartTimes = false;
      }
      final remaining = _parsed?.rows.length ?? 0;
      if (errors.isEmpty && remaining == 0) {
        _draftDebounce?.cancel();
        await clearScheduleImportDraft(
          scope: widget.scope,
          semesterId: _semesterId,
        );
        if (!mounted) return;
        _lastSavedSnapshot = null;
        showSuccessToast(
          context,
          'Imported $created defense schedule slots. View them on the Defense Board.',
        );
        widget.onBack();
      } else {
        await _refreshConflictSchedules();
        if (!mounted) return;
        setState(() {
          _importErrors = errors;
          _importResultMessage = created > 0
              ? 'Imported $created slots. $remaining ${remaining == 1 ? 'slot remains' : 'slots remain'} in your draft.'
              : null;
          _collapsedSessions.clear();
        });
        await _persistDraft();
        if (_reviewScrollController.hasClients) {
          _reviewScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _importErrors = ['Unable to import slots: $error']);
      }
    } finally {
      _awaitingImportConfirmation = false;
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Widget _headerPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: DefensysTokens.textSecondaryOf(context),
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

  Widget _buildTemplateSpecTag(String label, {bool isRequired = false}) {
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
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isRequired ? FontWeight.w600 : FontWeight.w500,
                color: isRequired ? _ink : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleFormatCard(String activeSemLabel) {
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
                  child: const Icon(
                    Icons.description_outlined,
                    color: _maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPit
                            ? 'Official PIT Timetable Specification'
                            : 'Official Capstone Timetable Specification',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel · Standard Defense Timetable Format',
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

            // Two-Tier Document Blueprint Container
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
                  // Tier 1: Preamble Metadata
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.assignment_outlined,
                        size: 14,
                        color: Color(0xFF475569),
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
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
                      _buildTemplateSpecTag(
                        _isPit ? 'Event Header' : 'Stage Header',
                      ),
                      _buildTemplateSpecTag('Date Header'),
                      _buildTemplateSpecTag('Room / Venue Header'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  // Tier 2: Core Required Columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.table_rows_outlined,
                        size: 14,
                        color: _maroon,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'DEFENSE ROSTER SPECIFICATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
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
                      _buildTemplateSpecTag('Time Slot', isRequired: true),
                      _buildTemplateSpecTag('Team Name', isRequired: true),
                      _buildTemplateSpecTag(
                        _isPit ? 'PIT Project' : 'Capstone Project',
                        isRequired: true,
                      ),
                      _buildTemplateSpecTag('Adviser', isRequired: true),
                      _buildTemplateSpecTag('Panelists', isRequired: true),
                      if (!_isPit) _buildTemplateSpecTag('Documenter'),
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
                    'Multi-row or single-row timetable formats accepted. Headers are auto-extracted.',
                    style: TextStyle(
                      fontSize: 11,
                      color: _muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showScheduleBlueprintModal(
                    context,
                    isPit: _isPit,
                    activeSemLabel: activeSemLabel,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('View Sheet Layout Blueprint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _downloadSampleTemplate,
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download Sample Template (.xlsx)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleUploadCard(
    int totalRows,
    int readyCount,
  ) => DefensysCard(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      color: DefensysTokens.maroonOf(context),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upload Defense Spreadsheet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Supports Microsoft Excel (.xlsx) and CSV (.csv) timetables',
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_sourceFiles.isNotEmpty &&
                        constraints.maxWidth >= 360) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _pickFile(),
                        child: const Text('Add files'),
                      ),
                    ],
                  ],
                ),
                if (_sourceFiles.isNotEmpty && constraints.maxWidth < 360)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _pickFile(),
                        child: const Text('Add files'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _busy ? null : () => _pickFile(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              decoration: BoxDecoration(
                color: DefensysTokens.backgroundOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DefensysTokens.borderOf(context)),
              ),
              child: Column(
                children: [
                  if (_fileBusy)
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 28,
                      color: DefensysTokens.maroonOf(context),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Click to choose timetable spreadsheets (.xlsx / .csv)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add multiple files to the same review draft.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildFormatPill('XLSX'),
                      _buildFormatPill('CSV'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_sourceFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  '${_sourceFiles.length} ${_sourceFiles.length == 1 ? 'file' : 'files'} · $totalRows staged slots',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _pickFile(replaceAll: true),
                  child: const Text('Replace all'),
                ),
              ],
            ),
            for (final file in _sourceFiles)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DefensysTokens.borderOf(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () =>
                                      setState(() => _selectedFileId = file.id),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              foregroundColor:
                                  DefensysTokens.textPrimaryOf(context),
                              padding: EdgeInsets.zero,
                            ),
                            icon: Icon(
                              Icons.description_outlined,
                              size: 14,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                            label: Text(
                              file.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          Text(
                            '${file.parsed.rows.length} slots staged',
                            style: TextStyle(
                              fontSize: 11,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _pickFile(replaceFileId: file.id),
                      child: const Text('Replace'),
                    ),
                    IconButton(
                      tooltip: 'Remove ${file.name}',
                      onPressed: _busy ? null : () => _removeSource(file),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _buildMismatchBanner({
    required String message,
    required VoidCallback onDismiss,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB45309),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFFB45309),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }

  Widget _buildRedefenseBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8B4FE)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.replay_circle_filled_rounded,
            color: Color(0xFF7E22CE),
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Detected Re-defense timetable: Attempt 2 schedules will be created for eligible teams. Attempt 1 grades and remarks are preserved in audit history.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF581C87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearReviewFilters() {
    setState(() {
      _searchCtrl.clear();
      _showIssuesOnly = false;
      _filterDate = null;
      _filterRoom = null;
    });
  }

  String _targetLabel(DefenseSchedulerState state) => _isPit
      ? _importEventName
      : state.defenseStages
                .where((stage) => asInt(stage['id']) == _importStageId)
                .firstOrNull?['label']
                ?.toString() ??
            'Defense stage';

  Future<void> _viewGradingSetup() async {
    await _persistDraft();
    if (!mounted) return;
    context.go(
      _isPit
          ? FacultyRoutes.pitEvents
          : _importStageId == null
          ? AdminRoutes.defenseStages
          : AdminRoutes.defenseStageEdit(_importStageId!, initialTab: 1),
    );
  }

  Future<void> _openSettings(DefenseSchedulerState state) async {
    if (_busy || _parsed == null) return;
    final result = await showDialog<ScheduleImportSettingsResult>(
      context: context,
      builder: (_) => ScheduleImportSettingsDialog(
        title: _targetLabel(state),
        files: _sourceFiles,
        rows: _parsed!.rows,
        previewRows: _buildPreviewRows(state),
        targets: _isPit ? state.pitEvents : state.defenseStages,
        isPit: _isPit,
        stageId: _importStageId,
        eventName: _importEventName,
        date: _dateController.text.isNotEmpty
            ? _dateController.text
            : _parsed?.rows
                    .map((r) => r.date.trim())
                    .firstWhere((d) => d.isNotEmpty, orElse: () => '') ??
                '',
        room: _roomController.text.isNotEmpty
            ? _roomController.text
            : _parsed?.rows
                    .map((r) => r.room.trim())
                    .firstWhere((r) => r.isNotEmpty, orElse: () => '') ??
                '',
        duration: int.tryParse(_durationController.text) ??
            _parsed?.rows.map((r) => r.slotDuration).whereType<int>().firstOrNull ??
            60,
        selectedFileId: _selectedFileId,
        gradingSummaries: [
          'Panel: ${_panelRubricName ?? 'Not configured'} ($_panelWeight%)',
          'Peer: ${_peerRubricName ?? 'Not configured'} ($_peerWeight%)',
          if (!_isPit) 'Adviser: ${_adviserRubricName ?? 'Not configured'}',
        ],
        onViewGrading: _viewGradingSetup,
        timingIssues: (rows) => _previewForRows(rows, state)
            .expand((row) => row.slotIssues)
            .where(
              (issue) =>
                  issue.startsWith('Time overlap') ||
                  issue.contains('past midnight'),
            )
            .toSet()
            .toList(),
      ),
    );
    if (result == null || !mounted) return;
    if (result.clearDraft) {
      await _confirmDiscardDraft();
      return;
    }
    final targetChanged =
        result.stageId != _importStageId ||
        result.eventName != _importEventName;
    setState(() {
      _parsed = _parsed!.copyWith(rows: result.rows);
      _importStageId = result.stageId;
      _importEventName = result.eventName;
      _dateController.text = result.date;
      _roomController.text = result.room;
      _durationController.text = result.duration.toString();
      _collapsedSessions.clear();
      _importErrors = [];
    });
    if (targetChanged) {
      if (_isPit) {
        await _loadPitEventConfig(_importEventName);
      } else {
        await _loadStageRubrics(_importStageId);
      }
    }
    _scheduleDraftSave();
  }

  Widget _buildStageHeader(
    DefenseSchedulerState state,
    List<ScheduleImportPreviewRow> rows,
  ) {
    final groups = _partitionIntoCommitteeGroups(rows),
        durations = rows.map((row) => row.duration).toSet();
    final configured =
        _panelRubricId != null &&
        _peerRubricId != null &&
        (_isPit || _adviserRubricId != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _targetLabel(state).isEmpty
                        ? 'Select a target'
                        : _targetLabel(state),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: DefensysTokens.maroonOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${rows.length} slots · ${groups.length} ${groups.length == 1 ? 'session' : 'sessions'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _openSettings(state),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: DefensysTokens.borderOf(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              icon: const Icon(Icons.tune_outlined, size: 16),
              label: const Text('Settings'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 4.5,
              ),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: DefensysTokens.borderOf(context).withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                durations.length > 1
                    ? 'Mixed slot durations'
                    : '${durations.firstOrNull ?? _durationController.text} min / slot',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 4.5,
              ),
              decoration: BoxDecoration(
                color: _rubricLoading
                    ? DefensysTokens.surfaceHigherOf(context)
                    : configured
                    ? DefensysTokens.successBg
                    : DefensysTokens.warningBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _rubricLoading
                      ? DefensysTokens.borderOf(context)
                      : configured
                      ? DefensysTokens.successBorder
                      : DefensysTokens.warningBorder,
                ),
              ),
              child: Text(
                _rubricLoading
                    ? 'Checking rubrics…'
                    : configured
                    ? 'Rubrics configured'
                    : 'Rubrics incomplete',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _rubricLoading
                      ? DefensysTokens.textSecondaryOf(context)
                      : configured
                      ? DefensysTokens.successText
                      : DefensysTokens.goldOf(context),
                ),
              ),
            ),
          ],
        ),
        if (_showDraftRestoredNotice)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved draft restored. Your source files and session edits are ready to review.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss draft notice',
                  onPressed: () =>
                      setState(() => _showDraftRestoredNotice = false),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final choices = [
              ButtonSegment<String>(
                value: 'all',
                label: Text('All files ${rows.length}'),
              ),
              for (final file in _sourceFiles)
                ButtonSegment(
                  value: file.id,
                  label: Text('${file.name} ${file.parsed.rows.length}'),
                ),
            ];
            if (constraints.maxWidth < 700 ||
                _sourceFiles.length > 3 ||
                _sourceFiles.fold<int>(
                      110,
                      (sum, file) => sum + file.name.length * 7 + 80,
                    ) >
                    constraints.maxWidth) {
              return DropdownButtonFormField<String>(
                key: ValueKey(_selectedFileId),
                initialValue: _selectedFileId ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Review files',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All files'),
                  ),
                  for (final file in _sourceFiles)
                    DropdownMenuItem(
                      value: file.id,
                      child: Text(file.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(
                          () => _selectedFileId = value == 'all' ? null : value,
                        );
                        _scheduleDraftSave();
                      },
              );
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: choices,
                selected: {_selectedFileId ?? 'all'},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (value) {
                        setState(
                          () => _selectedFileId = value.first == 'all'
                              ? null
                              : value.first,
                        );
                        _scheduleDraftSave();
                      },
                style: SegmentedButton.styleFrom(
                  side: BorderSide(color: DefensysTokens.borderOf(context)),
                  backgroundColor: DefensysTokens.surfaceOf(context),
                  selectedBackgroundColor: DefensysTokens.surfaceHigherOf(
                    context,
                  ),
                  selectedForegroundColor: DefensysTokens.textPrimaryOf(
                    context,
                  ),
                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                  textStyle: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Divider(color: DefensysTokens.borderOf(context), height: 1),
      ],
    );
  }

  Widget _buildPreflightReviewCard({
    required DefenseSchedulerState schedState,
    required List<ScheduleImportPreviewRow> previewRows,
  }) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final scopeRows = previewRows
        .where(
          (row) =>
              _selectedFileId == null ||
              row.source.sourceFileId == _selectedFileId,
        )
        .toList();
    final issueCount = scopeRows.where((row) => !row.ready).length;
    final dates = scopeRows.map((row) => row.date).toSet().toList()..sort();
    final rooms = scopeRows.map((row) => row.room).toSet().toList()..sort();
    final selectedDate = dates.contains(_filterDate) ? _filterDate : null;
    final selectedRoom = rooms.contains(_filterRoom) ? _filterRoom : null;
    final filteredRows = previewRows.where((row) {
      if (_selectedFileId != null &&
          row.source.sourceFileId != _selectedFileId) {
        return false;
      }
      if (_showIssuesOnly && row.ready) return false;
      if (selectedDate != null && row.date != selectedDate) return false;
      if (selectedRoom != null && row.room != selectedRoom) return false;
      if (query.isEmpty) return true;
      return [
        row.teamLabel,
        row.projectLabel,
        row.source.adviser,
        row.adviserLabel,
        row.panelLabel,
        row.room,
        row.source.documenter,
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
    final noIssues =
        _showIssuesOnly &&
        issueCount == 0 &&
        query.isEmpty &&
        selectedDate == null &&
        selectedRoom == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          if (!DefensysTokens.isDark(context))
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStageHeader(schedState, previewRows),
          const Align(
            alignment: Alignment.centerRight,
            child: PanelistPoolButton(),
          ),
          if (schedState.canApprovePanelists)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Confirming this import approves the listed faculty as reusable panelists and assigns them to these defenses.',
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontSize: 13,
                ),
              ),
            ),
          if (_conflictCheckError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _conflictCheckError!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _conflictLoading
                        ? null
                        : _refreshConflictSchedules,
                    child: const Text('Retry validation'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          ScheduleImportFilterBar(
            totalCount: previewRows
                .where(
                  (row) =>
                      _selectedFileId == null ||
                      row.source.sourceFileId == _selectedFileId,
                )
                .length,
            issueCount: previewRows
                .where(
                  (row) =>
                      !row.ready &&
                      (_selectedFileId == null ||
                          row.source.sourceFileId == _selectedFileId),
                )
                .length,
            issuesOnly: _showIssuesOnly,
            searchController: _searchCtrl,
            enabled: !_importBusy,
            onSearchChanged: (_) => setState(() {}),
            onIssuesOnlyChanged: (value) =>
                setState(() => _showIssuesOnly = value),
            dates: dates,
            rooms: rooms,
            selectedDate: selectedDate,
            selectedRoom: selectedRoom,
            onDateChanged: (value) => setState(() => _filterDate = value),
            onRoomChanged: (value) => setState(() => _filterRoom = value),
            onClear: _clearReviewFilters,
          ),
          if (_importResultMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: DefensysTokens.successText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _importResultMessage!,
                      style: TextStyle(
                        fontSize: 14,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _importBusy ? null : () => widget.onBack(),
                    child: const Text('View Defense Board'),
                  ),
                ],
              ),
            ),
          if (_importErrors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: _buildImportErrorBox(_importErrors),
            ),
          const SizedBox(height: 12),
          if (filteredRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                children: [
                  Icon(
                    noIssues
                        ? Icons.task_alt_rounded
                        : Icons.search_off_rounded,
                    size: 32,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    previewRows.isEmpty
                        ? 'No schedule slots found'
                        : noIssues
                        ? 'No slots need attention'
                        : 'No matching schedule slots',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    previewRows.isEmpty
                        ? 'Check the spreadsheet format and replace the file.'
                        : noIssues
                        ? 'All slots passed validation. Review them in the All tab.'
                        : 'Try a different search or clear your filters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  if (previewRows.isNotEmpty)
                    TextButton(
                      onPressed: _clearReviewFilters,
                      child: Text(
                        noIssues ? 'View all slots' : 'Clear filters',
                      ),
                    ),
                ],
              ),
            )
          else
            _buildGroupedSlotsDataTable(filteredRows, allRows: previewRows),
          ScheduleImportActionBar(
            totalCount: previewRows.length,
            readyCount: previewRows.where((row) => row.ready).length,
            busy: _busy,
            validating: _rubricLoading || _conflictLoading,
            validationFailed: _conflictCheckError != null,
            onSave: () => _persistDraft(showToast: true),
            onDiscard: _confirmDiscardDraft,
            showDraftOptions: false,
            savedAt: _draftSavedAt,
            onImport: () => _importReadySlots(previewRows),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedSlotsDataTable(
    List<ScheduleImportPreviewRow> rows, {
    required List<ScheduleImportPreviewRow> allRows,
  }) {
    final visibleSources = rows.map((row) => row.source).toSet();
    final allGroups = _partitionIntoCommitteeGroups(allRows);
    final groups = allGroups
        .where(
          (group) =>
              group.rows.any((row) => visibleSources.contains(row.source)),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = Text(
                '${rows.length} slots across ${groups.length} ${groups.length == 1 ? 'session' : 'sessions'}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              );
              final actions = Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _collapsedSessions.clear()),
                    style: TextButton.styleFrom(
                      foregroundColor: DefensysTokens.textSecondaryOf(context),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Expand all'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _collapsedSessions.addAll(
                              groups.map((group) => group.identity),
                            ),
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: DefensysTokens.textSecondaryOf(context),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Collapse all'),
                  ),
                ],
              );
              return constraints.maxWidth < 500
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [summary, const SizedBox(height: 8), actions],
                    )
                  : Row(
                      children: [
                        Expanded(child: summary),
                        actions,
                      ],
                    );
            },
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            ScheduleImportSessionCard(
              key: ValueKey('session_${groups[i].identity}'),
              index: allGroups.indexOf(groups[i]) + 1,
              date: groups[i].date,
              room: groups[i].room,
              timeSpan: groups[i].timeSpanLabel,
              chair: groups[i].chair,
              panelMembers: groups[i].panelMembers,
              documenter: _isPit ? null : groups[i].documenter,
              totalCount: groups[i].totalCount,
              issueCount: groups[i].issueCount,
              expanded: !_collapsedSessions.contains(groups[i].identity),
              enabled: !_importBusy,
              onToggle: () => setState(() {
                final id = groups[i].identity;
                if (!_collapsedSessions.remove(id)) _collapsedSessions.add(id);
              }),
              committeeVaries: groups[i].committeeVaries,
              table: _buildCommitteeTable(
                groups[i],
                visibleRows: groups[i].rows
                    .where((row) => visibleSources.contains(row.source))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_CommitteeSessionGroup> _partitionIntoCommitteeGroups(
    List<ScheduleImportPreviewRow> rows,
  ) {
    final byId = {for (final row in rows) row.source.importRowId: row};
    final effective = rows
        .map(
          (row) => row.source.copyWith(
            date: row.date,
            room: row.room,
            startTime: row.effectiveStartTime,
            endTime: row.effectiveEndTime,
            slotDuration: row.duration,
          ),
        )
        .toList();
    return scheduleImportSessionGroups(effective).map((group) {
      final first = group.first;
      return _CommitteeSessionGroup(
        date: first.date,
        room: first.room,
        chair: first.chair,
        panelMembers: first.panelMembers,
        documenter: first.documenter,
        rows: group.map((row) => byId[row.importRowId]!).toList(),
      );
    }).toList();
  }

  Widget _buildCommitteeTable(
    _CommitteeSessionGroup group, {
    required List<ScheduleImportPreviewRow> visibleRows,
  }) {
    final showIssues = visibleRows.any(
      (row) => !row.ready || row.warnings.isNotEmpty,
    );
    final primary = TextStyle(
      fontSize: 13,
      color: DefensysTokens.textPrimaryOf(context),
    );
    final secondary = TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: DefensysTokens.textSecondaryOf(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            dataRowMinHeight: 54,
            dataRowMaxHeight: double.infinity,
            headingRowHeight: 38,
            headingRowColor: WidgetStateProperty.all(
              DefensysTokens.surfaceHigherOf(context).withValues(alpha: 0.6),
            ),
            headingTextStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            horizontalMargin: 16,
            columnSpacing: 28,
            dividerThickness: 0.5,
            columns: [
              const DataColumn(label: Text('Time')),
              const DataColumn(label: Text('Team / source')),
              const DataColumn(label: Text('Adviser')),
              if (group.committeeVaries)
                const DataColumn(label: Text('Committee')),
              const DataColumn(label: Text('Status')),
              if (showIssues) const DataColumn(label: Text('Issues / notices')),
            ],
            rows: visibleRows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: DefensysTokens.surfaceHigherOf(context)
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            scheduleReviewTimeRange(
                              row.effectiveStartTime,
                              row.effectiveEndTime,
                            ),
                            style: primary.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.teamLabel,
                                style: primary.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Tooltip(
                                message:
                                    '${row.source.sourceFileName} · Row ${row.source.sheetRow}',
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 240,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.table_chart_outlined,
                                        size: 11,
                                        color: DefensysTokens.textSecondaryOf(
                                          context,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          '${row.source.sourceFileName} · Row ${row.source.sheetRow}',
                                          style: secondary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          row.adviserLabel.isEmpty ? '—' : row.adviserLabel,
                          style: row.adviserLabel.isEmpty ? secondary : primary,
                        ),
                      ),
                      if (group.committeeVaries)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'Chair: ${row.source.chair}\nPanel: ${row.panelLabel}\nDocumenter: ${row.source.documenter}',
                                style: secondary,
                              ),
                            ),
                          ),
                        ),
                      DataCell(_importStatusChip(row)),
                      if (showIssues)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: _buildValidationIssuesCell(context, row),
                          ),
                        ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildValidationIssuesCell(
    BuildContext context,
    ScheduleImportPreviewRow row,
  ) {
    if (row.ready && row.warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    final issueWidgets = <Widget>[];

    if (row.stageIssues.isNotEmpty) {
      issueWidgets.add(
        _issueCategoryPill(
          prefix: 'Stage',
          message: row.stageIssues.join('; '),
          color: const Color(0xFFB45309),
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          tooltip: row.scope == 'pit'
              ? 'Click to configure PIT event in PIT Events Management'
              : 'Click to configure stage rubrics in Defense Stages Setup',
          onTap: () {
            if (row.scope == 'pit') {
              context.go(FacultyRoutes.pitEvents);
            } else if (row.stageId != null) {
              context.go(
                AdminRoutes.defenseStageEdit(row.stageId!, initialTab: 1),
              );
            } else {
              context.go(AdminRoutes.defenseStages);
            }
          },
        ),
      );
    }

    if (row.teamIssues.isNotEmpty) {
      issueWidgets.add(
        _issueCategoryPill(
          prefix: 'Team',
          message: row.teamIssues.join('; '),
          color: const Color(0xFFB42318),
          bg: const Color(0xFFFEF3F2),
          border: const Color(0xFFFECDCA),
          tooltip: row.teamId != null
              ? 'Click to view ${row.teamLabel} details & endorsement status'
              : 'Click to open Student Teams Hub',
          onTap: () {
            if (row.teamId != null) {
              context.go(AdminRoutes.teamDetail(row.teamId!));
            } else {
              context.go(AdminRoutes.studentTeams);
            }
          },
        ),
      );
    }

    if (row.slotIssues.isNotEmpty) {
      final hasFileIssue =
          row.source.parseIssues.isNotEmpty || row.source.chair.trim().isEmpty;
      final needsFacultyReview =
          !hasFileIssue &&
          row.slotIssues.any(
            (s) =>
                !s.toLowerCase().contains('overlap') &&
                (s.toLowerCase().contains('panel') ||
                    s.toLowerCase().contains('documenter') ||
                    s.toLowerCase().contains('faculty')),
          );
      issueWidgets.add(
        _issueCategoryPill(
          prefix: hasFileIssue ? 'File' : 'Slot',
          message: row.slotIssues.join('; '),
          color: const Color(0xFF991B1B),
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          tooltip: hasFileIssue
              ? 'Correct the spreadsheet and upload it again'
              : needsFacultyReview
              ? 'Click to open User Management to check faculty accounts'
              : null,
          onTap: needsFacultyReview
              ? () {
                  context.go(AdminRoutes.users);
                }
              : null,
        ),
      );
    }

    if (row.warnings.isNotEmpty) {
      issueWidgets.add(
        _issueCategoryPill(
          prefix: 'Notice',
          message: row.warnings.join('; '),
          color: const Color(0xFF475569),
          bg: const Color(0xFFF1F5F9),
          border: const Color(0xFFCBD5E1),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < issueWidgets.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            issueWidgets[i],
          ],
        ],
      ),
    );
  }

  Widget _issueCategoryPill({
    required String prefix,
    required String message,
    required Color color,
    required Color bg,
    required Color border,
    String? tooltip,
    VoidCallback? onTap,
  }) {
    final pillWidget = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  prefix.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 5),
                Icon(Icons.open_in_new_rounded, size: 11.5, color: color),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: pillWidget);
    }
    return pillWidget;
  }

  Widget _importStatusChip(ScheduleImportPreviewRow row) {
    if (row.ready && (_conflictLoading || _conflictCheckError != null)) {
      return _statusChipBadge(
        label: _conflictLoading ? 'Checking' : 'Unverified',
        icon: Icons.schedule_outlined,
        fg: DefensysTokens.textSecondaryOf(context),
        bg: DefensysTokens.surfaceHigherOf(context),
        border: DefensysTokens.borderOf(context),
      );
    }
    if (row.ready) {
      if (row.isRedefense) {
        return _statusChipBadge(
          label: 'Re-defense',
          icon: Icons.replay_circle_filled_rounded,
          fg: const Color(0xFF7E22CE),
          bg: const Color(0xFFF3E8FF),
          border: const Color(0xFFD8B4FE),
        );
      }
      return _statusChipBadge(
        label: 'Ready',
        icon: Icons.check_circle_rounded,
        fg: const Color(0xFF027A48),
        bg: const Color(0xFFECFDF3),
        border: const Color(0xFFA6F4C5),
      );
    }

    if (row.hasStageIssue) {
      return _statusChipBadge(
        label: 'Stage Incomplete',
        icon: Icons.layers_clear_outlined,
        fg: const Color(0xFFB45309),
        bg: const Color(0xFFFFFBEB),
        border: const Color(0xFFFDE68A),
      );
    }
    if (row.isAlreadyPassed) {
      return _statusChipBadge(
        label: 'Already Passed',
        icon: Icons.task_alt_rounded,
        fg: const Color(0xFF475569),
        bg: const Color(0xFFF1F5F9),
        border: const Color(0xFFCBD5E1),
      );
    }
    if (row.isAlreadyScheduled) {
      return _statusChipBadge(
        label: 'Already Scheduled',
        icon: Icons.schedule_rounded,
        fg: const Color(0xFFB45309),
        bg: const Color(0xFFFFFBEB),
        border: const Color(0xFFFDE68A),
      );
    }
    if (row.isNotEndorsed) {
      return _statusChipBadge(
        label: 'Not Endorsed',
        icon: Icons.lock_clock_rounded,
        fg: const Color(0xFFB42318),
        bg: const Color(0xFFFEF3F2),
        border: const Color(0xFFFECDCA),
      );
    }
    if (row.teamId == null) {
      return _statusChipBadge(
        label: 'Team Unresolved',
        icon: Icons.person_search_outlined,
        fg: const Color(0xFFB42318),
        bg: const Color(0xFFFEF3F2),
        border: const Color(0xFFFECDCA),
      );
    }
    if (row.hasSlotIssue) {
      final conflict = row.slotIssues.any(
        (issue) => issue.startsWith('Time overlap'),
      );
      return _statusChipBadge(
        label: conflict ? 'Time conflict' : 'Incomplete Slot',
        icon: conflict
            ? Icons.warning_amber_rounded
            : Icons.edit_calendar_outlined,
        fg: const Color(0xFFB42318),
        bg: const Color(0xFFFEF3F2),
        border: const Color(0xFFFECDCA),
      );
    }
    return _statusChipBadge(
      label: 'Needs attention',
      icon: Icons.warning_amber_rounded,
      fg: const Color(0xFFB42318),
      bg: const Color(0xFFFFF7ED),
      border: const Color(0xFFFEDF89),
    );
  }

  Widget _statusChipBadge({
    required String label,
    required IconData icon,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportErrorBox(List<String> errors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors
            .take(4)
            .map(
              (error) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _downloadSampleTemplate() async {
    try {
      await downloadBinaryFile(
        filename: _isPit
            ? 'defensys-pit-defense-schedule-template.xlsx'
            : 'defensys-capstone-defense-schedule-template.xlsx',
        bytes: generateDefenseScheduleExcelBytes(isCapstone: !_isPit),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Unable to download the schedule template. Please try again.',
        );
      }
    }
  }

  void _showScheduleBlueprintModal(
    BuildContext context, {
    required bool isPit,
    required String activeSemLabel,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 840),
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
                        child: const Icon(
                          Icons.grid_on_rounded,
                          color: _maroon,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPit
                                  ? 'Official PIT Defense Schedule Blueprint'
                                  : 'Official Capstone Defense Schedule Blueprint',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Term: $activeSemLabel · Visual guide for defense timetables & panel assignments',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _muted,
                        ),
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
                        // Institutional Notice Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFF475569),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF334155),
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Single- & Multi-Day Schedules: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            'Use one Excel file for all defense days. Keep one day block for a single day, or copy a complete block below for more dates.\n\n',
                                      ),
                                      TextSpan(
                                        text:
                                            'Auto-Detection & Multi-Panelists: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            'Preamble rows (Stage, Date, Room) are automatically matched to system records. Multiple panel members can be specified in individual columns (Chair, Panel 1, etc.) or combined into a single comma-separated column.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Spreadsheet Preview (Scrollable horizontally and vertically)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: 1040,
                            child: _buildSampleScheduleSheetPreview(
                              isPit: isPit,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, color: _line),
                // Modal Footer
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _downloadSampleTemplate();
                          },
                          icon: const Icon(Icons.download_rounded, size: 15),
                          label: const Text('Download Sample Template (.xlsx)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ink,
                            side: const BorderSide(color: _line),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSampleScheduleSheetPreview({required bool isPit}) {
    final days = defenseScheduleTemplateDays(isCapstone: !isPit);
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 12,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isPit
                            ? 'pit_defense_schedule.xlsx'
                            : 'capstone_defense_schedule.xlsx',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: const Text(
                    'Preamble Auto-Detection & Panel Roster',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),

          for (var index = 0; index < days.length; index++) ...[
            if (index > 0)
              Container(
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFCBD5E1)),
                    bottom: BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: _buildGutterCell('${index * 9}'),
              ),
            _buildScheduleTemplateDay(
              isPit: isPit,
              day: days[index],
              firstRow: index * 9 + 1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleTemplateDay({
    required bool isPit,
    required DefenseScheduleTemplateDay day,
    required int firstRow,
  }) {
    final preamble = [day.stage, day.date, day.room];
    return Column(
      key: ValueKey('schedule_blueprint_day_${day.date}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < preamble.length; row++) ...[
          _buildCenteredSpreadsheetPreambleRow(
            rowNum: '${firstRow + row}',
            text: preamble[row],
            isBold: row == 0,
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
        ],
        Container(
          color: const Color(0xFFE2E8F0),
          child: Row(
            children: [
              _buildGutterCell('${firstRow + 3}', isHeader: true),
              _buildColumnHeaderCell('#', flex: 1),
              _buildColumnHeaderCell('Time', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
              _buildColumnHeaderCell('Adviser', flex: 4, isRequired: true),
              _buildColumnHeaderCell('Panel Chair', flex: 4, isRequired: true),
              _buildColumnHeaderCell(
                'Panel Member 1',
                flex: 4,
                isRequired: true,
              ),
              _buildColumnHeaderCell(
                'Panel Member 2',
                flex: 4,
                isRequired: true,
              ),
              _buildColumnHeaderCell(
                'Panel Member 3',
                flex: 4,
                isRequired: true,
              ),
              if (!isPit) _buildColumnHeaderCell('Documenter', flex: 4),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFCBD5E1)),

        _buildScheduleMerged4RowBlock(
          isPit: isPit,
          day: day,
          firstSlotRow: firstRow + 4,
        ),
      ],
    );
  }

  Widget _buildCenteredSpreadsheetPreambleRow({
    required String rowNum,
    required String text,
    bool isBold = false,
  }) {
    return Container(
      color: Colors.white,
      height: 28,
      child: Row(
        children: [
          _buildGutterCell(rowNum),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleMerged4RowBlock({
    required bool isPit,
    required DefenseScheduleTemplateDay day,
    required int firstSlotRow,
  }) {
    const slotHeight = 34.0;
    final rowCount = day.teams.length;
    final blockHeight = slotHeight * rowCount + rowCount - 1;

    Widget column(
      List<String> values, {
      required int flex,
      bool isBold = false,
      Color color = const Color(0xFF475569),
    }) => Expanded(
      flex: flex,
      child: Column(
        children: [
          for (var row = 0; row < rowCount; row++) ...[
            _buildSubCell(values[row], isBold: isBold, color: color),
            if (row < rowCount - 1)
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ],
        ],
      ),
    );

    Widget merged(String value, {bool documenter = false}) => Expanded(
      flex: 4,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: documenter
              ? const Color(0xFFFEF3C7).withValues(alpha: 0.35)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: documenter
                ? const Color(0xFFD97706)
                : const Color(0xFF94A3B8),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: documenter ? 10 : 10.5,
            fontWeight: FontWeight.w700,
            color: documenter
                ? const Color(0xFFB45309)
                : const Color(0xFF1E293B),
          ),
        ),
      ),
    );

    return SizedBox(
      height: blockHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                for (var row = 0; row < rowCount; row++) ...[
                  SizedBox(
                    height: slotHeight,
                    child: _buildGutterCell('${firstSlotRow + row}'),
                  ),
                  if (row < rowCount - 1)
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                ],
              ],
            ),
          ),
          column(
            List.generate(rowCount, (row) => '${row + 1}'),
            flex: 1,
            isBold: true,
          ),
          column(
            List.generate(rowCount, day.timeForSlot),
            flex: 3,
            isBold: true,
            color: const Color(0xFF334155),
          ),
          column(
            day.teams,
            flex: 3,
            isBold: true,
            color: const Color(0xFF1E293B),
          ),
          merged(day.adviser),
          column(
            List.generate(rowCount, (row) => day.panels[row ~/ 2][0]),
            flex: 4,
            isBold: true,
            color: _maroon,
          ),
          for (var member = 1; member <= 3; member++)
            column(
              List.generate(rowCount, (row) => day.panels[row ~/ 2][member]),
              flex: 4,
            ),
          if (!isPit) merged(day.documenter, documenter: true),
        ],
      ),
    );
  }

  Widget _buildSubCell(String text, {bool isBold = false, Color? color}) {
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: color ?? const Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _buildGutterCell(String rowNum, {bool isHeader = false}) {
    return Container(
      width: 26,
      padding: const EdgeInsets.symmetric(vertical: 5),
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

  Widget _buildColumnHeaderCell(
    String title, {
    required int flex,
    bool isRequired = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: _maroon,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommitteeSessionGroup {
  _CommitteeSessionGroup({
    required this.date,
    required this.room,
    required this.chair,
    required this.panelMembers,
    required this.documenter,
    required this.rows,
  });

  final String date;
  final String room;
  final String chair;
  final List<String> panelMembers;
  final String documenter;
  final List<ScheduleImportPreviewRow> rows;

  String get identity => rows.map((row) => row.source.importRowId).join('_');

  bool get committeeVaries =>
      rows
          .map(
            (row) =>
                '${row.chairLabel}|${row.panelLabel}|${row.documenterLabel}',
          )
          .toSet()
          .length >
      1;

  String get panelLabel =>
      panelMembers.isNotEmpty ? panelMembers.join(', ') : '-';

  String get timeSpanLabel {
    if (rows.isEmpty) return '';
    final ordered = List<ScheduleImportPreviewRow>.from(rows)
      ..sort((a, b) => a.effectiveStartTime.compareTo(b.effectiveStartTime));
    final start = ordered.first.effectiveStartTime;
    final ends = rows.map((row) => row.effectiveEndTime).toList()..sort();
    return '${scheduleReviewTime(start)} – ${scheduleReviewTime(ends.last)}';
  }

  List<String> get distinctAdvisers {
    final list = <String>[];
    for (final r in rows) {
      final adv = r.source.adviser.trim();
      if (adv.isNotEmpty && adv != '-' && !list.contains(adv)) {
        list.add(adv);
      }
    }
    return list;
  }

  int get readyCount => rows.where((r) => r.ready).length;
  int get issueCount => rows.where((r) => !r.ready).length;
  int get totalCount => rows.length;
}
