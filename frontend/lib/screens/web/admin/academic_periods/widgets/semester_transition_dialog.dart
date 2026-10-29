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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Confirm semester switch',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        _note(
          [
            if (continuing > 0)
              '$continuing ${continuing == 1 ? 'team' : 'teams'} continuing to Capstone 2',
            if (completed > 0)
              '$completed completed ${completed == 1 ? 'team' : 'teams'} in History',
            if (failed > 0)
              '$failed failed ${failed == 1 ? 'team' : 'teams'} in History',
            if (review > 0)
              '$review ${review == 1 ? 'team requires' : 'teams require'} review',
            if (_teams.isEmpty) 'No Capstone roster changes for this switch.',
          ].join('\n'),
        ),
        if (pending) ...[
          const SizedBox(height: 12),
          Text(
            'Student enrollment can be rolled over after this switch.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Outgoing semester checks · PIT and Capstone',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if ((_preview['issues'] as List? ?? []).isEmpty)
          Text(
            'No outstanding semester checks.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ...(_preview['issues'] as List? ?? []).map((raw) {
          final issue = raw as Map;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  issue['message']?.toString() ?? '',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                if (issue['route'] != null)
                  ShadButton.ghost(
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.pop(context, false);
                            context.go(issue['route'].toString());
                          },
                    child: Text(issue['action_label']?.toString() ?? 'Review'),
                  ),
              ],
            ),
          );
        }),
        if (_blocked) ...[
          const SizedBox(height: 12),
          _note(
            'Resolve the outstanding work before switching. A calendar override keeps its unresolved status.',
            warning: true,
          ),
          const SizedBox(height: 12),
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
    );
  }

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
