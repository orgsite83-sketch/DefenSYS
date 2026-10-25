import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

/// Rubric settings using the portal's neutral shadcn controls.
class RubricDetailsFields extends StatelessWidget {
  const RubricDetailsFields({
    super.key,
    required this.semesterLabel,
    required this.semesterActive,
    required this.hasSemester,
    required this.nameController,
    required this.customName,
    required this.onNameChanged,
    required this.onResetName,
    required this.isPit,
    required this.evaluationType,
    required this.onEvaluationChanged,
    required this.scale,
    required this.scales,
    required this.customPoints,
    required this.onScaleChanged,
    required this.onCustomPointsChanged,
    required this.target,
    required this.onTargetChanged,
    required this.assignment,
    required this.enabled,
  });

  final String semesterLabel, evaluationType, scale, target;
  final bool semesterActive, hasSemester, customName, isPit, enabled;
  final TextEditingController nameController, customPoints;
  final List<String> scales;
  final ValueChanged<String> onNameChanged,
      onEvaluationChanged,
      onScaleChanged,
      onCustomPointsChanged,
      onTargetChanged;
  final VoidCallback onResetName;
  final Widget assignment;

  TextStyle _body(BuildContext context) => DefensysTokens.body.copyWith(
    color: DefensysTokens.textPrimaryOf(context),
  );

  TextStyle _caption(BuildContext context) => DefensysTokens.caption.copyWith(
    color: DefensysTokens.textSecondaryOf(context),
  );

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: DefensysTokens.tableCell.copyWith(
      fontWeight: FontWeight.w600,
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );

  Widget _choice(
    BuildContext context,
    String value,
    String label,
    String selected, {
    String? description,
    double? width,
    required ValueChanged<String> onSelected,
  }) => MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled && value != selected ? () => onSelected(value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value == selected
              ? DefensysTokens.surfaceHigherOf(context)
              : DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          border: Border.all(
            color: value == selected
                ? DefensysTokens.maroonOf(context)
                : DefensysTokens.borderOf(context),
          ),
        ),
        child: ShadRadio<String>(
          value: value,
          color: DefensysTokens.maroonOf(context),
          label: Text(label, style: _body(context)),
          sublabel: description == null
              ? null
              : Text(description, style: _caption(context)),
        ),
      ),
    ),
  );

  Widget _evaluation(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(context, 'Evaluation type'),
      const SizedBox(height: 8),
      ShadRadioGroup<String>(
        key: ValueKey('eval-$evaluationType'),
        initialValue: evaluationType,
        enabled: enabled,
        axis: Axis.horizontal,
        spacing: 8,
        runSpacing: 8,
        onChanged: (value) {
          if (value != null && value != evaluationType) {
            onEvaluationChanged(value);
          }
        },
        items: [
          _choice(
            context,
            'panel',
            'Panel',
            evaluationType,
            onSelected: onEvaluationChanged,
          ),
          if (!isPit)
            _choice(
              context,
              'adviser',
              'Adviser',
              evaluationType,
              onSelected: onEvaluationChanged,
            ),
          _choice(
            context,
            'peer',
            'Peer',
            evaluationType,
            onSelected: onEvaluationChanged,
          ),
        ],
      ),
    ],
  );

  Widget _scale(BuildContext context) {
    final custom = scale == 'Custom Scale';
    final points = int.tryParse(customPoints.text.trim());
    final valid = points != null && points >= 1 && points <= 32767;
    const labels = {
      '5-Point Scale': '5-point',
      '10-Point Scale': '10-point',
      '100-Point Scale': '100-point',
      'Custom Scale': 'Custom',
    };
    final maximum = custom
        ? points
        : switch (scale) {
            '5-Point Scale' => 5,
            '100-Point Scale' => 100,
            _ => 10,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Evaluation scale'),
        const SizedBox(height: 8),
        ShadRadioGroup<String>(
          key: ValueKey('scale-$scale'),
          initialValue: scale,
          enabled: enabled,
          axis: Axis.horizontal,
          spacing: 8,
          runSpacing: 8,
          onChanged: (value) {
            if (value != null && value != scale) onScaleChanged(value);
          },
          items: [
            for (final option in scales)
              _choice(
                context,
                option,
                labels[option] ?? option,
                scale,
                onSelected: onScaleChanged,
              ),
          ],
        ),
        if (custom) ...[
          const SizedBox(height: 14),
          _label(context, 'Maximum points per criterion'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 140,
              child: ShadInput(
                key: const ValueKey('custom-scale-points'),
                controller: customPoints,
                enabled: enabled,
                keyboardType: TextInputType.number,
                style: _body(context),
                onChanged: onCustomPointsChanged,
              ),
            ),
          ),
          if (!valid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Enter a whole number from 1 to 32767.',
                style: _caption(
                  context,
                ).copyWith(color: DefensysTokens.maroonTextOf(context)),
              ),
            ),
        ],
        if (!custom || valid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$maximum ${maximum == 1 ? 'point' : 'points'} per criterion',
              style: _caption(context),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        key: const ValueKey('rubric-semester-info'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Academic period', style: _caption(context)),
                const SizedBox(height: 4),
                Text(semesterLabel, style: _body(context)),
              ],
            ),
            if (semesterActive)
              const ShadBadge.secondary(child: Text('Active semester')),
          ],
        ),
      ),
      if (!hasSemester)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Configure an active semester in Academic Periods before creating a rubric.',
            style: _caption(context),
          ),
        ),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _label(context, 'Rubric name'),
          if (customName && enabled)
            ShadButton.ghost(
              key: const ValueKey('reset-rubric-name'),
              size: ShadButtonSize.sm,
              onPressed: onResetName,
              child: const Text('Use suggested name'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      ShadInput(
        key: const ValueKey('rubric-name'),
        controller: nameController,
        enabled: enabled,
        maxLength: 160,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        style: _body(context),
        onChanged: onNameChanged,
      ),
      const SizedBox(height: 8),
      Text(
        'Use the suggested name or enter your own.',
        style: _caption(context),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _evaluation(context),
                const SizedBox(height: 20),
                _scale(context),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _evaluation(context)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _scale(context)),
            ],
          );
        },
      ),
      const SizedBox(height: 28),
      _label(context, 'Who receives the score?'),
      const SizedBox(height: 8),
      if (evaluationType == 'peer')
        Container(
          key: const ValueKey('peer-individual-scoring'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Individual scoring', style: _body(context)),
              const SizedBox(height: 4),
              Text(
                'Each student must evaluate themselves and every teammate using this rubric. All ratings count equally toward each student\'s peer score.',
                style: _caption(context),
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 640
                ? constraints.maxWidth
                : (constraints.maxWidth - 24) / 3;
            return ShadRadioGroup<String>(
              key: ValueKey('target-$target'),
              initialValue: target,
              enabled: enabled,
              axis: Axis.horizontal,
              spacing: 12,
              runSpacing: 12,
              onChanged: (value) {
                if (value != null && value != target) onTargetChanged(value);
              },
              items: [
                _choice(
                  context,
                  'team',
                  'Team',
                  target,
                  description: 'One shared team grade',
                  width: width,
                  onSelected: onTargetChanged,
                ),
                _choice(
                  context,
                  'individual',
                  'Individual',
                  target,
                  description: 'A grade for each student',
                  width: width,
                  onSelected: onTargetChanged,
                ),
                _choice(
                  context,
                  'both',
                  'Team + individual',
                  target,
                  description: 'Criteria for both',
                  width: width,
                  onSelected: onTargetChanged,
                ),
              ],
            );
          },
        ),
      if (evaluationType != 'peer' && target == 'both')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Include at least one team criterion and one individual criterion.',
            style: _caption(context),
          ),
        ),
      const SizedBox(height: 24),
      Divider(height: 1, color: DefensysTokens.borderOf(context)),
      const SizedBox(height: 24),
      assignment,
    ],
  );
}
