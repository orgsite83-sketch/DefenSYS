import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/academic_period_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../../../widgets/shadcn/workflow_step_progress.dart';

Future<bool?> showSemesterTransitionReview(
  BuildContext context,
  WidgetRef ref,
  int semesterId,
) async {
  final preview = await ref
      .read(academicPeriodProvider.notifier)
      .fetchTransitionPreview(semesterId);
  if (!context.mounted || preview == null) return false;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        SemesterTransitionDialog(semesterId: semesterId, preview: preview),
  );
}

/// Calendar activation applies existing academic outcomes; it never authorizes recovery.
class SemesterTransitionDialog extends ConsumerStatefulWidget {
  const SemesterTransitionDialog({
    super.key,
    required this.semesterId,
    required this.preview,
    this.creationDraft,
    this.schoolYearId,
  });
  final int semesterId;
  final Map<String, dynamic> preview;
  final Map<String, dynamic>? creationDraft;
  final int? schoolYearId;

  @override
  ConsumerState<SemesterTransitionDialog> createState() =>
      _SemesterTransitionDialogState();
}

class _SemesterTransitionDialogState
    extends ConsumerState<SemesterTransitionDialog> {
  late Map<String, dynamic> _preview;
  final _reason = TextEditingController();
  final _search = TextEditingController();
  int _step = 0, _page = 0;
  bool _busy = false, _force = false;
  String? _error;
  late final _requestId =
      '${widget.semesterId}-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  Color get _muted => DefensysTokens.textSecondaryOf(context);
  Map get _review => _preview['capstone_review'] as Map? ?? {};
  List<Map<String, dynamic>> get _teams => (_review['teams'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  bool get _blocked => _preview['can_switch'] == false;
  bool get _canSubmit =>
      !_busy && (!_blocked || (_force && _reason.text.trim().isNotEmpty));

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
  }

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final notifier = ref.read(academicPeriodProvider.notifier);
    final result = widget.creationDraft == null
        ? await notifier.fetchTransitionPreview(widget.semesterId)
        : await notifier.fetchCreateTransitionPreview(
            widget.schoolYearId!,
            widget.creationDraft!,
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) {
        _preview = result;
        _step = 0;
        _page = 0;
        _force = false;
        _error = null;
      } else {
        _error = ref.read(academicPeriodProvider).error;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(academicPeriodProvider.notifier);
    final activation = <String, dynamic>{
      'force': _force,
      'reason': _reason.text.trim(),
      'preview_revision': _preview['preview_revision']?.toString() ?? '',
      'request_id': _requestId,
    };
    final ok = widget.creationDraft == null
        ? await notifier.activateSemester(
            widget.semesterId,
            force: _force,
            reason: _reason.text.trim(),
            previewRevision: activation['preview_revision'] as String,
            requestId: _requestId,
          )
        : await notifier.addSemester(
            widget.schoolYearId!,
            widget.creationDraft!['label'] as String,
            startsOn: widget.creationDraft!['starts_on'] as String,
            endsOn: widget.creationDraft!['ends_on'] as String,
            setActive: true,
            activation: activation,
          );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          ref.read(academicPeriodProvider).error ??
          'The semester switch could not be saved.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefensysShadcnScope(
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: DefensysTokens.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        child: SizedBox(
          width: 880,
          height: min(720, MediaQuery.sizeOf(context).height - 40),
          child: DefaultTextStyle(
            style: DefensysTokens.body.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Review semester switch',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                          ),
                        ),
                      ),
                      ShadButton.ghost(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Icon(LucideIcons.x, size: 18),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: WorkflowStepProgress(
                    currentStep: _step + 1,
                    labels: const ['Review teams', 'Confirm'],
                    compactLabels: const ['Review', 'Confirm'],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          _note(_error!, warning: true),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ShadButton.ghost(
                              onPressed: _busy ? null : _refresh,
                              child: const Text('Refresh review'),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_step == 0) _reviewStep() else _confirmStep(),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ShadButton.outline(
                        onPressed: _busy
                            ? null
                            : () {
                                if (_step == 0) {
                                  Navigator.pop(context, false);
                                } else {
                                  setState(() => _step = 0);
                                }
                              },
                        child: Text(_step == 0 ? 'Cancel' : 'Back'),
                      ),
                      ShadButton(
                        enabled: !_busy && (_step != 1 || _canSubmit),
                        backgroundColor: DefensysTokens.maroonOf(context),
                        foregroundColor: Colors.white,
                        onPressed: _busy || (_step == 1 && !_canSubmit)
                            ? null
                            : _step == 1
                            ? _submit
                            : () => setState(() => _step = 1),
                        child: Text(
                          _busy
                              ? 'Saving…'
                              : _step == 1
                              ? 'Confirm switch'
                              : 'Continue',
                        ),
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

  Widget _reviewStep() {
    final source = _preview['current_semester'] as Map?;
    final target = _preview['target_semester'] as Map?;
    final query = _search.text.toLowerCase();
    final filtered = _teams
        .where(
          (r) => '${r['name']} ${r['project_title']} ${r['outcome']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    final pages = max(1, (filtered.length / 20).ceil());
    final page = min(_page, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${source?['display_name'] ?? 'Current period'} → ${target?['display_name'] ?? target?['label'] ?? 'Next period'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Text(
          '${_teams.length} outgoing Capstone teams',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ShadInput(
          controller: _search,
          placeholder: const Text('Search team, project, or outcome'),
          onChanged: (_) => setState(() => _page = 0),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _note(
            _teams.isEmpty
                ? 'No Capstone teams need migration.'
                : 'No teams match your search.',
          ),
        ...filtered.skip(page * 20).take(20).map(_teamRow),
        if (pages > 1)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              ShadButton.ghost(
                onPressed: page > 0 ? () => setState(() => _page--) : null,
                child: const Text('Previous'),
              ),
              Text('${page + 1} / $pages'),
              ShadButton.ghost(
                onPressed: page + 1 < pages
                    ? () => setState(() => _page++)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _teamRow(Map<String, dynamic> team) {
    final ready = team['can_include'] == true;
    final destination = team['destination'];
    final label = ready
        ? 'Ready for Capstone 2'
        : switch (destination) {
            'history' => 'Completed · History',
            'failed_history' => 'Failed · History',
            _ => 'Needs review',
          };
    final dark = DefensysTokens.isDark(context);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: ready
            ? DefensysTokens.success.withValues(alpha: dark ? .15 : .09)
            : DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: ready
              ? (dark ? const Color(0xFF6EE7B7) : DefensysTokens.successText)
              : _muted,
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          team['name']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          team['project_title']?.toString() ?? '',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        if (ready && team['section_progression'] is Map) ...[
          const SizedBox(height: 4),
          Text(
            (team['section_progression']['section']?.toString().isNotEmpty ?? false)
                ? 'Section: ${team['section_progression']['source_section']} → ${team['section_progression']['section']}'
                : 'Section needs review; enrollment remains separate.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        if (!ready && (team['reason']?.toString().isNotEmpty ?? false)) ...[
          const SizedBox(height: 4),
          Text(
            team['reason'].toString(),
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 9), badge],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  badge,
                ],
              ),
      ),
    );
  }

  Widget _confirmStep() {
    final continuing = _teams.where((t) => t['can_include'] == true).length;
    final completed = _teams.where((t) => t['destination'] == 'history').length;
    final failed = _teams
        .where((t) => t['destination'] == 'failed_history')
        .length;
    final review = _teams.length - continuing - completed - failed;
    final pending = _teams.any(
      (t) => t['can_include'] == true && t['pending_enrollment'] == true,
    );
    final effects = (_preview['effects'] as List? ?? []).whereType<Map>();
    final issues = (_preview['issues'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final source = _preview['current_semester'] as Map?;
    final target = _preview['target_semester'] as Map?;
    final pitCount =
        (_preview['impact_counts'] as Map?)?['pit_teams'] as int? ?? 0;
    final newIntake =
        (_preview['capstone_review'] as Map?)?['kind'] == 'close_cycle';
    final successColor = DefensysTokens.isDark(context)
        ? const Color(0xFF6EE7B7)
        : DefensysTokens.successText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          key: const ValueKey('semester-switch-summary'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Semester switch summary',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                ),
                if (!_blocked)
                  ShadBadge.secondary(
                    backgroundColor: DefensysTokens.success.withValues(
                      alpha: .1,
                    ),
                    foregroundColor: successColor,
                    child: const Text('Ready to activate'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final outgoing = _semesterSummaryCard(
                  cardKey: const ValueKey('semester-switch-outgoing'),
                  heading: 'Outgoing semester',
                  period: '${source?['display_name'] ?? 'No active semester'}',
                  children: [
                    _teamCount(pitCount, 'PIT'),
                    const SizedBox(height: 5),
                    _cardDescription('Stay in this semester'),
                    if (completed + failed + review > 0) ...[
                      const SizedBox(height: 16),
                      Divider(
                        height: 1,
                        color: DefensysTokens.borderOf(context),
                      ),
                      const SizedBox(height: 12),
                      if (completed > 0)
                        _cardDescription(
                          '$completed completed Capstone ${completed == 1 ? 'team' : 'teams'} · History',
                        ),
                      if (failed > 0)
                        _cardDescription(
                          '$failed failed Capstone ${failed == 1 ? 'team' : 'teams'} · History',
                        ),
                      if (review > 0)
                        _cardDescription(
                          '$review Capstone ${review == 1 ? 'team requires' : 'teams require'} review',
                        ),
                    ],
                  ],
                );
                final incoming = _semesterSummaryCard(
                  cardKey: const ValueKey('semester-switch-incoming'),
                  heading: 'Next active semester',
                  period:
                      '${target?['display_name'] ?? target?['label'] ?? 'Next semester'}',
                  continuing: continuing > 0,
                  children: [
                    if (continuing > 0) ...[
                      _teamCount(continuing, 'Capstone', color: successColor),
                      const SizedBox(height: 5),
                      Text(
                        'Continue to Capstone 2',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: successColor,
                        ),
                      ),
                    ] else ...[
                      Text(
                        newIntake
                            ? 'New Capstone 1 intake'
                            : 'No Capstone teams moving',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _cardDescription(
                        newIntake
                            ? 'Import a new roster after activation.'
                            : 'Existing team records stay in the outgoing semester.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Divider(height: 1, color: DefensysTokens.borderOf(context)),
                    const SizedBox(height: 12),
                    const Text(
                      'New PIT rosters',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _cardDescription('PIT starts fresh next semester.'),
                  ],
                );
                if (constraints.maxWidth < 640) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      outgoing,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Icon(
                          LucideIcons.arrowDown,
                          size: 18,
                          color: _muted,
                        ),
                      ),
                      incoming,
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: outgoing),
                      SizedBox(
                        width: 40,
                        child: Center(
                          child: Icon(
                            LucideIcons.arrowRight,
                            size: 18,
                            color: _muted,
                          ),
                        ),
                      ),
                      Expanded(child: incoming),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ...effects.map(
              (effect) => effect['key'] == 'pit_teams'
                  ? const SizedBox.shrink()
                  : _switchDetail(
                      LucideIcons.lockKeyhole,
                      effect['message'].toString(),
                    ),
            ),
            if (pending)
              _switchDetail(
                LucideIcons.users,
                'Student enrollment can be rolled over after this switch.',
              ),
          ],
        ),
        if (issues.isNotEmpty || _blocked) ...[
          const SizedBox(height: 18),
          ShadCard(
            key: const ValueKey('semester-switch-attention'),
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            backgroundColor: DefensysTokens.goldOf(
              context,
            ).withValues(alpha: .05),
            shadows: const [],
            radius: BorderRadius.circular(8),
            border: ShadBorder.all(
              color: DefensysTokens.goldOf(context).withValues(alpha: .4),
              width: 1,
              radius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.circleAlert,
                      size: 18,
                      color: DefensysTokens.goldOf(context),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'Needs attention before switching',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Resolve these checks before activating the semester.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                ),
                ...issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Text(
                          issue['message']?.toString() ?? '',
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                        if (issue['route'] != null)
                          ShadButton.outline(
                            onPressed: _busy
                                ? null
                                : () {
                                    Navigator.pop(context, false);
                                    context.go(issue['route'].toString());
                                  },
                            child: Text(
                              issue['action_label']?.toString() ?? 'Review',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_blocked) ...[
                  Divider(
                    height: 1,
                    color: DefensysTokens.goldOf(
                      context,
                    ).withValues(alpha: .25),
                  ),
                  const SizedBox(height: 16),
                  ShadCheckbox(
                    value: _force,
                    enabled: !_busy,
                    onChanged: (value) => setState(() => _force = value),
                    label: const Text('Force calendar switch with a reason'),
                  ),
                  if (_force) ...[
                    const SizedBox(height: 18),
                    WorkflowField(
                      label: 'Reason for calendar override',
                      helper:
                          'This calendar override leaves the outstanding work unresolved.',
                      child: ShadInput(
                        controller: _reason,
                        placeholder: const Text(
                          'Record the approved calendar exception',
                        ),
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _semesterSummaryCard({
    required Key cardKey,
    required String heading,
    required String period,
    required List<Widget> children,
    bool continuing = false,
  }) => ShadCard(
    key: cardKey,
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    shadows: const [],
    backgroundColor: continuing
        ? DefensysTokens.success.withValues(
            alpha: DefensysTokens.isDark(context) ? .07 : .04,
          )
        : DefensysTokens.surfaceHigherOf(context),
    radius: BorderRadius.circular(8),
    border: ShadBorder.all(
      width: 1,
      color: continuing
          ? DefensysTokens.success.withValues(alpha: .35)
          : DefensysTokens.borderOf(context),
      radius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: TextStyle(
            fontSize: 12,
            color: _muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          period,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );

  Widget _teamCount(int count, String program, {Color? color}) => Text(
    '$count $program ${count == 1 ? 'team' : 'teams'}',
    style: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
      color: color,
    ),
  );

  Widget _cardDescription(String text) =>
      Text(text, style: TextStyle(fontSize: 12, height: 1.6, color: _muted));

  Widget _switchDetail(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: _muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.5, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _note(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(8),
      border: warning
          ? Border.all(
              color: DefensysTokens.goldOf(context).withValues(alpha: .4),
            )
          : null,
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
    ),
  );
}
