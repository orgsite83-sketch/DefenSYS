import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

List<Map<String, dynamic>> conceptRows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((row) => Map<String, dynamic>.from(row))
    .toList();

bool isSharedConceptWorkflow(Map<String, dynamic> workflow) =>
    workflow['selection_mode'] == 'shared_module' ||
    workflow['section_project_id'] != null;

Map<String, dynamic>? linkedModule(Map<String, dynamic> workflow) {
  final selection = workflow['shared_selection'] as Map? ?? {};
  if (selection['module'] is Map) {
    return Map<String, dynamic>.from(selection['module'] as Map);
  }
  final key =
      '${selection['selected_key'] ?? workflow['section_selected_key'] ?? ''}';
  return conceptRows(
    workflow['concepts'],
  ).where((c) => c['key'] == key && key.isNotEmpty).firstOrNull;
}

String moduleReviewLabel(String status) => switch (status) {
  'approved' => 'Module accepted',
  'revisions_pending' || 'approved_with_revisions' => 'Revisions pending',
  'revisions_cleared' => 'Revisions cleared',
  'another_review_required' ||
  'for_redefense' => 'Another module review required',
  'not_scheduled' => 'Not scheduled',
  'awaiting_system_selection' => 'Waiting for section selection',
  'ready_for_review' => 'Ready for module review',
  _ => 'Module review pending',
};

class SharedSystemSelectionBanner extends StatelessWidget {
  const SharedSystemSelectionBanner({super.key, required this.project});
  final Map<String, dynamic> project;

  @override
  Widget build(BuildContext context) {
    final selected = conceptRows(project['systems'])
        .where(
          (s) =>
              s['key'] == project['selected_key'] &&
              '${project['selected_key'] ?? ''}'.isNotEmpty,
        )
        .firstOrNull;
    return Container(
      key: const ValueKey('section-system-selection'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            selected == null
                ? 'Section system selection'
                : 'Selected section system',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selected == null
                ? 'One system for the whole section'
                : '${selected['title']}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selected == null
                ? 'Review the section proposals, then select one system. Each team will follow its corresponding module.'
                : project['shared_revisions_pending'] == true
                ? 'Shared paper revisions are pending. Each linked module keeps its own review and clearance.'
                : 'Each team follows the module linked to this system. Review the modules separately below.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class SharedTeamModuleSummary extends StatelessWidget {
  const SharedTeamModuleSummary({
    super.key,
    required this.workflow,
    required this.onOpen,
  });
  final Map<String, dynamic> workflow;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final selection = workflow['shared_selection'] as Map? ?? {};
    final module = linkedModule(workflow);
    final systemTitle =
        '${selection['system_title'] ?? module?['system_title'] ?? ''}';
    final secondary = DefensysTokens.textSecondaryOf(context);
    final outcome = workflow['concept_revisions_cleared'] == true
        ? 'revisions_cleared'
        : '${module?['decision'] ?? workflow['decision'] ?? ''}';
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShadCard(
          key: const ValueKey('shared-team-module-summary'),
          width: double.infinity,
          title: const Text(
            'Shared section system',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              if (module == null)
                Text(
                  'The section system is selected once for all participating teams. Your linked module will appear here after that decision.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
                )
              else ...[
                Text(
                  'Selected system',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 4),
                Text(
                  systemTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'This team’s linked module',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${module['title']}'.trim().isEmpty
                      ? 'Module name needed'
                      : '${module['title']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  moduleReviewLabel(outcome),
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                if ('${module['remarks'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${module['remarks']}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
                if (selection['revisions_pending'] == true ||
                    workflow['section_revisions_pending'] == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Shared system revisions still require clearance before event completion.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: secondary,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.outline(
                  onPressed: onOpen,
                  child: Text(
                    module == null
                        ? 'Open section systems'
                        : 'Open module reviews',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharedModuleReviewTable extends StatelessWidget {
  const SharedModuleReviewTable({
    super.key,
    required this.project,
    required this.onReview,
    required this.onConfirmNames,
    required this.onClearRevisions,
    this.busy = false,
  });
  final Map<String, dynamic> project;
  final ValueChanged<Map<String, dynamic>> onReview;
  final ValueChanged<Map<String, dynamic>> onConfirmNames;
  final ValueChanged<Map<String, dynamic>> onClearRevisions;
  final bool busy;

  Map<String, dynamic>? selectedModule(Map<String, dynamic> team) =>
      team['selected_module'] is Map
      ? Map<String, dynamic>.from(team['selected_module'] as Map)
      : conceptRows(team['concepts'])
            .where(
              (m) =>
                  m['key'] == project['selected_key'] &&
                  '${project['selected_key'] ?? ''}'.isNotEmpty,
            )
            .firstOrNull;

  Widget _teamName(Map<String, dynamic> team, BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${team['name']}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
      if ('${team['leader_name'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          '${team['leader_name']}',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    ],
  );

  Widget _moduleName(
    Map<String, dynamic> team,
    Map<String, dynamic>? selected,
    BuildContext context,
  ) => selected != null && '${team['verdict'] ?? ''}'.isNotEmpty
      ? Text(
          '${selected['title']}'.trim().isEmpty
              ? 'Module name needed'
              : '${selected['title']}',
          style: const TextStyle(fontSize: 13, height: 1.5),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in conceptRows(team['concepts']))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${m['key'] == project['selected_key'] ? 'Selected system · ' : ''}${m['system_title'] ?? m['key']} → ${'${m['title'] ?? ''}'.trim().isEmpty ? 'Module name needed' : m['title']}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
          ],
        );

  Widget _actions(Map<String, dynamic> team, Map<String, dynamic>? selected) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (team['can_confirm_names'] == true && team['schedule_id'] == null)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              enabled: !busy,
              onPressed: () => onConfirmNames(team),
              child: const Text('Confirm module names'),
            ),
          if (selected != null &&
              (team['can_record_decision'] == true ||
                  team['can_issue_verdict'] == true))
            ShadButton(
              size: ShadButtonSize.sm,
              enabled: !busy,
              onPressed: () => onReview(team),
              child: const Text('Review module'),
            ),
          if (selected != null && team['can_clear_concept_revisions'] == true)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              enabled: !busy,
              onPressed: () => onClearRevisions(team),
              child: const Text('Clear module revisions'),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final teams = conceptRows(project['teams']);
    final selectedKey = '${project['selected_key'] ?? ''}';
    final secondary = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    String status(Map<String, dynamic> team) {
      if (selectedKey.isEmpty) {
        return moduleReviewLabel('awaiting_system_selection');
      }
      final outcome = '${team['verdict'] ?? ''}';
      if (outcome == 'approved_with_revisions' &&
          team['concept_revisions_cleared'] == true) {
        return moduleReviewLabel('revisions_cleared');
      }
      final code = '${team['module_review_status'] ?? outcome}';
      if ((code.isEmpty || code == 'awaiting_review') &&
          (team['can_record_decision'] == true ||
              team['can_issue_verdict'] == true)) {
        return moduleReviewLabel('ready_for_review');
      }
      return moduleReviewLabel(code);
    }

    String papers(Map<String, dynamic> t, Map<String, dynamic>? m) => m != null
        ? switch (m['documents_status']) {
            'accepted' => 'Accepted',
            'corrections_requested' => 'Corrections requested',
            'pending_review' => 'Awaiting paper review',
            _ => 'Papers needed',
          }
        : '${conceptRows(t['concepts']).where((m) => m['documents_status'] == 'accepted').length}/${conceptRows(t['concepts']).length} proposals accepted';
    return DefensysShadcnScope(
      child: Column(
        key: const ValueKey('shared-module-review-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Team module reviews',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            selectedKey.isEmpty
                ? 'Select the section system first. Each team’s module follows that selection.'
                : 'Review each team’s linked module. Module outcomes and grades remain individual to each team.',
            style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
          ),
          const SizedBox(height: 14),
          if (teams.isEmpty)
            Text(
              'No participating teams are available.',
              style: TextStyle(fontSize: 13, color: secondary),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                Widget cell(Widget child) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: child,
                );
                if (wide) {
                  return Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.5),
                      1: FlexColumnWidth(2.5),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.5),
                      4: FlexColumnWidth(1.8),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: border),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: DefensysTokens.surfaceHigherOf(context),
                        ),
                        children: [
                          for (final title in [
                            'Team',
                            selectedKey.isEmpty
                                ? 'Proposed modules'
                                : 'Linked module',
                            'Papers',
                            'Review',
                            'Actions',
                          ])
                            cell(
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: secondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (final team in teams)
                        TableRow(
                          children: [
                            cell(_teamName(team, context)),
                            cell(
                              _moduleName(team, selectedModule(team), context),
                            ),
                            cell(
                              Text(
                                papers(team, selectedModule(team)),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: secondary,
                                ),
                              ),
                            ),
                            cell(
                              Text(
                                status(team),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            cell(_actions(team, selectedModule(team))),
                          ],
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final team in teams)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: border)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _teamName(team, context),
                            const SizedBox(height: 10),
                            _moduleName(team, selectedModule(team), context),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                Text(
                                  'Papers: ${papers(team, selectedModule(team))}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondary,
                                  ),
                                ),
                                Text(
                                  status(team),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _actions(team, selectedModule(team)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
