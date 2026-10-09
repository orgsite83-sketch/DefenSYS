import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense_stages_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/feedback/defensys_skeleton.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

bool stageSetupLocked(Map<String, dynamic> stage) =>
    stage['is_locked'] == true || stage['status'] == 'locked';

bool stagePublished(Map<String, dynamic> stage) => stage['is_active'] is bool
    ? stage['is_active'] == true
    : stage['status'] == 'published';

List<String> stageSetupIssues(Map<String, dynamic> stage) {
  final readiness = stage['setup_readiness'];
  if (readiness is! Map) return ['Refresh to check setup readiness.'];
  final issues = readiness['issues'];
  if (issues is List && issues.isNotEmpty) {
    return issues.map((issue) => issue.toString()).toList();
  }
  return readiness['ready'] == true ? [] : ['Review stage configuration.'];
}

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    : [];

typedef StageMutation = Future<dynamic> Function(Map<String, dynamic> stage);

/// Master setup keeps publication, readiness and edit locks independent.
class DefenseStageDirectory extends StatefulWidget {
  const DefenseStageDirectory({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onAdd,
    required this.onConfigure,
    required this.onPublish,
    required this.onDelete,
    required this.onMove,
  });
  final DefenseStagesState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAdd;
  final ValueChanged<Map<String, dynamic>> onConfigure;
  final StageMutation onPublish, onDelete;
  final Future<void> Function(Map<String, dynamic>, int, int) onMove;

  @override
  State<DefenseStageDirectory> createState() => _DefenseStageDirectoryState();
}

class _DefenseStageDirectoryState extends State<DefenseStageDirectory> {
  bool _table = false, _refreshing = false, _adding = false;
  final Set<Object> _expanded = {};
  bool get _busy =>
      widget.state.isSaving || widget.state.isLoading || _refreshing || _adding;
  Color get _muted => DefensysTokens.textSecondaryOf(context);
  Color get _border => DefensysTokens.borderOf(context);
  Color get _surface => DefensysTokens.surfaceOf(context);
  Color get _ink => DefensysTokens.textPrimaryOf(context);
  Color get _fill => DefensysTokens.surfaceHigherOf(context);
  bool get _dark => DefensysTokens.isDark(context);
  Color get _success =>
      _dark ? DefensysTokens.success : DefensysTokens.successText;
  Color get _warning => DefensysTokens.goldOf(context);
  TextStyle get _small => TextStyle(fontSize: 13, height: 1.5, color: _muted);

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _addStage() async {
    if (_busy) return;
    setState(() => _adding = true);
    try {
      await widget.onAdd();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: DefensysTokens.maroonOf(context),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              24,
              compact ? 16 : 24,
              36,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(compact),
                const SizedBox(height: 24),
                if (widget.state.isLoading)
                  _loading()
                else ...[
                  if (widget.state.error == null ||
                      widget.state.stages.isNotEmpty) ...[
                    _summary(compact),
                    const SizedBox(height: 28),
                  ],
                  if (widget.state.error != null) ...[
                    ShadAlert.destructive(
                      icon: const Icon(LucideIcons.circleAlert, size: 18),
                      title: const Text('Stage request failed'),
                      description: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.state.error!),
                          const SizedBox(height: 8),
                          ShadButton.outline(
                            size: ShadButtonSize.sm,
                            enabled: !_busy,
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (widget.state.stages.isEmpty)
                    if (widget.state.error == null)
                      _empty()
                    else
                      const SizedBox.shrink()
                  else ...[
                    _directoryHeader(compact),
                    const SizedBox(height: 16),
                    if (_table)
                      _tableView()
                    else
                      for (var i = 0; i < widget.state.stages.length; i++) ...[
                        _stageItemWithSpine(
                          stage: widget.state.stages[i],
                          index: i,
                          isLast: i == widget.state.stages.length - 1,
                          compact: compact,
                        ),
                        if (i < widget.state.stages.length - 1)
                          _timelineConnectorSpacer(compact),
                      ],
                  ],
                ],
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _header(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Defense Stages',
          style: DefensysTokens.pageTitle.copyWith(fontSize: 26, color: _ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Set the stage sequence, evaluation rubrics and defense requirements.',
          style: _small,
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ShadButton.outline(
          enabled: !_busy,
          leading: const Icon(LucideIcons.refreshCw, size: 16),
          onPressed: _refresh,
          child: Text(_refreshing ? 'Refreshing…' : 'Refresh'),
        ),
        ShadButton(
          enabled: !_busy,
          backgroundColor: DefensysTokens.maroonOf(context),
          hoverBackgroundColor: DefensysTokens.maroonDark,
          foregroundColor: Colors.white,
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: _addStage,
          child: Text(_adding ? 'Preparing stage…' : 'Add stage'),
        ),
      ],
    );
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 16), actions],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 24),
              actions,
            ],
          );
  }

  Widget _summary(bool compact) {
    final stages = widget.state.stages;
    final attention = stages
        .where((stage) => stageSetupIssues(stage).isNotEmpty)
        .length;
    final items = [
      _metric('Total stages', stages.length, 'Configured milestones'),
      _metric(
        'Published',
        stages.where(stagePublished).length,
        'Available in defense scheduling',
      ),
      _metric(
        'Needs attention',
        attention,
        stages.isEmpty
            ? 'Add a stage to get started'
            : attention == 0
            ? 'All stage setups are ready'
            : 'Review the requirements below',
        warning: attention > 0,
      ),
    ];
    return ShadCard(
      width: double.infinity,
      backgroundColor: _surface,
      padding: const EdgeInsets.all(20),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i < items.length - 1) Divider(height: 28, color: _border),
                ],
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 24),
                      child: items[i],
                    ),
                  ),
                  if (i < items.length - 1)
                    Container(width: 1, height: 58, color: _border),
                ],
              ],
            ),
    );
  }

  Widget _metric(
    String label,
    int value,
    String hint, {
    bool warning = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _small.copyWith(fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 26,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: warning ? _warning : _ink,
        ),
      ),
      const SizedBox(height: 6),
      Text(hint, style: _small.copyWith(fontSize: 12)),
    ],
  );

  Widget _directoryHeader(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stage sequence',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Setup readiness describes configuration. Team progress is tracked in Defense Operations.',
          style: _small.copyWith(fontSize: 12),
        ),
      ],
    );
    final toggle = SizedBox(
      width: 250,
      child: ShadTabs<String>(
        scrollable: true,
        value: _table ? 'table' : 'sequence',
        onChanged: (value) => setState(() => _table = value == 'table'),
        tabs: const [
          ShadTab(value: 'sequence', child: Text('Sequence')),
          ShadTab(value: 'table', child: Text('Table')),
        ],
      ),
    );
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), toggle],
          )
        : Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              toggle,
            ],
          );
  }

  Widget _publication(Map<String, dynamic> stage) {
    final published = stagePublished(stage);
    return ShadBadge.secondary(
      backgroundColor: published
          ? (_dark
                ? DefensysTokens.success.withValues(alpha: .12)
                : DefensysTokens.successBg)
          : null,
      foregroundColor: published ? _success : _muted,
      child: Text(published ? 'Published' : 'Draft'),
    );
  }

  Widget _stageItemWithSpine({
    required Map<String, dynamic> stage,
    required int index,
    required bool isLast,
    required bool compact,
  }) {
    if (compact || MediaQuery.sizeOf(context).width < 1000) {
      return _stageCard(stage, index, compact, showInlineNode: true);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                _buildMilestoneNode(stage, index),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: _border,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _stageCard(stage, index, compact, showInlineNode: false),
          ),
        ],
      ),
    );
  }

  Widget _timelineConnectorSpacer(bool compact) {
    if (compact || MediaQuery.sizeOf(context).width < 1000) {
      return const SizedBox(height: 14);
    }
    return SizedBox(
      height: 14,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Center(
              child: Container(
                width: 2,
                color: _border,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMilestoneNode(
    Map<String, dynamic> stage,
    int index, {
    double size = 44,
  }) {
    final locked = stageSetupLocked(stage);
    final published = stagePublished(stage);
    final issues = stageSetupIssues(stage);
    final ready = issues.isEmpty;

    Color borderColor;
    Color bgColor;
    Widget? cornerBadge;
    String tooltipMessage;

    if (locked) {
      borderColor = DefensysTokens.maroonOf(context).withValues(alpha: 0.5);
      bgColor = _dark
          ? DefensysTokens.maroonOf(context).withValues(alpha: 0.14)
          : const Color(0xFFFDF2F2);
      cornerBadge = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: DefensysTokens.maroonOf(context),
          shape: BoxShape.circle,
          border: Border.all(color: _surface, width: 1.5),
        ),
        child: const Icon(LucideIcons.lockKeyhole, size: 8, color: Colors.white),
      );
      tooltipMessage =
          'Configuration locked · ${stage['lock_reason'] ?? 'Defenses scheduled'}';
    } else if (!published) {
      borderColor = _border;
      bgColor = _fill;
      cornerBadge = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: _muted,
          shape: BoxShape.circle,
          border: Border.all(color: _surface, width: 1.5),
        ),
        child: const Icon(LucideIcons.circleDashed, size: 8, color: Colors.white),
      );
      tooltipMessage = 'Draft milestone';
    } else if (ready) {
      borderColor = _success.withValues(alpha: 0.5);
      bgColor = _dark
          ? DefensysTokens.success.withValues(alpha: 0.12)
          : const Color(0xFFF0FDF4);
      cornerBadge = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: _success,
          shape: BoxShape.circle,
          border: Border.all(color: _surface, width: 1.5),
        ),
        child: const Icon(LucideIcons.check, size: 8, color: Colors.white),
      );
      tooltipMessage = 'Setup ready · Published';
    } else {
      borderColor = _warning.withValues(alpha: 0.6);
      bgColor = _dark
          ? DefensysTokens.goldOf(context).withValues(alpha: 0.12)
          : const Color(0xFFFFFBEB);
      cornerBadge = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: _warning,
          shape: BoxShape.circle,
          border: Border.all(color: _surface, width: 1.5),
        ),
        child: const Icon(LucideIcons.alertTriangle, size: 8, color: Colors.white),
      );
      tooltipMessage = issues.join('\n');
    }

    return Tooltip(
      message: tooltipMessage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: size >= 40 ? 14 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: locked
                    ? DefensysTokens.maroonOf(context)
                    : (published ? _ink : _muted),
              ),
            ),
          ),
          if (cornerBadge != null)
            Positioned(
              top: -3,
              right: -3,
              child: cornerBadge,
            ),
        ],
      ),
    );
  }

  Widget _readiness(Map<String, dynamic> stage) {
    final issues = stageSetupIssues(stage);
    final ready = issues.isEmpty;
    return Tooltip(
      message: ready
          ? 'Required grading and deliverable settings are configured.'
          : issues.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ready
              ? (_dark
                  ? DefensysTokens.success.withValues(alpha: .1)
                  : const Color(0xFFF0FDF4))
              : (_dark
                  ? DefensysTokens.goldOf(context).withValues(alpha: .1)
                  : const Color(0xFFFFFBEB)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: ready
                ? _success.withValues(alpha: 0.35)
                : _warning.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              ready ? LucideIcons.circleCheck : LucideIcons.circleAlert,
              size: 15,
              color: ready ? _success : _warning,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                ready
                    ? 'Setup ready'
                    : issues.first +
                          (issues.length > 1
                              ? ' (+${issues.length - 1} more)'
                              : ''),
                style: _small.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ready ? _success : _warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockNotice(Map<String, dynamic> stage) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _fill,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.lockKeyhole, size: 14, color: _muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Configuration locked · ${stage['lock_reason'] ?? 'This stage has scheduled defenses or recorded grades.'}',
            style: _small.copyWith(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _stageCard(
    Map<String, dynamic> stage,
    int index,
    bool compact, {
    bool showInlineNode = false,
  }) {
    final key = stage['id'] ?? index;
    final expanded = _expanded.contains(key);
    final deliverables = _rows(stage['deliverables']);
    final system = _rows(stage['system_deliverables']);
    final pre = deliverables
        .where((d) => (d['deliverable_type'] ?? d['type']) == 'pre')
        .length;
    final post = deliverables.length - pre;
    final info = stage['rubric_info'] is Map ? stage['rubric_info'] as Map : {};
    final count = info['count'] ?? stage['rubrics_count'] ?? 0;
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showInlineNode) ...[
          _buildMilestoneNode(stage, index, size: 38),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    stage['label']?.toString() ?? 'Stage',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  _publication(stage),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                index == 0
                    ? 'First stage in the sequence'
                    : 'Requires ${stage['previous_stage_label'] ?? widget.state.stages[index - 1]['label']}',
                style: _small.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    return ShadCard(
      key: ValueKey('stage-card-$key'),
      width: double.infinity,
      backgroundColor: _surface,
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            title
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 20),
                _actions(stage, index),
              ],
            ),
          if ((stage['description'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(stage['description'].toString(), style: _small),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metadataPill(
                LucideIcons.clipboardList,
                '$count ${count == 1 ? 'rubric' : 'rubrics'} attached',
              ),
              if (stage['is_presentation_only'] == true)
                _metadataPill(LucideIcons.presentation, 'Presentation only')
              else
                _metadataPill(
                  LucideIcons.folder,
                  '$pre pre-defense · $post post-defense',
                ),
              if (system.isNotEmpty)
                _metadataPill(LucideIcons.fileCheck, 'Signed minutes required'),
            ],
          ),
          const SizedBox(height: 10),
          _readiness(stage),
          if (stageSetupLocked(stage)) ...[
            const SizedBox(height: 10),
            _lockNotice(stage),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: _border),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadButton.ghost(
                key: ValueKey('stage-requirements-$key'),
                size: ShadButtonSize.sm,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                trailing: Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 15,
                ),
                onPressed: () => setState(
                  () => expanded ? _expanded.remove(key) : _expanded.add(key),
                ),
                child: Text(
                  expanded ? 'Hide requirements' : 'View requirements',
                ),
              ),
              if (compact) _actions(stage, index),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            _details(stage, compact),
          ],
        ],
      ),
    );
  }

  Widget _metadataPill(IconData icon, String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _fill,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? _muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _small.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color ?? _ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metadata(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: _muted),
      const SizedBox(width: 7),
      Flexible(child: Text(text, style: _small)),
    ],
  );

  Widget _actions(Map<String, dynamic> stage, int index) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ShadButton.outline(
        key: ValueKey('stage-configure-${stage['id']}'),
        enabled: !_busy && stage['id'] != null,
        size: ShadButtonSize.sm,
        onPressed: () => widget.onConfigure(stage),
        child: Flexible(
          child: Text(
            stageSetupLocked(stage) ? 'View configuration' : 'Configure stage',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      _StageActionsMenu(
        stage: stage,
        busy: _busy,
        canMoveUp:
            index > 0 &&
            !stageSetupLocked(stage) &&
            !stageSetupLocked(widget.state.stages[index - 1]),
        canMoveDown:
            index < widget.state.stages.length - 1 &&
            !stageSetupLocked(stage) &&
            !stageSetupLocked(widget.state.stages[index + 1]),
        onPublish: () => widget.onPublish(stage),
        onDelete: () => widget.onDelete(stage),
        onMoveUp: () => widget.onMove(stage, index, -1),
        onMoveDown: () => widget.onMove(stage, index, 1),
      ),
    ],
  );

  Widget _details(Map<String, dynamic> stage, bool compact) {
    final info = stage['rubric_info'] is Map ? stage['rubric_info'] as Map : {};
    final readiness = stage['setup_readiness'] is Map
        ? stage['setup_readiness'] as Map
        : {};
    final roles = readiness['required_rubric_roles'] is List
        ? readiness['required_rubric_roles'] as List
        : [];
    final rubrics = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.clipboardCheck, size: 15, color: _ink),
            const SizedBox(width: 6),
            Text(
              'Evaluation rubrics',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final role in ['panel', 'adviser', 'peer'])
          _rubricCard(
            role: role,
            name: info['${role}_rubric_name']?.toString(),
            isRequired: roles.contains(role),
            isReady: readiness['ready'] == true,
          ),
        if (stageSetupIssues(stage).isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final issue in stageSetupIssues(stage))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.circleAlert, size: 13, color: _warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue,
                      style: _small.copyWith(fontSize: 12, color: _warning),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
    final deliverables = _rows(stage['deliverables']);
    final pre = deliverables
        .where((d) => (d['deliverable_type'] ?? d['type']) == 'pre')
        .toList();
    final post = deliverables
        .where((d) => (d['deliverable_type'] ?? d['type']) != 'pre')
        .toList();
    final requirements = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage['is_presentation_only'] == true)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.presentation, size: 16, color: _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Presentation only. Student file uploads are not required.',
                    style: _small,
                  ),
                ),
              ],
            ),
          )
        else ...[
          _requirementGroup('Pre-defense requirements', pre),
          const SizedBox(height: 14),
          _requirementGroup('Post-defense requirements', post),
        ],
        if (_rows(stage['system_deliverables']).isNotEmpty) ...[
          const SizedBox(height: 14),
          _requirementGroup(
            'Documenter requirements',
            _rows(stage['system_deliverables']),
            system: true,
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: (compact || MediaQuery.sizeOf(context).width < 1000)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rubrics,
                Divider(height: 28, color: _border),
                requirements,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: rubrics),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: requirements),
              ],
            ),
    );
  }

  Widget _rubricCard({
    required String role,
    required String? name,
    required bool isRequired,
    required bool isReady,
  }) {
    final hasRubric = name != null && name.trim().isNotEmpty;
    final roleLabel = '${role[0].toUpperCase()}${role.substring(1)} evaluation';
    final fallbackText = isRequired
        ? 'Rubric required'
        : (isReady
            ? 'Not required for current grading settings'
            : 'Not attached');

    IconData roleIcon;
    Color roleColor;
    switch (role) {
      case 'panel':
        roleIcon = LucideIcons.graduationCap;
        roleColor = DefensysTokens.maroonOf(context);
        break;
      case 'adviser':
        roleIcon = LucideIcons.userCheck;
        roleColor = const Color(0xFF0284C7);
        break;
      default:
        roleIcon = LucideIcons.users;
        roleColor = const Color(0xFF7C3AED);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(roleIcon, size: 16, color: roleColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: _small.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRubric ? name : fallbackText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hasRubric ? _ink : _muted,
                  ),
                ),
              ],
            ),
          ),
          if (hasRubric)
            Icon(LucideIcons.check, size: 15, color: _success)
          else if (isRequired)
            ShadBadge.outline(
              backgroundColor: _dark
                  ? DefensysTokens.goldOf(context).withValues(alpha: 0.1)
                  : const Color(0xFFFEF3C7),
              foregroundColor: _warning,
              child: const Text('Required'),
            ),
        ],
      ),
    );
  }

  Widget _requirementGroup(
    String title,
    List<Map<String, dynamic>> rows, {
    bool system = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(
            system
                ? LucideIcons.stamp
                : (title.contains('Pre') ? LucideIcons.fileUp : LucideIcons.fileCheck),
            size: 15,
            color: _ink,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(width: 6),
            ShadBadge.secondary(
              child: Text('${rows.length}'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          child: Text('No requirements configured', style: _small),
        )
      else
        for (final row in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      system ? LucideIcons.fileCheck : LucideIcons.fileText,
                      size: 16,
                      color: system ? DefensysTokens.maroonOf(context) : _muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row['label']?.toString() ?? 'Deliverable',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ShadBadge.outline(
                      backgroundColor: row['required'] == true
                          ? (_dark
                              ? DefensysTokens.maroonOf(context).withValues(alpha: 0.15)
                              : const Color(0xFFFEE2E2))
                          : null,
                      foregroundColor: row['required'] == true
                          ? DefensysTokens.maroonOf(context)
                          : _muted,
                      child: Text(
                        row['required'] == true ? 'Required' : 'Optional',
                      ),
                    ),
                  ],
                ),
                if (system) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Assigned documenter · All required signatures completed',
                    style: _small.copyWith(fontSize: 12),
                  ),
                ] else if (_requirementMetadata(row).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _requirementMetadata(row),
                    style: _small.copyWith(fontSize: 12),
                  ),
                ],
                if ((row['archive_file_template'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _fill,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      'Archive filename: ${row['archive_file_template']}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
    ],
  );

  String _requirementMetadata(Map<String, dynamic> row) => [
    if (row['file_format'] != null && row['file_format'] != 'any')
      row['file_format'].toString().toUpperCase(),
    if (row['verdict_condition'] == 'revisions_only') 'Revisions verdict only',
    if (row['is_defense_material'] == true) 'Visible to panelists',
    if (row['is_restricted'] == true) 'Private archive',
  ].join(' · ');

  Widget _tableView() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: constraints.maxWidth < 1100 ? 1100 : constraints.maxWidth,
        child: ShadCard(
          width: double.infinity,
          padding: EdgeInsets.zero,
          backgroundColor: _surface,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FixedColumnWidth(64),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FixedColumnWidth(225),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: _fill),
                children: [
                  for (final label in [
                    'Order',
                    'Stage',
                    'Requirements',
                    'Setup status',
                    'Actions',
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Text(
                        label,
                        style: _small.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              for (var i = 0; i < widget.state.stages.length; i++)
                _tableRow(widget.state.stages[i], i),
            ],
          ),
        ),
      ),
    ),
  );

  TableRow _tableRow(Map<String, dynamic> stage, int index) {
    final info = stage['rubric_info'] is Map ? stage['rubric_info'] as Map : {};
    final pre = _rows(
      stage['deliverables'],
    ).where((d) => (d['deliverable_type'] ?? d['type']) == 'pre').length;
    final post = _rows(stage['deliverables']).length - pre;
    return TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text((index + 1).toString().padLeft(2, '0'), style: _small),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stage['label']?.toString() ?? 'Stage',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              _publication(stage),
              const SizedBox(height: 6),
              Text(
                index == 0
                    ? 'First stage'
                    : 'Requires ${stage['previous_stage_label'] ?? widget.state.stages[index - 1]['label']}',
                style: _small.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${info['count'] ?? stage['rubrics_count'] ?? 0} rubrics attached',
                style: _small,
              ),
              Text(
                stage['is_presentation_only'] == true
                    ? 'Presentation only'
                    : '$pre pre-defense · $post post-defense',
                style: _small.copyWith(fontSize: 12),
              ),
              if (_rows(stage['system_deliverables']).isNotEmpty)
                Text(
                  'Signed minutes required',
                  style: _small.copyWith(fontSize: 12),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _readiness(stage),
              if (stageSetupLocked(stage)) ...[
                const SizedBox(height: 8),
                _lockNotice(stage),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _actions(stage, index),
        ),
      ],
    );
  }

  Widget _empty() => ShadCard(
    width: double.infinity,
    backgroundColor: _surface,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
    child: Column(
      children: [
        Icon(LucideIcons.layers, size: 30, color: _muted),
        const SizedBox(height: 16),
        Text(
          'Build your defense sequence',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add your first stage, then configure its rubrics and requirements.',
          textAlign: TextAlign.center,
          style: _small,
        ),
      ],
    ),
  );

  Widget _loading() => Semantics(
    label: 'Loading defense stages',
    child: Column(
      children: [
        DefensysSkeleton.box(
          height: 112,
          color: _border.withValues(alpha: .45),
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ShadCard(
              width: double.infinity,
              backgroundColor: _surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FractionallySizedBox(
                    widthFactor: .45,
                    alignment: Alignment.centerLeft,
                    child: DefensysSkeleton.box(
                      height: 20,
                      color: _border.withValues(alpha: .5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  DefensysSkeleton.box(
                    height: 14,
                    color: _border.withValues(alpha: .35),
                  ),
                  const SizedBox(height: 12),
                  FractionallySizedBox(
                    widthFactor: .7,
                    alignment: Alignment.centerLeft,
                    child: DefensysSkeleton.box(
                      height: 14,
                      color: _border.withValues(alpha: .35),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _StageActionsMenu extends StatefulWidget {
  const _StageActionsMenu({
    required this.stage,
    required this.busy,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onPublish,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });
  final Map<String, dynamic> stage;
  final bool busy, canMoveUp, canMoveDown;
  final VoidCallback onPublish, onDelete, onMoveUp, onMoveDown;
  @override
  State<_StageActionsMenu> createState() => _StageActionsMenuState();
}

class _StageActionsMenuState extends State<_StageActionsMenu> {
  final _controller = ShadPopoverController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _item(
    String label,
    IconData icon,
    VoidCallback action, {
    bool enabled = true,
    String? hint,
    bool destructive = false,
  }) => Tooltip(
    message: hint ?? label,
    child: ShadButton.ghost(
      width: 240,
      size: ShadButtonSize.sm,
      mainAxisAlignment: MainAxisAlignment.start,
      enabled: enabled && !widget.busy,
      foregroundColor: destructive ? DefensysTokens.danger : null,
      leading: Icon(icon, size: 15),
      onPressed: () {
        _controller.hide();
        action();
      },
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final locked = stageSetupLocked(widget.stage);
    final ready = stageSetupIssues(widget.stage).isEmpty;
    return ShadPopover(
      controller: _controller,
      padding: const EdgeInsets.all(6),
      popover: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Stage actions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
          if (!stagePublished(widget.stage))
            _item(
              'Publish stage',
              LucideIcons.send,
              widget.onPublish,
              enabled: !locked && ready,
              hint: locked
                  ? 'Publication is locked for this stage.'
                  : ready
                  ? 'Make this stage available in defense scheduling.'
                  : 'Configure the missing requirements before publishing.',
            ),
          _item(
            'Move earlier',
            LucideIcons.arrowUp,
            widget.onMoveUp,
            enabled: widget.canMoveUp,
            hint: locked
                ? 'Stages with scheduled defenses or recorded grades cannot be reordered.'
                : widget.canMoveUp
                ? 'Move one position earlier.'
                : 'Already first, or the preceding stage is locked.',
          ),
          _item(
            'Move later',
            LucideIcons.arrowDown,
            widget.onMoveDown,
            enabled: widget.canMoveDown,
            hint: locked
                ? 'Stages with scheduled defenses or recorded grades cannot be reordered.'
                : widget.canMoveDown
                ? 'Move one position later.'
                : 'Already last, or the next stage is locked.',
          ),
          Divider(color: DefensysTokens.borderOf(context)),
          _item(
            'Delete stage',
            LucideIcons.trash2,
            widget.onDelete,
            enabled: !locked,
            destructive: true,
            hint: locked
                ? 'Stages with scheduled defenses or recorded grades cannot be deleted.'
                : 'Delete this stage after confirmation.',
          ),
          if ((widget.stage['code'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 224,
                child: Text(
                  'Stage code: ${widget.stage['code']}',
                  style: TextStyle(
                    fontSize: 11,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: Tooltip(
        message: 'More actions for ${widget.stage['label'] ?? 'stage'}',
        child: ShadButton.outline(
          key: ValueKey('stage-menu-${widget.stage['id']}'),
          enabled: !widget.busy && widget.stage['id'] != null,
          size: ShadButtonSize.sm,
          width: 34,
          padding: EdgeInsets.zero,
          onPressed: _controller.toggle,
          child: const Icon(LucideIcons.ellipsis, size: 16),
        ),
      ),
    );
  }
}
