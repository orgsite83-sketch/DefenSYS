import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
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
  List<String> _importErrors = [];

  Timer? _draftDebounce;
  bool _draftRestored = false;
  DateTime? _draftSavedAt;
  String? _lastSavedSnapshot;
  bool _showIssuesOnly = false;

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

      if (!_isPit) {
        final rawStage = _parsed?.stage?.trim() ?? '';
        if (rawStage.isNotEmpty) {
          final match = findBestMatch<Map<String, dynamic>>(
            source: rawStage,
            items: schedState.defenseStages,
            labelGetter: (s) => s['label']?.toString() ?? '',
          );
          if (match.isMatched) {
            _headerMatch = match;
          }
        }
        if (_importStageId != null &&
            !schedState.defenseStages.any((s) => asInt(s['id']) == _importStageId)) {
          if (_headerMatch != null && _headerMatch!.isMatched) {
            _importStageId = asInt(_headerMatch!.item?['id']);
          } else {
            _importStageId = null;
            _headerMatch = null;
          }
        }
      } else {
        final rawEvent = _parsed?.stage?.trim() ?? '';
        if (rawEvent.isNotEmpty) {
          final match = findBestMatch<Map<String, dynamic>>(
            source: rawEvent,
            items: schedState.pitEvents,
            labelGetter: (e) => e['event_name']?.toString() ?? '',
          );
          if (match.isMatched) {
            _headerMatch = match;
          }
        }
        if (_importEventName.isNotEmpty &&
            !schedState.pitEvents.any((e) => e['event_name'] == _importEventName)) {
          if (_headerMatch != null && _headerMatch!.isMatched) {
            _importEventName = _headerMatch!.label;
          } else {
            _importEventName = '';
            _headerMatch = null;
          }
        }
      }

      _draftRestored = true;
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
    _draftSavedAt = draft.savedAt;
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
      _draftRestored = false;
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
            int.tryParse(config['panel_weight']?.toString() ?? '') ?? _panelWeight;
        _peerWeight =
            int.tryParse(config['peer_weight']?.toString() ?? '') ?? _peerWeight;
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
      final parsedResult = parseScheduleImportFile(bytes: bytes, filename: file.name);
      final rawStage = parsedResult.stage?.trim() ?? '';
      MatchResult<dynamic>? resolvedMatch;
      String? warning;

      if (_isPit) {
        resolvedMatch = findBestMatch<Map<String, dynamic>>(
          source: rawStage,
          items: schedState.pitEvents,
          labelGetter: (e) => e['event_name']?.toString() ?? '',
        );
        if (resolvedMatch.isMatched) {
          final matchedName = resolvedMatch.label;
          if (_importEventName.isNotEmpty &&
              _importEventName != matchedName &&
              (widget.initialEventName ?? '').trim().isNotEmpty &&
              widget.initialEventName!.trim() == _importEventName) {
            warning =
                'File header specifies "$rawStage" (matched to "$matchedName"), while scheduler was previously set to "$_importEventName".';
          }
          _importEventName = matchedName;
        } else if (rawStage.isNotEmpty) {
          warning =
              'File header "$rawStage" could not be matched to any registered PIT event for this semester.';
        }
      } else {
        resolvedMatch = findBestMatch<Map<String, dynamic>>(
          source: rawStage,
          items: schedState.defenseStages,
          labelGetter: (s) => s['label']?.toString() ?? '',
        );
        if (resolvedMatch.isMatched) {
          final matchedStageId = asInt(resolvedMatch.item?['id']);
          if (_importStageId != null &&
              _importStageId != matchedStageId &&
              widget.initialStageId != null &&
              widget.initialStageId == _importStageId) {
            final prevLabel = schedState.defenseStages.firstWhere(
              (s) => asInt(s['id']) == _importStageId,
              orElse: () => <String, dynamic>{},
            )['label'] ?? '';
            warning =
                'File header specifies "$rawStage" (matched to "${resolvedMatch.label}"), while scheduler was previously set to "$prevLabel".';
          }
          _importStageId = matchedStageId;
        } else if (rawStage.isNotEmpty) {
          warning =
              'File header "$rawStage" could not be matched to any Capstone defense stage.';
        }
      }

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
        _headerMatch = resolvedMatch;
        _mismatchWarning = warning;
        _draftRestored = false;
        if (parsedResult.date != null && parsedResult.date!.isNotEmpty) {
          _dateController.text = normalizeImportDate(parsedResult.date!);
        }
        if (defaultRoom.isNotEmpty) {
          _roomController.text = defaultRoom;
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

  @override
  Widget build(BuildContext context) {
    final schedState = ref.watch(defenseSchedulerProvider);
    final activeSemLabel = _getActiveSemLabel(schedState);

    final previewRows = _parsed == null
        ? <ScheduleImportPreviewRow>[]
        : buildScheduleImportPreviewRows(
            _parsed!,
            schedState,
            scope: widget.scope,
            stageId: _importStageId,
            eventName: _importEventName,
            date: _dateController.text,
            room: _roomController.text,
            fallbackDuration:
                int.tryParse(_durationController.text.trim()) ?? 60,
            panelRubricId: _panelRubricId,
            adviserRubricId: _adviserRubricId,
            peerRubricId: _peerRubricId,
            panelWeight: _panelWeight,
            peerWeight: _peerWeight,
          );

    final readyRows = previewRows.where((row) => row.ready).toList();
    final redefenseRows = previewRows.where((row) => row.isRedefense).length;
    final passedRows = previewRows.where((row) => row.isAlreadyPassed).length;
    final issueRows = previewRows.length - readyRows.length;
    final totalRows = previewRows.length;

    return PopScope(
      canPop: !_isDirty(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canClose = await _handleAttemptClose();
        if (canClose && mounted) {
          widget.onBack();
        }
      },
      child: SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.schedule_send_rounded,
              title: _isPit
                  ? 'Bulk Import PIT Defense Schedules'
                  : 'Bulk Import Capstone Defense Schedules',
              subtitle: _isPit
                  ? 'Upload and parse PIT defense timetables, match panel assignments, and commit ready slots.'
                  : 'Upload and parse Capstone timetable spreadsheets, match panelists, and schedule defense slots.',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeSemLabel.isNotEmpty) ...[
                    _headerPill(activeSemLabel),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: _importBusy
                        ? null
                        : () async {
                            final canClose = await _handleAttemptClose();
                            if (canClose && mounted) {
                              widget.onBack();
                            }
                          },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back to Defense Board'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Top 2-Column Section: Left is Smart Format Guide, Right is Primary Upload Action
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                if (!isWide) {
                  return Column(
                    children: [
                      _buildScheduleFormatCard(activeSemLabel),
                      const SizedBox(height: 18),
                      _buildScheduleUploadCard(totalRows, readyRows.length),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildScheduleFormatCard(activeSemLabel),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: _buildScheduleUploadCard(
                        totalRows,
                        readyRows.length,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Draft Restored Notification Banner
            if (_draftRestored && _parsed != null) ...[
              _buildDraftRestoredBanner(
                savedAt: _draftSavedAt,
                rowCount: _parsed!.rows.length,
                onDiscard: _discardDraft,
              ),
              const SizedBox(height: 16),
            ],

            // Mismatch Warning Banner
            if (_mismatchWarning != null) ...[
              _buildMismatchBanner(
                message: _mismatchWarning!,
                onDismiss: () => setState(() => _mismatchWarning = null),
              ),
              const SizedBox(height: 16),
            ],

            // Re-defense Notice Banner
            if (_parsed?.isRedefense == true) ...[
              _buildRedefenseBanner(),
              const SizedBox(height: 16),
            ],

            // Preflight Defense Schedule Intake Review Card (Unified Table Card)
            _buildPreflightReviewCard(
              schedState: schedState,
              previewRows: previewRows,
              readyRows: readyRows,
              redefenseRows: redefenseRows,
              passedRows: passedRows,
              issueRows: issueRows,
              totalRows: totalRows,
            ),
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

  Widget _buildHeaderStatBadge({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.12) : bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? color : borderColor,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isSelected ? color : const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Tooltip(
        message: isSelected ? 'Show all slots' : 'Filter by $label slots',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: badge,
        ),
      );
    }
    return badge;
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
                        'Target Term: $activeSemLabel • Standard Defense Timetable Format',
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                  label: const Text('Download Sample Template'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                            ? '$_fileName • $totalRows slot(s) staged • $readyCount ready'
                            : 'Supports official Microsoft Excel (.xlsx) and CSV (.csv) timetables',
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

            InkWell(
              onTap: _importBusy ? null : _pickFile,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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

  Widget _buildDraftRestoredBanner({
    required DateTime? savedAt,
    required int rowCount,
    required VoidCallback onDiscard,
  }) {
    final timeStr = savedAt != null
        ? '${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restored from saved draft ($rowCount staged ${rowCount == 1 ? 'row' : 'rows'}${timeStr.isNotEmpty ? ' · Saved at $timeStr' : ''})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your previously uploaded schedule and configurations have been restored.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onDiscard,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 15,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              'Discard Draft',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
          DropdownMenuItem<String>(
            value: name,
            child: Text(name),
          ),
        );
      }
    }
    final effectiveEventName =
        pitEventItems.any((e) => e.value == _importEventName)
            ? _importEventName
            : null;

    final pRubricName =
        _getRubricName(schedState, _panelRubricId, _panelRubricName);
    final aRubricName =
        _getRubricName(schedState, _adviserRubricId, _adviserRubricName);
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
    final isRubricMissing =
        _isPit ? isPitRubricMissing : isCapstoneRubricMissing;
    final missingRubrics =
        _isPit ? missingPitRubrics : missingCapstoneRubrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Stage or PIT Event
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPit ? Icons.event_note_rounded : Icons.school_outlined,
                    size: 14,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isPit ? 'Event:' : 'Stage:',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_isPit) ...[
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: ValueKey('compact_pit_event_$effectiveEventName'),
                          value: effectiveEventName,
                          isDense: true,
                          hint: const Text(
                            'Select PIT event',
                            style: TextStyle(
                                fontSize: 11.5, color: Color(0xFF94A3B8)),
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          items: pitEventItems,
                          onChanged: (val) async {
                            setState(() {
                              _importEventName = val ?? '';
                              _headerMatch = null;
                            });
                            if (val != null) {
                              await _loadPitEventConfig(val);
                            }
                          },
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          key: ValueKey('compact_stage_$effectiveStageId'),
                          value: effectiveStageId,
                          isDense: true,
                          hint: const Text(
                            'Select stage',
                            style: TextStyle(
                                fontSize: 11.5, color: Color(0xFF94A3B8)),
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          items: stageItems,
                          onChanged: (val) async {
                            setState(() {
                              _importStageId = val;
                              _headerMatch = null;
                            });
                            await _loadStageRubrics(val);
                          },
                        ),
                      ),
                    ),
                  ],
                  if (_headerMatch != null) ...[
                    const SizedBox(width: 8),
                    _buildCompactHeaderMatchIndicator(_headerMatch!),
                  ],
                ],
              ),

              // 2. Defense Start Date
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Defense Start Date:',
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
                            DateTime.tryParse(_dateController.text) ?? today,
                        firstDate: today,
                        lastDate: DateTime(now.year + 3, now.month, now.day),
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
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
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

              // 3. Duration
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
                    'Duration:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 32,
                    width: 80,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _durationController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                              hintText: '60',
                              hintStyle: TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _scheduleDraftSave();
                            },
                          ),
                        ),
                        const Text(
                          'min',
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

              // Vertical Divider
              Container(
                height: 18,
                width: 1,
                color: const Color(0xFFCBD5E1),
                margin: const EdgeInsets.symmetric(horizontal: 2),
              ),

              // 5. Rubrics
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
                        isAssigned: _adviserRubricId != null &&
                            aRubricName.isNotEmpty,
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
              color: isAssigned ? const Color(0xFF166534) : const Color(0xFF991B1B),
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
        border: Border(
          bottom: BorderSide(color: Color(0xFFFDE68A)),
        ),
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
                context.go(AdminRoutes.defenseStageEdit(
                  _importStageId!,
                  initialTab: 1,
                ));
              } else {
                context.go(AdminRoutes.defenseStages);
              }
            },
            icon: const Icon(Icons.tune_rounded, size: 13, color: Color(0xFF92400E)),
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 12, color: Color(0xFF16A34A)),
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF8FF),
          borderRadius: BorderRadius.circular(6),
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
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFB45309)),
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

  Widget _buildPreflightReviewCard({
    required DefenseSchedulerState schedState,
    required List<ScheduleImportPreviewRow> previewRows,
    required List<ScheduleImportPreviewRow> readyRows,
    required int redefenseRows,
    required int passedRows,
    required int issueRows,
    required int totalRows,
  }) {
    final activeSemLabel = _getActiveSemLabel(schedState);
    final query = _searchCtrl.text.trim().toLowerCase();

    final filteredRows = previewRows.where((row) {
      if (_showIssuesOnly && row.ready) return false;
      if (query.isNotEmpty) {
        final team = row.teamLabel.toLowerCase();
        final project = row.projectLabel.toLowerCase();
        final adviser = row.source.adviser.toLowerCase();
        final panel = row.panelLabel.toLowerCase();
        final room = row.room.toLowerCase();
        final matches = team.contains(query) ||
            project.contains(query) ||
            adviser.contains(query) ||
            panel.contains(query) ||
            room.contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header (Unified with Capstone Stages style)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: DefensysUi.primaryMaroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Defense Schedule Review',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Verify time slots, venue availability, panelist rosters, and evaluation rubrics before confirming.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (activeSemLabel.isNotEmpty) _headerPill(activeSemLabel),
                    if (totalRows > 0) ...[
                      _buildHeaderStatBadge(
                        label: 'Ready',
                        count: readyRows.length,
                        color: const Color(0xFF16A34A),
                        bgColor: const Color(0xFFF0FDF4),
                        borderColor: const Color(0xFFBBF7D0),
                        icon: Icons.check_circle_rounded,
                      ),
                      if (issueRows > 0)
                        _buildHeaderStatBadge(
                          label: 'Needs Attention',
                          count: issueRows,
                          color: const Color(0xFFD97706),
                          bgColor: _showIssuesOnly
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFFFFBEB),
                          borderColor: _showIssuesOnly
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFFDE68A),
                          icon: Icons.warning_amber_rounded,
                          onTap: () =>
                              setState(() => _showIssuesOnly = !_showIssuesOnly),
                          isSelected: _showIssuesOnly,
                        ),
                      if (redefenseRows > 0)
                        _buildHeaderStatBadge(
                          label: 'Re-defense',
                          count: redefenseRows,
                          color: const Color(0xFF7E22CE),
                          bgColor: const Color(0xFFFAF5FF),
                          borderColor: const Color(0xFFE9D5FF),
                          icon: Icons.replay_rounded,
                        ),
                      if (passedRows > 0)
                        _buildHeaderStatBadge(
                          label: 'Already Passed',
                          count: passedRows,
                          color: const Color(0xFF64748B),
                          bgColor: const Color(0xFFF1F5F9),
                          borderColor: const Color(0xFFCBD5E1),
                          icon: Icons.history_rounded,
                        ),
                      _buildHeaderStatBadge(
                        label: 'Total Slots',
                        count: totalRows,
                        color: const Color(0xFF475569),
                        bgColor: const Color(0xFFF8FAFC),
                        borderColor: const Color(0xFFE2E8F0),
                        icon: Icons.layers_outlined,
                      ),
                    ] else
                      _headerPill('0 slots staged'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Unified Compact Session & Grading Configuration Toolbar
          _buildCompactSessionToolbar(schedState),

          // Search + Filter Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: _muted,
                        ),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear_rounded,
                                  size: 16,
                                  color: _muted,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        hintText:
                            'Search by team name, project title, adviser, panelist, or room...',
                        hintStyle:
                            const TextStyle(fontSize: 12.5, color: _muted),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _maroon),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: Text(
                    issueRows > 0
                        ? 'Issues only ($issueRows)'
                        : 'Issues only',
                  ),
                  selected: _showIssuesOnly,
                  onSelected: _importBusy
                      ? null
                      : (val) => setState(() => _showIssuesOnly = val),
                  selectedColor: const Color(0xFFFEF2F2),
                  checkmarkColor: const Color(0xFFDC2626),
                  side: BorderSide(
                    color: _showIssuesOnly
                        ? const Color(0xFFFECACA)
                        : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _showIssuesOnly
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Error box if import failed
          if (_importErrors.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildImportErrorBox(_importErrors),
            ),
          ],

          // Table Content
          if (previewRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.table_rows_rounded,
                      size: 38,
                      color: Color(0xFF98A2B3),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No Schedule Slots Staged',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose or drop a timetable spreadsheet above to begin preflight review.',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredRows.isEmpty)
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 30,
                    color: _muted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showIssuesOnly
                        ? 'No schedule slots currently have validation issues.'
                        : 'No staged slots match the current search filter.',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Try clearing the search query or disable the "Issues only" filter.',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            _buildGroupedSlotsDataTable(filteredRows),

          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Table Footer Actions Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: Color(0xFF667085),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    previewRows.isNotEmpty
                        ? '${readyRows.length} of $totalRows defense slots ready to import'
                        : 'Review panel assignments and room availability before confirming import.',
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
                if (_draftRestored &&
                    _parsed != null &&
                    _parsed!.rows.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: _importBusy ? null : _discardDraft,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: Color(0xFFDC2626),
                    ),
                    label: const Text(
                      'Discard Draft',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (_parsed != null && _parsed!.rows.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: _importBusy
                        ? null
                        : () async {
                            await _persistDraft(showToast: true);
                            setState(() => _draftRestored = true);
                          },
                    icon: const Icon(Icons.save_as_rounded, size: 14),
                    label: const Text('Save Draft'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  onPressed: _importBusy
                      ? null
                      : () async {
                          final canClose = await _handleAttemptClose();
                          if (canClose && mounted) {
                            widget.onBack();
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFD0D5DD)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _importBusy || readyRows.isEmpty
                      ? null
                      : () async {
                          setState(() {
                            _importBusy = true;
                            _importErrors = [];
                          });
                          final payloads =
                              readyRows.map((row) => row.toPayload()).toList();
                          final result = await ref
                              .read(defenseSchedulerProvider.notifier)
                              .importSchedules(payloads);
                          if (!mounted) return;
                          setState(() => _importBusy = false);

                          final createdCount = result['created'] as int? ?? 0;
                          final errors = (result['errors'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [];

                          if (errors.isEmpty) {
                            await clearScheduleImportDraft(scope: widget.scope);
                            if (mounted) {
                              showSuccessToast(
                                context,
                                'Successfully imported $createdCount defense schedule slots.',
                              );
                              widget.onBack();
                            }
                          } else {
                            if (mounted) {
                              setState(() {
                                _importErrors = errors;
                              });
                            }
                          }
                        },
                  icon: _importBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                        ),
                  label: Text(
                    _importBusy
                        ? 'Importing Slots...'
                        : (readyRows.isNotEmpty
                            ? 'Import ${readyRows.length} Ready Slot${readyRows.length == 1 ? '' : 's'}'
                            : 'Import Ready Slots'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateSessionDate(_CommitteeSessionGroup group, String newDate) {
    if (_parsed == null) return;
    final targetSheetRows = group.rows.map((r) => r.source.sheetRow).toSet();
    final trimmed = newDate.trim();
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

  Widget _buildGroupedSlotsDataTable(List<ScheduleImportPreviewRow> rows) {
    final groups = _partitionIntoCommitteeGroups(rows);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _CommitteeSessionCard(
              key: ValueKey('session_card_${i}_${groups[i].date}_${groups[i].room}_${groups[i].chair}'),
              group: groups[i],
              sessionIndex: i + 1,
              totalSessions: groups.length,
              isPit: _isPit,
              onDateChanged: (newDate) =>
                  _updateSessionDate(groups[i], newDate),
              onVenueChanged: (newVenue) =>
                  _updateSessionVenue(groups[i], newVenue),
              table: _buildCommitteeTable(groups[i]),
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
      final key =
          '$date|$room|$chair|$panelSignature|$documenter'.toLowerCase();

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

  Widget _buildCommitteeTable(_CommitteeSessionGroup group) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dataRowMinHeight: 52,
              dataRowMaxHeight: double.infinity,
              headingRowHeight: 40,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFFBFCFD)),
              headingTextStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                letterSpacing: 0.2,
              ),
              columns: const [
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Time Slot')),
                DataColumn(label: Text('Team & Project')),
                DataColumn(label: Text('Adviser')),
                DataColumn(label: Text('Validation Issues')),
              ],
              rows: group.rows.map((row) {
                return DataRow(
                  color: WidgetStateProperty.all(
                    row.ready
                        ? (row.isRedefense
                            ? const Color(0xFFFAF5FF)
                            : Colors.white)
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
                          const Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            row.timeLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
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
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            if (row.projectLabel.isNotEmpty &&
                                row.projectLabel != '-')
                              Text(
                                row.projectLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
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
                                  style: const TextStyle(
                                    fontSize: 10,
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
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
    if (row.ready) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: Color(0xFF027A48),
          ),
          SizedBox(width: 6),
          Text(
            'All fields verified',
            style: TextStyle(
              color: Color(0xFF027A48),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
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
              context.go(AdminRoutes.defenseStageEdit(row.stageId!, initialTab: 1));
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
      issueWidgets.add(
        _issueCategoryPill(
          prefix: 'Slot',
          message: row.slotIssues.join('; '),
          color: const Color(0xFF991B1B),
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          tooltip: row.slotIssues.any((s) =>
                  s.toLowerCase().contains('panel') ||
                  s.toLowerCase().contains('documenter') ||
                  s.toLowerCase().contains('faculty'))
              ? 'Click to open User Management to check faculty accounts'
              : null,
          onTap: row.slotIssues.any((s) =>
                  s.toLowerCase().contains('panel') ||
                  s.toLowerCase().contains('documenter') ||
                  s.toLowerCase().contains('faculty'))
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
      return Tooltip(
        message: tooltip,
        child: pillWidget,
      );
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
    if (_isPit) {
      await downloadTextFile(
        filename: 'defensys-pit-defense-schedule-template.csv',
        content: '3rd Year Expo,,,,,,,,\n'
            'May 18, 2026,,,,,,,,\n'
            'SMART ROOM,,,,,,,,\n'
            'Time,Team Name,Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3\n'
            '9:00AM-9:30AM,Team SkyLedger,Alumni Career Tracker,"Ricardo Fontanilla","VILLAR, Marcus",Suarez,Beltran,Corpuz,Villanueva\n'
            ',,,,"ONG, Patricia",,,,\n'
            ',,,,"SALAZAR, Ethan",,,,\n'
            ',,,,"CASTILLO, Zoe",,,,\n',
      );
    } else {
      await downloadTextFile(
        filename: 'defensys-capstone-defense-schedule-template.csv',
        content: 'REDEFENSE - Capstone Project and Research 1,,,,,,,,,\n'
            'May 18, 2026,,,,,,,,,\n'
            'SMART ROOM,,,,,,,,,\n'
            'Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter\n'
            '9:00AM-9:30AM,Team SkyLedger,Alumni Career Tracker,"Ricardo Fontanilla","VILLAR, Marcus",Suarez,Beltran,Corpuz,Villanueva,Magbanua\n'
            ',,,,"ONG, Patricia",,,,,\n'
            ',,,,"SALAZAR, Ethan",,,,,\n'
            ',,,,"CASTILLO, Zoe",,,,,\n',
      );
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
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
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
                              'Target Term: $activeSemLabel • Visual guide for defense timetables & panel assignments',
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
                                        text: 'Auto-Detection & Multi-Panelists: ',
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

                        // Spreadsheet Preview
                        _buildSampleScheduleSheetPreview(isPit: isPit),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, color: _line),
                // Modal Footer
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _downloadSampleTemplate();
                        },
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Download Sample Template (.csv)'),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                            ? 'pit_defense_schedule.csv'
                            : 'capstone_defense_schedule.csv',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

          // Preamble Rows
          _buildSpreadsheetPreambleRow(
            rowNum: '1',
            label: isPit
                ? '3rd Year Expo'
                : 'REDEFENSE - Capstone Project and Research 1',
            badge: 'Stage Header',
            isBold: true,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSpreadsheetPreambleRow(
            rowNum: '2',
            label: 'May 18, 2026',
            badge: 'Date Header',
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSpreadsheetPreambleRow(
            rowNum: '3',
            label: 'SMART ROOM',
            badge: 'Room Header',
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Row 4: Column Headers
          Container(
            color: const Color(0xFFE2E8F0),
            child: Row(
              children: [
                _buildGutterCell('4', isHeader: true),
                _buildColumnHeaderCell('Time', flex: 3, isRequired: true),
                _buildColumnHeaderCell('Team Name', flex: 3, isRequired: true),
                _buildColumnHeaderCell(
                  isPit ? 'PIT Project' : 'Capstone Project',
                  flex: 4,
                  isRequired: true,
                ),
                _buildColumnHeaderCell('Adviser', flex: 3, isRequired: true),
                _buildColumnHeaderCell('Panelists', flex: 4, isRequired: true),
                if (!isPit)
                  _buildColumnHeaderCell('Documenter', flex: 3),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCBD5E1)),

          // Sample Data Rows
          _buildSampleDataRow(
            rowNum: '5',
            time: '9:00-9:30 AM',
            team: 'SkyLedger',
            project: 'Alumni Tracker',
            adviser: 'R. Fontanilla',
            panel: 'Suarez, Beltran, Corpuz',
            documenter: isPit ? null : 'Magbanua',
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildSampleDataRow(
            rowNum: '6',
            time: '9:30-10:00 AM',
            team: 'Team Nexus',
            project: 'Smart Campus IoT',
            adviser: 'M. Santos',
            panel: 'Tan, Reyes, Cruz',
            documenter: isPit ? null : 'Alonzo',
            isAlt: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetPreambleRow({
    required String rowNum,
    required String label,
    required String badge,
    bool isBold = false,
  }) {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNum),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: isBold ? _maroon : const Color(0xFF334155),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleDataRow({
    required String rowNum,
    required String time,
    required String team,
    required String project,
    required String adviser,
    required String panel,
    String? documenter,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                time,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                team,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                project,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                adviser,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                panel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _maroon,
                ),
              ),
            ),
          ),
          if (documenter != null)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  documenter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB45309),
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

class _CommitteeSessionCard extends StatefulWidget {
  const _CommitteeSessionCard({
    super.key,
    required this.group,
    required this.sessionIndex,
    required this.totalSessions,
    required this.isPit,
    required this.onDateChanged,
    required this.onVenueChanged,
    required this.table,
  });

  final _CommitteeSessionGroup group;
  final int sessionIndex;
  final int totalSessions;
  final bool isPit;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onVenueChanged;
  final Widget table;

  @override
  State<_CommitteeSessionCard> createState() => _CommitteeSessionCardState();
}

class _CommitteeSessionCardState extends State<_CommitteeSessionCard> {
  late TextEditingController _roomCtrl;
  late FocusNode _roomFocusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final initialRoom =
        widget.group.room == 'Unassigned' ? '' : widget.group.room;
    _roomCtrl = TextEditingController(text: initialRoom);
    _roomFocusNode = FocusNode();
    _roomFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_roomFocusNode.hasFocus) {
      final val = _roomCtrl.text.trim();
      final current =
          widget.group.room == 'Unassigned' ? '' : widget.group.room.trim();
      if (val != current) {
        _debounce?.cancel();
        widget.onVenueChanged(val);
      }
    }
  }

  double _calculateRoomFieldWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? 'Set Venue' : text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return (painter.width + 10).clamp(65.0, 220.0);
  }

  Future<void> _pickSessionDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial = today;
    if (widget.group.date.isNotEmpty) {
      final parsed = DateTime.tryParse(widget.group.date);
      if (parsed != null) {
        initial = parsed;
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 3, now.month, now.day),
    );
    if (picked != null) {
      final formatted = formatScheduleDate(picked);
      widget.onDateChanged(formatted);
    }
  }

  @override
  void didUpdateWidget(covariant _CommitteeSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentRoom =
        widget.group.room == 'Unassigned' ? '' : widget.group.room;
    if (oldWidget.group.room != widget.group.room &&
        !_roomFocusNode.hasFocus &&
        _roomCtrl.text.trim() != currentRoom.trim()) {
      _roomCtrl.text = currentRoom;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _roomFocusNode.removeListener(_onFocusChange);
    _roomFocusNode.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(16, 24, 40, 0.03),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          widget.table,
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final group = widget.group;
    final hasChair = group.chair.isNotEmpty && group.chair != '-';
    final hasDoc =
        !widget.isPit && group.documenter.isNotEmpty && group.documenter != '-';
    final hasPanel = group.panelMembers.isNotEmpty;
    final isRoomMissing =
        group.room.trim().isEmpty || group.room == 'Unassigned';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Session Number Circle (matching Capstone stages card design)
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  '${widget.sessionIndex}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Date Badge (Editable on click, matching Image 2 design)
              Tooltip(
                message: 'Click to change date for this session',
                waitDuration: const Duration(milliseconds: 400),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickSessionDate,
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: const Color(0xFFF1F5F9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: Color(0xFF334155),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            group.date.isNotEmpty ? group.date : 'Set Date',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Venue Badge (Always styled like Image 2, directly editable with no oval)
              Tooltip(
                message: 'Click to edit venue for this session',
                waitDuration: const Duration(milliseconds: 400),
                child: GestureDetector(
                  onTap: () => _roomFocusNode.requestFocus(),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isRoomMissing
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          size: 13,
                          color: isRoomMissing
                              ? const Color(0xFFD97706)
                              : const Color(0xFF475569),
                        ),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: _calculateRoomFieldWidth(_roomCtrl.text),
                          child: TextField(
                            controller: _roomCtrl,
                            focusNode: _roomFocusNode,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isRoomMissing
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF1E293B),
                            ),
                            cursorColor: DefensysUi.primaryMaroon,
                            cursorWidth: 1.5,
                            cursorHeight: 14,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              hintText: 'Set Venue',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {});
                              _debounce?.cancel();
                              _debounce = Timer(
                                const Duration(milliseconds: 300),
                                () {
                                  widget.onVenueChanged(val.trim());
                                },
                              );
                            },
                            onSubmitted: (val) {
                              _debounce?.cancel();
                              widget.onVenueChanged(val.trim());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Committee Details
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Chair
                    if (hasChair)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.gavel_rounded,
                            size: 13,
                            color: DefensysUi.primaryMaroon,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Chair: ',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            group.chair,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: DefensysUi.primaryMaroon,
                            ),
                          ),
                        ],
                      ),

                    // Panel Members
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.groups_outlined,
                          size: 14,
                          color: DefensysUi.primaryMaroon,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Panel: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          hasPanel
                              ? group.panelMembers.join(', ')
                              : 'No panel members specified',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: hasPanel
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),

                    // Documenter
                    if (hasDoc)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_note_rounded,
                              size: 13,
                              color: Color(0xFF92400E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Doc: ${group.documenter}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Time span badge
              if (group.timeSpanLabel.isNotEmpty && group.timeSpanLabel != '-')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        group.timeSpanLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(width: 8),

              // Slot count & ready badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: group.issueCount == 0
                      ? const Color(0xFFECFDF3)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: group.issueCount == 0
                        ? const Color(0xFFA6F4C5)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      group.issueCount == 0
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: group.issueCount == 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.issueCount == 0
                          ? '${group.totalCount} Team${group.totalCount == 1 ? '' : 's'} Ready'
                          : '${group.readyCount}/${group.totalCount} Ready (${group.issueCount} Issue${group.issueCount == 1 ? '' : 's'})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: group.issueCount == 0
                            ? const Color(0xFF166534)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Subline: Session Advisers (if available)
          if (group.distinctAdvisers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 12,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  'Adviser${group.distinctAdvisers.length > 1 ? 's' : ''} in session (${group.distinctAdvisers.length}): ',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                Expanded(
                  child: Text(
                    group.distinctAdvisers.join('  •  '),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
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
    final end = last.source.endTime.isNotEmpty
        ? last.source.endTime
        : (last.timeLabel.contains('-')
            ? last.timeLabel.split('-').last.trim()
            : last.timeLabel);
    if (start.isEmpty || end.isEmpty || rows.length == 1) {
      return rows.first.timeLabel;
    }
    return '$start – $end';
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

