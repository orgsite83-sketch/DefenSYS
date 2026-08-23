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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.maroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.upload_file_rounded,
                      color: AppColors.maroon,
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
                              ? 'Import PIT Defense Schedule'
                              : 'Import Capstone Defense Schedule',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Upload and parse institutional defense timetable spreadsheets (.xlsx, .csv)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    splashRadius: 18,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: 1140,
                height: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2-Column Top Section: Left is Format Guide, Right is File Staging & Upload
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildFormatGuideCard(isPit: isPit),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: _buildUploadCard(
                              fileName: fileName,
                              onPickFile: pickFile,
                              isPit: isPit,
                            ),
                          ),
                        ],
                      ),
                      if (mismatchWarning != null) ...[
                        const SizedBox(height: 14),
                        _buildMismatchBanner(
                          message: mismatchWarning!,
                          onDismiss: () =>
                              setDialogState(() => mismatchWarning = null),
                        ),
                      ],
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      if (importErrors.isNotEmpty) ...[
                        _buildImportErrorBox(importErrors),
                        const SizedBox(height: 14),
                      ],
                      SizedBox(
                        height: 320,
                        child:
                            _buildImportPreviewTable(previewRows, isPit: isPit),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      importBusy ? null : () => Navigator.pop(dialogContext),
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
                          final errors = (result['errors'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [];

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

  static Widget _buildFormatGuideCard({required bool isPit}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.table_chart_outlined,
                  color: AppColors.maroon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPit ? 'PIT Schedule Format Guide' : 'Capstone Schedule Format Guide',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPit
                          ? 'Official PIT Timetable & Evaluation Spreadsheet'
                          : 'Official Capstone Timetable & Panel Assignment Spreadsheet',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Authentic Spreadsheet Blueprint Window
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
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
                  child: Row(
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
                              isPit ? 'pit_defense_schedule.csv' : 'capstone_defense_schedule.csv',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _buildMiniBadge('Auto-Detected Headers', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                    ],
                  ),
                ),

                // Spreadsheet Rows with Left Gutter Numbers
                _buildSpreadsheetRow(
                  rowNumber: '1',
                  label: isPit ? '3rd Year Expo' : 'REDEFENSE - Capstone Project and Research 1',
                  badge: 'Stage Header',
                  badgeBg: const Color(0xFFFEE2E2),
                  badgeFg: AppColors.maroon,
                  isBold: true,
                  isAlt: true,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSpreadsheetRow(
                  rowNumber: '2',
                  label: 'May 18, 2026',
                  badge: 'Date Header',
                  badgeBg: const Color(0xFFEFF6FF),
                  badgeFg: const Color(0xFF1D4ED8),
                  isAlt: false,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSpreadsheetRow(
                  rowNumber: '3',
                  label: 'SMART ROOM',
                  badge: 'Room Header',
                  badgeBg: const Color(0xFFF1F5F9),
                  badgeFg: const Color(0xFF475569),
                  isAlt: true,
                ),
                const Divider(height: 1, color: Color(0xFFCBD5E1)),

                // Row 4: Column Headers
                Container(
                  color: const Color(0xFFE2E8F0),
                  child: Row(
                    children: [
                      _buildGutterCell('4', isHeader: true),
                      Expanded(flex: 3, child: _buildHeaderCell('Time')),
                      Expanded(flex: 3, child: _buildHeaderCell('Team Name')),
                      Expanded(flex: 4, child: _buildHeaderCell('Project Title')),
                      Expanded(flex: 3, child: _buildHeaderCell('Adviser')),
                      Expanded(flex: 4, child: _buildHeaderCell('Panelists')),
                      if (!isPit)
                        Expanded(flex: 3, child: _buildHeaderCell('Documenter')),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFCBD5E1)),

                // Row 5 & 6: Sample Data Rows
                _buildSpreadsheetDataRow(
                  rowNumber: '5',
                  time: '9:00-9:30 AM',
                  team: 'SkyLedger',
                  project: 'Alumni Tracker',
                  adviser: 'R. Fontanilla',
                  panel: 'Suarez, Beltran, Corpuz',
                  documenter: isPit ? null : 'Magbanua',
                  isAlt: false,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSpreadsheetDataRow(
                  rowNumber: '6',
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
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.maroon),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isPit
                      ? 'PIT event name, date, room, adviser, and panel members are auto-matched from spreadsheet headers and rows.'
                      : 'Stage name, date, room, adviser, panelists, and documenter are auto-detected from spreadsheet headers and columns.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          OutlinedButton.icon(
            onPressed: () async {
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
            icon: const Icon(Icons.download_rounded, size: 15),
            label: const Text('Download Sample Template (.csv)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildGutterCell(String rowNum, {bool isHeader = false}) {
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

  static Widget _buildHeaderCell(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  static Widget _buildSpreadsheetRow({
    required String rowNumber,
    required String label,
    required String badge,
    required Color badgeBg,
    required Color badgeFg,
    bool isBold = false,
    bool isAlt = false,
  }) {
    return Container(
      color: isAlt ? const Color(0xFFFFFBEB).withValues(alpha: 0.5) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          const SizedBox(width: 8),
          _buildMiniBadge(badge, badgeBg, badgeFg),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: isBold ? AppColors.maroon : const Color(0xFF334155),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSpreadsheetDataRow({
    required String rowNumber,
    required String time,
    required String team,
    required String project,
    required String adviser,
    required String panel,
    required String? documenter,
    bool isAlt = false,
  }) {
    return Container(
      color: isAlt ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(team, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(project, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(adviser, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(panel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.maroon)),
            ),
          ),
          if (documenter != null)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(documenter, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _buildUploadCard({
    required String? fileName,
    required Future<void> Function() onPickFile,
    required bool isPit,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: AppColors.maroon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload & Stage Spreadsheet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPit
                          ? 'Stage and parse PIT timetable spreadsheets'
                          : 'Stage and parse Capstone timetable spreadsheets',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (fileName == null)
            InkWell(
              onTap: onPickFile,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.maroon.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.upload_file_rounded,
                        color: AppColors.maroon,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Click to browse or drag & drop schedule',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Supports Microsoft Excel (.xlsx) and CSV (.csv)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildMiniBadge('.XLSX Excel', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                        const SizedBox(width: 6),
                        _buildMiniBadge('.CSV Delimited', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.insert_drive_file_rounded,
                          color: Color(0xFF16A34A),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF15803D),
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF16A34A)),
                                SizedBox(width: 4),
                                Text(
                                  'Spreadsheet loaded & parsed successfully',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF16A34A),
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onPickFile,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                      label: const Text('Change Spreadsheet'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        foregroundColor: const Color(0xFF15803D),
                        side: const BorderSide(color: Color(0xFF86EFAC)),
                        backgroundColor: Colors.white,
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

  static Widget _buildMiniBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Icon(
                Icons.table_rows_rounded,
                size: 28,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Schedule Slots Staged Yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload an Excel (.xlsx) or CSV (.csv) file above to parse and review defense slots.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
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
          headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF334155),
          ),
          columns: [
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('Time Slot')),
            const DataColumn(label: Text('Team & Project')),
            const DataColumn(label: Text('Adviser')),
            const DataColumn(label: Text('Panel Members')),
            if (!isPit) const DataColumn(label: Text('Documenter')),
            const DataColumn(label: Text('Room')),
            const DataColumn(label: Text('Validation Issues')),
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
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF64748B)),
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
                  Column(
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
                      if (row.projectLabel.isNotEmpty && row.projectLabel != '-')
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
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    row.source.adviser.isNotEmpty ? row.source.adviser : '-',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                  ),
                ),
                DataCell(
                  Text(
                    row.panelLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.maroon,
                    ),
                  ),
                ),
                if (!isPit)
                  DataCell(
                    row.documenterLabel != '-'
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_note_rounded, size: 13, color: Color(0xFF92400E)),
                                const SizedBox(width: 4),
                                Text(
                                  row.documenterLabel,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.meeting_room_outlined, size: 13, color: Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(
                          row.room.isNotEmpty ? row.room : 'Unassigned',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: Text(
                      issueText.isEmpty ? 'All fields verified' : issueText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: row.issues.isNotEmpty
                            ? const Color(0xFFB42318)
                            : row.warnings.isNotEmpty
                                ? const Color(0xFFB45309)
                                : const Color(0xFF027A48),
                        fontSize: 11.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ready ? const Color(0xFFA6F4C5) : const Color(0xFFFEDF89),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 13,
            color: ready ? const Color(0xFF027A48) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: ready ? const Color(0xFF027A48) : const Color(0xFFB45309),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
