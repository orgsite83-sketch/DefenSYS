import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

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
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.outline(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
