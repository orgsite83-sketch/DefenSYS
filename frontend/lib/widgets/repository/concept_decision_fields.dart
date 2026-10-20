import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'document_policy_editor.dart';

String? conceptDecisionError(
  List<Map<String, dynamic>> concepts,
  String verdict,
) {
  if (concepts.isEmpty) return null;
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
      return 'Choose a decision for every concept.';
    }
    if (const [
          'rejected',
          'revise',
          'approved_with_revisions',
        ].contains(decision) &&
        '${concept['remarks'] ?? ''}'.trim().isEmpty) {
      return 'Explain each rejected concept or required revision.';
    }
    if (decision == 'approved' || decision == 'approved_with_revisions') {
      selected.add(concept);
    }
  }
  if (verdict == 'approved' || verdict == 'approved_with_revisions') {
    if (selected.length != 1 || selected.single['decision'] != verdict) {
      return 'Select exactly one concept matching the hearing approval verdict.';
    }
  } else if (selected.isNotEmpty) {
    return 'An approved concept requires an approval verdict for this hearing.';
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
    if (shared && selected < 0) {
      return const Text(
        'Select the section system in the shared workspace before reviewing this team’s linked module.',
      );
    }
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
            shared ? 'Linked module review' : 'Decisions for this concept set',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            shared
                ? 'Review the module linked to the selected section system. Record this team’s module outcome and any required changes.'
                : pit
                ? 'Select one concept to become the official project. Record a decision for every proposal. Reject all proposals to request a replacement set.'
                : 'Select one approved concept for an approval verdict. If all are rejected, choose For re-defense to request replacement concepts.',
          ),
          for (final i
              in shared ? [selected] : List.generate(concepts.length, (i) => i))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${concepts[i]['system_title'] == null ? '' : '${concepts[i]['system_title']} → '}${concepts[i]['title']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  WorkflowChoice(
                    value: '${concepts[i]['decision'] ?? ''}',
                    enabled:
                        enabled &&
                        (!concepts[i].containsKey('system_title') ||
                            concepts.any((c) => c['section_selected'] == true)),
                    options: {
                      '': shared
                          ? 'Choose module outcome'
                          : 'Choose concept decision',
                      if (!concepts[i].containsKey('system_title') ||
                          concepts[i]['section_selected'] == true)
                        'approved': shared
                            ? 'Approved module'
                            : 'Approved concept',
                      if (!concepts[i].containsKey('system_title') ||
                          concepts[i]['section_selected'] == true)
                        'approved_with_revisions': 'Approved with revisions',
                      'rejected': shared ? 'Module rejected' : 'Rejected',
                      if (!shared) 'not_selected': 'Not selected',
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
