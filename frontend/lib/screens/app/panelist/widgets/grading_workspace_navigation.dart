import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../panelist_models.dart';

enum GradingWorkspaceView { evaluation, sharedSystems, outcome }

class GradingWorkspaceTabs extends StatelessWidget {
  const GradingWorkspaceTabs({
    super.key,
    required this.shared,
    required this.value,
    required this.onChanged,
  });
  final bool shared;
  final GradingWorkspaceView value;
  final ValueChanged<GradingWorkspaceView> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tabs = [
      GradingWorkspaceView.evaluation,
      if (shared) GradingWorkspaceView.sharedSystems,
      GradingWorkspaceView.outcome,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => ShadTheme(
        data: theme.copyWith(
          secondaryButtonTheme: theme.secondaryButtonTheme.copyWith(
            expands: true,
          ),
        ),
        child: ShadTabs<GradingWorkspaceView>(
          key: ValueKey(value),
          value: value,
          gap: 0,
          tabsGap: 4,
          padding: const EdgeInsets.all(4),
          decoration: ShadDecoration(
            color: DefensysTokens.surfaceOf(context),
            border: ShadBorder.all(
              color: DefensysTokens.borderOf(context),
              radius: BorderRadius.circular(12),
            ),
          ),
          onChanged: onChanged,
          tabs: [
            for (final tab in tabs)
              ShadTab<GradingWorkspaceView>(
                key: ValueKey(switch (tab) {
                  GradingWorkspaceView.evaluation => 'grading-evaluation-tab',
                  GradingWorkspaceView.sharedSystems => 'grading-shared-tab',
                  GradingWorkspaceView.outcome => 'grading-outcome-tab',
                }),
                value: tab,
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 14,
                ),
                backgroundColor: DefensysTokens.surfaceOf(context),
                selectedBackgroundColor: DefensysTokens.maroonOf(context),
                hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
                selectedHoverBackgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: DefensysTokens.textPrimaryOf(context),
                selectedForegroundColor: Colors.white,
                shadows: const [],
                selectedShadows: const [],
                decoration: ShadDecoration(
                  border: ShadBorder.all(
                    width: 0,
                    radius: BorderRadius.circular(8),
                  ),
                ),
                child: SizedBox(
                  width:
                      ((constraints.maxWidth - 8 - (tabs.length - 1) * 4) /
                                  tabs.length -
                              8)
                          .clamp(0, double.infinity),
                  child: Text(
                    switch (tab) {
                      GradingWorkspaceView.evaluation => 'Evaluation',
                      GradingWorkspaceView.sharedSystems => 'Shared systems',
                      GradingWorkspaceView.outcome => 'Outcome',
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Assessment navigation never chooses the official project.
class ConceptAssessmentNavigator extends StatelessWidget {
  const ConceptAssessmentNavigator({
    super.key,
    required this.team,
    required this.activeKey,
    required this.enabled,
    required this.onChanged,
    this.sidebar = false,
  });
  final TeamData team;
  final String activeKey;
  final bool enabled, sidebar;
  final ValueChanged<String> onChanged;
  String get _noun => team.hasSharedSystem ? 'Module' : 'Concept';

  Widget _candidate(
    BuildContext context,
    Map<String, dynamic> row,
    ValueChanged<String> choose,
  ) {
    final key = row['key'].toString();
    final selected = key == activeKey;
    final progress = team.progressForConcept(key);
    final parent = team.systemTitleFor(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? DefensysTokens.surfaceHigherOf(context)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('assessment-candidate-$key'),
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? () => choose(key) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (parent.isNotEmpty) ...[
                    Text(
                      parent,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    row['title'].toString(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${progress.entered} of ${progress.required} criteria scored',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DefensysShadcnScope(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .78,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Choose ${_noun.toLowerCase()} to assess',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close assessment selector',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final row in team.assessmentConcepts)
                          _candidate(
                            context,
                            row,
                            (key) => Navigator.pop(context, key),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final index = team.assessmentConcepts.indexWhere(
      (row) => row['key'] == activeKey,
    );
    final progress = team.progressForConcept(activeKey);
    if (sidebar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
            child: Text(
              '$_noun assessment',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final row in team.assessmentConcepts)
                  _candidate(context, row, onChanged),
              ],
            ),
          ),
        ],
      );
    }
    return Material(
      key: const ValueKey('pinned-assessment-selector'),
      color: DefensysTokens.surfaceOf(context),
      child: InkWell(
        key: const ValueKey('assessment-selector'),
        onTap: enabled && team.assessmentConcepts.length > 1
            ? () => _choose(context)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: DefensysTokens.borderOf(context)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_noun ${index + 1} of ${team.assessmentConcepts.length}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${progress.entered} of ${progress.required} criteria scored',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (team.assessmentConcepts.length > 1)
                Icon(
                  Icons.unfold_more_rounded,
                  size: 20,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
