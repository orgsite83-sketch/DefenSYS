import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/defense_workflow_labels.dart';
import '../../models/team_workflow_status.dart';
import '../../theme/defensys_tokens.dart';
import '../repository/deliverable_file_widgets.dart';
import '../shadcn/defensys_shadcn_scope.dart';

String conceptDecisionLabel(dynamic value) => switch ('$value') {
  'not_selected' => 'Not selected',
  'rejected' => 'Not approved',
  'revise' => 'Revision requested',
  '' || 'null' => 'Pending',
  _ => defenseVerdictLabel('$value'),
};

class ConceptHistory extends StatelessWidget {
  const ConceptHistory({super.key, required this.workflow});
  final Map<String, dynamic> workflow;

  @override
  Widget build(BuildContext context) {
    final history = (workflow['history'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (history.isEmpty) return const SizedBox.shrink();
    final secondary = DefensysTokens.textSecondaryOf(context);
    final text = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
      height: 1.45,
      color: secondary,
    );
    return DefensysShadcnScope(
      child: ShadAccordion<String>(
        children: [
          for (final round in history)
            ShadAccordionItem(
              value: '${round['schedule_id']}-${round['round']}',
              title: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Attempt ${round['round']}',
                    style: const TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DeliverableStatusBadge(
                    label: '${round['verdict'] ?? ''}'.isEmpty
                        ? 'Scheduled'
                        : defenseVerdictLabel('${round['verdict']}'),
                    tone:
                        const {
                          'approved',
                          'approved_with_revisions',
                        }.contains(round['verdict'])
                        ? WorkflowStatusTone.success
                        : WorkflowStatusTone.neutral,
                  ),
                  if (DateTime.tryParse('${round['decided_at'] ?? ''}') != null)
                    Text(
                      MaterialLocalizations.of(context).formatMediumDate(
                        DateTime.parse('${round['decided_at']}').toLocal(),
                      ),
                      style: text,
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ('${round['decided_by_name'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Recorded by ${round['decided_by_name']}',
                        style: text,
                      ),
                    ),
                  if ('${round['remarks'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('${round['remarks']}', style: text),
                    ),
                  for (final concept
                      in (round['concepts'] as List? ?? []).whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${concept['title']}',
                            style: DefensysTokens.body.copyWith(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DeliverableStatusBadge(
                                label: conceptDecisionLabel(
                                  concept['decision'],
                                ),
                                tone:
                                    const {
                                      'approved',
                                      'approved_with_revisions',
                                    }.contains(concept['decision'])
                                    ? WorkflowStatusTone.success
                                    : WorkflowStatusTone.neutral,
                              ),
                            ],
                          ),
                          if ('${concept['remarks'] ?? ''}'.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${concept['remarks']}', style: text),
                            ),
                          if (const {
                            'revise',
                            'replace',
                          }.contains(concept['next_action']))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                concept['next_action'] == 'revise'
                                    ? 'Next attempt: Revise this concept'
                                    : 'Next attempt: Submit a replacement concept',
                                style: text,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (round['next_attempt_direction'] is Map)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        (round['next_attempt_direction'] as Map)['direction'] ==
                                'independent'
                            ? 'Next attempt: Independent concepts'
                            : 'Next attempt: Revise selected shared module',
                        style: text,
                      ),
                    ),
                  if ('${round['override_reason'] ?? ''}'.isNotEmpty)
                    Text(
                      'Clearance exception: ${round['override_reason']}',
                      style: text,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
