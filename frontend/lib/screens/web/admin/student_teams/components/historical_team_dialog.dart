import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/academic/student_capstone_history.dart';
import '../../../../../services/auth_provider.dart';

Future<void> showHistoricalTeam(
  BuildContext context,
  Map<String, dynamic> team,
) => showDialog<void>(
  context: context,
  builder: (context) => DefensysShadcnScope(
    child: Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                team['name']?.toString() ?? 'Team history',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${team['display_semester']} · Read-only record',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        team['project_title']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Project version ${team['project_version']} · ${team['status']}',
                        style: TextStyle(
                          color: DefensysTokens.textSecondaryOf(context),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Leader: ${team['leader_name']}\nAdviser: ${team['adviser_name'] ?? 'Unassigned'}',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final member in team['members'] as List? ?? [])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children: [
                              Text('${member['name']}'),
                              Consumer(
                                builder: (context, ref, _) =>
                                    StudentCapstoneParticipationButton(
                                      studentId:
                                          (member['student_id'] ?? member['id'])
                                              as int,
                                      name: '${member['name']}',
                                      number:
                                          (member['capstone_participation']
                                                  as Map?)?['number']
                                              as int?,
                                      canOpenHistory:
                                          ref
                                              .watch(authProvider)
                                              .user?['role'] ==
                                          'admin',
                                    ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Assessments in this term',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final assessment
                          in team['assessments'] as List? ?? [])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${assessment['stage_label']} · ${assessment['verdict']?.toString().replaceAll('_', ' ') ?? assessment['status']}\n'
                            '${assessment['project_title_snapshot']} · Version ${assessment['project_version']}',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Submitted files for this stage'),
                        children: [
                          if ((team['files'] as List? ?? []).isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'No recorded files for this selection.',
                              ),
                            ),
                          for (final file
                              in (team['files'] as List? ?? [])
                                  .whereType<Map>())
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${file['label']} · ${file['status']}',
                              ),
                              subtitle: Text(
                                '${file['file_name']} · Project version ${file['project_version']}',
                              ),
                            ),
                        ],
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Recorded activity'),
                        children: [
                          if ((team['timeline'] as List? ?? []).isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'No recorded activity is available for this selection.',
                              ),
                            ),
                          for (final event
                              in (team['timeline'] as List? ?? [])
                                  .whereType<Map>())
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${event['action']}'
                                    .replaceAll('capstone.', '')
                                    .replaceAll('_', ' '),
                              ),
                              subtitle: Text(
                                '${event['recorded_at']} · ${event['actor']}',
                              ),
                            ),
                        ],
                      ),
                      Text(
                        'This record preserves the earlier project and outcome even when the team is active in another term.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
