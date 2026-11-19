import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'stage_setup_validation.dart';

/// Shared destinations survive rebuilds while a requirement is expanded.
class StageSetupTargets {
  final _keys = <String, GlobalKey<_StageSetupTargetState>>{};

  Widget field(String target, Widget child, {String? error}) =>
      _StageSetupTarget(
        key: _keys.putIfAbsent(
          target,
          () => GlobalKey<_StageSetupTargetState>(),
        ),
        error: error,
        child: child,
      );

  void reveal(String target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keys[target]?.currentState?.reveal();
    });
  }
}

class _StageSetupTarget extends StatefulWidget {
  const _StageSetupTarget({super.key, required this.child, this.error});
  final Widget child;
  final String? error;

  @override
  State<_StageSetupTarget> createState() => _StageSetupTargetState();
}

class _StageSetupTargetState extends State<_StageSetupTarget> {
  final _focus = FocusNode(skipTraversal: true);

  void reveal() {
    if (!mounted) return;
    EditableText? input;
    FocusNode? action;
    BuildContext destination = context;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is EditableText &&
          !widget.readOnly &&
          widget.focusNode.canRequestFocus &&
          input == null) {
        input = widget;
        destination = element;
      }
      if (widget is Focus &&
          widget.focusNode != _focus &&
          widget.focusNode?.canRequestFocus == true &&
          action == null) {
        action = widget.focusNode;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    (input?.focusNode ?? action ?? _focus).requestFocus();
    Scrollable.ensureVisible(
      destination,
      alignment: .2,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: widget.error == null
              ? null
              : BoxDecoration(
                  border: Border.all(
                    color: DefensysTokens.isDark(context)
                        ? DefensysTokens.danger
                        : DefensysTokens.dangerText,
                  ),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
          child: widget.child,
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                widget.error!,
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.isDark(context)
                      ? DefensysTokens.danger
                      : DefensysTokens.dangerText,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class StageSetupSteps extends StatelessWidget {
  const StageSetupSteps({
    super.key,
    required this.activeTab,
    required this.review,
    required this.onSelected,
    required this.startedSteps,
    this.enabled = true,
  });
  final int activeTab;
  final StageSetupValidation review;
  final ValueChanged<int> onSelected;
  final Set<int> startedSteps;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: LayoutBuilder(
      builder: (context, constraints) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  selected: i == activeTab,
                  child: ShadButton.ghost(
                    key: ValueKey('stage-setup-step-$i'),
                    enabled: enabled,
                    height: 0,
                    expands: true,
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 400 ? 4 : 12,
                      vertical: constraints.maxWidth < 400 ? 10 : 12,
                    ),
                    backgroundColor: i == activeTab
                        ? DefensysTokens.maroonOf(context)
                        : DefensysTokens.surfaceHigherOf(context),
                    hoverBackgroundColor: i == activeTab
                        ? DefensysTokens.maroonOf(context)
                        : DefensysTokens.backgroundOf(context),
                    onPressed: () => onSelected(i),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            '1. Stage Details',
                            '2. Grading & Rubrics',
                            '3. Deliverables',
                          ][i],
                          textAlign: TextAlign.left,
                          style:
                              (constraints.maxWidth < 400
                                      ? DefensysTokens.caption
                                      : DefensysTokens.tableCell)
                                  .copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: i == activeTab
                                        ? Colors.white
                                        : DefensysTokens.textPrimaryOf(context),
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              review.stepComplete(i)
                                  ? LucideIcons.check
                                  : startedSteps.contains(i)
                                  ? LucideIcons.circleAlert
                                  : LucideIcons.circle,
                              size: 11,
                              color: i == activeTab
                                  ? Colors.white
                                  : DefensysTokens.textSecondaryOf(context),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                review.stepComplete(i)
                                    ? 'Complete'
                                    : startedSteps.contains(i)
                                    ? 'Needs setup'
                                    : 'Not started',
                                key: ValueKey('stage-setup-step-status-$i'),
                                textAlign: TextAlign.left,
                                style: DefensysTokens.caption.copyWith(
                                  color: i == activeTab
                                      ? Colors.white
                                      : DefensysTokens.textSecondaryOf(context),
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
            ],
          ],
        ),
      ),
    ),
  );
}

/// The steps own setup status; only actionable validation needs a header action.
class StageSetupIssueAction extends StatelessWidget {
  const StageSetupIssueAction({
    super.key,
    required this.review,
    required this.onReview,
    this.enabled = true,
    this.readOnly = false,
  });
  final StageSetupValidation review;
  final VoidCallback onReview;
  final bool enabled, readOnly;

  @override
  Widget build(BuildContext context) => readOnly || review.ready
      ? const SizedBox.shrink()
      : DefensysShadcnScope(
          child: Align(
            alignment: Alignment.centerRight,
            child: ShadButton.ghost(
              size: ShadButtonSize.sm,
              enabled: enabled,
              onPressed: onReview,
              child: Text(
                'Review issues',
                style: DefensysTokens.tableCell.copyWith(
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
            ),
          ),
        );
}

class StageSetupInformation extends StatelessWidget {
  const StageSetupInformation({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadAccordion<String>(
      children: [
        ShadAccordionItem(
          value: 'information',
          title: Text(
            'Additional stage information',
            style: DefensysTokens.tableCell.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          underlineTitleOnHover: false,
          separator: const SizedBox.shrink(),
          child: child,
        ),
      ],
    ),
  );
}
