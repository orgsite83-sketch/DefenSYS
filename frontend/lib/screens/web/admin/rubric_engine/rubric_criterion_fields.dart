import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import 'rubric_editor_field.dart';

/// A compact criterion summary that opens inline for editing.
class RubricCriterionFields extends StatefulWidget {
  const RubricCriterionFields({
    super.key,
    required this.index,
    this.section,
    required this.name,
    this.maxScore,
    this.weight,
    required this.description,
    required this.maximum,
    required this.enabled,
    required this.showTarget,
    required this.target,
    this.isPointsScale = false,
    this.hideWeight = false,
    this.badge,
    required this.onTargetChanged,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
    this.initiallyExpanded = false,
    this.showValidation = false,
    this.weightToBalance,
    this.nameError,
  });

  final int index, maximum;
  final TextEditingController? section, maxScore, weight;
  final TextEditingController name, description;
  final bool enabled, showTarget, isPointsScale, hideWeight;
  final bool initiallyExpanded, showValidation;
  final Widget? badge;
  final String target;
  final String? nameError;
  final num? weightToBalance;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp, onMoveDown, onRemove;

  @override
  State<RubricCriterionFields> createState() => RubricCriterionFieldsState();
}

class RubricCriterionFieldsState extends State<RubricCriterionFields> {
  late final ShadAccordionController<bool> _accordion;
  final _headerFocus = FocusNode();
  bool get _expanded => _accordion.value.contains(true);
  final _nameKey = GlobalKey<RubricEditorFieldState>();
  final _pointsKey = GlobalKey<RubricEditorFieldState>();
  final _weightKey = GlobalKey<RubricEditorFieldState>();

  String? _nameError(String value) =>
      value.trim().isEmpty ? 'Enter a criterion name.' : widget.nameError;

  bool get hasError =>
      _nameError(widget.name.text) != null ||
      (widget.isPointsScale &&
          widget.maxScore != null &&
          rubricPointsError(widget.maxScore!.text) != null) ||
      (!widget.hideWeight &&
          widget.weight != null &&
          rubricWeightError(widget.weight!.text) != null);

  void revealFirstError() {
    _accordion.value = [true];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final key in [_nameKey, _pointsKey, _weightKey]) {
        if (key.currentState?.error != null) {
          key.currentState!.focusError();
          break;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _accordion = ShadAccordionController<bool>(
      widget.initiallyExpanded || widget.name.text.trim().isEmpty ? true : null,
    )..addListener(_expansionChanged);
  }

  void _expansionChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _accordion.removeListener(_expansionChanged);
    _accordion.dispose();
    _headerFocus.dispose();
    super.dispose();
  }

  TextStyle _body(BuildContext context) => DefensysTokens.body.copyWith(
    color: DefensysTokens.textPrimaryOf(context),
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) => ShadTooltip(
    builder: (_) => Text(label),
    child: ShadButton.ghost(
      key: ValueKey('criterion-${widget.index}-$label'),
      size: ShadButtonSize.sm,
      width: 36,
      height: 36,
      padding: EdgeInsets.zero,
      enabled: widget.enabled && onPressed != null,
      onPressed: widget.enabled ? onPressed : null,
      child: Semantics(
        label: label,
        child: Icon(
          icon,
          size: 16,
          color: destructive ? DefensysTokens.maroonTextOf(context) : null,
        ),
      ),
    ),
  );

  void _changed(String _) {
    setState(() {});
    widget.onChanged();
  }

  Widget _fields(BuildContext context) {
    final name = RubricEditorField(
      key: _nameKey,
      label: 'Criterion name',
      inputKey: ValueKey('criterion-name-${widget.index}'),
      controller: widget.name,
      enabled: widget.enabled,
      showValidation: widget.showValidation,
      validator: _nameError,
      placeholder: 'Enter criterion name',
      onChanged: _changed,
    );
    final points = widget.isPointsScale && widget.maxScore != null
        ? RubricEditorField(
            key: _pointsKey,
            label: 'Maximum points',
            inputKey: ValueKey('criterion-max-score-${widget.index}'),
            controller: widget.maxScore!,
            enabled: widget.enabled,
            showValidation: widget.showValidation,
            validator: rubricPointsError,
            keyboardType: TextInputType.number,
            trailing: Text('pts', style: _body(context)),
            onChanged: _changed,
          )
        : null;
    final weight = !widget.hideWeight && widget.weight != null
        ? RubricEditorField(
            key: _weightKey,
            label: 'Weight',
            inputKey: ValueKey('criterion-weight-${widget.index}'),
            controller: widget.weight!,
            enabled: widget.enabled,
            showValidation: widget.showValidation,
            validator: rubricWeightError,
            placeholder: 'Enter weight',
            hint:
                widget.enabled &&
                    widget.weightToBalance != null &&
                    widget.weightToBalance! > 0 &&
                    widget.weightToBalance! <= 100 &&
                    num.tryParse(widget.weight!.text.trim()) !=
                        widget.weightToBalance
                ? 'Enter ${widget.weightToBalance!.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}% to reach 100%.'
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            trailing: Text('%', style: _body(context)),
            onChanged: _changed,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.section != null) ...[
          RubricEditorField(
            label: 'Section / Category',
            inputKey: ValueKey('criterion-section-${widget.index}'),
            controller: widget.section!,
            enabled: widget.enabled,
            onChanged: _changed,
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final extras = [
              if (points != null) (points, 210.0),
              if (weight != null) (weight, 170.0),
            ];
            if (constraints.maxWidth < (extras.length > 1 ? 760 : 600)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  name,
                  for (final field in extras) ...[
                    const SizedBox(height: 12),
                    field.$1,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: name),
                for (final field in extras) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: field.$2, child: field.$1),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        RubricEditorField(
          label: 'Evaluation guidelines',
          inputKey: ValueKey('criterion-description-${widget.index}'),
          controller: widget.description,
          enabled: widget.enabled,
          minLines: 1,
          maxLines: 5,
          placeholder: 'Add scoring guidance',
          onChanged: _changed,
        ),
        if (widget.showTarget) ...[
          const SizedBox(height: 12),
          ShadRadioGroup<String>(
            key: ValueKey('criterion-target-${widget.index}-${widget.target}'),
            initialValue: widget.target,
            enabled: widget.enabled,
            axis: Axis.horizontal,
            spacing: 16,
            runSpacing: 8,
            onChanged: (value) {
              if (value != null && value != widget.target) {
                widget.onTargetChanged(value);
              }
            },
            items: [
              ShadRadio(
                value: 'team',
                color: DefensysTokens.maroonOf(context),
                label: Text('Team', style: _body(context)),
              ),
              ShadRadio(
                value: 'individual',
                color: DefensysTokens.maroonOf(context),
                label: Text('Individual', style: _body(context)),
              ),
            ],
          ),
        ],
        if (!widget.hideWeight) ...[
          const SizedBox(height: 8),
          Text(
            '${widget.maximum} points maximum',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name.text.trim();
    final weight = widget.weight?.text.trim() ?? '';
    final summary = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${widget.index + 1} \u00b7 ${name.isEmpty ? 'Untitled criterion' : name}',
          style: DefensysTokens.tableCell.copyWith(
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        if (widget.badge != null)
          widget.badge!
        else if (!widget.hideWeight)
          ShadBadge.secondary(
            child: Text(weight.isEmpty ? 'Weight missing' : '$weight% weight'),
          ),
        ShadBadge.secondary(
          child: Text(widget.target == 'individual' ? 'Individual' : 'Team'),
        ),
        if (widget.showValidation && hasError)
          Text(
            'Needs attention',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.maroonTextOf(context),
            ),
          ),
      ],
    );
    final actions = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        _action('Move up', LucideIcons.arrowUp, widget.onMoveUp),
        _action('Move down', LucideIcons.arrowDown, widget.onMoveDown),
        if (widget.onRemove != null)
          _action(
            'Remove criterion',
            LucideIcons.trash2,
            widget.onRemove,
            destructive: true,
          ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: ShadAccordion<bool>(
        controller: _accordion,
        children: [
          ShadAccordionItem<bool>(
            value: true,
            focusNode: _headerFocus,
            padding: const EdgeInsets.symmetric(vertical: 12),
            underlineTitleOnHover: false,
            titleStyle: DefensysTokens.tableCell.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            icon: Icon(
              _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            iconEffects: const [],
            separator: const SizedBox.shrink(),
            title: Semantics(
              key: ValueKey('criterion-toggle-${widget.index}'),
              button: true,
              expanded: _expanded,
              child: ColoredBox(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (!widget.enabled) return summary;
                      if (constraints.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summary,
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: actions,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 12),
                          actions,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            child: _fields(context),
          ),
        ],
      ),
    );
  }
}
