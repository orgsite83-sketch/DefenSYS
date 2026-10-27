import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

class ConceptRevision {
  const ConceptRevision(this.scope, this.feedback);
  final String scope;
  final String feedback;
}

Future<ConceptRevision?> showConceptRevisionDialog(
  BuildContext context, {
  required String description,
  bool titleOnly = false,
  bool titleAvailable = false,
}) async {
  final controller = TextEditingController();
  var scope = titleOnly ? 'title' : 'paper';
  String? error;
  final result = await showDialog<ConceptRevision>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => DefensysShadcnScope(
        child: ShadDialog(
          title: Text(
            titleOnly ? 'Request title revision' : 'Request revision',
          ),
          description: Text(description),
          constraints: const BoxConstraints(maxWidth: 560),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ShadButton(
              backgroundColor: DefensysTokens.maroonOf(context),
              foregroundColor: Colors.white,
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  update(() => error = 'Explain what needs to change.');
                  return;
                }
                Navigator.pop(
                  context,
                  ConceptRevision(scope, controller.text.trim()),
                );
              },
              child: const Text('Send revision request'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!titleOnly && titleAvailable) ...[
                const Text('What needs changing?'),
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: RadioGroup<String>(
                    groupValue: scope,
                    onChanged: (value) => update(() => scope = value!),
                    child: const Column(
                      children: [
                        RadioListTile<String>(
                          value: 'paper',
                          title: Text('Paper only'),
                          subtitle: Text(
                            'Keep the title unchanged. Request a new file revision.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          value: 'title_and_paper',
                          title: Text('Title and paper'),
                          subtitle: Text(
                            'Return the matching title and this file in one request.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (scope == 'title_and_paper') ...[
                const Text(
                  'The student revises the title first. After title acceptance, they upload the updated paper. Other concept titles stay unchanged.',
                ),
                const SizedBox(height: 16),
              ],
              ShadInput(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                placeholder: const Text('Explain the changes needed.'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  // Keep the input alive throughout the dialog's exit animation.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}
