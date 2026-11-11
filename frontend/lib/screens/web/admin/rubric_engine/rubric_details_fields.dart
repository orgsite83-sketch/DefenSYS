import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import 'rubric_editor_field.dart';

/// Compact rubric settings using the portal's neutral shadcn controls.
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
    this.standardScale = '10-Point Scale',
    this.showValidation = false,
    this.nameFieldKey,
    this.pointsFieldKey,
  });

  final String semesterLabel, evaluationType, scale, standardScale, target;
  final bool semesterActive, hasSemester, customName, isPit, enabled;
  final bool showValidation;
  final TextEditingController nameController, customPoints;
  final List<String> scales;
  final ValueChanged<String> onNameChanged,
      onEvaluationChanged,
      onScaleChanged,
      onCustomPointsChanged,
      onTargetChanged;
  final VoidCallback onResetName;
  final Widget assignment;
  final GlobalKey<RubricEditorFieldState>? nameFieldKey, pointsFieldKey;

  bool get _sectioned => scale == 'Points-Based (Sections)';

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

  Widget _choices(
    BuildContext context,
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> onSelected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(context, label),
      const SizedBox(height: 6),
      ShadRadioGroup<String>(
        key: ValueKey('$label-$selected'),
        initialValue: selected,
        enabled: enabled,
        axis: Axis.horizontal,
        spacing: 6,
        runSpacing: 6,
        onChanged: (value) {
          if (value != null && value != selected) onSelected(value);
        },
        items: [
          for (final entry in options.entries)
            MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled && entry.key != selected
                    ? () => onSelected(entry.key)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: entry.key == selected
                        ? DefensysTokens.surfaceHigherOf(context)
                        : DefensysTokens.surfaceOf(context),
                    borderRadius: BorderRadius.circular(
                      DefensysTokens.radiusMd,
                    ),
                    border: Border.all(
                      color: entry.key == selected && enabled
                          ? DefensysTokens.maroonOf(context)
                          : DefensysTokens.borderOf(context),
                    ),
                  ),
                  child: ShadRadio<String>(
                    value: entry.key,
                    color: DefensysTokens.maroonOf(context),
                    label: Text(entry.value, style: _body(context)),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _scale(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _choices(context, 'Maximum points per criterion', scale, {
        for (final option in scales)
          if (option != 'Points-Based (Sections)')
            option: switch (option) {
              '5-Point Scale' => '5-point',
              '10-Point Scale' => '10-point',
              '100-Point Scale' => '100-point',
              'Custom Scale' => 'Custom',
              _ => option,
            },
      }, onScaleChanged),
      if (scale == 'Custom Scale') ...[
        const SizedBox(height: 10),
        RubricEditorField(
          key: pointsFieldKey,
          label: 'Custom maximum points',
          inputKey: const ValueKey('custom-scale-points'),
          controller: customPoints,
          enabled: enabled,
          showValidation: showValidation,
          validator: rubricPointsError,
          keyboardType: TextInputType.number,
          onChanged: onCustomPointsChanged,
        ),
      ],
    ],
  );

  Widget _recipient(BuildContext context) {
    if (evaluationType == 'peer') {
      return Column(
        key: const ValueKey('peer-individual-scoring'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, 'Score recipient'),
          const SizedBox(height: 6),
          Text('Individual scoring', style: _body(context)),
          const SizedBox(height: 4),
          Text(
            'Each student evaluates themselves and every teammate. All ratings count equally.',
            style: _caption(context),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choices(context, 'Score recipient', target, const {
          'team': 'Team',
          'individual': 'Individual',
          'both': 'Team + individual',
        }, onTargetChanged),
        if (target == 'both') ...[
          const SizedBox(height: 6),
          Text(
            'Include at least one team and one individual ${_sectioned ? 'section' : 'criterion'}.',
            style: _caption(context),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = RubricEditorField(
      key: nameFieldKey,
      label: 'Rubric name',
      inputKey: const ValueKey('rubric-name'),
      controller: nameController,
      enabled: enabled,
      showValidation: showValidation,
      validator: (text) => text.trim().isEmpty ? 'Enter a rubric name.' : null,
      placeholder: 'Enter rubric name',
      maxLength: 160,
      labelAction: customName && enabled
          ? ShadButton.ghost(
              key: const ValueKey('reset-rubric-name'),
              size: ShadButtonSize.sm,
              height: 24,
              onPressed: onResetName,
              child: const Text('Use suggested name'),
            )
          : null,
      onChanged: onNameChanged,
    );
    final semester = Column(
      key: const ValueKey('rubric-semester-info'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Academic period'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(semesterLabel, style: _body(context)),
              if (semesterActive) Text('Active', style: _caption(context)),
            ],
          ),
        ),
        if (!hasSemester) ...[
          const SizedBox(height: 6),
          Text(
            'Configure an active semester in Academic Periods before creating a rubric.',
            style: _caption(
              context,
            ).copyWith(color: DefensysTokens.maroonTextOf(context)),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [name, const SizedBox(height: 14), semester],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: name),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: semester),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _choices(
          context,
          'Scoring setup',
          _sectioned ? 'sections' : 'standard',
          const {
            'standard': 'Standard criteria',
            'sections': 'Weighted sections',
          },
          (value) => onScaleChanged(
            value == 'sections' ? 'Points-Based (Sections)' : standardScale,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _sectioned
              ? 'Set section weights; criterion points divide each section’s weight.'
              : 'Give each criterion a percentage of the rubric.',
          style: _caption(context),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              _choices(context, 'Evaluation type', evaluationType, {
                'panel': 'Panel',
                if (!isPit) 'adviser': 'Adviser',
                'peer': 'Peer',
              }, onEvaluationChanged),
              if (!_sectioned) _scale(context),
              _recipient(context),
            ];
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    fields[i],
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: !_sectioned && i == 1 ? 4 : 3,
                    child: fields[i],
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        assignment,
      ],
    );
  }
}
