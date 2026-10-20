import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'document_policy_editor.dart';

String? conceptDecisionError(
  List<Map<String, dynamic>> concepts,
  String verdict,
) {
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
  return null;
}

class ConceptVerdictFields extends StatelessWidget {
  const ConceptVerdictFields({
    super.key,
    required this.concepts,
    required this.onChanged,
    this.enabled = true,
    this.pit = false,
  });
  final List<Map<String, dynamic>> concepts;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final bool pit;
  @override
  Widget build(BuildContext context) {
    final shared = concepts.any((c) => c.containsKey('system_title'));
    final selected = concepts.indexWhere((c) => c['section_selected'] == true);
    final isSingle = !shared && concepts.length == 1;
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
                      ? 'The section choice is pending. All three module proposals remain available. Open the section workspace to select the shared system.'
                      : 'The selected system is highlighted. Review this team’s linked module and record its outcome. The alternatives remain visible until the decision is recorded.'
                : isSingle
                ? 'Evaluate this project defense: determine whether the proposal is approved, requires revisions, or needs re-defense.'
                : pit
                ? 'Select one concept to become the official project. Record a decision for every proposal. Reject all proposals to request a replacement set.'
                : 'Select one approved concept for an approval verdict. If all are rejected, choose For re-defense to request replacement concepts.',
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
                        if (!concepts[i].containsKey('system_title') ||
                            concepts[i]['section_selected'] == true)
                          'approved': shared
                              ? 'Approved module'
                              : isSingle
                              ? 'Approved'
                              : 'Approved concept',
                        if (!concepts[i].containsKey('system_title') ||
                            concepts[i]['section_selected'] == true)
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}
