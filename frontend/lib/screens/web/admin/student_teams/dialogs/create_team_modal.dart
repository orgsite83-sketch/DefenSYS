import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Future<void> showCreateTeamModal({
  required BuildContext context,
  required WidgetRef ref,
  required StudentTeamsState state,
  required bool isCapstoneAdmin,
  required bool isPitLeadManager,
  required String? pitLeadYear,
}) async {
  const yearOptions = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

  final statusOptions = state.statuses.isEmpty
      ? const ['Pending', 'Approved', 'Failed', 'Delayed/Extended']
      : state.statuses;
  final name = TextEditingController();
  final projectTitle = TextEditingController();
  final isFirstSem = state.activeSemester?['label']?.toString().toLowerCase().contains('1st') ?? false;
  final isPitView = state.level.toUpperCase().contains('PIT') || isPitLeadManager;
  final defaultYear = isPitLeadManager
      ? (pitLeadYear ?? '3rd Year')
      : (isPitView
          ? (state.yearLevel ?? '1st Year')
          : (isFirstSem ? '4th Year' : '3rd Year'));
  var yearLevel = defaultYear;
  if (!yearOptions.contains(yearLevel)) {
    yearLevel = defaultYear;
  }
  var level = isPitView
      ? '$yearLevel PIT'
      : (yearLevel == '4th Year' || (yearLevel == '3rd Year' && !isFirstSem)
          ? '$yearLevel Capstone'
          : '$yearLevel PIT');
  String? selectedPitEvent = state.eventName;
  var status = 'Pending';
  if (!statusOptions.contains(status)) {
    status = statusOptions.first;
  }
  int? adviserId;
  final selectedMembers = <int>{};
  int? leaderId;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            title: const Text('Create New Team'),
            content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Team Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: projectTitle,
                      decoration: const InputDecoration(
                        labelText: 'Project Title',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isPitLeadManager)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Program',
                        ),
                        child: Text(
                          '$yearLevel PIT',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Program',
                        ),
                        child: Text(
                          level.contains('Capstone') ? 'Capstone · $yearLevel' : '$yearLevel PIT',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Team Result',
                      ),
                      items: statusOptions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          status = value ?? status;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!isPitLeadManager && level.toUpperCase().contains('CAPSTONE')) ...[
                      DropdownButtonFormField<int?>(
                        initialValue: adviserId,
                        decoration: const InputDecoration(labelText: 'Adviser'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Unassigned'),
                          ),
                          ...state.advisers.map(
                            (adviser) => DropdownMenuItem<int?>(
                              value: _asInt(adviser['id']),
                              child: Text(
                                '${adviser['name']} (${adviser['username']})',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            adviserId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      if (state.pitEvents.isNotEmpty) ...[
                        DropdownButtonFormField<String?>(
                          initialValue: selectedPitEvent,
                          decoration: const InputDecoration(
                            labelText: 'PIT Event',
                            hintText: 'Assign to specific event (optional)',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('None / General PIT'),
                            ),
                            ...state.pitEvents.map((ev) {
                              final evName = ev['event_name']?.toString() ?? '';
                              return DropdownMenuItem<String?>(
                                value: evName,
                                child: Text(evName),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedPitEvent = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Members (${selectedMembers.length}/4)',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: state.students.map((student) {
                          final studentId = _asInt(student['id'])!;
                          final selected = selectedMembers.contains(
                            studentId,
                          );
                          return CheckboxListTile(
                            value: selected,
                            title: Text(
                              '${student['name']} (${student['username']})',
                            ),
                            subtitle: leaderId == studentId
                                ? const Text('Team Leader')
                                : null,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  if (selectedMembers.length >= 4 &&
                                      !selected) {
                                    return;
                                  }
                                  selectedMembers.add(studentId);
                                  leaderId ??= studentId;
                                } else {
                                  selectedMembers.remove(studentId);
                                  if (leaderId == studentId) {
                                    leaderId = selectedMembers.isEmpty
                                        ? null
                                        : selectedMembers.first;
                                  }
                                }
                              });
                            },
                            secondary: selected
                                ? IconButton(
                                    tooltip: 'Set as leader',
                                    icon: Icon(
                                      leaderId == studentId
                                          ? Icons.workspace_premium_rounded
                                          : Icons.circle_outlined,
                                      color: leaderId == studentId
                                          ? DefensysUi.accentGold
                                          : DefensysUi.steelGrey,
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        leaderId = studentId;
                                      });
                                    },
                                  )
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select up to 4 members. Use the medal button to choose the leader.',
                        style: TextStyle(color: DefensysUi.steelGrey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed:
                    selectedMembers.isEmpty ||
                        leaderId == null ||
                        name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Create Team'),
              ),
            ],
          );
        },
      );
    },
  );

  if (saved != true) {
    name.dispose();
    projectTitle.dispose();
    return;
  }

  final isCapstone = level.toUpperCase().contains('CAPSTONE');
  if (!isCapstone) {
    adviserId = null;
  }

  if (isPitLeadManager) {
    yearLevel = pitLeadYear ?? yearLevel;
    level = '$yearLevel PIT';
  }

  final payload = {
    'name': name.text.trim(),
    'project_title': projectTitle.text.trim().isEmpty
        ? name.text.trim()
        : projectTitle.text.trim(),
    if (isPitLeadManager || isPitView) 'level': level,
    if (isPitLeadManager || isPitView) 'year_level': yearLevel,
    'leader_id': leaderId,
    'member_ids': selectedMembers.toList(),
    'adviser_id': isCapstone ? adviserId : null,
    'status': status,
    if (!isCapstone && selectedPitEvent != null && selectedPitEvent!.trim().isNotEmpty)
      'current_defense_stage': selectedPitEvent!.trim(),
  };

  name.dispose();
  projectTitle.dispose();

  await ref.read(studentTeamsProvider.notifier).addTeam(payload);
}
