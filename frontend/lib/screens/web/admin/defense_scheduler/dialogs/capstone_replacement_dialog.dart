import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';

class CapstoneReplacementDecision {
  const CapstoneReplacementDecision(this.scope, this.reason);
  final String scope, reason;
  bool get continuing => scope == 'continuing';
}

class CapstoneReplacementDialog extends StatefulWidget {
  const CapstoneReplacementDialog({
    super.key,
    required this.adviser,
    required this.stage,
    required this.changes,
  });
  final String adviser, stage;
  final List<Map<String, String>> changes;

  @override
  State<CapstoneReplacementDialog> createState() =>
      _CapstoneReplacementDialogState();
}

class _CapstoneReplacementDialogState extends State<CapstoneReplacementDialog> {
  final _reason = TextEditingController();
  String? _scope;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 640),
      title: const Text('Change assigned people'),
      description: Text('${widget.adviser} · ${widget.stage}'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ShadButton(
          backgroundColor: DefensysTokens.maroonOf(context),
          foregroundColor: Colors.white,
          enabled: _scope != null && _reason.text.trim().length >= 5,
          onPressed: _scope == null || _reason.text.trim().length < 5
              ? null
              : () => Navigator.pop(
                  context,
                  CapstoneReplacementDecision(_scope!, _reason.text.trim()),
                ),
          child: const Text('Apply change'),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .6,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Applies to ${widget.changes.map((c) => c['team']).join(', ')}.',
              ),
              const SizedBox(height: 12),
              if (widget.changes
                      .map((c) => '${c['before']}|${c['after']}')
                      .toSet()
                      .length ==
                  1)
                WorkflowComparison(
                  label: 'Assigned people',
                  before: widget.changes.first['before']!,
                  after: widget.changes.first['after']!,
                )
              else
                for (final change in widget.changes)
                  WorkflowComparison(
                    label: change['team']!,
                    before: change['before']!,
                    after: change['after']!,
                  ),
              const SizedBox(height: 10),
              const Text(
                'How should this change apply?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => ShadRadioGroup<String>(
                  onChanged: (value) => setState(() => _scope = value),
                  spacing: 12,
                  items: [
                    _scopeOption(
                      context,
                      constraints.maxWidth,
                      'stage_only',
                      'This stage only',
                      'Keep the continuing panel and documenter for later stages.',
                    ),
                    _scopeOption(
                      context,
                      constraints.maxWidth,
                      'continuing',
                      'This and future stages',
                      'Update the continuing assignment for these adviser teams.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              WorkflowField(
                label: 'Audit reason',
                helper: 'Required · at least 5 characters.',
                child: ShadInput(
                  key: const ValueKey('replacement-audit-reason'),
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 2000,
                  placeholder: const Text(
                    'For example, a panelist is unavailable due to travel.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text(
                'Select Assign to save these choices. Existing confirmed defenses are managed in Schedule Management.',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _scopeOption(
    BuildContext context,
    double width,
    String value,
    String label,
    String description,
  ) => SizedBox(
    width: width,
    child: ShadRadio<String>(
      value: value,
      label: Text(label),
      sublabel: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
          fontFamily: DefensysTokens.fontFamilyInter,
        ),
      ),
    ),
  );
}
