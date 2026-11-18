import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/grading/outcome_dissemination_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'grade_table_values.dart';

Future<bool?> showOutcomeDisseminationDialog(
  BuildContext context, {
  required Map<String, String> filters,
  List<int>? gradeIds,
  GradeRow? statusCell,
  bool history = false,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => OutcomeDisseminationDialog(
    filters: filters,
    gradeIds: gradeIds,
    statusCell: statusCell,
    history: history,
  ),
);

class OutcomeDisseminationDialog extends ConsumerStatefulWidget {
  const OutcomeDisseminationDialog({
    super.key,
    required this.filters,
    this.gradeIds,
    this.statusCell,
    this.history = false,
  });
  final Map<String, String> filters;
  final List<int>? gradeIds;
  final GradeRow? statusCell;
  final bool history;

  @override
  ConsumerState<OutcomeDisseminationDialog> createState() =>
      _OutcomeDisseminationDialogState();
}

class _OutcomeDisseminationDialogState
    extends ConsumerState<OutcomeDisseminationDialog> {
  GradeRow? _review;
  List<GradeRow> _history = [];
  String? _error;
  bool _busy = true, _changed = false;
  final _batchId = newOutcomeBatchId();
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(outcomeDisseminationApiProvider);
      if (widget.history) {
        final data = await api.history(widget.filters);
        if (mounted) setState(() => _history = gradeMaps(data['batches']));
      } else if (widget.statusCell != null &&
          gradeMap(widget.statusCell!['dissemination'])['status'] ==
              'released') {
        final data = await api.history(widget.filters);
        final releaseId = gradeMap(
          widget.statusCell!['dissemination'],
        )['release_id'];
        if (mounted) {
          setState(
            () => _history = gradeMaps(data['batches'])
                .where(
                  (batch) => gradeMaps(
                    batch['entries'],
                  ).any((entry) => entry['release_id'] == releaseId),
                )
                .toList(),
          );
        }
      } else if (widget.statusCell == null) {
        final data = await api.preview(widget.filters, widget.gradeIds);
        if (mounted) setState(() => _review = data);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _review == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(outcomeDisseminationApiProvider)
          .confirm('${_review!['review_token']}', _batchId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hold(bool held) async {
    final entries = gradeMaps(_review?['entries']);
    final entry =
        widget.statusCell ?? (entries.length == 1 ? entries.first : null);
    if (entry == null) return;
    final metadata = gradeMap(entry['metadata'] ?? entry['dissemination']);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(outcomeDisseminationApiProvider)
          .hold(
            gradeNumber(entry['grade_id'])!.toInt(),
            metadata,
            held,
            _reason.text.trim(),
          );
      _changed = true;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _verdict(dynamic value) => switch (value) {
    'approved' => 'Approved',
    'approved_with_revisions' => 'Approved with revisions',
    'for_redefense' => 'For re-defense',
    'failed' => 'Failed',
    'project_rejected' => 'Project rejected',
    _ => 'Pending',
  };

  Widget _snapshot(GradeRow data) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: ShadAccordion<String>(
      children: [
        ShadAccordionItem<String>(
          value: '${data['team_id']}-${data['schedule_id']}',
          title: Text(
            '${data['team_name']} · Attempt ${data['attempt'] ?? 1} · ${_verdict(data['verdict'])}',
            style: const TextStyle(fontFamily: DefensysTokens.fontFamilyInter),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ('${data['approved_title'] ?? ''}'.isNotEmpty) ...[
                Text('${data['approved_title']}'),
                const SizedBox(height: 8),
              ],
              const Text(
                'Panel feedback',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${data['verdict_remarks'] ?? ''}'.isEmpty
                    ? 'No panel feedback recorded.'
                    : '${data['verdict_remarks']}',
              ),
              if (data['revision_deadline'] != null) ...[
                const SizedBox(height: 8),
                Text('Deadline: ${data['revision_deadline']}'),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final entries = gradeMaps(_review?['entries']);
    final status = gradeMap(widget.statusCell?['dissemination']);
    final title = widget.history
        ? 'Dissemination history'
        : widget.statusCell != null
        ? '${status['label'] ?? 'Outcome status'}'
        : _review == null
        ? 'Review dissemination'
        : 'Disseminate ${_review!['team_count']} ${entries.length == 1 ? 'outcome' : 'outcomes'}?';
    return PopScope(
      canPop: !_busy,
      child: DefensysShadcnScope(
        child: ShadDialog(
          constraints: const BoxConstraints(maxWidth: 640),
          actionsAxis:
              MediaQuery.sizeOf(context).width < 900 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.2
              ? Axis.vertical
              : Axis.horizontal,
          title: Text(title),
          description: Text(
            '${gradeMap(_review?['context'])['assessment_label'] ?? widget.filters['stage_label'] ?? 'Selected assessment'}',
          ),
          actions: [
            ShadButton.outline(
              enabled: !_busy,
              onPressed: _busy ? null : () => Navigator.pop(context, _changed),
              child: const Text('Close'),
            ),
            if (status['status'] == 'held')
              ShadButton(
                backgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: Colors.white,
                enabled: !_busy,
                onPressed: _busy ? null : () => _hold(false),
                child: const Text('Remove hold'),
              ),
            if (_review != null && entries.length == 1)
              ShadButton.outline(
                enabled: !_busy,
                onPressed: _busy ? null : () => _hold(true),
                child: const Text('Place on hold'),
              ),
            if (_review != null)
              ShadButton(
                backgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: Colors.white,
                enabled: !_busy,
                onPressed: _busy ? null : _confirm,
                child: Text(
                  _busy
                      ? 'Please wait…'
                      : 'Disseminate ${_review!['team_count']} ${entries.length == 1 ? 'outcome' : 'outcomes'}',
                ),
              ),
          ],
          child: SizedBox(
            width: 580,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .62,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_busy)
                        ShadButton.outline(
                          onPressed: _load,
                          child: Text(
                            _review == null ? 'Retry review' : 'Review again',
                          ),
                        ),
                    ],
                    if (widget.statusCell != null) ...[
                      Text('${status['reason'] ?? status['label'] ?? ''}'),
                      const SizedBox(height: 8),
                      if (status['status'] == 'held')
                        const Text(
                          'Removing the hold does not release this outcome.',
                        ),
                    ],
                    if (_review != null) ...[
                      Text(
                        '${_review!['team_count']} ${entries.length == 1 ? 'team' : 'teams'} · ${_review!['student_count']} students',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _review!['selection_mode'] == 'selected'
                            ? 'Selected teams only.'
                            : 'Ready teams matching your filters, across all pages. Each team appears once.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Outcome, official concept and panel feedback are released together. Numeric grades remain private.',
                      ),
                      ...entries.map(
                        (entry) => _snapshot(gradeMap(entry['snapshot'])),
                      ),
                      Text(
                        '${_review!['excluded_count']} matching teams excluded. Later completions remain private until another release.',
                      ),
                      ...gradeMaps(_review!['excluded']).map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${entry['team_name']}: ${entry['reason'] ?? entry['label']}',
                          ),
                        ),
                      ),
                      if (entries.length == 1) ...[
                        const SizedBox(height: 16),
                        ShadInput(
                          controller: _reason,
                          placeholder: const Text(
                            'Hold reason (optional, admin only)',
                          ),
                          maxLength: 1000,
                        ),
                      ],
                    ],
                    if (widget.history && !_busy && _history.isEmpty)
                      const Text(
                        'No outcomes have been disseminated for this assessment.',
                      ),
                    ..._history.map(
                      (batch) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            '${batch['actor_name']} · ${batch['released_at']}',
                          ),
                          Text(
                            '${batch['team_count']} team outcomes · ${batch['student_count']} students',
                          ),
                          ...gradeMaps(batch['entries']).map(
                            (entry) => _snapshot(gradeMap(entry['snapshot'])),
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
      ),
    );
  }
}
