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
  int semesterId, {
  bool returning = false,
}) async {
  final preview = await ref
      .read(academicPeriodProvider.notifier)
      .fetchTransitionPreview(semesterId, returning: returning);
  if (!context.mounted || preview == null) return false;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SemesterTransitionDialog(
      semesterId: semesterId,
      preview: preview,
      returning: returning,
    ),
  );
}

/// One review flow for both activation surfaces and late returning-team review.
class SemesterTransitionDialog extends ConsumerStatefulWidget {
  const SemesterTransitionDialog({
    super.key,
    required this.semesterId,
    required this.preview,
    this.returning = false,
  });
  final int semesterId;
  final Map<String, dynamic> preview;
  final bool returning;
  @override
  ConsumerState<SemesterTransitionDialog> createState() =>
      _SemesterTransitionDialogState();
}

class _SemesterTransitionDialogState
    extends ConsumerState<SemesterTransitionDialog> {
  late Map<String, dynamic> _preview;
  final _reason = TextEditingController();
  final _search = TextEditingController();
  final Map<int, Map<String, dynamic>> _decisions = {};
  final Map<int, TextEditingController> _titles = {};
  int _step = 0, _page = 0;
  bool _busy = false, _force = false;
  String? _error;
  late final String _requestId =
      '${widget.semesterId}-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  Map<String, dynamic> get _review =>
      Map<String, dynamic>.from(_preview['capstone_review'] as Map? ?? {});
  List<Map<String, dynamic>> get _teams => (_review['teams'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get _returning =>
      _teams.where((r) => r['requires_project_choice'] == true).toList();
  bool get _blocked => _preview['can_switch'] == false;
  Color get _muted => DefensysTokens.textSecondaryOf(context);

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    _prepareChoices();
  }

  void _prepareChoices() {
    for (final row in _returning) {
      final id = (row['team_id'] as num).toInt();
      _decisions.putIfAbsent(id, () => {'team_id': id, 'include': true});
      _titles.putIfAbsent(id, TextEditingController.new);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    for (final title in _titles.values) {
      title.dispose();
    }
    super.dispose();
  }

  bool get _choicesValid => _returning.every((row) {
    final d = _decisions[row['team_id']]!;
    return d['include'] == false ||
        (d['project_choice'] == 'continue' ||
            (d['project_choice'] == 'new' &&
                _titles[row['team_id']]!.text.trim().isNotEmpty &&
                _titles[row['team_id']]!.text.trim().length <= 255));
  });
  bool get _needsReason =>
      (_blocked && _force) ||
      _decisions.values.any((d) => d['include'] == true);
  bool get _canSubmit =>
      !_busy &&
      _choicesValid &&
      (!_blocked || _force) &&
      (!_needsReason || _reason.text.trim().isNotEmpty);

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final fresh = await ref
        .read(academicPeriodProvider.notifier)
        .fetchTransitionPreview(widget.semesterId, returning: widget.returning);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (fresh != null) {
        _preview = fresh;
        _prepareChoices();
        _step = 0;
        _page = 0;
        final eligible = _returning.map((r) => r['team_id']).toSet();
        _decisions.removeWhere((id, _) => !eligible.contains(id));
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
    final decisions = _returning.map((row) {
      final id = row['team_id'] as int;
      return {
        ..._decisions[id]!,
        if (_decisions[id]!['project_choice'] == 'new')
          'project_title': _titles[id]!.text.trim(),
      };
    }).toList();
    final ok = await ref
        .read(academicPeriodProvider.notifier)
        .activateSemester(
          widget.semesterId,
          returning: widget.returning,
          force: _force,
          reason: _reason.text.trim(),
          decisions: decisions,
          previewRevision: _preview['preview_revision']?.toString() ?? '',
          requestId: _requestId,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          ref.read(academicPeriodProvider).error ??
          'The transition could not be saved.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
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
          height: min(740, size.height - 40),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.returning
                                  ? 'Review returning teams'
                                  : 'Review semester transition',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Preserve each team’s progress and original academic records.',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
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
                    labels: const [
                      'Review teams',
                      'Returning teams',
                      'Confirm',
                    ],
                    compactLabels: const ['Review', 'Returning', 'Confirm'],
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
                              child: const Text(
                                'Refresh review · keep my choices',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_step == 0) _reviewStep(),
                        if (_step == 1) _returningStep(),
                        if (_step == 2) _confirmStep(),
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
                                  setState(() => _step--);
                                }
                              },
                        child: Text(_step == 0 ? 'Cancel' : 'Back'),
                      ),
                      if (_busy)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            'Saving…',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                        ),
                      ShadButton(
                        backgroundColor: DefensysTokens.maroonOf(context),
                        foregroundColor: Colors.white,
                        onPressed:
                            _busy ||
                                (_step == 1 && !_choicesValid) ||
                                (_step == 2 && !_canSubmit)
                            ? null
                            : _step == 2
                            ? _submit
                            : () => setState(() => _step++),
                        child: Text(
                          _step == 2
                              ? (widget.returning
                                    ? 'Include returning teams'
                                    : 'Confirm switch')
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
    final visible = filtered.skip(page * 20).take(20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${source?['display_name'] ?? 'Current period'}  →  ${target?['display_name'] ?? target?['label'] ?? 'Next period'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _note(
          widget.returning
              ? 'Include eligible failed teams after their enrollment is verified.'
              : 'Completed teams enter History. Eligible failed teams can return as Extended alongside the new batch.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text(
              '${_teams.length} outgoing teams',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'All results included',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ShadInput(
          controller: _search,
          placeholder: const Text('Search team, project, or outcome'),
          onChanged: (_) => setState(() => _page = 0),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _note(
            _teams.isEmpty
                ? 'No Capstone teams need transition review.'
                : 'No teams match your search.',
          ),
        if (visible.isNotEmpty)
          SizedBox(
            height: min(320, visible.length * 96.0),
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
              itemBuilder: (_, i) {
                final r = visible[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['name'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              r['project_title']?.toString() ?? '',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r['reason']?.toString() ?? '',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _badge(_destination(r)),
                    ],
                  ),
                );
              },
            ),
          ),
        if (pages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ShadButton.ghost(
                onPressed: page > 0
                    ? () => setState(() => _page = page - 1)
                    : null,
                child: const Text('Previous'),
              ),
              Text(
                '${page + 1} / $pages',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              ShadButton.ghost(
                onPressed: page + 1 < pages
                    ? () => setState(() => _page = page + 1)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          'The fresh batch comes from the existing roster import. The semester switch creates no new teams.',
          style: TextStyle(fontSize: 12, height: 1.5, color: _muted),
        ),
      ],
    );
  }

  Widget _returningStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Choose how returning teams continue',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Each included failed team keeps its original cohort and extension end semester.',
        style: TextStyle(fontSize: 12, color: _muted),
      ),
      const SizedBox(height: 18),
      if (_returning.isEmpty)
        _note(
          'No failed teams need a project decision. Eligible normal and ongoing Extended teams continue with verified enrollment.',
        ),
      ..._returning.map((r) {
        final id = r['team_id'] as int;
        final decision = _decisions[id]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShadCheckbox(
                  value: decision['include'] == true,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => decision['include'] = v),
                  label: Text(
                    'Include ${r['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enrollment verified · ${r['original_cohort'] ?? 'Original cohort'}\nExtended through ${r['extension_deadline']}',
                  style: TextStyle(fontSize: 11, height: 1.5, color: _muted),
                ),
                const SizedBox(height: 6),
                Text(
                  'Current project: ${r['project_title']}',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                if (decision['include'] == true) ...[
                  const SizedBox(height: 16),
                  ShadRadioGroup<String>(
                    initialValue: decision['project_choice'] as String?,
                    enabled: !_busy,
                    onChanged: (v) =>
                        setState(() => decision['project_choice'] = v),
                    items: [
                      ShadRadio(
                        value: 'continue',
                        label: const Text('Continue existing project'),
                        sublabel: Text(
                          r['project_title']?.toString() ??
                              'Retain valid progress and authorize a retake.',
                        ),
                      ),
                      const ShadRadio(
                        value: 'new',
                        label: Text('Start a new project'),
                        sublabel: Text(
                          'Restart at the first configured stage. Previous work stays in History.',
                        ),
                      ),
                    ],
                  ),
                  if (decision['project_choice'] == 'new') ...[
                    const SizedBox(height: 14),
                    WorkflowField(
                      label: 'Proposed project title',
                      child: ShadInput(
                        controller: _titles[id],
                        placeholder: const Text('Enter the new project title'),
                        maxLength: 255,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      }),
      _note(
        'Only an official Failed result starts an extension. Pending grades, re-defense, or missing clearance stay unresolved.',
      ),
    ],
  );

  Widget _confirmStep() {
    final included = _teams
        .where(
          (r) =>
              r['can_include'] == true &&
              (_decisions[r['team_id']]?['include'] ?? true),
        )
        .length;
    final history = _teams.where((r) => r['destination'] == 'history').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirm the next roster',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 12),
        _note(
          '$included continuing teams · $history completed teams entering History\n${_teams.length - included - history} excluded or requiring review\nEarlier outcomes, grades, and files keep their original academic period.',
        ),
        const SizedBox(height: 18),
        ...(_preview['issues'] as List? ?? []).map((raw) {
          final issue = raw as Map;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    issue['message']?.toString() ?? '',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
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
            'Resolve unfinished workflows before switching. An approved override preserves their unresolved status.',
            warning: true,
          ),
          const SizedBox(height: 12),
          ShadCheckbox(
            value: _force,
            enabled: !_busy,
            onChanged: (v) => setState(() => _force = v),
            label: const Text('Force switch with an institutional reason'),
          ),
        ],
        if (_needsReason) ...[
          const SizedBox(height: 18),
          WorkflowField(
            label: 'Institutional decision or reference',
            helper:
                'Recorded with the transition and any recovery authorizations.',
            child: ShadInput(
              controller: _reason,
              placeholder: const Text(
                'Record the authorization or approved exception',
              ),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'An Extended team keeps the original end semester when changing projects or enrolling late.',
          style: TextStyle(fontSize: 12, height: 1.5, color: _muted),
        ),
      ],
    );
  }

  String _destination(Map<String, dynamic> row) => switch (row['destination']) {
    'history' => 'History',
    'continue' => row['can_include'] == true ? 'Continue' : 'Enrollment needed',
    'extended' => row['can_include'] == true ? 'Extended' : 'Enrollment needed',
    'institutional_review' => 'Institutional review',
    _ => 'Needs review',
  };
  Widget _badge(String text) => Container(
    constraints: const BoxConstraints(maxWidth: 140),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: _muted,
      ),
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
