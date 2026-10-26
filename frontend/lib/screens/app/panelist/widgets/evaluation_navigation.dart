import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../panelist_models.dart';

/// Completion belongs to the active rubric/concept, while the caller owns saves.
class EvaluationTargetTabs extends StatelessWidget {
  const EvaluationTargetTabs({
    super.key,
    required this.individuals,
    required this.teamEntered,
    required this.teamRequired,
    required this.membersComplete,
    required this.membersRequired,
    required this.enabled,
    required this.onChanged,
  });

  final bool individuals, enabled;
  final int teamEntered, teamRequired, membersComplete, membersRequired;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // This shadcn version does not forward label expansion from ShadTab.
    // Constrain its button content so the labels and progress share the width.
    return ShadTheme(
      data: theme.copyWith(
        secondaryButtonTheme: theme.secondaryButtonTheme.copyWith(
          expands: true,
        ),
      ),
      child: ShadTabs<bool>(
        // ShadTabs selects optimistically. Recreate it when navigation finishes so
        // a failed save restores the actual target rather than the attempted tab.
        key: ValueKey('$individuals:$enabled'),
        value: individuals,
        gap: 0,
        tabsGap: 4,
        padding: const EdgeInsets.all(4),
        decoration: ShadDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          border: ShadBorder.all(
            color: DefensysTokens.borderOf(context),
            radius: BorderRadius.circular(DefensysTokens.radiusLg),
          ),
        ),
        onChanged: enabled ? onChanged : null,
        tabs: [
          for (final target in [false, true]) _tab(context, target),
        ],
      ),
    );
  }

  ShadTab<bool> _tab(BuildContext context, bool target) {
    final selected = individuals == target;
    final entered = target ? membersComplete : teamEntered;
    final required = target ? membersRequired : teamRequired;
    final complete = required > 0 && entered >= required;
    final label = target ? 'Individuals' : 'Team';
    final progress = target
        ? '$entered of $required members'
        : '$entered of $required criteria';
    final accent = DefensysTokens.maroonOf(context);
    final foreground = selected
        ? Colors.white
        : DefensysTokens.textPrimaryOf(context);
    final secondary = selected
        ? Colors.white
        : DefensysTokens.textSecondaryOf(context);

    return ShadTab<bool>(
      value: target,
      enabled: enabled,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      backgroundColor: Colors.transparent,
      hoverBackgroundColor: DefensysTokens.surfaceOf(context),
      selectedBackgroundColor: accent,
      selectedHoverBackgroundColor: Color.alphaBlend(
        Colors.black.withValues(alpha: .1),
        accent,
      ),
      selectedForegroundColor: Colors.white,
      foregroundColor: DefensysTokens.textPrimaryOf(context),
      decoration: ShadDecoration(
        border: ShadBorder.all(
          width: 0,
          radius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
      ),
      shadows: const [],
      selectedShadows: const [],
      child: Semantics(
        selected: selected,
        label: '$label, $progress ${target ? 'complete' : 'scored'}',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  target ? Icons.person_outline_rounded : Icons.groups_outlined,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.start,
                    style: DefensysTokens.tableCell.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (complete)
                  Icon(Icons.check_rounded, size: 14, color: foreground),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              progress,
              textAlign: TextAlign.start,
              style: DefensysTokens.caption.copyWith(color: secondary),
            ),
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                child: LinearProgressIndicator(
                  value: required > 0
                      ? (entered / required).clamp(0.0, 1.0)
                      : 0,
                  minHeight: 3,
                  color: selected
                      ? Colors.white
                      : DefensysTokens.maroonTextOf(context),
                  backgroundColor: selected
                      ? Colors.white.withValues(alpha: .25)
                      : DefensysTokens.borderOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EvaluationMemberNavigator extends StatefulWidget {
  const EvaluationMemberNavigator({
    super.key,
    required this.members,
    required this.criteria,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
  });

  final List<TeamMember> members;
  final Map<String, List<Criterion>> criteria;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  State<EvaluationMemberNavigator> createState() =>
      _EvaluationMemberNavigatorState();
}

class _EvaluationMemberNavigatorState extends State<EvaluationMemberNavigator> {
  final _chooser = ShadPopoverController();

  @override
  void dispose() {
    _chooser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Member ${widget.selectedIndex + 1} of ${widget.members.length}',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ),
      const SizedBox(width: 8),
      ShadPopover(
        controller: _chooser,
        popover: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.max(
              0,
              math.min(340, MediaQuery.sizeOf(context).width - 64),
            ),
            maxHeight: MediaQuery.sizeOf(context).height * .55,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Choose member',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final (index, member) in widget.members.indexed)
                  Builder(
                    builder: (context) {
                      final criteria =
                          widget.criteria[member.id] ?? <Criterion>[];
                      final entered = criteria.where((c) => c.isScored).length;
                      final selected = index == widget.selectedIndex;
                      return Semantics(
                        selected: selected,
                        child: ShadButton.ghost(
                          key: ValueKey('student-selector-${member.id}'),
                          height: 0,
                          expands: true,
                          enabled: widget.enabled && criteria.isNotEmpty,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          onPressed: () {
                            _chooser.hide();
                            widget.onSelected(index);
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      member.isLeader
                                          ? 'Team leader'
                                          : 'Team member',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: DefensysTokens.textSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (criteria.isNotEmpty &&
                                  entered == criteria.length)
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: DefensysTokens.isDark(context)
                                      ? DefensysTokens.success
                                      : DefensysTokens.successText,
                                )
                              else
                                Text(
                                  '$entered/${criteria.length}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.person_outline_rounded,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        child: ShadButton.outline(
          key: const ValueKey('choose-evaluation-member'),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          enabled: widget.enabled,
          trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          onPressed: _chooser.toggle,
          child: const Text('Choose member', style: TextStyle(fontSize: 12)),
        ),
      ),
    ],
  );
}
