import 'package:flutter/material.dart';
import 'widgets/semester_transition_dialog.dart';
import 'widgets/semester_calendar_fields.dart';
import 'widgets/semester_status_badge.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        ShadAccordion,
        ShadAccordionItem,
        ShadBorder,
        ShadBorderSide,
        ShadButton,
        ShadButtonSize,
        ShadDecoration,
        ShadDialog,
        ShadSwitch,
        ShadTab,
        ShadTabs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/admin/user_management_provider.dart';
import '../../../../services/defense_scheduler_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../grade_center/grade_center_shared.dart'
    show showPeerGradingHelpDialog;
import '../../../../widgets/shadcn/defensys_breadcrumb.dart';

class SemesterDetailScreen extends ConsumerStatefulWidget {
  const SemesterDetailScreen({
    super.key,
    required this.semesterId,
    this.onBack,
  });

  final int? semesterId;
  final VoidCallback? onBack;

  @override
  ConsumerState<SemesterDetailScreen> createState() =>
      _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends ConsumerState<SemesterDetailScreen> {
  int _selectedTab = 0;
  List<Map<String, dynamic>> _pitEventConfigs = [];
  bool _loadingPitConfigs = false;

  bool get _isDark => DefensysTokens.isDark(context);
  Color get _borderColor => DefensysTokens.borderOf(context);
  Color get _surfaceColor => DefensysTokens.surfaceOf(context);
  Color get _inkColor => DefensysTokens.textPrimaryOf(context);
  Color get _mutedColor => DefensysTokens.textSecondaryOf(context);
  Color get _subtleSurface =>
      _isDark ? DefensysTokens.mistPanel : DefensysTokens.background;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    ref.read(academicPeriodProvider.notifier).fetchPeriods();
    ref.read(defenseStagesProvider.notifier).fetchStages();
    ref.read(userManagementProvider.notifier).fetchUsers();
    _loadPitEvents();
  }

  Future<void> _loadPitEvents() async {
    if (widget.semesterId == null) return;
    setState(() => _loadingPitConfigs = true);
    try {
      final configs = await ref
          .read(defenseSchedulerProvider.notifier)
          .fetchPitEventConfigs(semesterId: widget.semesterId);
      if (mounted) {
        setState(() {
          _pitEventConfigs = configs;
          _loadingPitConfigs = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPitConfigs = false);
      }
    }
  }

  Map<String, dynamic>? _findSemester(AcademicPeriodState state) {
    if (widget.semesterId == null) return null;
    for (final year in state.schoolYears) {
      final rawSemesters = year['semesters'];
      if (rawSemesters is List) {
        for (final sem in rawSemesters) {
          if (sem is Map<String, dynamic> &&
              int.tryParse(sem['id']?.toString() ?? '') == widget.semesterId) {
            return {
              ...sem,
              'school_year_label': year['label'],
              'school_year_id': year['id'],
            };
          }
        }
      }
    }
    if (state.activeSemester != null &&
        int.tryParse(state.activeSemester!['id']?.toString() ?? '') ==
            widget.semesterId) {
      return state.activeSemester;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(academicPeriodProvider);
    final userState = ref.watch(userManagementProvider);
    final semester = _findSemester(state);

    if (state.isLoading && semester == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (semester == null) {
      return Scaffold(
        backgroundColor: DefensysTokens.backgroundOf(context),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: DefensysEmptyState.table(
            icon: Icons.error_outline_rounded,
            title: 'Semester not found',
            description: 'This semester does not exist or has been deleted.',
            primaryAction: DefensysEmptyAction(
              label: 'Back to academic periods',
              icon: Icons.arrow_back_rounded,
              onPressed: _goBack,
            ),
          ),
        ),
      );
    }

    final yearLabel =
        semester['school_year_label']?.toString() ??
        semester['school_year']?.toString() ??
        '';
    final termName = semester['label']?.toString() ?? 'Semester';
    final isActive = semester['is_active'] == true;

    return DefensysShadcnScope(
      maroonActions: true,
      child: Scaffold(
        backgroundColor: DefensysTokens.backgroundOf(context),
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 600 ? 16 : 28,
              20,
              constraints.maxWidth < 600 ? 16 : 28,
              48,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefensysBreadcrumb(
                      onBack: _goBack,
                      backLabel: 'Back to academic periods',
                      items: [DefensysBreadcrumbItem(label: 'A.Y. $yearLabel')],
                    ),
                    const SizedBox(height: 24),
                    _buildTermHeader(
                      semester,
                      termName,
                      isActive,
                      state.isSaving,
                    ),
                    const SizedBox(height: 24),
                    _buildTabBar(),
                    const SizedBox(height: 22),
                    switch (_selectedTab) {
                      0 => _buildCapstoneTab(semester, state.isSaving),
                      1 => _buildPitTab(state.isSaving, userState.users),
                      _ => _buildMasterControlsTab(semester, state.isSaving),
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AdminRoutes.academicPeriods);
    }
  }

  Text _copy(
    String text, {
    bool muted = false,
    double size = 14,
    FontWeight weight = FontWeight.w400,
  }) => Text(
    text,
    style: TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: size,
      fontWeight: weight,
      color: muted ? _mutedColor : _inkColor,
    ),
  );

  Widget _buildTermHeader(
    Map<String, dynamic> semester,
    String termName,
    bool isActive,
    bool isSaving,
  ) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _copy(termName, size: 30, weight: FontWeight.w600),
            SemesterStatusBadge(isActive: isActive),
          ],
        ),
      ],
    );
    final calendar = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconTile(LucideIcons.calendar, size: 42),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copy('Semester dates', muted: true, size: 12),
              const SizedBox(height: 3),
              _copy(
                semesterDateRange(semester),
                size: 13,
                weight: FontWeight.w500,
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          enabled: !isSaving,
          onPressed: () => showSemesterCalendarEditor(context, ref, semester),
          child: const Text('Edit dates'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            850;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (narrow) ...[
              identity,
              const SizedBox(height: 20),
              calendar,
            ] else
              Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 24),
                  calendar,
                ],
              ),
            if (!isActive) ...[
              const SizedBox(height: 18),
              ShadButton(
                size: ShadButtonSize.sm,
                enabled: !isSaving,
                onPressed: () => _activateThisSemester(semester),
                child: const Text('Set as Active Semester'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTabBar() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: _borderColor)),
    ),
    child: ShadTabs<int>(
      value: _selectedTab,
      onChanged: (value) => setState(() => _selectedTab = value),
      scrollable: true,
      gap: 0,
      tabsGap: 8,
      padding: EdgeInsets.zero,
      decoration: ShadDecoration.none,
      tabBarAlignment: Alignment.centerLeft,
      tabs: [
        for (final entry in [
          'Capstone',
          'PIT',
          'General settings',
        ].asMap().entries)
          ShadTab(
            value: entry.key,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            height: 50,
            selectedBackgroundColor: Colors.transparent,
            selectedHoverBackgroundColor: Colors.transparent,
            selectedForegroundColor: DefensysTokens.maroonTextOf(context),
            foregroundColor: _mutedColor,
            selectedShadows: const [],
            decoration: ShadDecoration(
              border: ShadBorder(
                radius: BorderRadius.zero,
                bottom: ShadBorderSide(
                  color: DefensysTokens.maroonTextOf(context),
                  width: entry.key == _selectedTab ? 2 : 0,
                ),
              ),
            ),
            child: Text(entry.value),
          ),
      ],
    ),
  );

  Widget _buildCapstoneTab(Map<String, dynamic> semester, bool isSaving) {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    final phase = semester['capstone_program_phase']?.toString();
    final isCapstone1 = phase == 'capstone_1';
    final isCapstone2 = phase == 'capstone_2';
    final canAdd = semester['capstone_team_creation_enabled'] == true;
    final policies = _card(
      title: 'Capstone this semester',
      icon: LucideIcons.graduationCap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final course = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _copy('Course', muted: true, size: 12),
                    const SizedBox(height: 8),
                    _copy(
                      isCapstone1
                          ? 'Capstone 1'
                          : isCapstone2
                          ? 'Capstone 2'
                          : 'Not offered',
                      size: 24,
                      weight: FontWeight.w600,
                    ),
                  ],
                );
                final intake = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _copy('Adding teams', muted: true, size: 12),
                    const SizedBox(height: 10),
                    _badge(
                      isCapstone2
                          ? 'Continuing teams only'
                          : canAdd
                          ? 'Allowed'
                          : 'Not allowed',
                      good: isCapstone1 && canAdd,
                    ),
                    const SizedBox(height: 8),
                    _copy(
                      isCapstone2
                          ? 'Register verified continuing students in Student Teams.'
                          : canAdd
                          ? 'Create or import teams in Student Teams.'
                          : 'New teams cannot be added this semester.',
                      muted: true,
                      size: 13,
                    ),
                  ],
                );
                if (constraints.maxWidth /
                        MediaQuery.textScalerOf(context).scale(1) <
                    490) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [course, const SizedBox(height: 24), intake],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: course),
                    Container(
                      width: 1,
                      height: 86,
                      color: _borderColor,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    Expanded(flex: 6, child: intake),
                  ],
                );
              },
            ),
          ),
          if (isCapstone1 || isCapstone2) ...[
            Divider(height: 1, color: _borderColor),
            Container(
              color: _subtleSurface,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _disclosure(
                key: 'capstone-continuation',
                title: isCapstone1
                    ? 'Continuing to Capstone 2'
                    : 'Moving to the next semester',
                child: _copy(
                  isCapstone1
                      ? 'You’ll review which teams can continue to Capstone 2 before activating the next semester.'
                      : 'Review team outcomes before activating the next semester. Completed and failed teams keep their records in History.',
                  muted: true,
                  size: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final evaluation = _card(
      title: 'Evaluation access',
      icon: LucideIcons.slidersHorizontal,
      description: 'Capstone · this semester',
      child: Column(
        children: [
          _evaluationToggleTile(
            key: const ValueKey('capstone-peer-access'),
            title: 'Student peer evaluation',
            subtitle: 'Allow students to submit peer evaluations.',
            value: semester['capstone_peer_evaluation_enabled'] != false,
            enabled: !isSaving && semesterId != null,
            onChanged: (value) => ref
                .read(academicPeriodProvider.notifier)
                .updateSemesterEvaluationSettings(
                  semesterId!,
                  peerEvaluationEnabled: value,
                ),
          ),
          Divider(height: 1, color: _borderColor),
          _evaluationToggleTile(
            key: const ValueKey('capstone-adviser-access'),
            title: 'Adviser grading',
            subtitle: 'Allow assigned advisers to submit grades.',
            value: semester['capstone_adviser_grading_enabled'] != false,
            enabled: !isSaving && semesterId != null,
            onChanged: (value) => ref
                .read(academicPeriodProvider.notifier)
                .updateSemesterEvaluationSettings(
                  semesterId!,
                  adviserGradingEnabled: value,
                ),
          ),
          Divider(height: 1, color: _borderColor),
          Container(
            width: double.infinity,
            color: _subtleSurface,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _copy(
                  'PIT peer evaluation is controlled per event.',
                  muted: true,
                  size: 13,
                ),
                const SizedBox(height: 8),
                ShadButton.link(
                  size: ShadButtonSize.sm,
                  padding: EdgeInsets.zero,
                  foregroundColor: DefensysTokens.maroonTextOf(context),
                  hoverForegroundColor: DefensysTokens.maroonTextOf(context),
                  onPressed: () =>
                      showPeerGradingHelpDialog(context, isPit: false),
                  child: const Text('Peer evaluation guide'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            policies,
            const SizedBox(height: 24),
            _buildDefenseStages(),
          ],
        );
        if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            850) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 24), evaluation],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: left),
            const SizedBox(width: 24),
            Expanded(flex: 5, child: evaluation),
          ],
        );
      },
    );
  }

  Future<void> _openStages([Map<String, dynamic>? stage]) async {
    final id = int.tryParse(stage?['id']?.toString() ?? '');
    await context.push(
      id == null ? AdminRoutes.defenseStages : AdminRoutes.defenseStageEdit(id),
    );
    if (mounted) ref.read(defenseStagesProvider.notifier).fetchStages();
  }

  Widget _buildDefenseStages() {
    final state = ref.watch(defenseStagesProvider);
    return _card(
      title: 'Defense stages',
      icon: LucideIcons.layers,
      trailing: state.isLoading
          ? null
          : state.error != null
          ? _badge('Could not load', warning: true)
          : Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _badge(
                  state.stages.isEmpty
                      ? 'Not configured'
                      : '${state.stages.length} configured',
                  warning: state.stages.isEmpty,
                ),
                if (state.stages.isNotEmpty)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => _openStages(),
                    child: const Text('Manage stages'),
                  ),
              ],
            ),
      child: state.isLoading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : state.error != null
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _copy(
                    'Could not load defense stages. Try again.',
                    muted: true,
                  ),
                  const SizedBox(height: 12),
                  ShadButton.outline(
                    onPressed: () =>
                        ref.read(defenseStagesProvider.notifier).fetchStages(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : state.stages.isEmpty
          ? Container(
              width: double.infinity,
              color: _subtleSurface,
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _copy(
                    'Set up the defense sequence',
                    size: 18,
                    weight: FontWeight.w600,
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _copy(
                      'Add the stages and requirements students will use.',
                      muted: true,
                      size: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShadButton(
                    onPressed: () => _openStages(),
                    leading: const Icon(LucideIcons.plus, size: 16),
                    child: const Text('Configure stages'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (final entry in state.stages.asMap().entries)
                  _buildStagePipelineRow(entry.key + 1, entry.value),
              ],
            ),
    );
  }

  Widget _buildPitTab(bool isSaving, List<Map<String, dynamic>> users) {
    final userState = ref.watch(userManagementProvider);
    final schedulerSaving = ref.watch(
      defenseSchedulerProvider.select((state) => state.isSaving),
    );
    const years = {
      '1st Year': 'Concept pitch',
      '2nd Year': 'System design',
      '3rd Year': 'Capstone readiness',
    };
    final matched = <Map<String, dynamic>>{};
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final year in years.keys) {
      groups[year] = _pitEventConfigs
          .where((event) => _eventMatchesCohort(event, year))
          .toList();
      matched.addAll(groups[year]!);
    }
    final additional = _pitEventConfigs
        .where((event) => !matched.contains(event))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          title: 'Year coordinators & events',
          icon: LucideIcons.users,
          description: 'Coordinators manage each year’s pitch events.',
          child: Column(
            children: [
              for (final entry in years.entries) ...[
                if (entry.key != years.keys.first)
                  Divider(height: 1, color: _borderColor),
                _buildPitCohort(
                  entry.key,
                  entry.value,
                  _findPitLeadForYear(users, entry.key),
                  groups[entry.key]!,
                  isSaving || schedulerSaving,
                  loadingLead: userState.isLoading,
                  leadError: userState.error != null,
                ),
              ],
            ],
          ),
        ),
        if (additional.isNotEmpty) ...[
          const SizedBox(height: 18),
          _card(
            title: 'Other PIT events',
            child: Column(
              children: [
                for (final event in additional)
                  _buildCohortEventItem(event, isSaving || schedulerSaving),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        _copy(
          'Panel and peer weights are configured per event. PIT does not use adviser grading.',
          muted: true,
          size: 13,
        ),
        const SizedBox(height: 16),
        _disclosure(
          key: 'pit-responsibilities',
          title: 'Responsibilities & evaluation rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copy(
                'Coordinators manage teams, panel assignments, deliverables, and schedules. Administrators assign coordinators and oversee evaluation access.',
                muted: true,
                size: 12,
              ),
              const SizedBox(height: 10),
              ShadButton.link(
                size: ShadButtonSize.sm,
                padding: EdgeInsets.zero,
                foregroundColor: DefensysTokens.maroonTextOf(context),
                hoverForegroundColor: DefensysTokens.maroonTextOf(context),
                onPressed: () =>
                    showPeerGradingHelpDialog(context, isPit: true),
                child: const Text('PIT peer evaluation guide'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openCoordinators() async {
    await context.push(AdminRoutes.users);
    if (mounted) ref.read(userManagementProvider.notifier).fetchUsers();
  }

  Widget _buildPitCohort(
    String year,
    String course,
    Map<String, dynamic>? lead,
    List<Map<String, dynamic>> events,
    bool isSaving, {
    required bool loadingLead,
    required bool leadError,
  }) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _copy(year, size: 15, weight: FontWeight.w600),
        const SizedBox(height: 5),
        _copy(course, muted: true, size: 13),
      ],
    );
    final coordinator = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loadingLead)
          _copy('Loading coordinator…', muted: true, size: 12)
        else if (leadError)
          _copy('Could not load coordinator.', muted: true, size: 12)
        else if (lead == null)
          _badge('No coordinator', warning: true)
        else
          _copy(_getUserDisplayName(lead), weight: FontWeight.w500),
        const SizedBox(height: 4),
        _copy(
          _loadingPitConfigs
              ? 'Loading events…'
              : events.isEmpty
              ? 'No events configured'
              : '${events.length} ${events.length == 1 ? 'event' : 'events'} configured',
          muted: true,
          size: 12,
        ),
      ],
    );
    final action = ShadButton.outline(
      size: ShadButtonSize.sm,
      enabled: !loadingLead,
      onPressed: _openCoordinators,
      trailing: const Icon(LucideIcons.arrowUpRight, size: 14),
      child: Text(
        leadError
            ? 'View users'
            : lead == null
            ? 'Assign lead'
            : 'Manage lead',
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 12),
                    coordinator,
                    const SizedBox(height: 12),
                    action,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  Expanded(child: coordinator),
                  const SizedBox(width: 16),
                  action,
                ],
              );
            },
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 4),
            _disclosure(
              key: 'pit-events-$year',
              title: 'View events · $year',
              child: Column(
                children: [
                  for (final config in events)
                    _buildCohortEventItem(config, isSaving),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCohortEventItem(Map<String, dynamic> config, bool isSaving) {
    final eventName = config['event_name']?.toString() ?? 'PIT event';
    final panel = config['panel_weight']?.toString() ?? '—';
    final peer = config['peer_weight']?.toString() ?? '—';
    final isLocked = config['is_locked'] == true;
    final peerEnabled = config['peer_grading_enabled'] != false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _copy(eventName, weight: FontWeight.w500),
          const SizedBox(height: 5),
          _copy('Panel $panel% · Peer $peer%', muted: true, size: 12),
          if (isLocked) ...[
            const SizedBox(height: 7),
            _badge('Settings locked', warning: true),
            const SizedBox(height: 5),
            _copy(
              config['lock_reason']?.toString() ??
                  'Defenses are scheduled for this event.',
              muted: true,
              size: 12,
            ),
          ],
          _evaluationToggleTile(
            key: ValueKey('pit-peer-${config['id'] ?? eventName}'),
            title: 'Student peer evaluation',
            subtitle: peerEnabled
                ? 'Enabled for this event.'
                : 'Disabled for this event.',
            value: peerEnabled,
            enabled: !isSaving && !isLocked,
            padding: const EdgeInsets.only(top: 12),
            onChanged: (value) => _togglePitEventPeerEval(config, value),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterControlsTab(Map<String, dynamic> semester, bool isSaving) {
    final isActive = semester['is_active'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          title: 'Semester details',
          icon: LucideIcons.calendar,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _copy('Semester dates', weight: FontWeight.w500),
                        const SizedBox(height: 5),
                        _copy(
                          semesterDateRange(semester),
                          muted: true,
                          size: 12,
                        ),
                      ],
                    ),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      enabled: !isSaving,
                      onPressed: () =>
                          showSemesterCalendarEditor(context, ref, semester),
                      child: const Text('Edit dates'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _borderColor),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _copy('Operating semester', weight: FontWeight.w500),
                    const SizedBox(height: 5),
                    _copy(
                      isActive
                          ? 'Schedules, submissions, and grades use this semester.'
                          : 'This semester is inactive. Review its setup before activating it.',
                      muted: true,
                      size: 12,
                    ),
                    if (!isActive) ...[
                      const SizedBox(height: 14),
                      ShadButton(
                        size: ShadButtonSize.sm,
                        enabled: !isSaving,
                        onPressed: () => _activateThisSemester(semester),
                        child: const Text('Activate this semester'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _copy(
              'To change the active semester, open another semester in Academic Periods and review its transition.',
              muted: true,
              size: 12,
            ),
          ),
        const SizedBox(height: 24),
        _disclosure(
          key: 'semester-advanced',
          title: 'Advanced settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copy('Delete semester', weight: FontWeight.w500),
              const SizedBox(height: 5),
              _copy(
                isActive
                    ? 'The active semester cannot be deleted.'
                    : 'Only semesters without teams, grades, or enrollments can be deleted.',
                muted: true,
                size: 12,
              ),
              const SizedBox(height: 14),
              ShadButton.destructive(
                size: ShadButtonSize.sm,
                enabled: !isActive && !isSaving,
                onPressed: () => _deleteThisSemester(semester),
                child: const Text('Delete semester'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStagePipelineRow(
    int index,
    Map<String, dynamic> stage,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _subtleSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: _copy(
                '$index',
                muted: true,
                size: 13,
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _copy(
                    stage['label']?.toString() ?? 'Stage',
                    weight: FontWeight.w500,
                  ),
                  if (stage['description']?.toString().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    _copy(
                      stage['description'].toString(),
                      muted: true,
                      size: 12,
                    ),
                  ],
                  if (stage['is_presentation_only'] == true) ...[
                    const SizedBox(height: 5),
                    _badge('Presentation only'),
                  ],
                ],
              ),
            ),
          ],
        );
        final action = ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _openStages(stage),
          child: const Text('Configure'),
        );
        if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            450) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 12), action],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 14),
            action,
          ],
        );
      },
    ),
  );

  Widget _card({
    required String title,
    required Widget child,
    String? description,
    Widget? trailing,
    IconData? icon,
  }) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _surfaceColor,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
      border: Border.all(color: _borderColor),
      boxShadow: [
        if (!_isDark)
          BoxShadow(
            color: DefensysTokens.textPrimary.withValues(alpha: 0.025),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final heading = Row(
                children: [
                  if (icon != null) ...[
                    _iconTile(icon, size: 36),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _copy(title, size: 16, weight: FontWeight.w600),
                        if (description != null) ...[
                          const SizedBox(height: 4),
                          _copy(description, muted: true, size: 13),
                        ],
                      ],
                    ),
                  ),
                ],
              );
              if (trailing == null) return heading;
              if (constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  450) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 12), trailing],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  trailing,
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: _borderColor),
        child,
      ],
    ),
  );

  Widget _iconTile(IconData icon, {double size = 44}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _subtleSurface,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
    ),
    child: Icon(
      icon,
      size: size > 40 ? 21 : 18,
      color: DefensysTokens.maroonTextOf(context),
    ),
  );

  Widget _badge(String label, {bool good = false, bool warning = false}) {
    final color = good
        ? (_isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : warning
        ? (_isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E))
        : _mutedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: good
            ? (_isDark ? const Color(0xFF15382D) : const Color(0xFFECFDF5))
            : warning
            ? (_isDark ? const Color(0xFF372D1D) : const Color(0xFFFFFBEB))
            : DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _disclosure({
    required String key,
    required String title,
    required Widget child,
  }) => ShadAccordion<String>(
    children: [
      ShadAccordionItem(
        key: ValueKey(key),
        value: key,
        title: _copy(title, muted: true, size: 13),
        underlineTitleOnHover: false,
        separator: const SizedBox.shrink(),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ],
  );

  Widget _evaluationToggleTile({
    Key? key,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 22,
    ),
  }) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copy(title, weight: FontWeight.w500),
              const SizedBox(height: 6),
              _copy(subtitle, muted: true, size: 13),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Semantics(
          label: title,
          child: ShadSwitch(
            key: key,
            value: value,
            enabled: enabled,
            thumbColor: Colors.white,
            checkedTrackColor: DefensysTokens.maroonOf(context),
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    ),
  );

  Map<String, dynamic>? _findPitLeadForYear(
    List<Map<String, dynamic>> users,
    String yearKey,
  ) {
    for (final user in users) {
      final isLead =
          user['is_pit_lead'] == true ||
          (user['roles'] is Map && user['roles']['is_pit_lead'] == true);
      if (!isLead) continue;

      final rawYear =
          (user['pit_lead_year'] ??
                  (user['roles'] is Map
                      ? user['roles']['pit_lead_year']
                      : null))
              ?.toString()
              .trim()
              .toLowerCase() ??
          '';

      if (yearKey == '1st Year') {
        if (rawYear.contains('1st') ||
            rawYear.contains('first') ||
            rawYear.contains('101')) {
          return user;
        }
      } else if (yearKey == '2nd Year') {
        if (rawYear.contains('2nd') ||
            rawYear.contains('second') ||
            rawYear.contains('201')) {
          return user;
        }
      } else if (yearKey == '3rd Year') {
        if (rawYear.contains('3rd') ||
            rawYear.contains('third') ||
            rawYear.contains('301')) {
          return user;
        }
      }
    }
    return null;
  }

  String _getUserDisplayName(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return '$first $last'.trim();
    }
    final name = (user['name'] ?? user['username'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return (user['email'] ?? 'Faculty Lead').toString().trim();
  }

  bool _eventMatchesCohort(Map<String, dynamic> config, String yearKey) {
    final name = (config['event_name']?.toString() ?? '').toLowerCase();
    final code = (config['event_code']?.toString() ?? '').toLowerCase();
    final combined = '$name $code';

    if (yearKey == '1st Year') {
      return combined.contains('1st') ||
          combined.contains('first') ||
          combined.contains('101') ||
          combined.contains('concept');
    } else if (yearKey == '2nd Year') {
      return combined.contains('2nd') ||
          combined.contains('second') ||
          combined.contains('201') ||
          combined.contains('design') ||
          combined.contains('architect');
    } else if (yearKey == '3rd Year') {
      return combined.contains('3rd') ||
          combined.contains('third') ||
          combined.contains('301') ||
          combined.contains('readiness') ||
          combined.contains('pre-capstone');
    }
    return false;
  }

  Future<void> _togglePitEventPeerEval(
    Map<String, dynamic> config,
    bool newValue,
  ) async {
    if (config['is_locked'] == true) {
      showValidationToast(
        context,
        config['lock_reason']?.toString() ??
            'Peer evaluation settings are locked because defenses are scheduled.',
      );
      return;
    }

    final previousValue = config['peer_grading_enabled'] != false;
    final eventName = config['event_name']?.toString() ?? 'PIT Event';

    setState(() {
      config['peer_grading_enabled'] = newValue;
    });

    final payload = <String, dynamic>{
      if (widget.semesterId != null) 'semester_id': widget.semesterId,
      'event_name': config['event_name'],
      if (config['event_code'] != null) 'event_code': config['event_code'],
      'panel_weight': config['panel_weight'] is int
          ? config['panel_weight']
          : int.tryParse(config['panel_weight']?.toString() ?? '80') ?? 80,
      'peer_weight': config['peer_weight'] is int
          ? config['peer_weight']
          : int.tryParse(config['peer_weight']?.toString() ?? '20') ?? 20,
      if (config['panel_rubric_id'] != null)
        'panel_rubric_id': config['panel_rubric_id'],
      if (config['peer_rubric_id'] != null)
        'peer_rubric_id': config['peer_rubric_id'],
      if (config['archive_file_template'] != null)
        'archive_file_template': config['archive_file_template'],
      'deliverables': config['deliverables'] ?? [],
      'peer_grading_enabled': newValue,
    };

    final success = await ref
        .read(defenseSchedulerProvider.notifier)
        .savePitEventConfig(payload);

    if (mounted) {
      if (success) {
        showSuccessToast(
          context,
          newValue
              ? 'Peer evaluation enabled for $eventName.'
              : 'Peer evaluation disabled for $eventName.',
        );
      } else {
        setState(() {
          config['peer_grading_enabled'] = previousValue;
        });
        final err =
            ref.read(defenseSchedulerProvider).error ??
            'Failed to update peer evaluation setting.';
        showErrorToast(context, err);
      }
    }
  }

  Future<void> _activateThisSemester(Map<String, dynamic> semester) async {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    if (semesterId == null) return;

    final confirmed = await showSemesterTransitionReview(
      context,
      ref,
      semesterId,
    );
    if (confirmed == true && mounted) {
      context.go('/admin/student-teams');
    }
  }

  Future<void> _deleteThisSemester(Map<String, dynamic> semester) async {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    if (semesterId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DefensysShadcnScope(
        maroonActions: true,
        child: ShadDialog(
          title: const Text('Delete semester?'),
          description: const Text(
            'Permanently delete this semester configuration.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ShadButton.destructive(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(academicPeriodProvider.notifier)
          .deleteSemester(semesterId);
      if (success && mounted) {
        if (widget.onBack != null) {
          widget.onBack!();
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go(AdminRoutes.academicPeriods);
        }
      }
    }
  }
}
