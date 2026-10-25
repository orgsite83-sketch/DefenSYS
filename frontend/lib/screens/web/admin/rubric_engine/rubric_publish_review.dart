import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

/// Reviews the same validated snapshot that will be sent when publishing.
class RubricPublishReview extends StatelessWidget {
  const RubricPublishReview({
    super.key,
    required this.payload,
    required this.semesterLabel,
    required this.assignmentLabel,
    required this.assignmentNotice,
  });

  final Map<String, dynamic> payload;
  final String semesterLabel;
  final String assignmentLabel;
  final String assignmentNotice;

  String _targetLabel(String? target) => switch (target) {
    'individual' => 'Individual',
    'both' => 'Team & Individual',
    _ => 'Team',
  };

  String _percentage(num value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Widget _detail(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: DefensysTokens.caption.copyWith(
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: DefensysTokens.tableCell.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final criteria = (payload['criteria'] as List).cast<Map<String, dynamic>>();
    final total = criteria.fold<num>(
      0,
      (sum, criterion) => sum + (criterion['weight'] as num),
    );
    final isPit = payload['scope'] == 'pit';
    final evaluator = switch (payload['evaluation_type']) {
      'peer' => 'Peer evaluation',
      'adviser' => 'Adviser evaluation',
      _ => 'Panel evaluation',
    };
    final scale = payload['scale'] == 'Custom Scale'
        ? 'Custom (${payload['custom_max_score']} points)'
        : payload['scale'].toString();
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);

    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 24),
      child: ShadDialog(
        key: const ValueKey('rubric-publish-review'),
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        scrollable: true,
        titlePinned: true,
        actionsPinned: true,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        title: const Text('Review rubric before publishing'),
        description: const Text(
          'Check the details, criteria, and weights before publishing.',
        ),
        actions: [
          ShadButton.outline(
            key: const ValueKey('rubric-review-back'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to editing'),
          ),
          ShadButton(
            key: const ValueKey('rubric-review-publish'),
            onPressed: () => Navigator.pop(context, true),
            backgroundColor: DefensysTokens.maroonOf(context),
            foregroundColor: Colors.white,
            leading: const Icon(LucideIcons.check, size: 16),
            child: const Text('Publish rubric'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    payload['name'].toString(),
                    style: DefensysTokens.sectionTitle.copyWith(color: primary),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth < 480
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 20) / 2;
                      final details = [
                        ('Program', isPit ? 'PIT' : 'Capstone'),
                        ('Academic period', semesterLabel),
                        ('Evaluation type', evaluator),
                        ('Evaluation scale', scale),
                        (
                          'Scoring target',
                          _targetLabel(payload['target_type'] as String?),
                        ),
                        (
                          isPit ? 'PIT event' : 'Defense stage',
                          assignmentLabel,
                        ),
                      ];
                      return Wrap(
                        spacing: 20,
                        runSpacing: 16,
                        children: [
                          for (final (label, value) in details)
                            SizedBox(
                              width: width,
                              child: _detail(context, label, value),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              assignmentNotice,
              style: DefensysTokens.tableCell.copyWith(color: primary),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  'Evaluation criteria (${criteria.length})',
                  style: DefensysTokens.sectionTitle.copyWith(color: primary),
                ),
                ShadBadge.secondary(
                  child: Text('Total weight: ${_percentage(total)}%'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (index, criterion) in criteria.indexed) ...[
              Padding(
                key: ValueKey('rubric-review-criterion-$index'),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}. ${criterion['name']}',
                            style: DefensysTokens.body.copyWith(
                              color: primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${_percentage(criterion['weight'] as num)}%',
                          style: DefensysTokens.body.copyWith(
                            color: primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_targetLabel((payload['target_type'] == 'both' ? criterion['target_type'] : payload['target_type']) as String?)} · '
                      '${criterion['max_score']} points maximum',
                      style: DefensysTokens.caption.copyWith(color: secondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Evaluation guidelines',
                      style: DefensysTokens.caption.copyWith(color: secondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (criterion['description'] as String).isEmpty
                          ? 'No evaluation guidelines provided.'
                          : criterion['description'] as String,
                      style: DefensysTokens.tableCell.copyWith(color: primary),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: DefensysTokens.borderOf(context)),
            ],
            const SizedBox(height: 16),
            Text(
              'You can edit criteria until defenses are scheduled or evaluations begin.',
              style: DefensysTokens.caption.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}
