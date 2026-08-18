import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/string_matching_utils.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../models/schedule_import_models.dart';

class ScheduleImportDialog {
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required DefenseSchedulerState state,
    required String scope,
    required int? initialStageId,
    required String initialEventName,
    required int? initialRubricId,
    required int? initialAdviserRubricId,
    required int? initialPeerRubricId,
    required int? initialCapstonePeerRubricId,
    required String initialDate,
    required String initialRoom,
    required String initialDuration,
    required String initialPanelWeight,
    required String initialPeerWeight,
    required bool Function(DefenseSchedulerState state, String scope) canScheduleScope,
    required String Function(DefenseSchedulerState state) scheduleNoticeMessage,
  }) async {
    if (!canScheduleScope(state, scope)) {
      showValidationToast(context, scheduleNoticeMessage(state));
      return;
    }

    final importScope = scope;
    final isPit = importScope == 'pit';

    ParsedScheduleImport? parsed;
    String? fileName;
    int? importStageId = isPit ? null : initialStageId;
    String importEventName = isPit ? initialEventName.trim() : '';
    MatchResult<dynamic>? headerMatch;
    String? mismatchWarning;
    int? panelRubricId = initialRubricId;
    int? adviserRubricId = initialAdviserRubricId;
    int? peerRubricId = isPit ? initialPeerRubricId : initialCapstonePeerRubricId;
    int panelWeight = int.tryParse(initialPanelWeight) ?? 80;
    int peerWeight = int.tryParse(initialPeerWeight) ?? 20;
    final dateController = TextEditingController(text: initialDate);
    final roomController = TextEditingController(text: initialRoom);
    final durationController = TextEditingController(text: initialDuration);
    var rubricLoading = false;
    var importBusy = false;
    var importErrors = <String>[];

    Future<void> loadStageRubrics(
      int? stageId,
      void Function(void Function()) setDialogState,
    ) async {
      if (stageId == null) return;
      setDialogState(() => rubricLoading = true);
      final semesterId = asInt(state.activeSemester?['id']);
      if (semesterId == null) {
        setDialogState(() => rubricLoading = false);
        return;
      }
      final detail = await ref
          .read(defenseStagesProvider.notifier)
          .fetchStageDetail(stageId, semesterId: semesterId);
      final grading = detail?['grading_config'];
      if (!context.mounted) return;
      setDialogState(() {
        if (grading is Map) {
          panelRubricId = asInt(grading['panel_rubric_id']) ?? panelRubricId;
          adviserRubricId = asInt(grading['adviser_rubric_id']) ?? adviserRubricId;
          peerRubricId = asInt(grading['peer_rubric_id']) ?? peerRubricId;
        }
        rubricLoading = false;
      });
    }

    Future<void> loadPitEventConfig(
      String eventName,
      void Function(void Function()) setDialogState,
    ) async {
      if (eventName.trim().isEmpty) return;
      setDialogState(() => rubricLoading = true);
      final semesterId = asInt(state.activeSemester?['id']);
      final config = await ref
          .read(defenseSchedulerProvider.notifier)
          .fetchPitEventConfig(eventName: eventName, semesterId: semesterId);
      if (!context.mounted) return;
      setDialogState(() {
        if (config != null) {
          panelRubricId = asInt(config['panel_rubric_id']) ?? panelRubricId;
          peerRubricId = asInt(config['peer_rubric_id']) ?? peerRubricId;
          panelWeight = int.tryParse(config['panel_weight']?.toString() ?? '') ?? panelWeight;
          peerWeight = int.tryParse(config['peer_weight']?.toString() ?? '') ?? peerWeight;
        }
        rubricLoading = false;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewRows = parsed == null
                ? <ScheduleImportPreviewRow>[]
                : buildScheduleImportPreviewRows(
                    parsed!,
                    state,
                    scope: importScope,
                    stageId: importStageId,
                    eventName: importEventName,
                    date: dateController.text,
                    room: roomController.text,
                    fallbackDuration:
                        int.tryParse(durationController.text.trim()) ?? 60,
                    panelRubricId: panelRubricId,
                    adviserRubricId: adviserRubricId,
                    peerRubricId: peerRubricId,
                    panelWeight: panelWeight,
                    peerWeight: peerWeight,
                  );
            final readyRows = previewRows.where((row) => row.ready).toList();
            final issueRows = previewRows.length - readyRows.length;

            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['xlsx', 'csv'],
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              final bytes = file.bytes;
              if (bytes == null) {
                if (context.mounted) {
                  showErrorToast(context, 'Unable to read the selected file.');
                }
                return;
              }

              try {
                final parsedResult = parseScheduleImportFile(bytes: bytes, filename: file.name);
                final rawStage = parsedResult.stage?.trim() ?? '';
                MatchResult<dynamic>? resolvedMatch;
                String? warning;

                if (isPit) {
                  resolvedMatch = findBestMatch<Map<String, dynamic>>(
                    source: rawStage,
                    items: state.pitEvents,
                    labelGetter: (e) => e['event_name']?.toString() ?? '',
                  );
                  if (resolvedMatch.isMatched) {
                    final matchedName = resolvedMatch.label;
                    if (importEventName.isNotEmpty &&
                        importEventName != matchedName &&
                        initialEventName.trim().isNotEmpty &&
                        initialEventName.trim() == importEventName) {
                      warning =
                          'File header specifies "$rawStage" (matched to "$matchedName"), while scheduler was previously set to "$importEventName".';
                    }
                    importEventName = matchedName;
                  } else if (rawStage.isNotEmpty) {
                    warning =
                        'File header "$rawStage" could not be matched to any registered PIT event for this semester.';
                  }
                } else {
                  resolvedMatch = findBestMatch<Map<String, dynamic>>(
                    source: rawStage,
                    items: state.defenseStages,
                    labelGetter: (s) => s['label']?.toString() ?? '',
                  );
                  if (resolvedMatch.isMatched) {
                    final matchedStageId = asInt(resolvedMatch.item?['id']);
                    if (importStageId != null &&
                        importStageId != matchedStageId &&
                        initialStageId != null &&
                        initialStageId == importStageId) {
                      final prevLabel = state.defenseStages.firstWhere(
                        (s) => asInt(s['id']) == importStageId,
                        orElse: () => <String, dynamic>{},
                      )['label'] ?? '';
                      warning =
                          'File header specifies "$rawStage" (matched to "${resolvedMatch.label}"), while scheduler was previously set to "$prevLabel".';
                    }
                    importStageId = matchedStageId;
                  } else if (rawStage.isNotEmpty) {
                    warning =
                        'File header "$rawStage" could not be matched to any Capstone defense stage.';
                  }
                }

                setDialogState(() {
                  parsed = parsedResult;
                  fileName = file.name;
                  headerMatch = resolvedMatch;
                  mismatchWarning = warning;
                  if (parsedResult.date != null && parsedResult.date!.isNotEmpty) {
                    dateController.text = normalizeImportDate(parsedResult.date!);
                  }
                  if (parsedResult.room != null && parsedResult.room!.isNotEmpty) {
                    roomController.text = parsedResult.room!;
                  }
                });

                if (!isPit && importStageId != null) {
                  await loadStageRubrics(importStageId, setDialogState);
                } else if (isPit && importEventName.isNotEmpty) {
                  await loadPitEventConfig(importEventName, setDialogState);
                }
              } catch (e) {
                if (context.mounted) {
                  showErrorToast(context, 'Failed to parse schedule file: $e');
                }
              }
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.upload_file_rounded,
                    color: AppColors.maroon,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isPit
                        ? 'Import PIT Defense Schedule'
                        : 'Import Capstone Defense Schedule',
                  ),
                ],
              ),
              content: SizedBox(
                width: 1080,
                height: 680,
                child: Column(
                  children: [
                    _buildImportUploadPanel(
                      fileName: fileName,
                      onPickFile: pickFile,
                      isPit: isPit,
                    ),
                    if (mismatchWarning != null) ...[
                      const SizedBox(height: 10),
                      _buildMismatchBanner(
                        message: mismatchWarning!,
                        onDismiss: () => setDialogState(() => mismatchWarning = null),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _buildImportContextPanel(
                      context,
                      state,
                      scope: importScope,
                      stageId: importStageId,
                      eventName: importEventName,
                      headerMatch: headerMatch,
                      dateController: dateController,
                      roomController: roomController,
                      durationController: durationController,
                      panelRubricId: panelRubricId,
                      peerRubricId: peerRubricId,
                      rubricLoading: rubricLoading,
                      rowsDetected: previewRows.length,
                      readyRows: readyRows.length,
                      issueRows: issueRows,
                      onStageChanged: (val) async {
                        setDialogState(() {
                          importStageId = val;
                          headerMatch = null;
                        });
                        await loadStageRubrics(val, setDialogState);
                      },
                      onEventChanged: (val) async {
                        setDialogState(() {
                          importEventName = val ?? '';
                          headerMatch = null;
                        });
                        if (val != null) {
                          await loadPitEventConfig(val, setDialogState);
                        }
                      },
                      onContextChanged: () => setDialogState(() {}),
                    ),
                    const SizedBox(height: 14),
                    if (importErrors.isNotEmpty) ...[
                      _buildImportErrorBox(importErrors),
                      const SizedBox(height: 14),
                    ],
                    Expanded(
                      child: _buildImportPreviewTable(previewRows, isPit: isPit),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: importBusy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: importBusy || readyRows.isEmpty
                      ? null
                      : () async {
                          setDialogState(() {
                            importBusy = true;
                            importErrors = [];
                          });
                          final payloads =
                              readyRows.map((row) => row.toPayload()).toList();
                          final result = await ref
                              .read(defenseSchedulerProvider.notifier)
                              .importSchedules(payloads);
                          setDialogState(() => importBusy = false);

                          final createdCount = result['created'] as int? ?? 0;
                          final errors = (result['errors'] as List?)?.map((e) => e.toString()).toList() ?? [];

                          if (errors.isEmpty) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                              showSuccessToast(
                                context,
                                'Successfully imported $createdCount schedule slots.',
                              );
                            }
                          } else {
                            setDialogState(() {
                              importErrors = errors;
                            });
                          }
                        },
                  icon: importBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    importBusy
                        ? 'Importing...'
                        : 'Import ${readyRows.length} Ready ${readyRows.length == 1 ? 'Slot' : 'Slots'}',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildImportUploadPanel({
    required String? fileName,
    required Future<void> Function() onPickFile,
    required bool isPit,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Icon(
              Icons.table_chart_outlined,
              color: AppColors.maroon,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName ?? (isPit ? 'Upload the PIT schedule template' : 'Upload the admin schedule template'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Supported files: .xlsx and .csv. Merged-cell-style team blocks are grouped automatically.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      if (isPit) {
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
                    },
                    child: const Text(
                      'Download sample CSV template',
                      style: TextStyle(
                        color: AppColors.maroon,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(fileName == null ? 'Upload File' : 'Replace File'),
          ),
        ],
      ),
    );
  }

  static Widget _buildMismatchBanner({
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
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 20),
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
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB45309)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }

  static Widget _buildHeaderMatchIndicator(MatchResult<dynamic>? match) {
    if (match == null || match.sourceText.isEmpty) {
      return const SizedBox.shrink();
    }
    if (match.isExact) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFA6F4C5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF027A48)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Detected from file: "${match.sourceText}"',
                style: const TextStyle(
                  color: Color(0xFF027A48),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (match.isCanonical) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF8FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFB2DDFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF175CD3)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Auto-matched from "${match.sourceText}" in file',
                style: const TextStyle(
                  color: Color(0xFF175CD3),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (match.isFuzzy) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline, size: 13, color: Color(0xFFB45309)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Typo resolved: "${match.sourceText}" ➔ "${match.label}" (${(match.similarity * 100).toInt()}% match)',
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFECDCA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFB42318)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Unrecognized header in file: "${match.sourceText}"',
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildImportContextPanel(
    BuildContext context,
    DefenseSchedulerState state, {
    required String scope,
    required int? stageId,
    required String eventName,
    required MatchResult<dynamic>? headerMatch,
    required TextEditingController dateController,
    required TextEditingController roomController,
    required TextEditingController durationController,
    required int? panelRubricId,
    required int? peerRubricId,
    required bool rubricLoading,
    required int rowsDetected,
    required int readyRows,
    required int issueRows,
    required ValueChanged<int?> onStageChanged,
    required ValueChanged<String?> onEventChanged,
    required VoidCallback onContextChanged,
  }) {
    final isPit = scope == 'pit';
    final stageItems = state.defenseStages
        .map(
          (stage) => DropdownMenuItem<int?>(
            value: asInt(stage['id']),
            child: Text(stage['label']?.toString() ?? ''),
          ),
        )
        .toList();
    final rubricName = _getRubricName(state, panelRubricId);
    final peerRubricName = isPit ? _getPeerRubricName(state, peerRubricId) : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detected Context',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: isPit
                    ? _labeledField(
                        'PIT Event',
                        DropdownButtonFormField<String>(
                          value: state.pitEvents.any((e) => e['event_name'] == eventName)
                              ? eventName
                              : null,
                          decoration: const InputDecoration(hintText: 'Select PIT event'),
                          items: state.pitEvents.map((e) {
                            final name = e['event_name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: onEventChanged,
                        ),
                        extra: _buildHeaderMatchIndicator(headerMatch),
                      )
                    : _labeledField(
                        'Stage',
                        DropdownButtonFormField<int?>(
                          initialValue: stageId,
                          decoration: const InputDecoration(hintText: 'Select stage if not detected'),
                          items: stageItems,
                          onChanged: onStageChanged,
                        ),
                        extra: _buildHeaderMatchIndicator(headerMatch),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeledField(
                  'Date',
                  TextField(
                    controller: dateController,
                    readOnly: true,
                    onTap: () async {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(dateController.text) ?? today,
                        firstDate: today,
                        lastDate: DateTime(now.year + 3, now.month, now.day),
                      );
                      if (picked != null) {
                        dateController.text = formatScheduleDate(picked);
                        onContextChanged();
                      }
                    },
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeledField(
                  'Default duration',
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onContextChanged(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _labeledField(
                  'Default room',
                  TextField(
                    controller: roomController,
                    decoration: const InputDecoration(hintText: 'Use only if rows have no room'),
                    onChanged: (_) => onContextChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _importMetric('Rows detected', rowsDetected.toString()),
              _importMetric('Ready', readyRows.toString(), success: true),
              _importMetric(
                'Needs attention',
                issueRows.toString(),
                warning: issueRows > 0,
              ),
              _importMetric(
                'Panel rubric',
                rubricLoading
                    ? 'Loading...'
                    : (rubricName.isEmpty ? 'Missing' : rubricName),
                warning: rubricName.isEmpty && !rubricLoading,
              ),
              if (isPit)
                _importMetric(
                  'Peer rubric',
                  rubricLoading
                    ? 'Loading...'
                    : (peerRubricName.isEmpty ? 'Missing' : peerRubricName),
                  warning: peerRubricName.isEmpty && !rubricLoading,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _labeledField(String label, Widget field, {Widget? extra}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        field,
        if (extra != null) extra,
      ],
    );
  }

  static Widget _importMetric(
    String label,
    String value, {
    bool success = false,
    bool warning = false,
  }) {
    final bg = success
        ? const Color(0xFFECFDF3)
        : warning
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFF8FAFC);
    final fg = success
        ? const Color(0xFF027A48)
        : warning
        ? const Color(0xFFB45309)
        : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }

  static Widget _buildImportErrorBox(List<String> errors) {
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

  static Widget _buildImportPreviewTable(
    List<ScheduleImportPreviewRow> rows, {
    required bool isPit,
  }) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Center(
          child: Text(
            'Upload a schedule file (.xlsx or .csv) to preview slots.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: [
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('Time')),
            const DataColumn(label: Text('Team')),
            const DataColumn(label: Text('Project')),
            const DataColumn(label: Text('Chair')),
            const DataColumn(label: Text('Panel Members')),
            if (!isPit) const DataColumn(label: Text('Documenter')),
            const DataColumn(label: Text('Room')),
            const DataColumn(label: Text('Issues')),
          ],
          rows: rows.map((row) {
            final issueText = row.issues.isNotEmpty
                ? row.issues.join('; ')
                : row.warnings.join('; ');
            return DataRow(
              color: WidgetStateProperty.all(
                row.ready ? Colors.white : const Color(0xFFFFFBEB),
              ),
              cells: [
                DataCell(_importStatusChip(row.ready ? 'Ready' : 'Needs attention')),
                DataCell(Text(row.timeLabel)),
                DataCell(Text(row.teamLabel)),
                DataCell(Text(row.projectLabel)),
                DataCell(Text(row.chairLabel)),
                DataCell(Text(row.panelLabel)),
                if (!isPit) DataCell(Text(row.documenterLabel)),
                DataCell(Text(row.room)),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: Text(
                      issueText.isEmpty ? 'No issues' : issueText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: row.issues.isNotEmpty
                            ? const Color(0xFFB42318)
                            : row.warnings.isNotEmpty
                                ? const Color(0xFFB45309)
                                : const Color(0xFF027A48),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  static Widget _importStatusChip(String label) {
    final ready = label == 'Ready';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ready ? const Color(0xFF027A48) : const Color(0xFFB45309),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  static String _getRubricName(DefenseSchedulerState state, int? rubricId) {
    if (rubricId == null) return '';
    for (final rubric in state.rubrics) {
      if (asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    return '';
  }

  static String _getPeerRubricName(DefenseSchedulerState state, int? rubricId) {
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
    return '';
  }
}
