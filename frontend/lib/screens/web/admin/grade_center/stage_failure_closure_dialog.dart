import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// Review named final-failure dispositions separately from assessment scores.
class StageFailureClosureDialog extends StatefulWidget {
  const StageFailureClosureDialog({
    super.key,
    required this.stageLabel,
    required this.teams,
  });
  final String stageLabel;
  final List<Map<String, dynamic>> teams;

  @override
  State<StageFailureClosureDialog> createState() =>
      _StageFailureClosureDialogState();
}

class _StageFailureClosureDialogState extends State<StageFailureClosureDialog> {
  final _reason = TextEditingController();
  bool _acknowledged = false;
  bool _confirming = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final ready = _acknowledged && _reason.text.trim().isNotEmpty;
    return DefensysShadcnScope(
      child: Dialog(
        backgroundColor: DefensysTokens.surfaceOf(context),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _confirming
                      ? 'Complete ${widget.stageLabel}?'
                      : 'Review stage completion',
                  style: DefensysTokens.dialogTitle.copyWith(color: ink),
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.teams.length == 1 ? 'This team' : 'These ${widget.teams.length} teams'} will be finalized as Failed for this stage.',
                  style: TextStyle(color: ink),
                ),
                const SizedBox(height: 16),
                for (final team in widget.teams)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${team['team_name']}',
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Re-defense required; no active hearing scheduled',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        if ((team['assessment'] as Map?)?['assessments']
                            is List)
                          for (final score
                              in (team['assessment']['assessments'] as List)
                                  .whereType<Map>())
                            Text(
                              '${score['title']?.toString().isNotEmpty == true ? score['title'] : 'Panel assessment'}: ${score['score'] ?? 'Not assessed'}${score['score'] == null ? '' : '%'}',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                      ],
                    ),
                  ),
                if (!_confirming) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShadCheckbox(
                        value: _acknowledged,
                        onChanged: (value) =>
                            setState(() => _acknowledged = value),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Finalize the named teams as Failed when completing this stage.',
                          style: TextStyle(color: ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Closure reason / institutional reference',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  ShadInput(
                    controller: _reason,
                    maxLength: 5000,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                ] else
                  Text(_reason.text.trim(), style: TextStyle(color: muted)),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      height: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      onPressed: () => _confirming
                          ? setState(() => _confirming = false)
                          : Navigator.of(context).pop(),
                      child: Flexible(
                        child: Text(
                          _confirming ? 'Go back' : 'Keep stage open',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    ShadButton(
                      height: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      onPressed: !ready
                          ? null
                          : () {
                              if (!_confirming) {
                                setState(() => _confirming = true);
                              } else {
                                Navigator.of(context).pop(_reason.text.trim());
                              }
                            },
                      child: Flexible(
                        child: Text(
                          _confirming
                              ? 'Complete stage'
                              : 'Review final decision',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
