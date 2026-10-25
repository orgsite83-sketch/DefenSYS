import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'document_policy_editor.dart';

String? conceptDecisionError(
  List<Map<String, dynamic>> concepts,
  String verdict, {
  bool requirePlan = false,
}) {
  if (concepts.isEmpty) return null;
  final shared = concepts.any((c) => c.containsKey('system_title'));
  final isSingle = !shared && concepts.length == 1;
  final selected = <Map<String, dynamic>>[];
  for (final concept in concepts) {
    final decision = concept['decision'];
    if (!const [
      'approved',
      'approved_with_revisions',
      'rejected',
      'not_selected',
      'revise',
    ].contains(decision)) {
      return isSingle
          ? 'Choose a verdict for this project proposal.'
          : 'Choose a decision for every concept.';
    }
    if (const [
          'rejected',
          'revise',
          'approved_with_revisions',
        ].contains(decision) &&
        '${concept['remarks'] ?? ''}'.trim().isEmpty) {
      return isSingle
          ? 'Explain the required revisions or reason for re-defense.'
          : 'Explain each rejected concept or required revision.';
    }
    if (decision == 'approved' || decision == 'approved_with_revisions') {
      if (concept['qualifies'] == false) {
        return 'Select a concept whose panel assessment meets the qualifying score.';
      }
      selected.add(concept);
    }
  }
  if (verdict == 'approved' || verdict == 'approved_with_revisions') {
    if (selected.length != 1 || selected.single['decision'] != verdict) {
      return isSingle
          ? 'The project proposal decision must match the hearing approval verdict.'
          : 'Select exactly one concept matching the hearing approval verdict.';
    }
  } else if (selected.isNotEmpty) {
    return isSingle
        ? 'An approved proposal requires an approval verdict for this hearing.'
        : 'An approved concept requires an approval verdict for this hearing.';
  }
  if (requirePlan && verdict == 'for_redefense') {
    final planned = conceptDecisionsForOutcome(concepts, verdict);
    final requested = planned.where((c) => c['next_action'] != 'omit');
    if (requested.isEmpty) {
      return 'Request at least one concept for the next hearing.';
    }
    for (final concept in requested) {
      if ('${concept['remarks'] ?? ''}'.trim().isEmpty) {
        return 'Record the panel instructions for every requested concept.';
      }
      if (shared && concept['section_selected'] != true) {
        return 'Request only the module linked to the selected shared system.';
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> conceptDecisionsForOutcome(
  List<Map<String, dynamic>> concepts,
  String verdict,
) => [
  for (final concept in concepts)
    {
      ...concept,
      if (verdict == 'for_redefense')
        'next_action':
            concept['next_action'] ??
            (concept['decision'] == 'revise' ? 'revise' : 'omit'),
    },
];

class ConceptVerdictFields extends StatelessWidget {
  const ConceptVerdictFields({
    super.key,
    required this.concepts,
    required this.onChanged,
    this.enabled = true,
    this.pit = false,
    this.forRedefense = false,
  });
  final List<Map<String, dynamic>> concepts;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final bool pit;
  final bool forRedefense;
  @override
  Widget build(BuildContext context) {
    final shared = concepts.any((c) => c.containsKey('system_title'));
    final selected = concepts.indexWhere((c) => c['section_selected'] == true);
    final isSingle = !shared && concepts.length == 1;
    final planning =
        forRedefense ||
        (pit &&
            concepts.every(
              (c) =>
                  '${c['decision'] ?? ''}'.isNotEmpty &&
                  ![
                    'approved',
                    'approved_with_revisions',
                  ].contains(c['decision']),
            ));
    List<Map<String, dynamic>> updatedConcepts() => [
      for (var i = 0; i < concepts.length; i++)
        if (shared && i != selected)
          {...concepts[i], 'decision': 'not_selected', 'remarks': ''}
        else
          Map<String, dynamic>.from(concepts[i]),
    ];
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            shared
                ? 'Module proposals and outcome'
                : isSingle
                ? 'Project proposal evaluation'
                : 'Decisions for this concept set',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            shared
                ? selected < 0
                      ? 'The section choice is pending. All configured module proposals remain available. Open the section workspace to select the shared system.'
                      : 'The selected system is highlighted. Review this team’s linked module and record its outcome. The alternatives remain visible until the decision is recorded.'
                : isSingle
                ? 'Evaluate this project defense: determine whether the proposal is approved, requires revisions, or needs re-defense.'
                : pit
                ? 'Select one concept to become the official project. For another hearing, specify which concepts to revise or replace.'
                : 'Select one qualifying concept for approval. For re-defense, specify the concepts and corrections for the next hearing.',
          ),
          for (final i in List.generate(concepts.length, (i) => i))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${shared && i == selected ? 'Selected system · ' : ''}${concepts[i]['system_title'] == null ? '' : '${concepts[i]['system_title']} → '}${concepts[i]['title']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  if (concepts[i].containsKey('panel_score')) ...[
                    Text(
                      'Panel assessment: ${concepts[i]['panel_score'] ?? 'Pending'}% · ${concepts[i]['qualifies'] == true ? 'Qualifies' : 'Does not qualify yet'}',
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (!shared || i == selected)
                    WorkflowChoice(
                      value: '${concepts[i]['decision'] ?? ''}',
                      enabled:
                          enabled &&
                          (!concepts[i].containsKey('system_title') ||
                              concepts.any(
                                (c) => c['section_selected'] == true,
                              )),
                      options: {
                        '': shared
                            ? 'Choose module outcome'
                            : isSingle
                            ? 'Choose project verdict'
                            : 'Choose concept decision',
                        if (concepts[i]['qualifies'] != false &&
                            (!concepts[i].containsKey('system_title') ||
                                concepts[i]['section_selected'] == true))
                          'approved': shared
                              ? 'Approved module'
                              : isSingle
                              ? 'Approved'
                              : 'Approved concept',
                        if (concepts[i]['qualifies'] != false &&
                            (!concepts[i].containsKey('system_title') ||
                                concepts[i]['section_selected'] == true))
                          'approved_with_revisions': 'Approved with revisions',
                        'rejected': shared ? 'Module rejected' : 'Rejected',
                        if (!shared && !isSingle)
                          'not_selected': 'Not selected',
                        'revise': shared
                            ? 'Revise this module'
                            : 'Revise and present again',
                      },
                      onChanged: (v) {
                        final updated = updatedConcepts();
                        updated[i]['decision'] = v;
                        onChanged(updated);
                      },
                    ),
                  const SizedBox(height: 6),
                  if (!shared || i == selected)
                    ShadInput(
                      key: ValueKey('${concepts[i]['key']}-remarks'),
                      enabled: enabled,
                      initialValue: '${concepts[i]['remarks'] ?? ''}',
                      placeholder: const Text('Reason or required corrections'),
                      onChanged: (v) {
                        final updated = updatedConcepts();
                        updated[i]['remarks'] = v;
                        onChanged(updated);
                      },
                    ),
                  if (planning && (!shared || i == selected)) ...[
                    const SizedBox(height: 10),
                    const Text('Next hearing'),
                    const SizedBox(height: 6),
                    WorkflowChoice(
                      key: ValueKey('${concepts[i]['key']}-next-hearing'),
                      value:
                          '${concepts[i]['next_action'] ?? (concepts[i]['decision'] == 'revise' ? 'revise' : 'omit')}',
                      enabled: enabled,
                      options: const {
                        'omit': 'Not requested',
                        'revise': 'Revise and present again',
                        'replace': 'Submit a replacement concept',
                      },
                      onChanged: (value) {
                        final updated = updatedConcepts();
                        updated[i]['next_action'] = value;
                        onChanged(updated);
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
