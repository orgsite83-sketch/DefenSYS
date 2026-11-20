import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'stage_outcome_settings.dart';

Future<bool> showFutureDefenseRulesDialog(
  BuildContext context, {
  required Map<String, dynamic> stage,
  required Future<String?> Function(Map<String, dynamic>) onSave,
}) async {
  final score = TextEditingController(
    text: '${stage['qualifying_score'] ?? ''}',
  );
  var carryover = '${stage['score_carryover'] ?? 'reassess'}';
  var areas = (stage['revision_areas'] as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
  var busy = false;
  String? error;
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => DefensysShadcnScope(
      child: StatefulBuilder(
        builder: (dialogContext, update) => ShadDialog(
          title: const Text('Rules for new hearings'),
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 800),
          actions: [
            ShadButton.outline(
              enabled: !busy,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              enabled: !busy,
              backgroundColor: DefensysTokens.maroonOf(dialogContext),
              foregroundColor: Colors.white,
              onPressed: () async {
                final validation = StageOutcomeSettings.validateScore(
                  score.text,
                );
                if (validation != null) {
                  update(() => error = validation);
                  return;
                }
                update(() {
                  busy = true;
                  error = null;
                });
                try {
                  final failure = await onSave({
                    'qualifying_score': double.parse(score.text.trim()),
                    'score_carryover': carryover,
                    'revision_areas': areas,
                  });
                  if (!dialogContext.mounted) return;
                  if (failure == null) {
                    Navigator.pop(dialogContext, true);
                  } else {
                    update(() {
                      busy = false;
                      error = failure;
                    });
                  }
                } catch (_) {
                  if (dialogContext.mounted) {
                    update(() {
                      busy = false;
                      error = 'Unable to save defense rules.';
                    });
                  }
                }
              },
              child: Text(busy ? 'Saving…' : 'Save rules'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New hearings capture these rules. Scheduled hearings keep their captured policy.',
                ),
                const SizedBox(height: 18),
                StageOutcomeSettings(
                  scoreController: score,
                  scoreCarryover: carryover,
                  conceptSelection:
                      (stage['concept_config'] as Map?)?['enabled'] == true,
                  enabled: !busy,
                  onChanged: () => update(() {}),
                  onCarryoverChanged: (value) =>
                      update(() => carryover = value),
                  revisionAreas: areas,
                  onRevisionAreasChanged: (value) =>
                      update(() => areas = value),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  score.dispose();
  return changed == true;
}
