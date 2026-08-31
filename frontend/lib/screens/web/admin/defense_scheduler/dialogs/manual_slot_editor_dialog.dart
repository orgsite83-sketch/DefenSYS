import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../models/schedule_import_models.dart';

class ManualSlotEditorDialog {
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required DefenseSchedulerState state,
    required String initialScope,
    required int? initialStageId,
    required int? initialRubricId,
    required int? initialAdviserRubricId,
    required int? initialCapstonePeerRubricId,
    required int? initialPeerRubricId,
    required Set<int> initialSelectedPanelistIds,
    int? initialDocumenterId,
    required String initialEvent,
    required String initialPitTemplate,
    required String initialDate,
    required String initialTime,
    required String initialDuration,
    required String initialRoom,
    required String initialPanelWeight,
    required String initialPeerWeight,
    required bool Function(DefenseSchedulerState state, String scope) canScheduleScope,
    required String Function(DefenseSchedulerState state) scheduleNoticeMessage,
  }) async {
    if (!canScheduleScope(state, initialScope)) {
      showValidationToast(context, scheduleNoticeMessage(state));
      return;
    }

    String scope = initialScope;
    int? stageId = initialStageId;
    int? teamId;
    int? rubricId = initialRubricId;
    int? peerRubricId = initialPeerRubricId;
    final panelWeight = TextEditingController(text: initialPanelWeight);
    final peerWeight = TextEditingController(text: initialPeerWeight);

    if (scope == 'capstone' && stageId != null && rubricId == null) {
      final semesterId = asInt(state.activeSemester?['id']);
      final detail = await ref
          .read(defenseStagesProvider.notifier)
          .fetchStageDetail(stageId, semesterId: semesterId);
      final grading = detail?['grading_config'];
      if (grading is Map) {
        rubricId = asInt(grading['panel_rubric_id']) ?? rubricId;
      }
    }

    final event = TextEditingController(text: initialEvent);
    final vaultFileTemplate = TextEditingController(text: initialPitTemplate);
    final date = TextEditingController(text: initialDate);
    final time = TextEditingController(text: initialTime);
    final duration = TextEditingController(text: initialDuration);
    final room = TextEditingController(text: initialRoom);
    final panelIds = <int>{...initialSelectedPanelistIds};
    int? documenterId = initialDocumenterId;

    if (!context.mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final teams = teamsForScope(state, scope);

            final validTeam = teams.any((item) => asInt(item['id']) == teamId)
                ? teamId
                : null;

            final scopes = <String>[
              if (canScheduleScope(state, 'capstone')) 'capstone',
              if (canScheduleScope(state, 'pit')) 'pit',
            ];
            final scopeValues = scopes.isNotEmpty
                ? scopes
                : [if (initialScope.isNotEmpty) initialScope else 'capstone'];
            if (!scopeValues.contains(scope) && scopeValues.isNotEmpty) {
              scope = scopeValues.first;
            }
            final allowedScopeItems = scopeValues
                .where((s) => s == 'capstone' || s == 'pit')
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(s == 'pit' ? 'PIT' : 'Capstone'),
                  ),
                )
                .toList();

            return AlertDialog(
              title: const Text('Manual Schedule Form'),
              content: SizedBox(
                width: 680,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: scopeValues.length > 1
                                ? DropdownButtonFormField<String>(
                                    initialValue: scope,
                                    decoration:
                                        const InputDecoration(labelText: 'Scope'),
                                    items: allowedScopeItems,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        scope = value ?? scope;
                                        stageId = null;
                                        teamId = null;
                                        rubricId = null;
                                        peerRubricId = null;
                                        documenterId = null;
                                      });
                                    },
                                  )
                                : TextFormField(
                                    key: ValueKey('scope_$scope'),
                                    initialValue:
                                        scope == 'pit' ? 'PIT' : 'Capstone',
                                    readOnly: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Scope',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
                                      suffixIcon: Icon(
                                        Icons.lock_outline_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: validTeam,
                              decoration: const InputDecoration(labelText: 'Team'),
                              items: teams
                                  .map(
                                    (team) => DropdownMenuItem<int?>(
                                      value: asInt(team['id']),
                                      child: Text(team['name']?.toString() ?? ''),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  teamId = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (scope == 'capstone') ...[
                        DropdownButtonFormField<int?>(
                          initialValue: stageId,
                          decoration: const InputDecoration(labelText: 'Defense Stage'),
                          items: state.defenseStages
                              .map(
                                (stage) => DropdownMenuItem<int?>(
                                  value: asInt(stage['id']),
                                  child: Text(stage['label']?.toString() ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            setDialogState(() {
                              stageId = value;
                              rubricId = null;
                            });
                            if (value != null) {
                              final semesterId = asInt(state.activeSemester?['id']);
                              final detail = await ref
                                  .read(defenseStagesProvider.notifier)
                                  .fetchStageDetail(value, semesterId: semesterId);
                              final grading = detail?['grading_config'];
                              if (grading is Map && dialogContext.mounted) {
                                setDialogState(() {
                                  rubricId = asInt(grading['panel_rubric_id']);
                                });
                              }
                            }
                          },
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: state.pitEvents
                                  .any((e) => e['event_name'] == event.text)
                              ? event.text
                              : null,
                          decoration:
                              const InputDecoration(labelText: 'PIT Event Name'),
                          items: state.pitEvents.map((e) {
                            final name = e['event_name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              event.text = val;
                              final eventName = val.trim();
                              final semesterId = asInt(state.activeSemester?['id']);
                              final config = await ref
                                  .read(defenseSchedulerProvider.notifier)
                                  .fetchPitEventConfig(
                                    eventName: eventName,
                                    semesterId: semesterId,
                                  );
                              if (config != null) {
                                setDialogState(() {
                                  rubricId = asInt(config['panel_rubric_id']) ?? rubricId;
                                  peerRubricId = asInt(config['peer_rubric_id']) ?? peerRubricId;
                                  panelWeight.text = config['panel_weight']?.toString() ?? '80';
                                  peerWeight.text = config['peer_weight']?.toString() ?? '20';
                                  vaultFileTemplate.text =
                                      (config['archive_file_template'] ?? config['vault_file_template'])
                                          ?.toString() ??
                                      '';
                                });
                              }
                            } else {
                              setDialogState(() {});
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: date,
                              readOnly: true,
                              onTap: () async {
                                final now = DateTime.now();
                                final today = DateTime(now.year, now.month, now.day);
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.tryParse(date.text) ?? today,
                                  firstDate: today,
                                  lastDate: DateTime(now.year + 3, now.month, now.day),
                                );
                                if (picked != null) {
                                  date.text = formatScheduleDate(picked);
                                  setDialogState(() {});
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: time,
                              readOnly: true,
                              onTap: () async {
                                final parts = time.text.split(':');
                                final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
                                final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59)),
                                );
                                if (picked != null) {
                                  time.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                  setDialogState(() {});
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: 'Start Time',
                                suffixIcon: Icon(Icons.access_time_outlined, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: room,
                              decoration: const InputDecoration(labelText: 'Room'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: duration,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Duration',
                                suffixText: 'mins',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Panelists (${panelIds.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.panelists.map((panelist) {
                          final id = asInt(panelist['id']);
                          final selected = id != null && panelIds.contains(id);

                          return FilterChip(
                            selected: selected,
                            label: Text(panelist['name']?.toString() ?? ''),
                            onSelected: id == null
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      if (value) {
                                        panelIds.add(id);
                                        if (documenterId == id) {
                                          documenterId = null;
                                        }
                                      } else {
                                        panelIds.remove(id);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      if (scope == 'capstone') ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Documenter (Optional)${documenterId != null ? ' (1 selected)' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if (documenterId != null)
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    documenterId = null;
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Clear',
                                  style: TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: state.documenters.map((doc) {
                            final id = asInt(doc['id']);
                            final name =
                                doc['name']?.toString() ?? 'Documenter';
                            final isPanelist =
                                id != null && panelIds.contains(id);
                            final selected = id != null && documenterId == id;

                            return FilterChip(
                              avatar: Icon(
                                selected
                                    ? Icons.assignment_turned_in_rounded
                                    : Icons.edit_note_rounded,
                                size: 16,
                                color: selected
                                    ? AppColors.maroon
                                    : (isPanelist
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B)),
                              ),
                              label: Text(
                                isPanelist ? '$name (Panelist)' : name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppColors.maroon
                                      : (isPanelist
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF344054)),
                                  decoration: isPanelist
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              selected: selected,
                              onSelected: (id == null || isPanelist)
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        documenterId = value ? id : null;
                                      });
                                    },
                              backgroundColor: const Color(0xFFF8FAFC),
                              selectedColor: const Color(0xFFFEECEC),
                              checkmarkColor: AppColors.maroon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.maroon
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Schedule'),
                  style: DefensysTokens.saveButtonStyle(isPill: false),
                ),
              ],
            );
          },
        );
      },
    );

    final eventText = event.text.trim();
    final panelWeightText = panelWeight.text.trim();
    final peerWeightText = peerWeight.text.trim();
    final dateText = date.text.trim();
    final timeText = time.text.trim();
    final durationText = duration.text.trim();
    final roomText = room.text.trim();

    Future.delayed(const Duration(milliseconds: 500), () {
      event.dispose();
      vaultFileTemplate.dispose();
      panelWeight.dispose();
      peerWeight.dispose();
      date.dispose();
      time.dispose();
      duration.dispose();
      room.dispose();
    });

    if (!context.mounted || saved != true) {
      return;
    }

    if (teamId == null || panelIds.isEmpty) {
      showValidationToast(context, 'Team and panelists are required.');
      return;
    }

    if (scope == 'capstone') {
      if (stageId == null) {
        showValidationToast(context, 'Select a defense stage.');
        return;
      }
    } else {
      if (eventText.isEmpty) {
        showValidationToast(context, 'Enter a PIT event name.');
        return;
      }
    }

    final schedulePayload = {
      'scope': scope,
      'team_id': teamId,
      'defense_stage_id': scope == 'capstone' ? stageId : null,
      'event_name': scope == 'pit' ? eventText : '',
      'rubric_id': rubricId,
      'scheduled_date': dateText,
      'start_time': timeText,
      'slot_duration': int.tryParse(durationText) ?? 60,
      'room': roomText,
      'panelist_ids': panelIds.toList(),
      if (scope == 'capstone') 'documenter_id': documenterId,
    };
    if (scope == 'pit') {
      schedulePayload['peer_rubric_id'] = peerRubricId;
      schedulePayload['panel_weight'] = int.tryParse(panelWeightText) ?? 80;
      schedulePayload['peer_weight'] = int.tryParse(peerWeightText) ?? 20;
      schedulePayload['archive_file_template'] = vaultFileTemplate.text.trim();
    }
    await ref
        .read(defenseSchedulerProvider.notifier)
        .createSchedule(schedulePayload);
  }
}
