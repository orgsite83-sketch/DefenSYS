import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import 'rubric_editor_field.dart';

/// Shared column headings for the inline criterion rows.
class RubricCriterionHeader extends StatelessWidget {
  const RubricCriterionHeader({
    super.key,
    this.points = false,
    this.showTarget = false,
  });
  final bool points, showTarget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < (showTarget ? 760 : 600)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DefaultTextStyle(
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
          child: Row(
            children: [
              const SizedBox(width: 28, child: Text('#')),
              const SizedBox(width: 12),
              const Expanded(child: Text('Criterion name')),
              const SizedBox(width: 12),
              SizedBox(
                width: points ? 112 : 120,
                child: Text(points ? 'Points' : 'Weight'),
              ),
              if (showTarget) ...[
                const SizedBox(width: 12),
                const SizedBox(width: 130, child: Text('Scoring target')),
              ],
              const SizedBox(width: 52),
            ],
          ),
        ),
      );
    },
  );
}

/// A criterion's name and score remain visible while its section is expanded.
class RubricCriterionFields extends StatefulWidget {
  const RubricCriterionFields({
    super.key,
    required this.index,
    required this.name,
    this.maxScore,
    this.weight,
    required this.enabled,
    required this.showTarget,
    required this.target,
    this.isPointsScale = false,
    this.showValidation = false,
    this.nameError,
    this.pointsError,
    this.weightError,
    required this.onTargetChanged,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
  });

  final int index;
  final TextEditingController name;
  final TextEditingController? maxScore, weight;
  final bool enabled, showTarget, isPointsScale, showValidation;
  final String target;
  final String? nameError, pointsError, weightError;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp, onMoveDown, onRemove;

  @override
  State<RubricCriterionFields> createState() => RubricCriterionFieldsState();
}

class RubricCriterionFieldsState extends State<RubricCriterionFields> {
  final _nameKey = GlobalKey<RubricEditorFieldState>();
  final _scoreKey = GlobalKey<RubricEditorFieldState>();
  final _menu = ShadContextMenuController();
  final _menuFocus = FocusNode();

  String? _nameError(String value) =>
      rubricCriterionNameError(value) ?? widget.nameError;
  String? _scoreError(String value) => widget.isPointsScale
      ? rubricPointsError(value) ?? widget.pointsError
      : rubricWeightError(value) ?? widget.weightError;

  bool get hasError =>
      _nameError(widget.name.text) != null ||
      _scoreError(
            (widget.isPointsScale ? widget.maxScore : widget.weight)?.text ??
                '',
          ) !=
          null;

  void focusName() => _nameKey.currentState?.focus();

  void revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final key in [_nameKey, _scoreKey]) {
        if (key.currentState?.error != null) {
          key.currentState!.focusError();
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    _menu.dispose();
    _menuFocus.dispose();
    super.dispose();
  }

  void _changed(String _) {
    setState(() {});
    widget.onChanged();
  }

  Widget _actions(BuildContext context) => ShadContextMenu(
    controller: _menu,
    items: [
      for (final action in [
        ('Move up', LucideIcons.arrowUp, widget.onMoveUp),
        ('Move down', LucideIcons.arrowDown, widget.onMoveDown),
        ('Delete criterion', LucideIcons.trash2, widget.onRemove),
      ])
        ShadContextMenuItem(
          key: ValueKey('criterion-${widget.index}-${action.$1}'),
          enabled: action.$3 != null,
          leading: Icon(action.$2, size: 16),
          onPressed: () {
            _menu.hide();
            action.$3?.call();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _menuFocus.requestFocus();
            });
          },
          child: Text(
            action.$1,
            style: DefensysTokens.body.copyWith(
              color: action.$1 == 'Delete criterion'
                  ? DefensysTokens.maroonTextOf(context)
                  : DefensysTokens.textPrimaryOf(context),
            ),
          ),
        ),
    ],
    child: ShadButton.ghost(
      key: ValueKey('criterion-actions-${widget.index}'),
      focusNode: _menuFocus,
      width: 44,
      height: 44,
      padding: EdgeInsets.zero,
      onPressed: _menu.toggle,
      child: Semantics(
        label: 'Actions for criterion ${widget.index + 1}',
        child: const Icon(LucideIcons.ellipsis, size: 18),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
    ),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < (widget.showTarget ? 760 : 600);
        final length = widget.name.text.trim().runes.length;
        final name = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RubricEditorField(
              key: _nameKey,
              label: 'Criterion ${widget.index + 1} name',
              showLabel: narrow,
              showRequired: false,
              inputKey: ValueKey('criterion-name-${widget.index}'),
              controller: widget.name,
              enabled: widget.enabled,
              showValidation: widget.showValidation,
              validator: _nameError,
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              placeholder: 'Enter criterion name',
              onChanged: _changed,
            ),
            if (length >= 800) ...[
              const SizedBox(height: 4),
              Text(
                '$length/$rubricCriterionNameLimit',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ],
        );
        final score = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RubricEditorField(
              key: _scoreKey,
              label: widget.isPointsScale ? 'Points' : 'Weight',
              showLabel: narrow,
              showRequired: false,
              inputKey: ValueKey(
                widget.isPointsScale
                    ? 'criterion-max-score-${widget.index}'
                    : 'criterion-weight-${widget.index}',
              ),
              controller: (widget.isPointsScale
                  ? widget.maxScore
                  : widget.weight)!,
              enabled: widget.enabled,
              showValidation: widget.showValidation,
              validator: _scoreError,
              keyboardType: TextInputType.numberWithOptions(
                decimal: !widget.isPointsScale,
              ),
              trailing: widget.isPointsScale ? null : const Text('%'),
              onChanged: _changed,
            ),
            if (widget.isPointsScale) ...[
              const SizedBox(height: 6),
              Text(
                '${formatRubricPercentage(num.tryParse(widget.weight?.text ?? '') ?? 0)}% of rubric',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ],
        );
        final target = widget.showTarget
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (narrow) ...[
                    Text(
                      'Scoring target',
                      style: DefensysTokens.caption.copyWith(
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  ShadSelect<String>(
                    key: ValueKey(
                      'criterion-target-${widget.index}-${widget.target}',
                    ),
                    initialValue: widget.target,
                    enabled: widget.enabled,
                    options: const [
                      ShadOption(value: 'team', child: Text('Team')),
                      ShadOption(
                        value: 'individual',
                        child: Text('Individual'),
                      ),
                    ],
                    selectedOptionBuilder: (_, value) =>
                        Text(value == 'individual' ? 'Individual' : 'Team'),
                    onChanged: (value) {
                      if (value != null) widget.onTargetChanged(value);
                    },
                  ),
                ],
              )
            : null;
        final fields = narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  name,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: 120, child: score),
                      if (target != null) SizedBox(width: 130, child: target),
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: widget.isPointsScale ? 112 : 120,
                    child: score,
                  ),
                  if (target != null) ...[
                    const SizedBox(width: 12),
                    SizedBox(width: 130, child: target),
                  ],
                ],
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: narrow ? 30 : 10),
              child: SizedBox(
                width: 28,
                child: Text(
                  '${widget.index + 1}'.padLeft(2, '0'),
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: fields),
            const SizedBox(width: 8),
            if (widget.enabled)
              _actions(context)
            else
              const SizedBox(width: 44),
          ],
        );
      },
    ),
  );
}
