import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/admin_overview_scope_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../shared/dashboard_schedule_planner.dart';
import 'audit_compliance/components/audit_format_utils.dart';
import 'widgets/overview_panel_row.dart';
import 'widgets/admin_pit_overview.dart';

/// Overview presents administrative work separately from academic readiness.
class AdminOverviewWorkspace extends ConsumerStatefulWidget {
  const AdminOverviewWorkspace({
    super.key,
    required this.data,
    required this.error,
    required this.loading,
    required this.refreshing,
    required this.onRefresh,
    required this.onAction,
  });
  final Map<String, dynamic>? data;
  final String? error;
  final bool loading, refreshing;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onAction;
  @override
  ConsumerState<AdminOverviewWorkspace> createState() =>
      _AdminOverviewWorkspaceState();
}

class _AdminOverviewWorkspaceState
    extends ConsumerState<AdminOverviewWorkspace> {
  bool expandedActions = false;
  bool attentionVisible = true;
  String get scope =>
      ref.watch(adminOverviewScopeProvider) == 'pit' ? 'pit' : 'capstone';
  Widget panel(String title, Widget child, {Widget? trailing, Key? key}) =>
      Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: DefensysTokens.cardDecoration(
          context,
        ).copyWith(boxShadow: []),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: DefensysTokens.sectionTitle.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
  Widget copy(String text) => Text(
    text,
    textAlign: TextAlign.start,
    style: DefensysTokens.body.copyWith(
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );
  Widget secondary(String text) => Text(
    text,
    textAlign: TextAlign.start,
    style: DefensysTokens.caption.copyWith(
      color: DefensysTokens.textSecondaryOf(context),
      height: 1.5,
    ),
  );
  Widget badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
    ),
    child: Text(
      text,
      style: DefensysTokens.caption.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: DefensysTokens.textSecondaryOf(context),
      ),
    ),
  );
  Widget metric(String value, String label, {String? contextLabel}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: DefensysTokens.pageTitle.copyWith(
          fontSize: 26,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      const SizedBox(height: 4),
      secondary(label),
      if (contextLabel != null) ...[
        const SizedBox(height: 3),
        secondary(contextLabel),
      ],
    ],
  );

  Widget actionItem(Map<String, dynamic> item) {
    final enrollmentReminder = RegExp(
      r'^enrollment:\d+$',
    ).hasMatch(item['id']?.toString() ?? '');
    final teamAssignment =
        item['kind'] == 'team_assignment' && item['affected_count'] is num;
    final title = enrollmentReminder
        ? 'Enrollment to review'
        : teamAssignment
        ? '${item['affected_count']} ${item['affected_count'] == 1 ? 'student' : 'students'} without a team'
        : item['title']?.toString() ?? 'Action needed';
    return ShadButton.ghost(
      key: ValueKey('overview-attention-item-${item['id']}'),
      width: double.infinity,
      height: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
      pressedBackgroundColor: DefensysTokens.surfaceHigherOf(context),
      onPressed: () => widget.onAction(item),
      child: Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            // Enrollment is already named in the title. Preserve context for
            // independent, unscoped approvals and other administrative work.
            if (item['scope'] == null &&
                item['category_label'] != null &&
                item['id'] != 'no_active_period' &&
                !enrollmentReminder) ...[
              const SizedBox(height: 3),
              secondary(item['category_label'].toString()),
            ],
            if (teamAssignment) ...[
              const SizedBox(height: 3),
              secondary(
                [
                  if (item['year_level'] != null) item['year_level'].toString(),
                  'Capstone',
                ].join(' · '),
              ),
            ] else if (item['description'] != null) ...[
              const SizedBox(height: 3),
              secondary(item['description'].toString()),
            ],
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                item['button_label']?.toString() ?? 'Review',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.maroonTextOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget attention(
    List<Map<String, dynamic>> items, {
    bool partial = false,
  }) => ShadCard(
    key: const ValueKey('overview-attention'),
    width: double.infinity,
    padding: EdgeInsets.zero,
    backgroundColor: DefensysTokens.surfaceOf(context),
    radius: BorderRadius.circular(DefensysTokens.radiusLg),
    shadows: const [],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Needs your attention',
                          style: DefensysTokens.body.copyWith(
                            color: DefensysTokens.textPrimaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (items.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          label:
                              '${items.length} pending ${items.length == 1 ? 'action' : 'actions'}',
                          excludeSemantics: true,
                          child: ShadBadge.secondary(
                            backgroundColor: DefensysTokens.surfaceHigherOf(
                              context,
                            ),
                            hoverBackgroundColor:
                                DefensysTokens.surfaceHigherOf(context),
                            foregroundColor: DefensysTokens.textSecondaryOf(
                              context,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                DefensysTokens.radiusSm,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            child: Text(
                              '${items.length}',
                              style: DefensysTokens.caption.copyWith(
                                color: DefensysTokens.textSecondaryOf(context),
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
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
              if (items.isNotEmpty)
                Semantics(
                  expanded: attentionVisible,
                  child: ShadButton.ghost(
                    key: const ValueKey('overview-attention-toggle'),
                    size: ShadButtonSize.sm,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: DefensysTokens.maroonTextOf(context),
                    hoverForegroundColor: DefensysTokens.maroonTextOf(context),
                    onPressed: () =>
                        setState(() => attentionVisible = !attentionVisible),
                    child: Text(attentionVisible ? 'Hide' : 'Show'),
                  ),
                ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: secondary(
              partial
                  ? 'Some release counts are unavailable. Open Evaluation & Grades to review.'
                  : 'No admin actions pending',
            ),
          )
        else if (attentionVisible)
          for (
            var index = 0;
            index < (expandedActions ? items.length : items.length.clamp(0, 3));
            index++
          ) ...[
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            actionItem(items[index]),
          ],
        if (attentionVisible && items.length > 3) ...[
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ShadButton.ghost(
              onPressed: () =>
                  setState(() => expandedActions = !expandedActions),
              trailing: Icon(
                expandedActions
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              child: Text(
                expandedActions
                    ? 'Show fewer'
                    : 'View all ${items.length} actions',
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget workflowCards(List<Map<String, dynamic>> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      copy('Semester workflow'),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 5
              : constraints.maxWidth >= 650
              ? 3
              : constraints.maxWidth >= 480
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          const icons = [
            Icons.manage_accounts_outlined,
            Icons.tune_rounded,
            Icons.groups_outlined,
            Icons.event_available_outlined,
            Icons.fact_check_outlined,
          ];
          return Column(
            children: [
              for (var start = 0; start < cards.length; start += columns) ...[
                if (start > 0) const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 12),
                        Expanded(
                          child: start + column >= cards.length
                              ? const SizedBox.shrink()
                              : workflowCard(
                                  cards[start + column],
                                  icons[start + column],
                                  width,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ],
  );

  Widget workflowCard(Map<String, dynamic> card, IconData icon, double width) =>
      ShadButton.outline(
        key: ValueKey('overview-workflow-${card['section']}'),
        backgroundColor: DefensysTokens.surfaceOf(context),
        hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
        pressedBackgroundColor: DefensysTokens.surfaceHigherOf(context),
        height: 0,
        width: width,
        padding: const EdgeInsets.all(16),
        onPressed: () => open(card['section'].toString()),
        child: SizedBox(
          width: width - 34,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17),
                  const SizedBox(width: 8),
                  Expanded(child: copy(card['title'].toString())),
                ],
              ),
              const SizedBox(height: 12),
              metric(card['value'].toString(), card['label'].toString()),
            ],
          ),
        ),
      );

  Widget readinessFact(
    String label,
    dynamic value, {
    bool needsAction = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: secondary(label)),
      const SizedBox(width: 5),
      Text(
        value?.toString() ?? '—',
        style: DefensysTokens.caption.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: needsAction
              ? DefensysTokens.maroonTextOf(context)
              : DefensysTokens.textPrimaryOf(context),
        ),
      ),
    ],
  );

  Widget recentActivity(Map<String, dynamic> data) {
    final logs = (data['recent_activity'] as List? ?? [])
        .whereType<Map>()
        .map((log) => Map<String, dynamic>.from(log))
        .take(5)
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: DefensysTokens.cardDecoration(
        context,
      ).copyWith(boxShadow: []),
      child: ShadAccordion<String>(
        children: [
          ShadAccordionItem(
            value: 'recent-activity',
            title: copy('Recent activity'),
            underlineTitleOnHover: false,
            separator: const SizedBox.shrink(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logs.isEmpty) secondary('No recent activity recorded.'),
                for (final log in logs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        copy(
                          log['action_label']?.toString() ??
                              log['description']?.toString() ??
                              AuditFormatUtils.formatAction(
                                log['action']?.toString(),
                              ),
                        ),
                        if (log['actor_name'] != null ||
                            (log['timestamp']?.toString().isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: secondary(
                              [
                                if (log['actor_name'] != null)
                                  log['actor_name'].toString(),
                                if (log['timestamp']?.toString().isNotEmpty ??
                                    false)
                                  AuditFormatUtils.formatTimestamp(
                                    log['timestamp'].toString(),
                                  ),
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
                  ),
                ShadButton.link(
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onAction({
                    'target_route': AdminRoutes.auditCompliance,
                    'target_section': 'auditCompliance',
                  }),
                  child: const Text('View audit trail'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void open(String section) =>
      widget.onAction({'target_section': section, 'scope': scope});
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final overview = Map<String, dynamic>.from(data?['overview'] as Map? ?? {});
    final items =
        ((overview['action_items'] ?? data?['action_items']) as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['scope'] == null || e['scope'] == scope)
            .toList();
    final totals = Map<String, dynamic>.from(
      (overview['totals'] as Map?)?[scope] as Map? ?? {},
    );
    final known = data != null && !widget.loading;
    final ready = totals['ready'];
    final teams = totals['teams'];
    final workflow = (overview['workflow'] as List? ?? [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    // Older cached responses still provide safe module navigation while the
    // server projection refreshes. Missing figures remain explicitly unknown.
    if (workflow.isEmpty) {
      for (final entry in [
        ('Users', 'userManagement'),
        ('Stage setup', 'defenseStages'),
        ('Teams', 'studentTeams'),
        ('Scheduling', 'defenseBoardSchedules'),
        ('Results', 'gradeCenter'),
      ]) {
        workflow.add({
          'title': entry.$1,
          'section': entry.$2,
          'value': '—',
          'label': 'Summary unavailable',
          'detail': 'Refresh to check current status',
          'status': entry.$1 == 'Scheduling' && ready == 0
              ? 'Waiting for teams'
              : 'Unavailable',
          'action': false,
        });
      }
    }
    final readiness = Container(
      key: const ValueKey('overview-team-readiness'),
      padding: const EdgeInsets.all(20),
      decoration: DefensysTokens.cardDecoration(
        context,
      ).copyWith(boxShadow: []),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Team readiness',
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              badge(
                ready == null
                    ? 'Unavailable'
                    : ready > 0
                    ? 'Ready'
                    : 'Waiting',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                ready?.toString() ?? '—',
                style: DefensysTokens.pageTitle.copyWith(
                  fontSize: 36,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy('Ready to schedule'),
                    secondary('Capstone teams'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              readinessFact('Active teams', teams),
              readinessFact('Scheduled', totals['scheduled_teams']),
              readinessFact(
                'Need adviser',
                overview['missing_advisers'],
                needsAction: (overview['missing_advisers'] as num? ?? 0) > 0,
              ),
            ],
          ),
          if (ready == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: secondary('Open readiness to check current requirements.'),
            ),
          ShadButton.link(
            padding: EdgeInsets.zero,
            foregroundColor: DefensysTokens.maroonTextOf(context),
            hoverForegroundColor: DefensysTokens.maroonTextOf(context),
            onPressed: () => open('defenseBoardReadiness'),
            child: const Text('View readiness'),
          ),
        ],
      ),
    );
    final schedule = panel(
      'Defense schedule',
      DashboardSchedulePlanner(
        workspace: 'admin',
        refreshToken: data,
        padding: EdgeInsets.zero,
      ),
      key: const ValueKey('overview-defense-schedule'),
      trailing: ShadButton.link(
        padding: EdgeInsets.zero,
        foregroundColor: DefensysTokens.maroonTextOf(context),
        hoverForegroundColor: DefensysTokens.maroonTextOf(context),
        onPressed: () => open('defenseBoardSchedules'),
        child: Text(
          'Open schedule',
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.maroonTextOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
    return DefensysShadcnScope(
      maroonActions: true,
      neutralActionText: true,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth:
                    constraints.maxWidth -
                    (constraints.maxWidth < 600 ? 32 : 48),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header(data),
                  const SizedBox(height: 20),
                  if (widget.error != null) ...[
                    panel(
                      'Overview could not refresh',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          copy(
                            data == null
                                ? 'Could not load the overview. Please retry.'
                                : 'Showing previously loaded information. Refresh to check current requirements.',
                          ),
                          const SizedBox(height: 12),
                          ShadButton.outline(
                            onPressed: widget.onRefresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!known)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: LinearProgressIndicator(),
                    )
                  else ...[
                    if (scope == 'pit') ...[
                      AdminPitOverview(
                        cohorts: overview['pit_cohorts'] as List?,
                      ),
                      const SizedBox(height: 16),
                      attention(
                        items,
                        partial:
                            overview['partial'] == true || widget.error != null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (scope == 'capstone') ...[
                      workflowCards(workflow),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 900
                            ? Column(
                                children: [
                                  readiness,
                                  const SizedBox(height: 16),
                                  attention(
                                    items,
                                    partial:
                                        overview['partial'] == true ||
                                        widget.error != null,
                                  ),
                                  const SizedBox(height: 16),
                                  schedule,
                                ],
                              )
                            : OverviewPanelRow(
                                leading: Column(
                                  key: const ValueKey(
                                    'overview-readiness-attention',
                                  ),
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    readiness,
                                    const SizedBox(height: 16),
                                    attention(
                                      items,
                                      partial:
                                          overview['partial'] == true ||
                                          widget.error != null,
                                    ),
                                  ],
                                ),
                                schedule: schedule,
                              ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    recentActivity(data),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget header(Map<String, dynamic>? data) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: DefensysTokens.pageTitle.copyWith(
              fontSize: 24,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          secondary(
            data?['active_semester']?.toString() ?? 'Loading academic period…',
          ),
        ],
      );
      final refresh = ShadButton.outline(
        onPressed: widget.refreshing ? null : widget.onRefresh,
        leading: const Icon(Icons.refresh_rounded, size: 16),
        child: Text(widget.refreshing ? 'Refreshing…' : 'Refresh'),
      );
      final filters = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in [('capstone', 'Capstone'), ('pit', 'PIT')])
              Semantics(
                selected: scope == option.$1,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  width: 94 * MediaQuery.textScalerOf(context).scale(1),
                  height: 36 * MediaQuery.textScalerOf(context).scale(1),
                  backgroundColor: scope == option.$1
                      ? DefensysTokens.maroonOf(context)
                      : Colors.transparent,
                  hoverBackgroundColor: scope == option.$1
                      ? DefensysTokens.maroonOf(context)
                      : DefensysTokens.surfaceOf(context),
                  foregroundColor: scope == option.$1
                      ? Colors.white
                      : DefensysTokens.textSecondaryOf(context),
                  hoverForegroundColor: scope == option.$1
                      ? Colors.white
                      : DefensysTokens.textPrimaryOf(context),
                  onPressed: () => ref
                      .read(adminOverviewScopeProvider.notifier)
                      .select(option.$1),
                  child: Text(option.$2),
                ),
              ),
          ],
        ),
      );
      if (constraints.maxWidth >= 1000) {
        return Row(
          children: [
            Expanded(child: heading),
            filters,
            const SizedBox(width: 16),
            refresh,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (constraints.maxWidth < 450) ...[
            heading,
            const SizedBox(height: 12),
            refresh,
          ] else
            Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                refresh,
              ],
            ),
          const SizedBox(height: 12),
          filters,
        ],
      );
    },
  );
}
