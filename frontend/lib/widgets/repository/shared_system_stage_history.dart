import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/defense_workflow_labels.dart';
import '../../models/team_workflow_status.dart';
import '../../theme/defensys_tokens.dart';
import '../defense/concept_hearing_history.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'deliverable_file_widgets.dart';
import 'shared_concept_review.dart' show systemLetter;

/// Each selected stage owns its records. A missing snapshot is not an empty roster.
class SharedSystemStageHistory extends StatelessWidget {
  const SharedSystemStageHistory({
    super.key,
    required this.records,
    this.showHeading = true,
  });
  final List<Map<String, dynamic>> records;
  final bool showHeading;

  List<Map> rows(dynamic value) =>
      (value as List? ?? []).whereType<Map>().toList();

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final body = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
      height: 1.45,
      color: secondary,
    );
    String title(Map item) => switch (item['kind']) {
      'hearing' => 'Shared hearing · Attempt ${item['attempt']}',
      'shared_submission' => 'Shared submission',
      'team_direction' => '${item['team_name']} · Next direction',
      'team_defense' =>
        '${item['team_name']} · Defense${item['attempt'] == null ? '' : ' ${item['attempt']}'}',
      'selection_correction' => 'Shared selection corrected',
      _ => 'Recorded activity',
    };
    return DefensysShadcnScope(
      child: Column(
        key: const ValueKey('shared-stage-history'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeading) const SizedBox(height: 18),
          if (showHeading)
            const Text(
              'Stage history',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No activity recorded for this stage yet.',
                style: body,
              ),
            )
          else
            ShadAccordion<String>(
              children: [
                for (final item in records)
                  ShadAccordionItem(
                    value: '${item['id']}',
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title(item),
                          style: const TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if ('${item['outcome'] ?? ''}'.isNotEmpty)
                              DeliverableStatusBadge(
                                label: defenseVerdictLabel(
                                  '${item['outcome']}',
                                ),
                                tone:
                                    const {
                                      'approved',
                                      'approved_with_revisions',
                                    }.contains(item['outcome'])
                                    ? WorkflowStatusTone.success
                                    : WorkflowStatusTone.neutral,
                              ),
                            if (const {
                                  'hearing',
                                  'shared_submission',
                                }.contains(item['kind']) &&
                                item.containsKey('team_count'))
                              Text(
                                item['team_count'] == null
                                    ? 'Team roster not recorded'
                                    : '${item['team_count']} teams',
                                style: body,
                              ),
                            if (DateTime.tryParse('${item['date'] ?? ''}') !=
                                null)
                              Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(
                                  DateTime.parse('${item['date']}').toLocal(),
                                ),
                                style: body,
                              ),
                          ],
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ('${item['semester'] ?? ''}'.isNotEmpty)
                          Text('${item['semester']}', style: body),
                        if ('${item['remarks'] ?? ''}'.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text('${item['remarks']}', style: body),
                          ),
                        if (item['kind'] == 'team_direction')
                          Text(
                            item['direction'] == 'independent'
                                ? 'Continues with independent concepts'
                                : 'Continues with the selected shared module',
                            style: body,
                          ),
                        if ('${item['recorded_by'] ?? ''}'.isNotEmpty)
                          Text(
                            'Recorded by ${item['recorded_by']}',
                            style: body,
                          ),
                        if (item['kind'] == 'selection_correction')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'From: ${item['from_title']}\nTo: ${item['to_title']}',
                              style: body,
                            ),
                          ),
                        if ((item['joined_count'] as num? ?? 0) > 0 ||
                            (item['left_count'] as num? ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Roster change: ${item['joined_count'] ?? 0} added, ${item['left_count'] ?? 0} no longer listed',
                              style: body,
                            ),
                          ),
                        for (final system in rows(item['systems']))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 5,
                                  children: [
                                    Text(
                                      'System ${systemLetter(system['key'])}',
                                      style: body,
                                    ),
                                    if (system['key'] == item['selected_key'])
                                      const DeliverableStatusBadge(
                                        label: 'Selected system',
                                        tone: WorkflowStatusTone.success,
                                      )
                                    else if ('${system['decision'] ?? ''}'
                                        .isNotEmpty)
                                      DeliverableStatusBadge(
                                        label: conceptDecisionLabel(
                                          system['decision'],
                                        ),
                                        tone: WorkflowStatusTone.neutral,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${system['title']}',
                                  style: DefensysTokens.body.copyWith(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (item['teams'] is List)
                          ShadAccordion<String>(
                            children: [
                              ShadAccordionItem(
                                value: 'teams',
                                separator: const SizedBox.shrink(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                title: Text(
                                  'Participating teams (${rows(item['teams']).length})',
                                  style: body,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if ('${item['roster_basis'] ?? ''}'
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          '${item['roster_basis']}',
                                          style: body,
                                        ),
                                      ),
                                    for (final team in rows(item['teams']))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              '${team['name']}',
                                              style: DefensysTokens.body.copyWith(
                                                fontFamily: DefensysTokens
                                                    .fontFamilyInter,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    DefensysTokens.textPrimaryOf(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                            for (final module
                                                in rows(item['modules']).where(
                                                  (row) =>
                                                      row['team_id'] ==
                                                      team['id'],
                                                ))
                                              for (final concept
                                                  in rows(
                                                    module['concepts'],
                                                  ).where(
                                                    (row) =>
                                                        row['key'] ==
                                                        item['selected_key'],
                                                  ))
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    'Module attempt ${module['attempt']}: ${concept['title']} · ${conceptDecisionLabel(concept['decision'])}',
                                                    style: body,
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
