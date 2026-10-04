import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_action_menu.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../../widgets/feedback/defensys_loading.dart';

Future<void> showGradeCorrectionDialog(BuildContext context, int gradeId) =>
    showDialog<void>(
      context: context,
      builder: (_) => GradeCorrectionDialog(gradeId: gradeId),
    );

class GradeCorrectionDialog extends ConsumerStatefulWidget {
  const GradeCorrectionDialog({super.key, required this.gradeId});
  final int gradeId;
  @override
  ConsumerState<GradeCorrectionDialog> createState() =>
      _GradeCorrectionDialogState();
}

class _GradeCorrectionDialogState extends ConsumerState<GradeCorrectionDialog> {
  Map<String, dynamic>? _details, _preview, _reviewing;
  String _view = 'correct', _mode = 'criterion';
  String? _evaluator, _student, _rowId, _component, _expandedHistory;
  final _score = TextEditingController(),
      _reason = TextEditingController(),
      _approvalReason = TextEditingController();
  bool _busy = true, _acknowledged = false;
  String? _error, _notice;
  static const _labels = {
    'panel_score': 'Panel score',
    'adviser_score': 'Adviser score',
    'peer_score': 'Peer score',
    'final_grade': 'Final grade',
  };
  List<Map<String, dynamic>> _maps(dynamic value) =>
      (value is List ? value : [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
  Map<String, dynamic> get _grade =>
      Map<String, dynamic>.from(_details?['grade'] ?? {});
  List<Map<String, dynamic>> get _scores => _maps(
    _details?['scores'],
  ).where((row) => row['is_void'] != true).toList();
  List<Map<String, dynamic>> get _history => _maps(_details?['history']);
  bool get _hasPanelOverride => _grade['panel_score_is_override'] == true;
  Map<String, String> get _components => _grade['individual_grading'] == true
      ? {}
      : {
          for (final key in ['panel_score', 'adviser_score', 'peer_score'])
            if (_grade[key] != null &&
                (key != 'adviser_score' ||
                    _grade['adviser_grading_enabled'] == true) &&
                (key != 'panel_score' || _maps(_details?['scores']).isEmpty))
              key: _labels[key]!,
        };
  bool get _hasCorrection =>
      _scores.isNotEmpty || _components.isNotEmpty || _hasPanelOverride;
  String _evaluatorKey(Map<String, dynamic> row) =>
      '${row['evaluator_key'] ?? row['evaluator']}';
  String _studentKey(Map<String, dynamic> row) =>
      '${row['student_id'] ?? row['student'] ?? 'Team'}';
  Map<String, String> get _evaluators => {
    for (final row in _scores)
      _evaluatorKey(
        row,
      ): '${row['evaluator']}${_scores.where((other) => other['evaluator'] == row['evaluator']).map(_evaluatorKey).toSet().length > 1 ? ' · ${row['evaluator_reference'] ?? 'Recorded panelist'}' : ''}',
  };
  List<Map<String, dynamic>> get _evaluatorRows =>
      _scores.where((row) => _evaluatorKey(row) == _evaluator).toList();
  Map<String, String> get _students => {
    for (final row in _evaluatorRows)
      _studentKey(
        row,
      ): '${row['student']}${_evaluatorRows.where((other) => other['student'] == row['student']).map(_studentKey).toSet().length > 1 ? ' · ${row['student_reference'] ?? 'Recorded student'}' : ''}',
  };
  List<Map<String, dynamic>> get _studentRows =>
      _evaluatorRows.where((row) => _studentKey(row) == _student).toList();
  Map<String, dynamic>? get _row =>
      _studentRows.where((row) => '${row['id']}' == _rowId).firstOrNull;
  bool get _ready =>
      _hasCorrection &&
      (_mode == 'restore' ||
          _mode == 'aggregate' && _component != null ||
          const ['criterion', 'void'].contains(_mode) &&
              _row != null &&
              !_hasPanelOverride);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_score, _reason, _approvalReason]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _pickStudent(String? key) {
    _student = key;
    _rowId = _mode == 'void' || _studentRows.length == 1
        ? (_studentRows.firstOrNull?['id'])?.toString()
        : null;
    _score.clear();
  }

  void _pickEvaluator(String? key) {
    _evaluator = key;
    _pickStudent(_students.length == 1 ? _students.keys.first : null);
  }

  void _setMode(String mode) {
    _mode = mode;
    _error = null;
    _preview = null;
    _score.clear();
    _reason.clear();
    _component = _components.length == 1 ? _components.keys.first : null;
    _pickEvaluator(_evaluators.length == 1 ? _evaluators.keys.first : null);
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _preview = null;
    });
    try {
      final details = await ref
          .read(gradeCenterProvider.notifier)
          .correctionDetails(widget.gradeId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _reviewing = null;
        _setMode(
          _hasPanelOverride
              ? 'restore'
              : _scores.isEmpty && _components.isNotEmpty
              ? 'aggregate'
              : 'criterion',
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Map<String, dynamic> _changes() {
    if (_mode == 'restore') return {'clear_panel_override': true};
    if (_mode == 'void') return {'void_submission': _row!['submission_id']};
    if (_mode == 'aggregate') {
      return {
        'aggregate': {_component!: _score.text.trim()},
      };
    }
    return {
      'criterion': {'id': _row!['id'], 'score': _score.text.trim()},
    };
  }

  Future<void> _submit() async {
    if (!_ready) return;
    if (_reason.text.trim().length < 5) {
      setState(
        () => _error =
            'Explain the correction and how you verified the score. This will be saved in the audit trail.',
      );
      return;
    }
    if (const ['criterion', 'aggregate'].contains(_mode)) {
      final maximum = _mode == 'criterion'
          ? double.parse('${_row!['max_score']}')
          : 100.0;
      final value = double.tryParse(_score.text.trim());
      if (value == null || !value.isFinite || value < 0 || value > maximum) {
        setState(
          () => _error =
              'Enter a score between 0 and ${maximum.toStringAsFixed(maximum == maximum.roundToDouble() ? 0 : 2)}.',
        );
        return;
      }
      final current = double.tryParse(
        '${_mode == 'criterion' ? _row!['score'] : _grade[_component]}',
      );
      if (current == value) {
        setState(
          () => _error = 'The new score is the same as the current score.',
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final isPreview = _preview == null;
      final result = await ref
          .read(gradeCenterProvider.notifier)
          .correctGrade(widget.gradeId, {
            'expected_updated_at': _details!['updated_at'],
            'reason': _reason.text.trim(),
            'changes': _changes(),
            'preview': isPreview,
          });
      if (!mounted) return;
      if (isPreview) {
        setState(() => _preview = result);
      } else {
        await _load();
        if (mounted) {
          setState(() {
            _view = 'history';
            _notice = result['status'] == 'pending'
                ? 'Correction requested. It needs approval before the grade changes.'
                : 'Correction saved. The original score and reason are kept in history.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _preview = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review(bool approve) async {
    if (_approvalReason.text.trim().length < 5) {
      setState(
        () => _error =
            'Explain why you are approving or rejecting this correction.',
      );
      return;
    }
    if (approve && !_acknowledged) {
      setState(
        () => _error =
            'Confirm that you reviewed the evidence and authorize the grade change.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(gradeCenterProvider.notifier)
          .correctGrade(widget.gradeId, {
            'action': approve ? 'approve' : 'reject',
            'correction_id': _reviewing!['id'],
            'reason': _approvalReason.text.trim(),
            'acknowledge_published_change': _acknowledged,
          });
      _approvalReason.clear();
      _acknowledged = false;
      await _load();
      if (mounted) {
        setState(() {
          _view = 'history';
          _notice = approve
              ? 'Correction approved and recorded in history.'
              : 'Correction rejected. The grade is unchanged.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _summary(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final old in _maps(before['criteria']))
        for (final updated in _maps(after['criteria']))
          if (old['id'] == updated['id'] && old['score'] != updated['score'])
            WorkflowComparison(
              label:
                  '${old['criterion']} · ${old['evaluator']}${old['student_name'] == 'Team' ? '' : ' · ${old['student_name']}'}',
              before: '${old['score']} / ${old['max_score']}',
              after: '${updated['score']} / ${updated['max_score']}',
            ),
      for (final key in _labels.keys)
        if (before[key] != after[key])
          WorkflowComparison(
            label: _labels[key]!,
            before: '${before[key] ?? 'Incomplete'}',
            after: '${after[key] ?? 'Incomplete'}',
          ),
      for (final old in _maps(before['students']))
        for (final updated in _maps(after['students']))
          if (old['id'] == updated['id'] &&
              old['final_grade'] != updated['final_grade'])
            WorkflowComparison(
              label: '${old['student_name']} · Final grade',
              before: '${old['final_grade'] ?? 'Incomplete'}',
              after: '${updated['final_grade'] ?? 'Incomplete'}',
            ),
      if (before['panel_score_is_override'] != after['panel_score_is_override'])
        const Text(
          'Panel score will be calculated from the recorded evaluations.',
        ),
      for (final old in _maps(before['submissions']))
        for (final updated in _maps(after['submissions']))
          if (old['id'] == updated['id'] &&
              old['is_void'] != updated['is_void'])
            WorkflowComparison(
              label:
                  'Evaluation by ${_maps(before['criteria']).where((row) => row['submission_id'] == old['id']).firstOrNull?['evaluator'] ?? 'the recorded evaluator'}',
              before: 'Included in calculations',
              after: 'Excluded · original scores kept',
            ),
    ],
  );
  Widget _empty(String title, String message, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, size: 32, color: DefensysTokens.textSecondaryOf(context)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
        ),
      ],
    ),
  );
  Widget _reasonField() => WorkflowField(
    label: 'Why is this correction needed?',
    helper:
        'Required · include how you verified it. The reason is saved in the audit trail.',
    child: ShadInput(
      key: const ValueKey('grade-correction-reason'),
      controller: _reason,
      enabled: !_busy,
      minLines: 2,
      maxLines: 3,
      maxLength: 2000,
      placeholder: const Text(
        'For example: the panelist confirmed 9 on the signed grading sheet; 2 was entered by mistake.',
      ),
    ),
  );
  Widget _correctForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_hasCorrection)
        _empty(
          'No scores to correct yet',
          'Corrections become available after scores are recorded. There is nothing to change right now.',
          LucideIcons.clipboardList,
        )
      else ...[
        Text(
          '${_details!['completion']['submitted']} of ${_details!['completion']['required']} panel evaluations submitted',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 14),
        if (_details!['requires_approval'] == true)
          const WorkflowNotice(
            title: 'Approval required',
            message:
                'This grade is published or officially complete. Submit a correction request, then review it in History.',
          ),
        if (_scores.isNotEmpty &&
            (_components.isNotEmpty ||
                _mode != 'criterion' ||
                _hasPanelOverride))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _mode == 'criterion'
                        ? 'Correct a recorded score'
                        : _mode == 'void'
                        ? 'Exclude an evaluation'
                        : _mode == 'restore'
                        ? 'Use calculated panel scores'
                        : 'Edit a recorded total',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                DefensysActionMenu(
                  label: 'More correction options',
                  enabled: !_busy,
                  items: [
                    if (!_hasPanelOverride)
                      DefensysMenuItem(
                        label: 'Correct a criterion score',
                        icon: LucideIcons.pencil,
                        onPressed: () => setState(() => _setMode('criterion')),
                      ),
                    if (_components.isNotEmpty)
                      DefensysMenuItem(
                        label: 'Edit a recorded total',
                        icon: LucideIcons.calculator,
                        onPressed: () => setState(() => _setMode('aggregate')),
                      ),
                    if (_hasPanelOverride)
                      DefensysMenuItem(
                        label: 'Use calculated panel scores',
                        icon: LucideIcons.rotateCcw,
                        onPressed: () => setState(() => _setMode('restore')),
                      ),
                    if (!_hasPanelOverride)
                      DefensysMenuItem(
                        label: 'Exclude an evaluation',
                        icon: LucideIcons.circleMinus,
                        onPressed: () => setState(() => _setMode('void')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (_mode == 'restore')
          const WorkflowNotice(
            title: 'Recalculate from panel evaluations',
            message:
                'A manual panel total is currently in use. Restore the calculated scores before correcting an individual criterion.',
          ),
        if (const ['criterion', 'void'].contains(_mode)) ...[
          WorkflowSelect(
            label: 'Panelist',
            value: _evaluator,
            options: _evaluators,
            placeholder: 'Choose the panelist who entered the score',
            enabled: !_busy,
            onChanged: (value) => setState(() => _pickEvaluator(value)),
          ),
          if (_students.length > 1)
            WorkflowSelect(
              label: 'Student',
              value: _student,
              options: _students,
              placeholder: 'Choose the student being graded',
              enabled: !_busy,
              onChanged: (value) => setState(() => _pickStudent(value)),
            ),
          if (_mode == 'criterion')
            WorkflowSelect(
              label: 'Criterion',
              value: _rowId,
              options: {
                for (final row in _studentRows)
                  '${row['id']}': '${row['criterion']}',
              },
              placeholder: _evaluator == null
                  ? 'Choose a panelist first'
                  : _student == null
                  ? 'Choose a student first'
                  : 'Choose the criterion to correct',
              enabled: !_busy && _studentRows.isNotEmpty,
              onChanged: (value) => setState(() {
                _rowId = value;
                _score.clear();
              }),
            ),
          if (_mode == 'void')
            const WorkflowNotice(
              title: 'Exclude the entire evaluation',
              message:
                  'All criteria in this panelist’s evaluation for the selected student or team will be excluded from grade calculations. Original scores remain in history.',
            ),
        ],
        if (_mode == 'aggregate')
          WorkflowSelect(
            label: 'Recorded total',
            value: _component,
            options: _components,
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _component = value;
              _score.clear();
            }),
          ),
        if (_mode == 'criterion' && _row != null ||
            _mode == 'aggregate' && _component != null) ...[
          WorkflowField(
            label: 'Current score',
            child: Text(
              _mode == 'criterion'
                  ? '${_row!['score']} / ${_row!['max_score']}'
                  : '${_grade[_component]} / 100',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          WorkflowField(
            label: 'New score',
            helper: _mode == 'criterion'
                ? 'Enter a value from 0 to ${_row!['max_score']}.'
                : 'Enter a percentage from 0 to 100.',
            child: ShadInput(
              key: const ValueKey('grade-correction-score'),
              controller: _score,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              placeholder: const Text('Enter the correct score'),
            ),
          ),
        ],
        if (_ready) _reasonField(),
      ],
    ],
  );
  String _when(dynamic value) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? '$value'
        : DateFormat('MMM d, y · h:mm a').format(date.toLocal());
  }

  Widget _historyView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_history.isEmpty)
        _empty(
          'No corrections recorded',
          'Saved corrections and approval requests will appear here with their original scores and reasons.',
          LucideIcons.history,
        ),
      for (final item in _history)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: DefensysTokens.borderOf(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item['status'] == 'pending'
                    ? 'Awaiting approval'
                    : item['status'] == 'rejected'
                    ? 'Rejected'
                    : 'Correction saved',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${item['requested_by_name']} · ${_when(item['created_at'])}',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text('${item['reason']}'),
              if ('${item['approval_reason'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Review by ${item['approved_by_name']}: ${item['approval_reason']}',
                  ),
                ),
              if (_expandedHistory == '${item['id']}')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _summary(
                    Map<String, dynamic>.from(item['before']),
                    Map<String, dynamic>.from(item['after']),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShadButton.ghost(
                    enabled: !_busy,
                    onPressed: () => setState(
                      () =>
                          _expandedHistory = _expandedHistory == '${item['id']}'
                          ? null
                          : '${item['id']}',
                    ),
                    child: Text(
                      _expandedHistory == '${item['id']}'
                          ? 'Hide changes'
                          : 'View changes',
                    ),
                  ),
                  if (item['status'] == 'pending')
                    ShadButton.outline(
                      enabled: !_busy,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _view = 'review';
                              _reviewing = item;
                              _approvalReason.clear();
                              _acknowledged = false;
                              _error = null;
                            }),
                      child: const Text('Review request'),
                    ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
  Widget _reviewForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const WorkflowNotice(
        title: 'Review a published grade change',
        message:
            'Check the source evidence and the recalculated grade before approving this request.',
      ),
      Text('Requested by ${_reviewing!['requested_by_name']}'),
      const SizedBox(height: 6),
      Text('Reason: ${_reviewing!['reason']}'),
      const SizedBox(height: 14),
      _summary(
        Map<String, dynamic>.from(_reviewing!['before']),
        Map<String, dynamic>.from(_reviewing!['after']),
      ),
      WorkflowField(
        label: 'Your review reason',
        helper: 'Required for approval or rejection.',
        child: ShadInput(
          key: const ValueKey('grade-review-reason'),
          controller: _approvalReason,
          enabled: !_busy,
          minLines: 2,
          maxLines: 3,
          maxLength: 2000,
          placeholder: const Text(
            'Describe what you verified and your decision.',
          ),
        ),
      ),
      ShadCheckbox(
        value: _acknowledged,
        enabled: !_busy,
        onChanged: (value) => setState(() => _acknowledged = value),
        label: const Text(
          'I reviewed the evidence and authorize this grade change.',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 640),
      title: Text(
        _view == 'review'
            ? 'Review correction request'
            : _preview != null
            ? 'Confirm score correction'
            : 'Score corrections',
      ),
      description: Text(
        _details == null
            ? 'Loading recorded scores…'
            : '${_grade['team_name']} · ${_grade['stage_label']}',
      ),
      actions: [
        ShadButton.outline(
          enabled: !_busy,
          onPressed: _busy
              ? null
              : () {
                  if (_preview != null) {
                    setState(() => _preview = null);
                  } else if (_view == 'review') {
                    setState(() {
                      _view = 'history';
                      _reviewing = null;
                      _error = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
          child: Text(_preview != null || _view == 'review' ? 'Back' : 'Close'),
        ),
        if (_view == 'review') ...[
          ShadButton.outline(
            enabled: !_busy,
            onPressed: _busy ? null : () => _review(false),
            child: const Text('Reject request'),
          ),
          ShadButton(
            enabled: !_busy,
            onPressed: _busy ? null : () => _review(true),
            child: const Text('Approve correction'),
          ),
        ] else if (_view == 'correct' && _ready)
          ShadButton(
            enabled: !_busy,
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Please wait…'
                  : _preview == null
                  ? 'Review correction'
                  : _preview!['requires_approval'] == true
                  ? 'Request approval'
                  : 'Save correction',
            ),
          ),
      ],
      child: Container(
        width: 580,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: _busy && _details == null
            ? DefensysLoading.section(
                height: 140,
                label: 'Loading recorded scores…',
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      WorkflowNotice(
                        title: 'Check this correction',
                        message: _error!,
                        error: true,
                      ),
                    if (_notice != null)
                      WorkflowNotice(title: 'Saved', message: _notice!),
                    if (_details == null && !_busy)
                      ShadButton.outline(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    if (_details != null)
                      if (_view == 'review')
                        _reviewForm()
                      else if (_preview != null) ...[
                        _summary(
                          Map<String, dynamic>.from(_preview!['before']),
                          Map<String, dynamic>.from(_preview!['after']),
                        ),
                        Text('Reason: ${_reason.text.trim()}'),
                        const SizedBox(height: 12),
                        Text(
                          _preview!['requires_approval'] == true
                              ? 'This request needs approval before the grade changes.'
                              : 'The original score, author, and correction reason will remain in history.',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ] else
                        ShadTabs<String>(
                          key: ValueKey('correction-tabs-$_view'),
                          value: _view,
                          tabBarAlignment: Alignment.centerLeft,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  _view = value;
                                  _error = null;
                                }),
                          tabs: [
                            ShadTab(
                              value: 'correct',
                              enabled: !_busy,
                              content: _correctForm(),
                              child: const Text('Correct a score'),
                            ),
                            ShadTab(
                              value: 'history',
                              enabled: !_busy,
                              content: _historyView(),
                              child: Text(
                                'History${_history.where((item) => item['status'] == 'pending').isEmpty ? '' : ' (${_history.where((item) => item['status'] == 'pending').length} pending)'}',
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
      ),
    ),
  );
}
