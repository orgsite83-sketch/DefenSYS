import 'package:flutter/material.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/defense_scheduler_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/widgets.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/repository/repository_archive_naming_panel.dart';
import '../../../../widgets/repository/deliverable_timing_fields.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../services/dashboard_provider.dart';
import '../../../../utils/unsaved_changes.dart';
import '../../admin/widgets/defensys_admin_shell.dart';
import '../../admin/grade_center/grade_center_shared.dart' show showPeerGradingHelpDialog;
import '../../admin/defense_stages/widgets/stage_deliverable_choices.dart';
import '../../admin/defense_stages/widgets/stage_deliverable_overview.dart';
import '../../admin/defense_stages/widgets/stage_deliverable_presets_bar.dart';
import '../../admin/defense_stages/widgets/stage_deliverable_presets.dart';

class PitEventsManagementScreen extends ConsumerStatefulWidget {
  const PitEventsManagementScreen({super.key});

  @override
  ConsumerState<PitEventsManagementScreen> createState() => _PitEventsManagementScreenState();
}

class _PitEventsManagementScreenState extends ConsumerState<PitEventsManagementScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _isLoadingConfigs = true;
  bool _isMatrixView = false;
  final Set<int> _expandedConfigIds = {};

  Color get _muted => DefensysTokens.textSecondaryOf(context);
  Color get _border => DefensysTokens.borderOf(context);
  Color get _surface => DefensysTokens.surfaceOf(context);
  Color get _ink => DefensysTokens.textPrimaryOf(context);
  Color get _fill => DefensysTokens.surfaceHigherOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingConfigs = true);
    await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    final notifier = ref.read(defenseSchedulerProvider.notifier);
    final activeSem = ref.read(defenseSchedulerProvider).activeSemester;
    final semesterId = activeSem != null ? int.tryParse(activeSem['id']?.toString() ?? '') : null;
    final configsList = await notifier.fetchPitEventConfigs(semesterId: semesterId);
    if (mounted) {
      setState(() {
        _configs = configsList;
        _isLoadingConfigs = false;
      });
    }
  }

  Future<void> _deleteConfig(Map<String, dynamic> config) async {
    if (config['is_locked'] == true) {
      showErrorToast(context, config['lock_reason']?.toString() ?? 'Cannot delete a secured PIT event with active defenses or grades.');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Event Configuration',
      message: 'Are you sure you want to delete "${config['event_name']}"? This will also delete all associated deliverables.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    final configId = int.tryParse(config['id']?.toString() ?? '');
    if (configId == null) return;

    final success = await ref.read(defenseSchedulerProvider.notifier).deletePitEventConfig(configId);
    if (success && mounted) {
      showSuccessToast(context, 'Configuration deleted successfully.');
      _loadData();
    }
  }

  void _showEventDialog([Map<String, dynamic>? config]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EventConfigEditDialog(
        config: config,
        availableEvents: _configs,
        onSaveSuccess: () {
          Navigator.of(context).pop();
          _loadData();
        },
      ),
    );
  }

  Widget _eventActions(Map<String, dynamic> config) {
    if (config['is_locked'] == true) {
      return ShadButton.outline(
        size: ShadButtonSize.sm,
        leading: const Icon(LucideIcons.eye, size: 13),
        onPressed: () => _showEventDialog(config),
        child: const Text('View'),
      );
    }
    return _PitEventActionsMenu(
      eventId: config['id'],
      eventName: config['event_name']?.toString() ?? 'PIT event',
      onEdit: () => _showEventDialog(config),
      onDelete: () => _deleteConfig(config),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final isLoading = state.isLoading || _isLoadingConfigs;

    ref.listen<DefenseSchedulerState>(
      defenseSchedulerProvider,
      (previous, next) {
        if (next.error != null && next.error != previous?.error) {
          showErrorToast(context, next.error!);
        }
        if (next.message != null && next.message != previous?.message) {
          showSuccessToast(context, next.message!);
        }
      },
    );

    final activeSem = state.activeSemester;
    final activeSemLabel = activeSem != null
        ? (activeSem['display_name']?.toString() ?? '')
        : 'No active semester';

    if (isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(64.0),
          child: CircularProgressIndicator(color: DefensysTokens.maroonTextOf(context)),
        ),
      );
    }

    return DefensysShadcnScope(
      child: RefreshIndicator(
        color: DefensysTokens.maroonTextOf(context),
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: DefensysUi.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildExecutiveHeader(activeSemLabel, state.isSaving),
              const SizedBox(height: 20),
              _buildExecutiveStatCards(),
              const SizedBox(height: 24),
              _buildSectionHeader(),
              const SizedBox(height: 16),
              if (_configs.isEmpty)
                _buildEmptyState()
              else if (!_isMatrixView)
                _buildShowcaseCardsView()
              else
                _buildEventMatrixView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveHeader(String activeSemLabel, bool isSaving) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroonTextOf(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: DefensysTokens.maroonTextOf(context).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    LucideIcons.calendarCheck2,
                    color: DefensysTokens.maroonTextOf(context),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'PIT Event Operations & Setup',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      fontFamily: DefensysTokens.fontFamilyInter,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Configure discrete academic exhibition events, evaluation weight ratios (Panel vs Peer), rubrics, and deliverable checklists for $activeSemLabel.',
              style: TextStyle(
                color: _muted,
                fontSize: 13,
                height: 1.4,
                fontFamily: DefensysTokens.fontFamilyInter,
              ),
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const ReportExportMenu(reportId: 'pit-event-setup'),
            ShadButton.outline(
              enabled: !isSaving,
              leading: const Icon(LucideIcons.refreshCw, size: 15),
              onPressed: _loadData,
              child: const Text('Refresh'),
            ),
            ShadButton(
              enabled: !isSaving,
              backgroundColor: DefensysTokens.maroonTextOf(context),
              hoverBackgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              leading: const Icon(LucideIcons.plus, size: 16),
              onPressed: () => _showEventDialog(),
              child: const Text('Add Event'),
            ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 16),
              actionButtons,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 24),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _buildExecutiveStatCards() {
    final total = _configs.length;
    final rubricsLinked = _configs.where((config) {
      final peerWeight =
          int.tryParse(config['peer_weight']?.toString() ?? '') ?? 0;
      return config['panel_rubric_id'] != null &&
          (peerWeight == 0 || config['peer_rubric_id'] != null);
    }).length;
    final totalDeliverables = _configs.fold<int>(
      0,
      (sum, c) => sum + ((c['deliverables'] as List? ?? []).length),
    );

    final metrics = [
      _metricTile(
        'Total events',
        '$total',
        'Independent PIT events',
        LucideIcons.calendar,
      ),
      _metricTile(
        'Rubrics linked',
        '$rubricsLinked / $total',
        'Required evaluation rubrics attached',
        LucideIcons.clipboardCheck,
      ),
      _metricTile(
        'Checklist items',
        '$totalDeliverables',
        'Event deliverable requirements',
        LucideIcons.files,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 750;

        return ShadCard(
          width: double.infinity,
          backgroundColor: _surface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      metrics[i],
                      if (i < metrics.length - 1)
                        Divider(height: 24, color: _border),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 20),
                          child: metrics[i],
                        ),
                      ),
                      if (i < metrics.length - 1)
                        Container(width: 1, height: 46, color: _border),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _metricTile(String label, String value, String hint, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: _muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: _muted,
                fontFamily: DefensysTokens.fontFamilyInter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: _ink,
            fontFamily: DefensysTokens.fontFamilyInter,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11.5,
            color: _muted,
            fontFamily: DefensysTokens.fontFamilyInter,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PIT events',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
                fontFamily: DefensysTokens.fontFamilyInter,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Each event is independent. Numbers identify entries; they do not set an order.',
              style: TextStyle(
                fontSize: 12,
                color: _muted,
                fontFamily: DefensysTokens.fontFamilyInter,
              ),
            ),
          ],
        );
        final toggle = SizedBox(
          width: 250,
          child: ShadTabs<String>(
            scrollable: true,
            value: _isMatrixView ? 'matrix' : 'cards',
            onChanged: (val) => setState(() => _isMatrixView = val == 'matrix'),
            tabs: const [
              ShadTab(value: 'cards', child: Text('Events')),
              ShadTab(value: 'matrix', child: Text('Table')),
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
      },
    );
  }

  Widget _buildEmptyState() {
    return ShadCard(
      width: double.infinity,
      backgroundColor: _surface,
      padding: const EdgeInsets.all(32),
      child: DefensysEmptyState(
        icon: LucideIcons.calendar,
        title: 'No PIT Events Configured',
        description:
            'Configure evaluation weight splits, rubrics, and deliverable checklists for this academic semester.',
        size: DefensysEmptyStateSize.standard,
        primaryAction: DefensysEmptyAction(
          label: 'Add Event Configuration',
          icon: LucideIcons.plus,
          onPressed: _showEventDialog,
        ),
      ),
    );
  }

  Widget _buildShowcaseCardsView() {
    final state = ref.watch(defenseSchedulerProvider);
    final rubricList = state.rubrics;
    final peerRubricList = state.peerRubrics;

    String rubricName(dynamic id) {
      if (id == null) return 'Not Selected';
      final r = rubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Rubric';
    }

    String peerRubricName(dynamic id) {
      if (id == null) return 'Not Selected';
      final r = peerRubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Peer Rubric';
    }

    return Column(
      children: [
        for (var index = 0; index < _configs.length; index++) ...[
          Builder(
            builder: (context) {
            final config = _configs[index];
            final configId = int.tryParse(config['id']?.toString() ?? '') ?? index;
            final isExpanded = _expandedConfigIds.contains(configId);
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final postCount = delivs.where((d) => d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault').length;
            final isLocked = config['is_locked'] == true;
            final lockReason = config['lock_reason']?.toString() ?? 'Event is secured & locked';
            final panelWeight = int.tryParse(config['panel_weight']?.toString() ?? '') ?? 80;
            final peerWeight = int.tryParse(config['peer_weight']?.toString() ?? '') ?? 20;

              final missingRubrics = <String>[
                if (config['panel_rubric_id'] == null) 'panel',
                if (peerWeight > 0 && config['peer_rubric_id'] == null) 'peer',
              ];

            final eventName = config['event_name']?.toString() ?? '';
            final eventCode = config['event_code']?.toString() ?? '';

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: ValueKey('pit-event-number-$index'),
                    width: 44,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _fill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      (index + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ShadCard(
                      key: ValueKey('pit-event-card-$configId'),
              width: double.infinity,
              backgroundColor: _surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card Header Row: Title, Code, Status & Actions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    eventName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _ink,
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (eventCode.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _fill,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _border),
                                    ),
                                    child: Text(
                                      eventCode,
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 10.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (isLocked)
                                  Tooltip(
                                    message: lockReason,
                                    child: ShadBadge.secondary(
                                      backgroundColor: const Color(0xFFFEF3C7),
                                      foregroundColor: const Color(0xFF92400E),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(LucideIcons.lock, size: 10),
                                          SizedBox(width: 4),
                                          Text('Audit Locked'),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  ShadBadge.secondary(
                                    backgroundColor: _fill,
                                    foregroundColor: _muted,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.checkCircle2, size: 10, color: Color(0xFF10B981)),
                                        SizedBox(width: 4),
                                        Text('Active Showcase'),
                                      ],
                                    ),
                                  ),
                                if (peerWeight > 0)
                                  ShadBadge.outline(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          config['peer_grading_enabled'] == true ? LucideIcons.check : LucideIcons.pause,
                                          size: 10,
                                          color: config['peer_grading_enabled'] == true ? const Color(0xFF10B981) : _muted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(config['peer_grading_enabled'] == true ? 'Peer Open' : 'Peer Closed'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _eventActions(config),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Dual Evaluation Weight Gauge Bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: DefensysTokens.maroonTextOf(context), shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text(
                                'Panel: $panelWeight%',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: DefensysTokens.maroonTextOf(context),
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text(
                                'Peer: $peerWeight%',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFB45309),
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              if (panelWeight > 0)
                                Expanded(
                                  flex: panelWeight,
                                  child: Container(color: DefensysTokens.maroonTextOf(context)),
                                ),
                              if (peerWeight > 0)
                                Expanded(
                                  flex: peerWeight,
                                  child: Container(color: const Color(0xFFF59E0B)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Rubric Micro-cards Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildMicroRubricCard(
                          icon: LucideIcons.fileCheck,
                          label: 'Panel Rubric',
                          value: rubricName(config['panel_rubric_id']),
                          accentColor: DefensysTokens.maroonTextOf(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMicroRubricCard(
                          icon: LucideIcons.users,
                          label: 'Peer Rubric',
                          value: peerRubricName(config['peer_rubric_id']),
                          accentColor: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                          if (missingRubrics.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: DefensysTokens.goldOf(context)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: DefensysTokens.goldOf(context)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.circleAlert,
                                    size: 15,
                                    color: DefensysTokens.goldOf(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Attach ${missingRubrics.join(' and ')} evaluation rubric${missingRubrics.length == 1 ? '' : 's'}.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                  // Expandable Deliverable Checklist Drawer
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedConfigIds.remove(configId);
                        } else {
                          _expandedConfigIds.add(configId);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _fill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.folder, size: 14, color: _muted),
                              const SizedBox(width: 7),
                              Text(
                                'Deliverable Checklist ($preCount Pre, $postCount Post)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 14,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 110),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border),
                      ),
                      child: delivs.isEmpty
                          ? Text(
                              'No deliverable templates configured for this event.',
                              style: TextStyle(fontSize: 11, color: _muted, fontFamily: DefensysTokens.fontFamilyInter),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: delivs.map<Widget>((d) {
                                  final isPost = d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault';
                                  final isReq = d['required'] == true;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPost ? LucideIcons.archive : LucideIcons.fileText,
                                          size: 12,
                                          color: _muted,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            d['label']?.toString() ?? 'Deliverable',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: _ink,
                                              fontFamily: DefensysTokens.fontFamilyInter,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isReq)
                                          Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: DefensysTokens.maroonTextOf(context).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: DefensysTokens.maroonTextOf(context).withValues(alpha: 0.2)),
                                            ),
                                            child: Text(
                                              'Req',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                                color: DefensysTokens.maroonTextOf(context),
                                                fontFamily: DefensysTokens.fontFamilyInter,
                                              ),
                                            ),
                                          ),
                                        if (!isPost && d['is_defense_material'] == true) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: _fill,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: _border),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(LucideIcons.eye, size: 9.5, color: _muted),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Panel View',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: _muted,
                                                    fontFamily: DefensysTokens.fontFamilyInter,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (index < _configs.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildMicroRubricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _muted,
                    fontWeight: FontWeight.w500,
                    fontFamily: DefensysTokens.fontFamilyInter,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                    fontFamily: DefensysTokens.fontFamilyInter,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventMatrixView() {
    final state = ref.watch(defenseSchedulerProvider);
    final rubricList = state.rubrics;
    final peerRubricList = state.peerRubrics;

    String rubricName(dynamic id) {
      if (id == null) return 'None (No Rubric)';
      final r = rubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Rubric';
    }

    String peerRubricName(dynamic id) {
      if (id == null) return 'None (No Rubric)';
      final r = peerRubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Peer Rubric';
    }

    return ShadCard(
      width: double.infinity,
      backgroundColor: _surface,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_fill),
            dataRowMinHeight: 64,
            dataRowMaxHeight: 68,
          columns: [
            DataColumn(label: Text('No.', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Event & Code', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Weight Split', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Panel Rubric', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Peer Rubric', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Deliverables', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, color: _ink, fontFamily: DefensysTokens.fontFamilyInter, fontSize: 12.5))),
          ],
          rows: _configs.asMap().entries.map((entry) {
            final index = entry.key;
            final config = entry.value;
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final postCount = delivs.where((d) => d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault').length;
            final isLocked = config['is_locked'] == true;
            final lockReason = config['lock_reason']?.toString() ?? 'Secured & locked';

            return DataRow(
              cells: [
                DataCell(Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                )),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        config['event_name']?.toString() ?? '',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _ink, fontFamily: DefensysTokens.fontFamilyInter),
                      ),
                      if (config['event_code']?.toString().isNotEmpty == true)
                        Text(
                          config['event_code']?.toString() ?? '',
                          style: TextStyle(fontSize: 11, color: _muted, fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                ),
                DataCell(
                  isLocked
                      ? Tooltip(
                          message: lockReason,
                          child: ShadBadge.secondary(
                            backgroundColor: const Color(0xFFFEF3C7),
                            foregroundColor: const Color(0xFF92400E),
                            child: const Text('Locked'),
                          ),
                        )
                      : ShadBadge.secondary(
                          backgroundColor: _fill,
                          foregroundColor: _muted,
                          child: const Text('Active'),
                        ),
                ),
                DataCell(
                  Text(
                    '${config['panel_weight']}% / ${config['peer_weight']}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                DataCell(Text(rubricName(config['panel_rubric_id']), style: TextStyle(fontSize: 12, color: _ink, fontFamily: DefensysTokens.fontFamilyInter))),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(peerRubricName(config['peer_rubric_id']), style: TextStyle(fontSize: 12, color: _ink, fontFamily: DefensysTokens.fontFamilyInter)),
                      if ((config['peer_weight'] ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: config['peer_grading_enabled'] == true ? const Color(0xFF10B981) : _muted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                config['peer_grading_enabled'] == true ? 'Open' : 'Closed',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _muted,
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                DataCell(Text('$preCount Pre, $postCount Post', style: TextStyle(fontSize: 12, color: _muted, fontFamily: DefensysTokens.fontFamilyInter))),
                DataCell(
                  _eventActions(config),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    ),
  );
}
}

class _PitEventActionsMenu extends StatefulWidget {
  const _PitEventActionsMenu({
    required this.eventId,
    required this.eventName,
    required this.onEdit,
    required this.onDelete,
  });

  final Object? eventId;
  final String eventName;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  State<_PitEventActionsMenu> createState() => _PitEventActionsMenuState();
}

class _PitEventActionsMenuState extends State<_PitEventActionsMenu> {
  final _controller = ShadPopoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadPopover(
    controller: _controller,
    padding: const EdgeInsets.all(6),
    popover: (context) => SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadButton.ghost(
            width: 240,
            size: ShadButtonSize.sm,
            mainAxisAlignment: MainAxisAlignment.start,
            leading: const Icon(LucideIcons.pencil, size: 15),
            onPressed: () {
              _controller.hide();
              widget.onEdit();
            },
            child: const Text('Edit event'),
          ),
          Divider(height: 8, color: DefensysTokens.borderOf(context)),
          ShadButton.ghost(
            width: 240,
            size: ShadButtonSize.sm,
            mainAxisAlignment: MainAxisAlignment.start,
            foregroundColor: DefensysTokens.danger,
            leading: const Icon(LucideIcons.trash2, size: 15),
            onPressed: () async {
              _controller.hide();
              await widget.onDelete();
            },
            child: const Text('Delete event'),
          ),
        ],
      ),
    ),
    child: Tooltip(
      message: 'More actions for ${widget.eventName}',
      child: ShadButton.outline(
        key: ValueKey('pit-event-menu-${widget.eventId}'),
        size: ShadButtonSize.sm,
        width: 34,
        padding: EdgeInsets.zero,
        onPressed: _controller.toggle,
        child: const Icon(LucideIcons.ellipsis, size: 16),
      ),
    ),
  );
}

class _EventConfigEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? config;
  final List<Map<String, dynamic>> availableEvents;
  final VoidCallback onSaveSuccess;

  const _EventConfigEditDialog({
    this.config,
    required this.availableEvents,
    required this.onSaveSuccess,
  });

  @override
  ConsumerState<_EventConfigEditDialog> createState() => _EventConfigEditDialogState();
}

class _EventConfigEditDialogState extends ConsumerState<_EventConfigEditDialog> {
  int _activeTab = 0;
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _eventCodeController = TextEditingController();
  final _archiveFileTemplateController = TextEditingController();
  late final TextEditingController _panelWeightController;
  late final TextEditingController _peerWeightController;

  int? _panelRubricId;
  int? _peerRubricId;
  int _panelWeight = 80;
  int _peerWeight = 20;
  bool _peerGradingEnabled = true;

  List<Map<String, dynamic>> _deliverables = [];
  Map<String, dynamic>? _selectedDeliverable;
  bool _isDirty = false;
  bool _allowPop = false;

  bool _checkIfDirty() {
    final initialEventName = widget.config?['event_name']?.toString() ?? '';
    final initialCode = widget.config?['event_code']?.toString() ?? '';
    final initialTemplate = (widget.config?['archive_file_template'] ?? widget.config?['vault_file_template'])?.toString() ?? '';
    final initialPanelRubric = int.tryParse(widget.config?['panel_rubric_id']?.toString() ?? '');
    final initialPeerRubric = int.tryParse(widget.config?['peer_rubric_id']?.toString() ?? '');
    final initialPanelWeight = int.tryParse(widget.config?['panel_weight']?.toString() ?? '') ?? 80;
    final initialPeerWeight = int.tryParse(widget.config?['peer_weight']?.toString() ?? '') ?? 20;
    final initialPeerGrading = widget.config?['peer_grading_enabled'];
    final normInitialPeerGrading = initialPeerGrading is bool ? initialPeerGrading : true;

    final initialDelList = widget.config?['deliverables'] as List? ?? [];

    if (_eventNameController.text != initialEventName) return true;
    if (_eventCodeController.text != initialCode) return true;
    if (_archiveFileTemplateController.text != initialTemplate) return true;
    if (_panelRubricId != initialPanelRubric) return true;
    if (_peerRubricId != initialPeerRubric) return true;
    if (_panelWeight != initialPanelWeight) return true;
    if (_peerWeight != initialPeerWeight) return true;
    if (_peerGradingEnabled != normInitialPeerGrading) return true;

    if (_deliverables.length != initialDelList.length) return true;

    for (int i = 0; i < _deliverables.length; i++) {
      final current = _deliverables[i];
      final initial = Map<String, dynamic>.from(initialDelList[i] as Map);

      final curLabelCtrl = current['_labelController'] as TextEditingController?;
      final curLabel = curLabelCtrl != null ? curLabelCtrl.text : (current['label']?.toString() ?? '');
      if (curLabel != (initial['label']?.toString() ?? '')) return true;

      final currentType = current['deliverable_type']?.toString();
      final initialType = initial['deliverable_type']?.toString();
      final normCurrentType = currentType == 'vault' ? 'post' : currentType;
      final normInitialType = initialType == 'vault' ? 'post' : initialType;
      if (normCurrentType != normInitialType) return true;

      if ((current['required'] == true) != (initial['required'] == true)) return true;
      if ((current['is_restricted'] == true) != (initial['is_restricted'] == true)) return true;
      if ((current['is_defense_material'] == true) != (initial['is_defense_material'] == true)) return true;
      if ((current['requirement_timing'] ?? 'scheduling') != (initial['requirement_timing'] ?? 'scheduling')) return true;
      if ((current['deadline_hours_before'] ?? 24) != (initial['deadline_hours_before'] ?? 24)) return true;
      if ((current['file_format'] ?? 'any') != (initial['file_format'] ?? 'any')) return true;

      final curTplCtrl = current['_templateController'] as TextEditingController?;
      final currentTpl = curTplCtrl != null ? curTplCtrl.text : (current['archive_file_template'] ?? current['vault_file_template']);
      final initialTpl = initial['archive_file_template'] ?? initial['vault_file_template'];
      if (currentTpl?.toString() != initialTpl?.toString()) return true;
    }

    return false;
  }

  void _markDirty() {
    final isDirty = _checkIfDirty();
    if (_isDirty == isDirty) return;
    setState(() {
      _isDirty = isDirty;
    });
  }

  Future<void> _handleClose() async {
    if (_isDirty) {
      final discard = await confirmDiscardUnsavedChanges(context);
      if (discard && mounted) {
        setState(() {
          _allowPop = true;
        });
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _allowPop = true;
      });
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      _eventNameController.text = widget.config!['event_name']?.toString() ?? '';
      _eventCodeController.text = widget.config!['event_code']?.toString() ?? '';
      _archiveFileTemplateController.text = (widget.config!['archive_file_template'] ?? widget.config!['vault_file_template'])?.toString() ?? '';
      _panelRubricId = int.tryParse(widget.config!['panel_rubric_id']?.toString() ?? '');
      _peerRubricId = int.tryParse(widget.config!['peer_rubric_id']?.toString() ?? '');
      _panelWeight = int.tryParse(widget.config!['panel_weight']?.toString() ?? '') ?? 80;
      _peerWeight = int.tryParse(widget.config!['peer_weight']?.toString() ?? '') ?? 20;
      final initialPeerGrading = widget.config!['peer_grading_enabled'];
      _peerGradingEnabled = initialPeerGrading is bool ? initialPeerGrading : true;

      final delList = widget.config!['deliverables'] as List? ?? [];
      _deliverables = delList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        map['is_defense_material'] = item['is_defense_material'] == true;
        map['_labelController'] = TextEditingController(text: map['label']?.toString() ?? '');
        map['_templateController'] = TextEditingController(
          text: (map['archive_file_template'] ?? map['vault_file_template'])?.toString() ?? '',
        );
        return map;
      }).toList();
    }
    _panelWeightController = TextEditingController(text: _panelWeight.toString());
    _peerWeightController = TextEditingController(text: _peerWeight.toString());

    _eventNameController.addListener(_markDirty);
    _eventCodeController.addListener(_markDirty);
    _archiveFileTemplateController.addListener(_markDirty);
    _panelWeightController.addListener(_markDirty);
    _peerWeightController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _eventNameController.removeListener(_markDirty);
    _eventCodeController.removeListener(_markDirty);
    _archiveFileTemplateController.removeListener(_markDirty);
    _panelWeightController.removeListener(_markDirty);
    _peerWeightController.removeListener(_markDirty);

    _eventNameController.dispose();
    _eventCodeController.dispose();
    _archiveFileTemplateController.dispose();
    _panelWeightController.dispose();
    _peerWeightController.dispose();

    for (final item in _deliverables) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  void _onPanelWeightChanged(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _panelWeight = 0;
        _peerWeight = 100;
        _peerWeightController.text = '100';
      });
      _markDirty();
      return;
    }
    final parsed = int.tryParse(clean);
    if (parsed != null) {
      final clamped = parsed.clamp(0, 100);
      setState(() {
        _panelWeight = clamped;
        _peerWeight = 100 - clamped;
        _peerWeightController.text = (100 - clamped).toString();
        if (parsed != clamped) {
          _panelWeightController.text = clamped.toString();
        }
      });
    }
    _markDirty();
  }

  void _onPeerWeightChanged(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _peerWeight = 0;
        _panelWeight = 100;
        _panelWeightController.text = '100';
      });
      _markDirty();
      return;
    }
    final parsed = int.tryParse(clean);
    if (parsed != null) {
      final clamped = parsed.clamp(0, 100);
      setState(() {
        _peerWeight = clamped;
        _panelWeight = 100 - clamped;
        _panelWeightController.text = (100 - clamped).toString();
        if (parsed != clamped) {
          _peerWeightController.text = clamped.toString();
        }
      });
    }
    _markDirty();
  }

  void _addDeliverable({required String type}) {
    final existingPostCount = _deliverables.where((d) => d['deliverable_type'] == 'post').length;
    final defaultTemplate = type == 'post'
        ? (existingPostCount == 0 ? '{project}' : '{project}_{deliverable}')
        : '';
    final newMap = <String, dynamic>{
      'deliverable_id': 'D${_deliverables.length + 1}',
      'label': '',
      'deliverable_type': type,
      'required': true,
      'display_order': _deliverables.length + 1,
      'archive_note': '',
      'archive_file_template': defaultTemplate,
      'is_restricted': false,
      'is_defense_material': false,
      'file_format': 'any',
      'requirement_timing': 'scheduling',
      'deadline_hours_before': 24,
    };
    newMap['_labelController'] = TextEditingController(text: '');
    newMap['_templateController'] = TextEditingController(text: defaultTemplate);
    setState(() {
      _deliverables.add(newMap);
      _selectedDeliverable = newMap;
    });
    _markDirty();
  }

  void _removeDeliverable(Map<String, dynamic> item) {
    setState(() {
      if (identical(_selectedDeliverable, item)) {
        _selectedDeliverable = null;
      }
      _deliverables.remove(item);
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    });
    _markDirty();
  }


  Future<void> _save() async {
    final eventName = _eventNameController.text.trim();
    if (eventName.isEmpty) {
      setState(() => _activeTab = 0);
      showValidationToast(context, 'Please enter an event name.');
      return;
    }
    if (_panelWeight + _peerWeight != 100) {
      setState(() => _activeTab = 1);
      showValidationToast(context, 'Panel and Peer weights must total 100%.');
      return;
    }

    for (int i = 0; i < _deliverables.length; i++) {
      final d = _deliverables[i];
      final ctrl = d['_labelController'] as TextEditingController?;
      final lbl = (ctrl != null ? ctrl.text : d['label']?.toString() ?? '').trim();
      if (lbl.isEmpty) {
        setState(() => _activeTab = 2);
        showValidationToast(context, 'Deliverable name cannot be empty (item ${i + 1}).');
        return;
      }
    }

    final state = ref.read(defenseSchedulerProvider);
    final activeSem = state.activeSemester;
    final semesterId = activeSem != null ? int.tryParse(activeSem['id']?.toString() ?? '') : null;

    final deliverablesPayload = _deliverables.asMap().entries.map((e) {
      final idx = e.key;
      final d = e.value;
      final labelCtrl = d['_labelController'] as TextEditingController?;
      final tplCtrl = d['_templateController'] as TextEditingController?;
      return {
        if (d['id'] != null) 'id': d['id'],
        'deliverable_id': d['deliverable_id']?.toString().isNotEmpty == true
            ? d['deliverable_id']
            : 'D${idx + 1}',
        'label': labelCtrl != null ? labelCtrl.text.trim() : (d['label']?.toString().trim() ?? ''),
        'deliverable_type': d['deliverable_type'] ?? 'pre',
        'required': d['required'] == true,
        'display_order': idx + 1,
        'archive_note': d['archive_note'] ?? '',
        'archive_file_template': tplCtrl != null ? tplCtrl.text.trim() : (d['archive_file_template'] ?? ''),
        'is_restricted': d['is_restricted'] == true,
        'is_defense_material': d['is_defense_material'] == true,
        'requirement_timing': d['requirement_timing'] ?? 'scheduling',
        'deadline_hours_before': d['deadline_hours_before'] ?? 24,
        'file_format': d['file_format'] ?? 'any',
      };
    }).toList();

    final payload = {
      'semester_id': semesterId,
      'year_level': widget.config?['year_level'] ?? ref.read(dashboardProvider('faculty')).data?['pit_lead_year'],
      'event_name': eventName,
      'event_code': _eventCodeController.text.trim(),
      'panel_rubric_id': _panelRubricId,
      'peer_rubric_id': _peerRubricId,
      'panel_weight': _panelWeight,
      'peer_weight': _peerWeight,
      'peer_grading_enabled': _peerGradingEnabled,
      'archive_file_template': _archiveFileTemplateController.text.trim(),
      'deliverables': deliverablesPayload,
    };

    final success = await ref.read(defenseSchedulerProvider.notifier).savePitEventConfig(payload);
    if (success) {
      setState(() {
        _isDirty = false;
        _allowPop = true;
      });
      widget.onSaveSuccess();
    }
  }

  InputDecoration _dialogInputDecoration({
    required String labelText,
    String? hintText,
    String? helperText,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        fontFamily: DefensysTokens.fontFamily,
      ),
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
        fontFamily: DefensysTokens.fontFamily,
      ),
      helperStyle: const TextStyle(
        fontSize: 11,
        color: AppColors.textSecondary,
        fontFamily: DefensysTokens.fontFamily,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
      ),
    );
  }

  Widget _buildDialogTabBar({
    required int activeTab,
    required int deliverableCount,
    required int totalWeight,
    required void Function(int) onTabSelected,
  }) {
    final hasWeightError = totalWeight != 100;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _buildDialogTabItem(
            index: 0,
            label: '1. Event Details',
            icon: Icons.event_note_rounded,
            isSelected: activeTab == 0,
            onTap: () => onTabSelected(0),
          ),
          const SizedBox(width: 4),
          _buildDialogTabItem(
            index: 1,
            label: '2. Grading & Rubrics',
            icon: Icons.balance_rounded,
            badge: hasWeightError
                ? Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            isSelected: activeTab == 1,
            onTap: () => onTabSelected(1),
          ),
          const SizedBox(width: 4),
          _buildDialogTabItem(
            index: 2,
            label: '3. Deliverables',
            icon: Icons.inventory_2_rounded,
            badge: deliverableCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: activeTab == 2
                          ? Colors.white.withValues(alpha: 0.25)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$deliverableCount',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: activeTab == 2 ? Colors.white : AppColors.textPrimary,
                        fontFamily: DefensysTokens.fontFamily,
                      ),
                    ),
                  )
                : null,
            isSelected: activeTab == 2,
            onTap: () => onTabSelected(2),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTabItem({
    required int index,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? DefensysTokens.maroon : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: DefensysTokens.maroon.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeightDistributionBar(int panel, int peer) {
    final total = panel + peer;
    final isValid = total == 100;

    final pFlex = (panel > 0) ? panel : 0;
    final peFlex = (peer > 0) ? peer : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isValid ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    size: 15,
                    color: isValid ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isValid ? 'Balanced Allocation (100%)' : 'Allocation Error: Must Total 100%',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isValid ? AppColors.success : AppColors.danger,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ],
              ),
              Text(
                'Total: $total%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isValid ? AppColors.success : AppColors.danger,
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 10,
              width: double.infinity,
              color: const Color(0xFFE2E8F0),
              child: (total > 0)
                  ? Row(
                      children: [
                        if (pFlex > 0)
                          Flexible(
                            flex: pFlex,
                            child: Container(
                              color: DefensysTokens.maroon,
                              height: double.infinity,
                            ),
                          ),
                        if (peFlex > 0)
                          Flexible(
                            flex: peFlex,
                            child: Container(
                              color: const Color(0xFFD97706),
                              height: double.infinity,
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegendItem('Panel Evaluation', '$panel%', DefensysTokens.maroon),
              _buildLegendItem('Peer Evaluation', '$peer%', const Color(0xFFD97706)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
      ],
    );
  }

  Widget _buildDeliverableSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgHeaderColor,
    required Color borderColor,
    required int count,
    required String buttonText,
    required VoidCallback onAdd,
    required String emptyPlaceholderText,
    required List<Map<String, dynamic>> items,
    required bool isPost,
    required String pitYear,
    required bool isLocked,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgHeaderColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: accentColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              fontFamily: DefensysTokens.fontFamily,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DefensysShadcnScope(
                  child: ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: isLocked ? null : onAdd,
                    leading: const Icon(Icons.add_rounded, size: 14),
                    child: Text(buttonText),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: items.isEmpty
                ? InkWell(
                    onTap: isLocked ? null : onAdd,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPost ? Icons.inventory_2_outlined : Icons.folder_open_rounded,
                            size: 16,
                            color: const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              emptyPlaceholderText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : StageDeliverableOverview(
                    items: items,
                    isPost: isPost,
                    selectedItem: _selectedDeliverable,
                    onSelect: (item) => setState(() => _selectedDeliverable = item),
                    showDoneEditingButton: false,
                    buildEditor: (item, index) => _buildDeliverableItemCard(
                      item: item,
                      isPost: isPost,
                      pitYear: pitYear,
                      isLocked: isLocked,
                      index: index,
                      onDone: () => setState(() => _selectedDeliverable = null),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverableItemCard({
    required Map<String, dynamic> item,
    required bool isPost,
    required String pitYear,
    required bool isLocked,
    required int index,
    VoidCallback? onDone,
  }) {
    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(
          text: item['archive_file_template']?.toString() ?? '',
        ));

    const legacyDefault = '{year}.{course}.{project}.{stage}.{deliverable}.{semester}';
    if (templateController.text.trim() == legacyDefault) {
      templateController.text = '';
      item['archive_file_template'] = '';
    }

    final currentFormat = (item['file_format']?.toString().isNotEmpty == true)
        ? item['file_format'].toString()
        : 'any';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Item Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Text(
                    '#$index',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelController.text.trim().isNotEmpty
                        ? 'Deliverable #$index • ${labelController.text.trim()}'
                        : 'Deliverable #$index',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isLocked ? null : () => _removeDeliverable(item),
                  icon: Icon(Icons.delete_outline_rounded, color: isLocked ? Colors.grey : AppColors.danger, size: 18),
                  tooltip: 'Remove Deliverable #$index',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    hoverColor: isLocked ? Colors.transparent : AppColors.danger.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          // 2. Card Content Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final nameField = TextFormField(
                      controller: labelController,
                      readOnly: isLocked,
                      decoration: _dialogInputDecoration(
                        labelText: isPost ? 'Post-Defense Deliverable Name *' : 'Pre-Defense Deliverable Name *',
                        hintText: isPost
                            ? 'e.g. Final Manuscript PDF, Source Code Archive'
                            : 'e.g. Project Proposal Manuscript, Pitch Deck',
                      ),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: DefensysTokens.fontFamily),
                      onChanged: (value) {
                        item['label'] = value.trim();
                        setState(() {});
                        _markDirty();
                      },
                    );
                    final formatField = SizedBox(
                      width: 210,
                      child: StageFileFormatPicker(
                        value: currentFormat,
                        enabled: !isLocked,
                        onChanged: (val) {
                          setState(() {
                            item['file_format'] = val;
                          });
                          _markDirty();
                        },
                      ),
                    );
                    final requiredField = DefensysShadcnScope(
                      child: ShadCheckbox(
                        value: item['required'] == true,
                        enabled: !isLocked,
                        label: const Text('Required'),
                        onChanged: (value) {
                          setState(() {
                            item['required'] = value == true;
                          });
                          _markDirty();
                        },
                      ),
                    );

                    final hasAdvancedSettings = isPost
                        ? (item['is_restricted'] == true ||
                            (item['archive_file_template'] != null &&
                                item['archive_file_template'].toString().trim().isNotEmpty &&
                                item['archive_file_template'] != '{project}' &&
                                item['archive_file_template'] != '{project}_{deliverable}'))
                        : (item['is_defense_material'] == true || item['requirement_timing'] == 'defense');
                    final isAdvancedExpanded = item['_expandedAdvanced'] as bool? ?? hasAdvancedSettings;

                    final moreOptionsBtn = DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          setState(() {
                            item['_expandedAdvanced'] = !isAdvancedExpanded;
                          });
                        },
                        leading: Icon(
                          isAdvancedExpanded ? Icons.expand_less_rounded : Icons.tune_rounded,
                          size: 14,
                        ),
                        child: Text(
                          isAdvancedExpanded ? 'Fewer options' : 'More options',
                        ),
                      ),
                    );

                    return constraints.maxWidth < 620
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              nameField,
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [formatField, requiredField, moreOptionsBtn],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: nameField),
                              const SizedBox(width: 10),
                              formatField,
                              const SizedBox(width: 10),
                              requiredField,
                              const SizedBox(width: 6),
                              moreOptionsBtn,
                            ],
                          );
                  },
                ),

                Builder(
                  builder: (context) {
                    final hasAdvancedSettings = isPost
                        ? (item['is_restricted'] == true ||
                            (item['archive_file_template'] != null &&
                                item['archive_file_template'].toString().trim().isNotEmpty &&
                                item['archive_file_template'] != '{project}' &&
                                item['archive_file_template'] != '{project}_{deliverable}'))
                        : (item['is_defense_material'] == true || item['requirement_timing'] == 'defense');
                    final isAdvancedExpanded = item['_expandedAdvanced'] as bool? ?? hasAdvancedSettings;

                    if (!isAdvancedExpanded) {
                      final summaryText = isPost
                          ? 'Archive deliverable${item['is_restricted'] == true ? ' • Restricted archive' : ''}'
                          : (item['requirement_timing'] == 'defense'
                              ? 'Due ${item['deadline_hours_before'] ?? 24}h before defense${item['is_defense_material'] == true ? ' • Panel material' : ''}'
                              : 'Cleared before scheduling${item['is_defense_material'] == true ? ' • Panel material' : ''}');
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFF64748B)),
                                  const SizedBox(width: 5),
                                  Text(
                                    summaryText,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                      fontFamily: DefensysTokens.fontFamily,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF475569)),
                              const SizedBox(width: 6),
                              Text(
                                isPost ? 'Advanced Post-Defense Rules & Archiving' : 'Advanced Timing & Panel Access',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155),
                                  fontFamily: DefensysTokens.fontFamily,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (!isPost) ...[
                            DefenseMaterialToggle(
                              value: item['is_defense_material'] == true,
                              enabled: !isLocked,
                              onChanged: (value) {
                                setState(() {
                                  item['is_defense_material'] = value;
                                });
                                _markDirty();
                              },
                            ),
                            const SizedBox(height: 8),
                            DeliverableTimingFields(
                              timing: item['requirement_timing']?.toString() ?? 'scheduling',
                              hoursBefore: int.tryParse(item['deadline_hours_before']?.toString() ?? '') ?? 24,
                              enabled: !isLocked,
                              showTimingChoices: true,
                              isDefenseMaterial: item['is_defense_material'] == true,
                              onTimingChanged: (value) {
                                setState(() => item['requirement_timing'] = value);
                                _markDirty();
                              },
                              onHoursChanged: (value) {
                                setState(() => item['deadline_hours_before'] = value);
                                _markDirty();
                              },
                            ),
                          ],
                          if (isPost) ...[
                            Row(
                              children: [
                                DefensysShadcnScope(
                                  child: ShadCheckbox(
                                    value: item['is_restricted'] == true,
                                    enabled: !isLocked,
                                    onChanged: (value) {
                                      setState(() {
                                        item['is_restricted'] = value == true;
                                      });
                                      _markDirty();
                                    },
                                    label: const Text(
                                      'Restricted / Private in Institutional Archive',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                        fontFamily: DefensysTokens.fontFamily,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Tooltip(
                                  message: 'Private for faculty and admin records only; hidden from students.',
                                  constraints: BoxConstraints(maxWidth: 240),
                                  child: Icon(Icons.help_outline_rounded, size: 14, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            RepositoryArchiveNamingPanel(
                              templateController: templateController,
                              deliverableLabel: labelController.text,
                              fileFormat: currentFormat,
                              isLocked: isLocked,
                              isPit: true,
                              pitYear: pitYear,
                              stageOrEventLabel: _eventNameController.text,
                              siblingDeliverables: _deliverables.where((d) => d['deliverable_type'] == 'post').toList(),
                              currentIndex: _deliverables.where((d) => d['deliverable_type'] == 'post').toList().indexOf(item),
                              onChanged: () {
                                item['archive_file_template'] = templateController.text.trim();
                                setState(() {});
                                _markDirty();
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (onDone != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: onDone,
                        leading: const Icon(Icons.check_rounded, size: 14),
                        child: const Text('Done editing'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerGradingAccessCard(bool isLocked) {
    final hasPeerRubric = _peerRubricId != null && _peerWeight > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _peerGradingEnabled ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _peerGradingEnabled ? const Color(0xFFF0F9FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.how_to_vote_rounded,
                  size: 18,
                  color: _peerGradingEnabled ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Peer Evaluation Access',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            fontFamily: DefensysTokens.fontFamily,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Text(
                            'Open by Default',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF047857),
                              fontFamily: DefensysTokens.fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _peerGradingEnabled
                          ? 'Open — students can submit peer rubrics once defenses are scheduled.'
                          : 'Closed — students cannot submit peer evaluations for this event.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _peerGradingEnabled ? const Color(0xFF0369A1) : Colors.grey.shade600,
                        fontFamily: DefensysTokens.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _peerGradingEnabled,
                activeTrackColor: DefensysTokens.maroon,
                activeThumbColor: Colors.white,
                onChanged: isLocked
                    ? null
                    : (val) {
                        setState(() => _peerGradingEnabled = val);
                        _markDirty();
                      },
              ),
            ],
          ),
          if (!hasPeerRubric && _peerGradingEnabled) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Peer grading weight is 0% or no peer rubric is selected. Attach a rubric above to enable student peer scoring.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                        fontFamily: DefensysTokens.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Post-deliverables unlock once presentation finishes. Teams transition to "Awaiting Peers" until teammate evaluations are complete.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => showPeerGradingHelpDialog(context, isPit: true),
                  icon: const Icon(Icons.help_outline_rounded, size: 13),
                  label: const Text('Evaluation Guide'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLocked = widget.config?['is_locked'] == true;
    final String lockReason = widget.config?['lock_reason']?.toString() ??
        'This PIT Event is secured because active defenses or evaluation grades exist.';

    final state = ref.watch(defenseSchedulerProvider);
    final activeSem = state.activeSemester;
    final activeSemesterName = activeSem != null
        ? '${activeSem['academic_year'] ?? activeSem['school_year'] ?? ''} ${activeSem['semester'] ?? ''}'.trim()
        : 'Active Semester';

    final dashboard = ref.watch(dashboardProvider('faculty')).data;
    final assignedPitYear = dashboard?['pit_lead_year']?.toString().trim();
    final pitYear = assignedPitYear ?? '';

    final panelRubrics = state.rubrics.where((r) {
      return r['scope'] == 'pit' && r['evaluation_type'] == 'panel';
    }).toList();

    final peerRubrics = state.peerRubrics.where((r) {
      return r['scope'] == 'pit' && r['evaluation_type'] == 'peer';
    }).toList();

    final preDeliverables = _deliverables.where((d) => d['deliverable_type'] == 'pre').toList();
    final postDeliverables = _deliverables.where((d) => d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault').toList();

    return PopScope(
      canPop: !_isDirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _handleClose();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 960,
            maxHeight: MediaQuery.of(context).size.height * 0.90,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Dialog Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_note_rounded, size: 20, color: DefensysTokens.maroon),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.config != null
                                  ? (isLocked ? 'View PIT Event (Secured)' : 'Edit PIT Event')
                                  : 'Add PIT Event',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Configure event details, role grading weights, and submission requirements.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _handleClose,
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                        tooltip: 'Close',
                        style: IconButton.styleFrom(
                          hoverColor: const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Segmented Step Tab Bar
                _buildDialogTabBar(
                  activeTab: _activeTab,
                  deliverableCount: _deliverables.length,
                  totalWeight: _panelWeight + _peerWeight,
                  onTabSelected: (index) {
                    setState(() => _activeTab = index);
                  },
                ),

                // 3. Scrollable Tab Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        // TAB 0: Event Details
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isLocked) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_outline_rounded, color: Color(0xFFB45309), size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'PIT Event Locked (Read-Only)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF92400E),
                                              fontFamily: DefensysTokens.fontFamily,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            lockReason,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFFB45309),
                                              fontFamily: DefensysTokens.fontFamily,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _eventNameController,
                                    readOnly: isLocked,
                                    decoration: _dialogInputDecoration(
                                      labelText: 'Event Name',
                                      hintText: 'e.g. $pitYear PIT Expo',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Event Name is required.';
                                      }
                                      return null;
                                    },
                                    style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _eventCodeController,
                                    readOnly: isLocked,
                                    decoration: _dialogInputDecoration(
                                      labelText: 'Stage Code',
                                      hintText: 'e.g. PIT201',
                                      helperText: 'Unique system identifier',
                                    ),
                                    style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.school_outlined, size: 20, color: Color(0xFF2563EB)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Assigned PIT Scope',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                                fontFamily: DefensysTokens.fontFamily,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFBFDBFE)),
                                              ),
                                              child: Text(
                                                pitYear,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1D4ED8),
                                                  fontFamily: DefensysTokens.fontFamily,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                              ),
                                              child: Text(
                                                activeSemesterName,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF475569),
                                                  fontFamily: DefensysTokens.fontFamily,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'PIT events allow scheduling oral defense panels and peer review sessions specifically for this student cohort.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                            fontFamily: DefensysTokens.fontFamily,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // TAB 1: Grading Composition & Rubrics
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Role Score Distribution Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pie_chart_outline_rounded, size: 18, color: DefensysTokens.maroon),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Role Weight Distribution',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFBFDBFE)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF1D4ED8)),
                                            const SizedBox(width: 4),
                                            Text(
                                              activeSemesterName,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1D4ED8),
                                                fontFamily: DefensysTokens.fontFamily,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'How Panel and Peer scores combine for this PIT event. Standard default is 80 / 20.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary,
                                      fontFamily: DefensysTokens.fontFamily,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _buildWeightDistributionBar(_panelWeight, _peerWeight),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _panelWeightController,
                                          readOnly: isLocked,
                                          keyboardType: TextInputType.number,
                                          decoration: _dialogInputDecoration(
                                            labelText: 'Panel Weight (%)',
                                            prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: DefensysTokens.maroon),
                                          ),
                                          style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                          onChanged: _onPanelWeightChanged,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _peerWeightController,
                                          readOnly: isLocked,
                                          keyboardType: TextInputType.number,
                                          decoration: _dialogInputDecoration(
                                            labelText: 'Peer Weight (%)',
                                            prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFFD97706)),
                                          ),
                                          style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                          onChanged: _onPeerWeightChanged,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Slide or type to adjust weights:',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      activeTrackColor: DefensysTokens.maroon,
                                      inactiveTrackColor: const Color(0xFFD97706),
                                      thumbColor: DefensysTokens.maroon,
                                      overlayColor: DefensysTokens.maroon.withValues(alpha: 0.12),
                                      valueIndicatorColor: DefensysTokens.maroon,
                                      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                                      trackHeight: 6,
                                    ),
                                    child: Slider(
                                      value: _panelWeight.clamp(0, 100).toDouble(),
                                      min: 0,
                                      max: 100,
                                      divisions: 20,
                                      label: 'Panel: $_panelWeight% / Peer: $_peerWeight%',
                                      onChanged: isLocked
                                          ? null
                                          : (val) {
                                              final panelVal = val.toInt();
                                              final peerVal = 100 - panelVal;
                                              setState(() {
                                                _panelWeight = panelVal;
                                                _peerWeight = peerVal;
                                                _panelWeightController.text = panelVal.toString();
                                                _peerWeightController.text = peerVal.toString();
                                              });
                                              _markDirty();
                                            },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: isLocked
                                          ? null
                                          : () {
                                              setState(() {
                                                _panelWeight = 80;
                                                _peerWeight = 20;
                                                _panelWeightController.text = '80';
                                                _peerWeightController.text = '20';
                                              });
                                              _markDirty();
                                            },
                                      icon: const Icon(Icons.restore_rounded, size: 15),
                                      label: const Text('Reset to standard 80 / 20'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF475569),
                                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: DefensysTokens.fontFamily),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. Evaluation Rubrics Assignment Card
                            Builder(
                              builder: (context) {
                                final hasNoRubricsAtAll = panelRubrics.isEmpty && peerRubrics.isEmpty;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.assignment_outlined, size: 18, color: DefensysTokens.maroon),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Evaluation Rubrics Attachment',
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary,
                                              fontFamily: DefensysTokens.fontFamily,
                                            ),
                                          ),
                                          const Spacer(),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              context.go(FacultyRoutes.rubrics);
                                            },
                                            icon: const Icon(Icons.open_in_new_rounded, size: 13),
                                            label: const Text('Manage in Rubrics'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: DefensysTokens.maroon,
                                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: DefensysTokens.fontFamily),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0F9FF),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFBAE6FD)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.info_outline, size: 15, color: Color(0xFF0284C7)),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Assign published PIT rubrics to evaluate each role. You can leave as "None" and attach later before scheduling defenses.',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Color(0xFF0369A1),
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: DefensysTokens.fontFamily,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasNoRubricsAtAll) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFBEB),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFFDE68A)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
                                              const SizedBox(width: 8),
                                              const Expanded(
                                                child: Text(
                                                  'No published PIT rubrics found for this semester. Create rubrics in Evaluation Rubrics to attach.',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: Color(0xFF92400E),
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: DefensysTokens.fontFamily,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  context.go(FacultyRoutes.rubrics);
                                                },
                                                icon: const Icon(Icons.add_rounded, size: 13),
                                                label: const Text('Create Rubric'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFB45309),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: DefensysTokens.fontFamily),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      DropdownButtonFormField<int?>(
                                        initialValue: _panelRubricId,
                                        decoration: _dialogInputDecoration(
                                          labelText: 'Panel Rubric',
                                          helperText: panelRubrics.isEmpty ? 'No published panel rubrics found for this semester' : null,
                                          prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: DefensysTokens.maroon),
                                        ),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13.5, color: DefensysTokens.textPrimary),
                                        items: () {
                                          final list = <DropdownMenuItem<int?>>[
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('None (No Rubric)'),
                                            ),
                                          ];
                                          list.addAll(panelRubrics.map((r) {
                                            return DropdownMenuItem<int?>(
                                              value: int.tryParse(r['id']?.toString() ?? ''),
                                              child: Text(r['name']?.toString() ?? ''),
                                            );
                                          }));
                                          if (_panelRubricId != null && !panelRubrics.any((r) => int.tryParse(r['id']?.toString() ?? '') == _panelRubricId)) {
                                            final currentRubric = state.rubrics.firstWhere(
                                              (r) => int.tryParse(r['id']?.toString() ?? '') == _panelRubricId,
                                              orElse: () => const {},
                                            );
                                            list.add(DropdownMenuItem<int?>(
                                              value: _panelRubricId,
                                              child: Text(currentRubric['name']?.toString() ?? 'Selected Rubric'),
                                            ));
                                          }
                                          return list;
                                        }(),
                                        onChanged: isLocked ? null : (val) {
                                          setState(() => _panelRubricId = val);
                                          _markDirty();
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int?>(
                                        initialValue: _peerRubricId,
                                        decoration: _dialogInputDecoration(
                                          labelText: 'Peer Rubric',
                                          helperText: peerRubrics.isEmpty ? 'No published peer rubrics found for this semester' : null,
                                          prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFFD97706)),
                                        ),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13.5, color: DefensysTokens.textPrimary),
                                        items: () {
                                          final list = <DropdownMenuItem<int?>>[
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('None (No Rubric)'),
                                            ),
                                          ];
                                          list.addAll(peerRubrics.map((r) {
                                            return DropdownMenuItem<int?>(
                                              value: int.tryParse(r['id']?.toString() ?? ''),
                                              child: Text(r['name']?.toString() ?? ''),
                                            );
                                          }));
                                          if (_peerRubricId != null && !peerRubrics.any((r) => int.tryParse(r['id']?.toString() ?? '') == _peerRubricId)) {
                                            final currentRubric = state.peerRubrics.firstWhere(
                                              (r) => int.tryParse(r['id']?.toString() ?? '') == _peerRubricId,
                                              orElse: () => const {},
                                            );
                                            list.add(DropdownMenuItem<int?>(
                                              value: _peerRubricId,
                                              child: Text(currentRubric['name']?.toString() ?? 'Selected Rubric'),
                                            ));
                                          }
                                          return list;
                                        }(),
                                        onChanged: isLocked ? null : (val) {
                                          setState(() => _peerRubricId = val);
                                          _markDirty();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildPeerGradingAccessCard(isLocked),
                          ],
                        ),

                        // TAB 2: Deliverables
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StageDeliverablePresetsBar(
                              scope: DeliverablePresetScope.pit,
                              yearLevel: assignedPitYear,
                              currentSourceId: widget.config?['id'],
                              existingStages: [
                                ...widget.availableEvents.where((e) =>
                                    StageDeliverablePresetManager.pitEventMatchesYearLevel(
                                      e['year_level']?.toString() ?? '',
                                      assignedPitYear ?? '',
                                    )).map((e) => {
                                  'id': e['id'],
                                  'scope': 'pit',
                                  'year_level': e['year_level'],
                                  'label': e['event_name'] ?? e['name'] ?? 'PIT Event',
                                  'deliverables': e['deliverables'] ?? [],
                                }),
                              ],
                              currentDeliverables: _deliverables,
                              enabled: !isLocked,
                              onApplyDeliverables: (newDeliverables) {
                                setState(() {
                                  _deliverables.clear();
                                  _deliverables.addAll(newDeliverables);
                                  _selectedDeliverable = _deliverables.isNotEmpty ? _deliverables.first : null;
                                });
                                _markDirty();
                              },
                            ),
                            StageDeliverableCounts(
                              deliverables: _deliverables,
                              minutesRequired: false,
                            ),
                            _buildDeliverableSection(
                              title: 'Pre-Defense Requirements',
                              subtitle: 'Choose which files clear scheduling and which are due closer to the defense.',
                              icon: Icons.folder_open_rounded,
                              accentColor: const Color(0xFF0F172A),
                              bgHeaderColor: const Color(0xFFF8FAFC),
                              borderColor: const Color(0xFFE2E8F0),
                              count: preDeliverables.length,
                              buttonText: 'Add Pre-Defense',
                              onAdd: () => _addDeliverable(type: 'pre'),
                              emptyPlaceholderText: 'No pre-defense gatekeepers configured yet. (e.g. Project Proposal Manuscript, Pitch Deck)',
                              items: preDeliverables,
                              isPost: false,
                              pitYear: pitYear,
                              isLocked: isLocked,
                            ),
                            const SizedBox(height: 16),
                            _buildDeliverableSection(
                              title: 'Post-Defense Requirements & Archive',
                              subtitle: 'Deliverables required for final event clearance and repository archiving.',
                              icon: Icons.inventory_2_rounded,
                              accentColor: const Color(0xFF0F172A),
                              bgHeaderColor: const Color(0xFFF8FAFC),
                              borderColor: const Color(0xFFE2E8F0),
                              count: postDeliverables.length,
                              buttonText: 'Add Post-Defense',
                              onAdd: () => _addDeliverable(type: 'post'),
                              emptyPlaceholderText: 'No post-defense deliverables configured yet. (e.g. Final Manuscript PDF, Source Code Archive, Demo Video)',
                              items: postDeliverables,
                              isPost: true,
                              pitYear: pitYear,
                              isLocked: isLocked,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Footer Actions Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _handleClose,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: DefensysTokens.fontFamily),
                        ),
                        child: Text(isLocked ? 'Close' : 'Cancel'),
                      ),
                      const Spacer(),
                      if (_activeTab > 0) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _activeTab--);
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Back'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: DefensysTokens.fontFamily),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (_activeTab < 2)
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_activeTab == 0 && _eventNameController.text.trim().isEmpty) {
                              showValidationToast(context, 'Please enter an event name before proceeding.');
                              return;
                            }
                            if (_activeTab == 1 && (_panelWeight + _peerWeight) != 100) {
                              showValidationToast(context, 'Panel and Peer weights must total 100%.');
                              return;
                            }
                            setState(() => _activeTab++);
                          },
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: Text(_activeTab == 0 ? 'Next: Grading & Rubrics' : 'Next: Deliverables'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DefensysTokens.maroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: DefensysTokens.fontFamily),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      else if (isLocked)
                        ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white),
                          label: const Text('Secured (Read-Only)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      else
                        DefensysSaveButton(
                          height: 40,
                          onPressed: _save,
                          isSaving: state.isSaving,
                          label: widget.config != null ? 'Save Changes' : 'Save Configuration',
                          savingLabel: 'Saving…',
                          isPill: false,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

