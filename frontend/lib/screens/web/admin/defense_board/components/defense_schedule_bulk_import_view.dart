import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'schedule_import_review_widgets.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/export/defense_schedule_excel_generator.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/state/unsaved_changes.dart';
import 'package:defensys/utils/string_matching_utils.dart';

import '../../defense_scheduler/models/schedule_import_models.dart';

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
  static const Color _green = Color(0xFF15803D);
  static const Color _red = Color(0xFFB91C1C);

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  ParsedScheduleImport? _parsed;
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
  bool _showSettings = false;
  String? _filterDate;
  String? _filterRoom;
  String? _importResultMessage;
  final Set<String> _collapsedSessions = {};
  final ScrollController _reviewScrollController = ScrollController();

  bool get _isPit => widget.scope == 'pit';

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
    return '$_fileName|$_importStageId|$_importEventName|${_dateController.text.trim()}|${_roomController.text.trim()}|${_durationController.text.trim()}|$_panelRubricId|$_adviserRubricId|$_peerRubricId|$_panelWeight|$_peerWeight|${_parsed!.rows.length}';
  }

  bool _isDirty() {
    if (_parsed == null || _parsed!.rows.isEmpty) return false;
    if (_draftDebounce?.isActive ?? false) return true;
    final current = _currentDraftSnapshot();
    return _lastSavedSnapshot == null || current != _lastSavedSnapshot;
  }

  Future<void> _initDraftAndConfig() async {
    final schedState = ref.read(defenseSchedulerProvider);
    final existingDraft = await loadScheduleImportDraft(scope: widget.scope);

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
      _panelWeight = existingDraft.panelWeight;
      _peerWeight = existingDraft.peerWeight;

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

    if (mounted) setState(() {});
  }

  Future<void> _persistDraft({bool showToast = false}) async {
    _draftDebounce?.cancel();
    if (_parsed == null || _parsed!.rows.isEmpty) {
      await clearScheduleImportDraft(scope: widget.scope);
      _lastSavedSnapshot = null;
      return;
    }
    final draft = ScheduleImportDraft(
      parsed: _parsed!,
      scope: widget.scope,
      fileName: _fileName,
      stageId: _importStageId,
      eventName: _importEventName,
      date: _dateController.text,
      room: _roomController.text,
      duration: _durationController.text,
      panelRubricId: _panelRubricId,
      adviserRubricId: _adviserRubricId,
      peerRubricId: _peerRubricId,
      panelWeight: _panelWeight,
      peerWeight: _peerWeight,
      savedAt: DateTime.now(),
      rowCount: _parsed!.rows.length,
    );
    await saveScheduleImportDraft(draft);
    if (mounted) setState(() => _draftSavedAt = draft.savedAt);
    _lastSavedSnapshot = _currentDraftSnapshot();
    if (showToast && mounted) {
      showSuccessToast(context, 'Schedule import draft saved.');
    }
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), () {
      _persistDraft();
    });
  }

  Future<void> _discardDraft() async {
    _draftDebounce?.cancel();
    await clearScheduleImportDraft(scope: widget.scope);
    _lastSavedSnapshot = null;
    setState(() {
      _parsed = null;
      _fileName = null;
      _showDraftRestoredNotice = false;
      _showSettings = false;
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

  Future<void> _pickFile() async {
    final schedState = ref.read(defenseSchedulerProvider);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        showErrorToast(context, 'Unable to read the selected file.');
      }
      return;
    }

    try {
      final configuredStages = _isPit
          ? schedState.pitEvents
                .map((e) => e['event_name']?.toString() ?? '')
                .where((n) => n.isNotEmpty)
                .toList()
          : schedState.defenseStages
                .map((s) => s['label']?.toString() ?? '')
                .where((l) => l.isNotEmpty)
                .toList();

      final parsedResult = parseScheduleImportFile(
        bytes: bytes,
        filename: file.name,
        configuredStages: configuredStages,
      );

      _evaluateStageMatching(parsed: parsedResult, schedState: schedState);

      final defaultRoom = parsedResult.room?.trim() ?? '';
      final rowsWithInitialRoom = defaultRoom.isNotEmpty
          ? parsedResult.rows.map((r) {
              if (r.room.trim().isEmpty) {
                return r.copyWith(room: defaultRoom);
              }
              return r;
            }).toList()
          : parsedResult.rows;

      setState(() {
        _parsed = parsedResult.copyWith(rows: rowsWithInitialRoom);
        _fileName = file.name;
        _importErrors = [];
        _draftSavedAt = null;
        _lastSavedSnapshot = null;
        _showDraftRestoredNotice = false;
        _showSettings = false;
        _filterDate = null;
        _filterRoom = null;
        _searchCtrl.clear();
        _showIssuesOnly = false;
        _collapsedSessions.clear();
        _importResultMessage = null;
        if (parsedResult.date != null && parsedResult.date!.isNotEmpty) {
          _dateController.text = normalizeImportDate(parsedResult.date!);
        }
        if (defaultRoom.isNotEmpty) {
          _roomController.text = defaultRoom;
        }
        final detectedDuration = parsedResult.rows
            .map((r) => r.slotDuration)
            .firstWhere((d) => d != null && d > 0, orElse: () => null);
        if (detectedDuration != null) {
          _durationController.text = detectedDuration.toString();
        }
      });

      _scheduleDraftSave();

      if (!_isPit && _importStageId != null) {
        await _loadStageRubrics(_importStageId);
      } else if (_isPit && _importEventName.isNotEmpty) {
        await _loadPitEventConfig(_importEventName);
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Failed to parse schedule file: $e');
      }
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
      await clearScheduleImportDraft(scope: widget.scope);
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

  List<ScheduleImportPreviewRow> _buildPreviewRows(
    DefenseSchedulerState state,
  ) {
    return _parsed == null
        ? <ScheduleImportPreviewRow>[]
        : buildScheduleImportPreviewRows(
            _parsed!,
            state,
            scope: widget.scope,
            stageId: _importStageId,
            eventName: _importEventName,
            date: _dateController.text,
            room: _roomController.text,
            slotDuration: int.tryParse(_durationController.text.trim()),
            fallbackDuration:
                int.tryParse(_durationController.text.trim()) ?? 60,
            panelRubricId: _panelRubricId,
            adviserRubricId: _adviserRubricId,
            peerRubricId: _peerRubricId,
            panelWeight: _panelWeight,
            peerWeight: _peerWeight,
          );
  }

  @override
  Widget build(BuildContext context) {
    final schedState = ref.watch(defenseSchedulerProvider);
    final activeSemLabel = _getActiveSemLabel(schedState);
    final previewRows = _buildPreviewRows(schedState);
    final readyCount = previewRows.where((row) => row.ready).length;
    final hasFile = _parsed != null;

    return PopScope(
      canPop: !_importBusy && !_isDirty(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _importBusy) return;
        final canClose = await _handleAttemptClose();
        if (canClose && mounted) widget.onBack();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _reviewScrollController,
              padding: DefensysUi.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildReviewPageHeader(activeSemLabel, hasFile),
                  const SizedBox(height: 20),
                  Text(
                    hasFile
                        ? 'Upload complete  /  Review & resolve  /  Import'
                        : 'Upload spreadsheet  /  Review & resolve  /  Import',
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasFile)
                    ScheduleImportFileSummary(
                      fileName: _fileName,
                      slotCount: previewRows.length,
                      savedAt: _draftSavedAt,
                      busy: _importBusy,
                      onReplace: _pickFile,
                      onViewGuide: () => _showScheduleBlueprintModal(
                        context,
                        isPit: _isPit,
                        activeSemLabel: activeSemLabel,
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final format = _buildScheduleFormatCard(activeSemLabel);
                        final upload = _buildScheduleUploadCard(0, 0);
                        if (constraints.maxWidth < 960) {
                          return Column(
                            children: [
                              upload,
                              const SizedBox(height: 18),
                              format,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: format),
                            const SizedBox(width: 20),
                            Expanded(flex: 6, child: upload),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  if (_showDraftRestoredNotice && hasFile) ...[
                    _buildDraftRestoredBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (_mismatchWarning != null) ...[
                    _buildMismatchBanner(
                      message: _mismatchWarning!,
                      onDismiss: () => setState(() => _mismatchWarning = null),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_parsed?.isRedefense == true) ...[
                    _buildRedefenseBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (hasFile)
                    _buildPreflightReviewCard(
                      schedState: schedState,
                      previewRows: previewRows,
                    ),
                ],
              ),
            ),
          ),
          if (hasFile)
            ScheduleImportActionBar(
              totalCount: previewRows.length,
              readyCount: readyCount,
              busy: _importBusy,
              validating: _rubricLoading,
              onSave: () => _persistDraft(showToast: true),
              onDiscard: _confirmDiscardDraft,
              onImport: () => _importReadySlots(previewRows),
            ),
        ],
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
          onPressed: _importBusy
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
          title: hasFile
              ? 'Review defense schedule'
              : 'Import defense schedule',
          subtitle: hasFile
              ? 'Check assignments and resolve issues before importing.'
              : 'Upload a ${_isPit ? 'PIT' : 'Capstone'} timetable to review and schedule defense slots.',
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
    if (_importBusy || _awaitingImportConfirmation || _rubricLoading) return;
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
        _parsed = _parsed!.copyWith(
          rows: _parsed!.rows
              .where((row) => !importedSources.contains(row))
              .toList(),
        );
      }
      final remaining = _parsed?.rows.length ?? 0;
      if (errors.isEmpty && remaining == 0) {
        _draftDebounce?.cancel();
        await clearScheduleImportDraft(scope: widget.scope);
        if (!mounted) return;
        _lastSavedSnapshot = null;
        showSuccessToast(
          context,
          'Imported $created defense schedule slots. View them on the Defense Board.',
        );
        widget.onBack();
      } else {
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
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

  Widget _buildScheduleUploadCard(int totalRows, int readyCount) {
    final hasFile = _fileName != null && _parsed != null;
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
                    color: hasFile
                        ? const Color(0xFFDCFCE7)
                        : _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasFile
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: hasFile ? _green : _maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFile
                            ? 'Staged Timetable Spreadsheet'
                            : 'Upload Defense Spreadsheet',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasFile
                            ? '$_fileName · $totalRows slot(s) staged · $readyCount ready'
                            : 'Supports official Microsoft Excel (.xlsx) and CSV (.csv) timetables',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            InkWell(
              onTap: _importBusy ? null : _pickFile,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: hasFile
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasFile
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                    width: hasFile ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasFile
                          ? Icons.inventory_2_outlined
                          : Icons.cloud_upload_outlined,
                      size: 28,
                      color: hasFile ? _green : _maroon,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFile
                          ? '$_fileName (Click to Replace / Stage New File)'
                          : 'Click to choose timetable spreadsheet (.xlsx / .csv)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: hasFile ? const Color(0xFF15803D) : _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile
                          ? '$readyCount ready to schedule · ${issueCount > 0 ? '$issueCount needing review' : 'all valid'}'
                          : 'Multi-panelist, documenter, and custom rooms auto-matched',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasFile ? const Color(0xFF166534) : _muted,
                      ),
                    ),
                    if (!hasFile) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFormatPill('XLSX'),
                          const SizedBox(width: 6),
                          _buildFormatPill('CSV'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (hasFile) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _importBusy ? null : _discardDraft,
                  icon: const Icon(Icons.clear_all_rounded, size: 15),
                  label: const Text('Clear staged spreadsheet'),
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

  Widget _buildDraftRestoredBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history_rounded,
            size: 18,
            color: DefensysTokens.textSecondaryOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Draft restored. Your spreadsheet and settings are ready to review.',
              style: TextStyle(
                fontSize: 13,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss draft notification',
            onPressed: () => setState(() => _showDraftRestoredNotice = false),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

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

  Widget _buildCompactSessionToolbar(DefenseSchedulerState schedState) {
    final stageItems = <DropdownMenuItem<int?>>[];
    final seenStageIds = <int?>{};
    for (final stage in schedState.defenseStages) {
      final id = asInt(stage['id']);
      if (id != null && seenStageIds.add(id)) {
        stageItems.add(
          DropdownMenuItem<int?>(
            value: id,
            child: Text(stage['label']?.toString() ?? ''),
          ),
        );
      }
    }
    final effectiveStageId =
        stageItems.any((item) => item.value == _importStageId)
        ? _importStageId
        : null;

    final pitEventItems = <DropdownMenuItem<String>>[];
    final seenEvents = <String>{};
    for (final e in schedState.pitEvents) {
      final name = e['event_name']?.toString() ?? '';
      if (name.isNotEmpty && seenEvents.add(name)) {
        pitEventItems.add(
          DropdownMenuItem<String>(value: name, child: Text(name)),
        );
      }
    }
    final effectiveEventName =
        pitEventItems.any((e) => e.value == _importEventName)
        ? _importEventName
        : null;

    final pRubricName = _getRubricName(
      schedState,
      _panelRubricId,
      _panelRubricName,
    );
    final aRubricName = _getRubricName(
      schedState,
      _adviserRubricId,
      _adviserRubricName,
    );
    final peRubricName = _isPit
        ? _getPeerRubricName(schedState, _peerRubricId, _peerRubricName)
        : _getRubricName(schedState, _peerRubricId, _peerRubricName);

    final missingCapstoneRubrics = <String>[];
    if (!_isPit && _importStageId != null) {
      if (_panelRubricId == null) missingCapstoneRubrics.add('Panel');
      if (_adviserRubricId == null) missingCapstoneRubrics.add('Adviser');
      if (_peerRubricId == null) missingCapstoneRubrics.add('Peer');
    }
    final isCapstoneRubricMissing = missingCapstoneRubrics.isNotEmpty;

    final missingPitRubrics = <String>[];
    if (_isPit && _importEventName.isNotEmpty) {
      if (_panelRubricId == null) missingPitRubrics.add('Panel');
      if (_peerRubricId == null) missingPitRubrics.add('Peer');
    }
    final isPitRubricMissing = missingPitRubrics.isNotEmpty;
    final isRubricMissing = _isPit
        ? isPitRubricMissing
        : isCapstoneRubricMissing;
    final missingRubrics = _isPit ? missingPitRubrics : missingCapstoneRubrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Target Scope Group (Stage or PIT Event + Match indicator)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _isPit
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _isPit
                            ? Icons.event_note_rounded
                            : Icons.school_outlined,
                        size: 15,
                        color: _isPit
                            ? const Color(0xFF2563EB)
                            : DefensysUi.primaryMaroon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isPit ? 'TARGET EVENT' : 'TARGET STAGE',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 1),
                        if (_isPit) ...[
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: ValueKey(
                                'compact_pit_event_$effectiveEventName',
                              ),
                              value: effectiveEventName,
                              isDense: true,
                              hint: const Text(
                                'Select PIT event',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              icon: const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              items: pitEventItems,
                              onChanged: (val) async {
                                setState(() {
                                  _importEventName = val ?? '';
                                  if (_headerMatch != null &&
                                      _headerMatch!.isMatched) {
                                    if (_headerMatch!.label.toLowerCase() ==
                                        (val ?? '').toLowerCase()) {
                                      _mismatchWarning = null;
                                    } else {
                                      _mismatchWarning =
                                          'File header specifies "${_headerMatch!.sourceText}" (matched to "${_headerMatch!.label}"), while selected target event is "$val".';
                                    }
                                  } else if (_headerMatch != null &&
                                      !_headerMatch!.isMatched &&
                                      _headerMatch!.sourceText.isNotEmpty) {
                                    _mismatchWarning =
                                        'File header specifies event "${_headerMatch!.sourceText}", which does not match selected event "$val" (or any registered PIT event for this semester).';
                                  }
                                });
                                if (val != null) {
                                  await _loadPitEventConfig(val);
                                }
                              },
                            ),
                          ),
                        ] else ...[
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              key: ValueKey('compact_stage_$effectiveStageId'),
                              value: effectiveStageId,
                              isDense: true,
                              hint: const Text(
                                'Select stage',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              icon: const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              items: stageItems,
                              onChanged: (val) async {
                                setState(() {
                                  _importStageId = val;
                                  if (_headerMatch != null &&
                                      _headerMatch!.isMatched) {
                                    final matchedId = asInt(
                                      _headerMatch!.item?['id'],
                                    );
                                    if (matchedId == val) {
                                      _mismatchWarning = null;
                                    } else {
                                      final targetObj = schedState.defenseStages
                                          .firstWhere(
                                            (s) => asInt(s['id']) == val,
                                            orElse: () => <String, dynamic>{},
                                          );
                                      final targetLabel =
                                          targetObj['label'] ?? '';
                                      _mismatchWarning =
                                          'File header specifies "${_headerMatch!.sourceText}" (matched to "${_headerMatch!.label}"), while selected target stage is "$targetLabel".';
                                    }
                                  } else if (_headerMatch != null &&
                                      !_headerMatch!.isMatched &&
                                      _headerMatch!.sourceText.isNotEmpty) {
                                    final targetObj = schedState.defenseStages
                                        .firstWhere(
                                          (s) => asInt(s['id']) == val,
                                          orElse: () => <String, dynamic>{},
                                        );
                                    final targetLabel =
                                        targetObj['label'] ?? '';
                                    _mismatchWarning =
                                        'File header specifies stage "${_headerMatch!.sourceText}", which does not match selected stage "$targetLabel" (or any stage in your Academic Stage Chain).';
                                  }
                                });
                                await _loadStageRubrics(val);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_headerMatch != null) ...[
                      const SizedBox(width: 8),
                      _buildCompactHeaderMatchIndicator(_headerMatch!),
                    ],
                  ],
                ),
              ),

              // Vertical Divider between Scope and Parameters
              Container(height: 28, width: 1, color: const Color(0xFFCBD5E1)),

              // 2. Schedule Parameters Group (Date + Duration)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Start Date
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 13.5,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Start Date:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                DateTime.tryParse(_dateController.text) ??
                                today,
                            firstDate: today,
                            lastDate: DateTime(
                              now.year + 3,
                              now.month,
                              now.day,
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              _dateController.text = formatScheduleDate(picked);
                            });
                            _scheduleDraftSave();
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x06000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_month_outlined,
                                size: 13,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _dateController.text.isNotEmpty
                                    ? _dateController.text
                                    : 'YYYY-MM-DD',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _dateController.text.isNotEmpty
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Slot Duration
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Slot Duration:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        height: 32,
                        width: 106,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x06000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _durationController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                  hintText: '60',
                                  hintStyle: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                onChanged: (_) {
                                  setState(() {});
                                  _scheduleDraftSave();
                                },
                              ),
                            ),
                            const Text(
                              'min/slot',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Vertical Divider between Parameters and Rubrics
              Container(height: 28, width: 1, color: const Color(0xFFCBD5E1)),

              // 3. Evaluation Rubrics Group
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Rubrics:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_rubricLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    _compactRubricPill(
                      label: 'Panel',
                      value: pRubricName,
                      weight: '$_panelWeight%',
                      isAssigned:
                          _panelRubricId != null && pRubricName.isNotEmpty,
                    ),
                    if (!_isPit) ...[
                      const SizedBox(width: 6),
                      _compactRubricPill(
                        label: 'Adviser',
                        value: aRubricName,
                        isAssigned:
                            _adviserRubricId != null && aRubricName.isNotEmpty,
                      ),
                    ],
                    const SizedBox(width: 6),
                    _compactRubricPill(
                      label: 'Peer',
                      value: peRubricName,
                      weight: '$_peerWeight%',
                      isAssigned:
                          _peerRubricId != null && peRubricName.isNotEmpty,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Slim Missing Rubric Warning Banner
        if (!_rubricLoading && isRubricMissing)
          _buildSlimRubricsWarningBanner(schedState, missingRubrics),
      ],
    );
  }

  Widget _compactRubricPill({
    required String label,
    required String value,
    String? weight,
    required bool isAssigned,
  }) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: isAssigned ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isAssigned ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isAssigned ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 11,
            color: isAssigned ? const Color(0xFF16A34A) : _red,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isAssigned
                  ? const Color(0xFF166534)
                  : const Color(0xFF991B1B),
            ),
          ),
          Text(
            isAssigned
                ? (weight != null ? '$value ($weight)' : value)
                : 'Missing',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isAssigned ? const Color(0xFF14532D) : _red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlimRubricsWarningBanner(
    DefenseSchedulerState schedState,
    List<String> missingRubrics,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBEB),
        border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB45309),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPit
                  ? 'Event "$_importEventName" is missing required rubrics (${missingRubrics.join(', ')}). Slots cannot be imported until rubrics are assigned.'
                  : 'Stage "${_getStageLabel(schedState, _importStageId)}" is missing required rubrics (${missingRubrics.join(', ')}). Slots cannot be imported until rubrics are assigned.',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              if (_isPit) {
                context.go(FacultyRoutes.pitEvents);
              } else if (_importStageId != null) {
                context.go(
                  AdminRoutes.defenseStageEdit(_importStageId!, initialTab: 1),
                );
              } else {
                context.go(AdminRoutes.defenseStages);
              }
            },
            icon: const Icon(
              Icons.tune_rounded,
              size: 13,
              color: Color(0xFF92400E),
            ),
            label: Text(
              _isPit ? 'Configure Event' : 'Configure Stage Rubrics',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF92400E),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeaderMatchIndicator(MatchResult<dynamic> match) {
    if (match.sourceText.isEmpty) return const SizedBox.shrink();
    if (match.isExact) {
      return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 12,
              color: Color(0xFF16A34A),
            ),
            const SizedBox(width: 4),
            Text(
              'Matched: "${match.sourceText}"',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF166534),
              ),
            ),
          ],
        ),
      );
    }
    if (match.isCanonical || match.isFuzzy) {
      return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF8FF),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFB2DDFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 12, color: Color(0xFF175CD3)),
            const SizedBox(width: 4),
            Text(
              'Auto-matched "${match.sourceText}"',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF175CD3),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 4),
          Text(
            'Header in file: "${match.sourceText}"',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E),
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

  Widget _buildSettingsSummary(DefenseSchedulerState state) {
    final stage = state.defenseStages
        .where((s) => asInt(s['id']) == _importStageId)
        .firstOrNull;
    final label = _isPit ? _importEventName : stage?['label']?.toString() ?? '';
    final complete =
        _panelRubricId != null &&
        _peerRubricId != null &&
        (_isPit || _adviserRubricId != null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  label.isEmpty
                      ? 'Select a ${_isPit ? 'PIT event' : 'defense stage'}'
                      : label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                Text(
                  '${_durationController.text} minutes per slot',
                  style: TextStyle(
                    fontSize: 13,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                Text(
                  _rubricLoading
                      ? 'Checking rubrics...'
                      : complete
                      ? 'Rubrics configured'
                      : 'Rubrics incomplete',
                  style: TextStyle(
                    fontSize: 13,
                    color: !complete && !_rubricLoading
                        ? DefensysTokens.goldOf(context)
                        : DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _importBusy
                ? null
                : () => setState(() => _showSettings = !_showSettings),
            icon: Icon(
              _showSettings ? Icons.expand_less : Icons.tune_rounded,
              size: 16,
            ),
            label: Text(_showSettings ? 'Hide settings' : 'Edit settings'),
            style: TextButton.styleFrom(
              foregroundColor: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreflightReviewCard({
    required DefenseSchedulerState schedState,
    required List<ScheduleImportPreviewRow> previewRows,
  }) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final issueCount = previewRows.where((row) => !row.ready).length;
    final dates = previewRows.map((row) => row.date).toSet().toList()..sort();
    final rooms = previewRows.map((row) => row.room).toSet().toList()..sort();
    final selectedDate = dates.contains(_filterDate) ? _filterDate : null;
    final selectedRoom = rooms.contains(_filterRoom) ? _filterRoom : null;
    final filteredRows = previewRows.where((row) {
      if (_showIssuesOnly && row.ready) return false;
      if (selectedDate != null && row.date != selectedDate) return false;
      if (selectedRoom != null && row.room != selectedRoom) return false;
      if (query.isEmpty) return true;
      return [
        row.teamLabel,
        row.projectLabel,
        row.source.adviser,
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

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSettingsSummary(schedState),
          if (_showSettings)
            AbsorbPointer(
              absorbing: _importBusy,
              child: _buildCompactSessionToolbar(schedState),
            ),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          ScheduleImportFilterBar(
            totalCount: previewRows.length,
            issueCount: issueCount,
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
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
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
        ],
      ),
    );
  }

  void _updateSessionDate(_CommitteeSessionGroup group, String newDate) {
    if (_parsed == null) return;
    final targetSheetRows = group.rows.map((r) => r.source.sheetRow).toSet();
    final trimmed = newDate.trim();
    if (_filterDate == group.date) _filterDate = trimmed;
    final updatedRows = _parsed!.rows.map((r) {
      if (targetSheetRows.contains(r.sheetRow)) {
        return r.copyWith(date: trimmed);
      }
      return r;
    }).toList();

    setState(() {
      _parsed = _parsed!.copyWith(rows: updatedRows);
    });
    _scheduleDraftSave();
  }

  void _updateSessionVenue(_CommitteeSessionGroup group, String newRoom) {
    if (_parsed == null) return;
    final targetSheetRows = group.rows.map((r) => r.source.sheetRow).toSet();
    final trimmed = newRoom.trim();
    if (_filterRoom == group.room) _filterRoom = trimmed;
    final updatedRows = _parsed!.rows.map((r) {
      if (targetSheetRows.contains(r.sheetRow)) {
        return r.copyWith(room: trimmed);
      }
      return r;
    }).toList();

    setState(() {
      _parsed = _parsed!.copyWith(rows: updatedRows);
    });
    _scheduleDraftSave();
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length} slots across ${groups.length} ${groups.length == 1 ? 'session' : 'sessions'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                ),
                onPressed: _importBusy
                    ? null
                    : () => setState(() => _collapsedSessions.clear()),
                child: const Text('Expand all'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                ),
                onPressed: _importBusy
                    ? null
                    : () => setState(
                        () => _collapsedSessions.addAll(
                          groups.map((group) => group.identity),
                        ),
                      ),
                child: const Text('Collapse all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
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
              onDateChanged: (date) => _updateSessionDate(groups[i], date),
              onRoomChanged: (room) => _updateSessionVenue(groups[i], room),
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
    if (rows.isEmpty) return [];

    final groupMap = <String, _CommitteeSessionGroup>{};
    final orderedGroups = <_CommitteeSessionGroup>[];

    for (final row in rows) {
      final room = row.room.trim().isNotEmpty ? row.room.trim() : 'Unassigned';
      final chair = row.chairLabel.trim();
      final panelSignature = row.panelLabel.trim();
      final documenter = row.documenterLabel.trim();
      final date = row.date.trim();

      // Key groups all rows that share the same committee block
      final key = '$date|$room|$chair|$panelSignature|$documenter'
          .toLowerCase();

      if (groupMap.containsKey(key)) {
        groupMap[key]!.rows.add(row);
      } else {
        final newGroup = _CommitteeSessionGroup(
          date: date,
          room: room,
          chair: chair,
          panelMembers: List.from(row.source.panelMembers),
          documenter: documenter,
          rows: [row],
        );
        groupMap[key] = newGroup;
        orderedGroups.add(newGroup);
      }
    }

    return orderedGroups;
  }

  Widget _buildCommitteeTable(
    _CommitteeSessionGroup group, {
    required List<ScheduleImportPreviewRow> visibleRows,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dataRowMinHeight: 60,
              dataRowMaxHeight: double.infinity,
              headingRowHeight: 44,
              headingRowColor: WidgetStateProperty.all(
                DefensysTokens.surfaceHigherOf(context),
              ),
              headingTextStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
                letterSpacing: 0.2,
              ),
              columns: const [
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Time Slot')),
                DataColumn(label: Text('Team & Project')),
                DataColumn(label: Text('Adviser')),
                DataColumn(label: Text('Issues / notices')),
              ],
              rows: visibleRows.map((row) {
                return DataRow(
                  color: WidgetStateProperty.all(
                    DefensysTokens.isDark(context)
                        ? DefensysTokens.surfaceOf(context)
                        : row.ready
                        ? (row.isRedefense
                              ? const Color(0xFFFAF5FF)
                              : DefensysTokens.surfaceOf(context))
                        : (row.isAlreadyPassed
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFFFFFBEB).withValues(alpha: 0.5)),
                  ),
                  cells: [
                    DataCell(_importStatusChip(row)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            row.timeLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              row.teamLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            if (row.projectLabel.isNotEmpty &&
                                row.projectLabel != '-')
                              Text(
                                row.projectLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (row.room.isNotEmpty &&
                                row.room != group.room &&
                                row.room != 'Unassigned')
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Override Room: ${row.room}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0369A1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        row.source.adviser.isNotEmpty
                            ? row.source.adviser
                            : '-',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildValidationIssuesCell(context, row),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
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
                s.toLowerCase().contains('panel') ||
                s.toLowerCase().contains('documenter') ||
                s.toLowerCase().contains('faculty'),
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
      return _statusChipBadge(
        label: 'Incomplete Slot',
        icon: Icons.edit_calendar_outlined,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSampleScheduleSheetPreview({required bool isPit}) {
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

          // Preamble Rows (Centered exactly matching Picture 1)
          _buildCenteredSpreadsheetPreambleRow(
            rowNum: '1',
            text: isPit ? 'PIT Capstone Defense' : 'Concept Proposal',
            isBold: true,
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
          _buildCenteredSpreadsheetPreambleRow(
            rowNum: '2',
            text: isPit ? '5/18/2026' : '6/18/2026',
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),
          _buildCenteredSpreadsheetPreambleRow(
            rowNum: '3',
            text: isPit ? 'Smart Room' : 'Room 301',
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Row 4: Column Headers
          Container(
            color: const Color(0xFFE2E8F0),
            child: Row(
              children: [
                _buildGutterCell('4', isHeader: true),
                _buildColumnHeaderCell('#', flex: 1),
                _buildColumnHeaderCell('Time', flex: 3, isRequired: true),
                _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
                _buildColumnHeaderCell('Adviser', flex: 4, isRequired: true),
                _buildColumnHeaderCell(
                  'Panel Chair',
                  flex: 4,
                  isRequired: true,
                ),
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

          // 4 Schedule Rows (Rows 5 to 8) - Adviser & Documenter merged across all 4 rows
          _buildScheduleMerged4RowBlock(isPit: isPit),
        ],
      ),
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

  Widget _buildScheduleMerged4RowBlock({required bool isPit}) {
    const slotH = 34.0;
    const blockH = slotH * 4 + 3.0; // 139.0

    return SizedBox(
      height: blockH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gutter column (row numbers 5 to 8)
          SizedBox(
            width: 26,
            height: blockH,
            child: Column(
              children: List.generate(4, (index) {
                final rowNum = (index + 5).toString();
                return SizedBox(
                  height: index < 3 ? slotH + 1.0 : slotH,
                  child: Column(
                    children: [
                      SizedBox(height: slotH, child: _buildGutterCell(rowNum)),
                      if (index < 3)
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ],
                  ),
                );
              }),
            ),
          ),
          // Column A: # (1, 2, 3, 4)
          Expanded(
            flex: 1,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '1',
                      isBold: true,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '2',
                      isBold: true,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '3',
                      isBold: true,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '4',
                      isBold: true,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column B: Time
          Expanded(
            flex: 3,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '8:00 - 9:00',
                      isBold: true,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '9:00 - 10:00',
                      isBold: true,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '10:00 - 11:00',
                      isBold: true,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      '11:00 - 12:00',
                      isBold: true,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column C: Team Name
          Expanded(
            flex: 3,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Team SkyLedger' : 'Team Apex',
                      isBold: true,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Team BioPulse' : 'Team Horizon',
                      isBold: true,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Team SafeCity' : 'Team Nexus',
                      isBold: true,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Team CodeLearners' : 'Team Pulse',
                      isBold: true,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column D: Adviser (1 Big Merged Cell spanning all 4 rows)
          Expanded(
            flex: 4,
            child: Container(
              height: blockH,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: const Text(
                'Prof. Alex Santos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          // Column E: Panel Chair
          Expanded(
            flex: 4,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Suarez' : 'Dr. Alan Turing',
                      isBold: true,
                      color: _maroon,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Suarez' : 'Dr. Alan Turing',
                      isBold: true,
                      color: _maroon,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Tan' : 'Dr. Maria Santos',
                      isBold: true,
                      color: _maroon,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Tan' : 'Dr. Maria Santos',
                      isBold: true,
                      color: _maroon,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column F: Panel Member 1
          Expanded(
            flex: 4,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Beltran' : 'Prof. Ada Lovelace',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Beltran' : 'Prof. Ada Lovelace',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Reyes' : 'Prof. Robert Taylor',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Reyes' : 'Prof. Robert Taylor',
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column G: Panel Member 2
          Expanded(
            flex: 4,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Corpuz' : 'Dr. Grace Hopper',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Corpuz' : 'Dr. Grace Hopper',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Cruz' : 'Dr. Grace Miller',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Cruz' : 'Dr. Grace Miller',
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column H: Panel Member 3
          Expanded(
            flex: 4,
            child: SizedBox(
              height: blockH,
              child: Column(
                children: [
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Villanueva' : 'Prof. Claude Shannon',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Villanueva' : 'Prof. Claude Shannon',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Santos' : 'Engr. Alan Cruz',
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  SizedBox(
                    height: slotH,
                    child: _buildSubCell(
                      isPit ? 'Santos' : 'Engr. Alan Cruz',
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column I: Documenter (1 Big Merged Cell spanning all 4 rows)
          if (!isPit)
            Expanded(
              flex: 4,
              child: Container(
                height: blockH,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFFD97706),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: const Text(
                  'Engr. Mark Mendoza',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ),
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

  static String _getStageLabel(DefenseSchedulerState state, int? stageId) {
    if (stageId == null) return 'Selected stage';
    for (final stage in state.defenseStages) {
      if (asInt(stage['id']) == stageId) {
        return stage['label']?.toString() ?? 'Stage $stageId';
      }
    }
    return 'Stage $stageId';
  }

  static String _getRubricName(
    DefenseSchedulerState state,
    int? rubricId, [
    String? fallbackName,
  ]) {
    if (rubricId == null) return '';
    for (final rubric in state.rubrics) {
      if (asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    return 'Rubric #$rubricId';
  }

  static String _getPeerRubricName(
    DefenseSchedulerState state,
    int? rubricId, [
    String? fallbackName,
  ]) {
    if (rubricId == null) return '';
    for (final rubric in state.peerRubrics) {
      if (asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    for (final rubric in state.rubrics) {
      if (asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    return 'Peer Rubric #$rubricId';
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

  String get identity => rows.map((row) => row.source.sheetRow).join('_');

  String get panelLabel =>
      panelMembers.isNotEmpty ? panelMembers.join(', ') : '-';

  String get timeSpanLabel {
    if (rows.isEmpty) return '';
    final first = rows.first;
    final last = rows.last;
    final start = first.source.startTime.isNotEmpty
        ? first.source.startTime
        : (first.timeLabel.contains('-')
              ? first.timeLabel.split('-').first.trim()
              : first.timeLabel);
    final end = last.effectiveEndTime.isNotEmpty
        ? last.effectiveEndTime
        : (last.source.endTime.isNotEmpty
              ? last.source.endTime
              : (last.timeLabel.contains('-')
                    ? last.timeLabel.split('-').last.trim()
                    : last.timeLabel));
    if (start.isEmpty || end.isEmpty || rows.length == 1) {
      return rows.first.timeLabel;
    }
    return '${scheduleReviewTime(start)} – ${scheduleReviewTime(end)}';
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
