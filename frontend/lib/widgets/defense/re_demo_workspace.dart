import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/api_config.dart';
import '../../models/defense_workflow_labels.dart';
import '../../services/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../../utils/operation_request_id.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Open a team's follow-up in the existing defense workspace.
Future<void> showReDemoWorkspace(
  BuildContext context, {
  required int sourceScheduleId,
  bool scheduleNow = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
      child: ReDemoWorkspaceScreen(
        sourceScheduleId: sourceScheduleId,
        scheduleNow: scheduleNow,
      ),
    ),
  ),
);

/// Operational verification appointments. This workspace never submits grades.
class ReDemoWorkspaceScreen extends ConsumerStatefulWidget {
  const ReDemoWorkspaceScreen({
    super.key,
    this.sourceScheduleId,
    this.scheduleNow = false,
  });
  final int? sourceScheduleId;
  final bool scheduleNow;

  @override
  ConsumerState<ReDemoWorkspaceScreen> createState() =>
      _ReDemoWorkspaceScreenState();
}

class _ReDemoWorkspaceScreenState extends ConsumerState<ReDemoWorkspaceScreen> {
  List<Map<String, dynamic>> _items = [], _eligible = [], _people = [];
  bool _loading = true, _canManage = false;
  String? _error;
  int _offset = 0, _total = 0, _version = 0;
  int _eligibleOffset = 0, _eligibleTotal = 0;
  bool _bookingOpened = false;
  String get _base => '${ApiConfig.baseUrl}/defense/re-demos';

  String _statusLabel(Map item) {
    if (item['status'] == 'cancelled') return 'Cancelled';
    if (item['status'] == 'done') {
      return item['verification_result'] == 'verified'
          ? 'Demonstrations verified'
          : 'Further corrections required';
    }
    return switch (item['operation_state']) {
      'paused' => 'Interrupted',
      'postponed' => 'Postponed',
      'no_show' => 'No-show',
      _ => 'Scheduled · Awaiting verification',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse('$_base/').replace(
              queryParameters: {
                'offset': '$_offset',
                'limit': '50',
                'eligible_offset': '$_eligibleOffset',
                if (widget.sourceScheduleId != null)
                  'source_schedule_id': '${widget.sourceScheduleId}',
              },
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted || version != _version) return;
      final body = jsonDecode(response.body) as Map;
      if (response.statusCode != 200) {
        throw StateError(
          '${body['detail'] ?? 'Unable to load re-demo appointments.'}',
        );
      }
      setState(() {
        _items = (body['appointments'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _eligible = (body['eligible'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _people = (body['panelist_options'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _canManage = body['can_manage'] == true;
        _total = (body['total'] as num).toInt();
        _eligibleTotal =
            (body['eligible_total'] as num?)?.toInt() ?? _eligible.length;
      });
      if (widget.scheduleNow && !_bookingOpened && _eligible.length == 1) {
        _bookingOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _book(_eligible.single);
        });
      }
    } catch (error) {
      if (mounted && version == _version) setState(() => _error = '$error');
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await ref
        .read(authenticatedHttpClientProvider)
        .post(
          Uri.parse('$_base/$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map;
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('${body['detail'] ?? body}');
    }
    return Map<String, dynamic>.from(body['appointment'] as Map);
  }

  Widget _field(String label, Widget input) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(label), const SizedBox(height: 6), input],
    ),
  );

  Future<void> _book(
    Map<String, dynamic> source, {
    Map<String, dynamic>? existing,
  }) async {
    final now = DateTime.now();
    // Keep dialog options stable while the parent reloads after booking.
    final people = _people
        .where((person) => person['id'] != source['adviser_id'])
        .toList();
    final date = TextEditingController(
      text:
          '${existing?['scheduled_date'] ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'}',
    );
    final time = TextEditingController(
      text: '${existing?['start_time'] ?? '09:00'}',
    );
    final room = TextEditingController(
      text: '${existing?['room'] ?? source['room'] ?? ''}',
    );
    final duration = TextEditingController(
      text: '${existing?['slot_duration'] ?? 30}',
    );
    final reason = TextEditingController();
    final panel =
        (existing?['panelists'] as List?)
            ?.whereType<Map>()
            .map((p) => (p['id'] as num).toInt())
            .toSet() ??
        (source['panelist_ids'] as List? ?? [])
            .map((id) => (id as num).toInt())
            .toSet();
    int? chair = ((existing?['chair_id'] ?? source['chair_id']) as num?)
        ?.toInt();
    panel.retainAll(people.map((person) => (person['id'] as num).toInt()));
    if (!panel.contains(chair)) chair = null;
    final requestId = newOperationRequestId();
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => DefensysShadcnScope(
          child: ShadDialog(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
            title: Text(
              existing == null ? 'Schedule re-demo' : 'Reschedule re-demo',
            ),
            description: Text(
              '${source['team_name'] ?? existing?['team_name']} · ${source['stage_label'] ?? existing?['stage_label']}',
            ),
            actions: [
              ShadButton.outline(
                enabled: !busy,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ShadButton(
                enabled: !busy,
                onPressed: () async {
                  update(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    final data = <String, dynamic>{
                      'scheduled_date': date.text.trim(),
                      'start_time': time.text.trim(),
                      'room': room.text.trim(),
                      'slot_duration': int.tryParse(duration.text),
                      'chair_id': chair,
                      'panelist_ids': panel.toList(),
                    };
                    if (existing == null) {
                      data.addAll({
                        'request_id': requestId,
                        'outcome_id': source['outcome_id'],
                        'source_revision': source['source_revision'],
                      });
                      await _post('', data);
                    } else {
                      data.addAll({
                        'action': 'reschedule',
                        'revision': existing['revision'],
                        'reason': reason.text.trim(),
                      });
                      await _post('${existing['id']}/operate/', data);
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      showSuccessToast(
                        this.context,
                        'Re-demo scheduled. Original assessment retained.',
                      );
                      await _load();
                    }
                  } catch (failure) {
                    if (dialogContext.mounted) {
                      update(() {
                        busy = false;
                        error = '$failure';
                      });
                    }
                  }
                },
                child: Text(busy ? 'Saving…' : 'Confirm appointment'),
              ),
            ],
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'No new adviser approval is required. The panel will check the required demonstrations.',
                  ),
                  if ((source['requirements'] as List? ?? []).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Required demonstrations',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final requirement
                        in (source['requirements'] as List).whereType<Map>())
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('• ${requirement['text']}'),
                      ),
                  ],
                  _field(
                    'Date (YYYY-MM-DD)',
                    ShadInput(controller: date, enabled: !busy),
                  ),
                  _field(
                    'Start time (HH:MM)',
                    ShadInput(controller: time, enabled: !busy),
                  ),
                  _field(
                    'Duration in minutes',
                    ShadInput(
                      controller: duration,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  _field(
                    'Venue',
                    ShadInput(controller: room, enabled: !busy, maxLength: 120),
                  ),
                  _field(
                    'Panel',
                    Column(
                      children: [
                        for (final person in people)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ShadCheckbox(
                              value: panel.contains(person['id']),
                              enabled: !busy,
                              label: Text('${person['name']}'),
                              onChanged: (selected) => update(() {
                                final id = (person['id'] as num).toInt();
                                if (selected) {
                                  panel.add(id);
                                } else {
                                  panel.remove(id);
                                  if (chair == id) chair = null;
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _field(
                    'Assigned re-demo chair',
                    ShadSelect<int>(
                      key: ValueKey('redemo-chair-$chair-${panel.join()}'),
                      initialValue: chair,
                      placeholder: const Text('Select chair'),
                      enabled: !busy,
                      options: [
                        for (final person in people.where(
                          (p) => panel.contains(p['id']),
                        ))
                          ShadOption(
                            value: (person['id'] as num).toInt(),
                            child: Text('${person['name']}'),
                          ),
                      ],
                      selectedOptionBuilder: (context, id) => Text(
                        '${people.firstWhere((p) => p['id'] == id)['name']}',
                      ),
                      onChanged: (value) => update(() => chair = value),
                    ),
                  ),
                  if (existing != null)
                    _field(
                      'Reason for rescheduling',
                      ShadInput(
                        controller: reason,
                        enabled: !busy,
                        maxLines: 2,
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamilyInter,
                          color: DefensysTokens.dangerText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final controller in [date, time, room, duration, reason]) {
      controller.dispose();
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final requirements = (item['requirements'] as List)
        .whereType<Map>()
        .toList();
    final results = {
      for (final row in (item['results'] as List? ?? []).whereType<Map>())
        '${row['requirement_id']}': '${row['status']}',
    };
    final remarks = TextEditingController(text: '${item['remarks'] ?? ''}');
    final canVerify = item['can_verify'] == true;
    final requestId = newOperationRequestId();
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => DefensysShadcnScope(
          child: ShadDialog(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 800),
            title: Text('${item['team_name']} · Re-demo'),
            description: Text(
              '${item['scheduled_date']} · ${item['start_time']} · ${item['room']}',
            ),
            actions: [
              ShadButton.outline(
                enabled: !busy,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              if (canVerify)
                ShadButton(
                  enabled:
                      !busy &&
                      requirements.every(
                        (row) => results.containsKey('${row['id']}'),
                      ) &&
                      (!results.containsValue('needs_work') ||
                          remarks.text.trim().isNotEmpty),
                  onPressed: () async {
                    update(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await _post('${item['id']}/verify/', {
                        'request_id': requestId,
                        'review_token': item['review_token'],
                        'results': [
                          for (final requirement in requirements)
                            {
                              'requirement_id': requirement['id'],
                              'status': results['${requirement['id']}'],
                            },
                        ],
                        'remarks': remarks.text.trim(),
                      });
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (mounted) {
                        showSuccessToast(
                          this.context,
                          'Verification recorded. Original verdict and scores retained.',
                        );
                        await _load();
                      }
                    } catch (failure) {
                      if (dialogContext.mounted) {
                        update(() {
                          busy = false;
                          error = '$failure';
                        });
                      }
                    }
                  },
                  child: Text(busy ? 'Confirming…' : 'Confirm verification'),
                ),
            ],
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Original outcome: ${defenseVerdictLabel('${(item['outcome'] as Map?)?['verdict'] ?? ''}')}',
                  ),
                  const SizedBox(height: 8),
                  Text('Assigned chair: ${item['chair_name']}'),
                  if ('${(item['outcome'] as Map?)?['instructions'] ?? ''}'
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('${(item['outcome'] as Map)['instructions']}'),
                  ],
                  if (item['original_assessment'] is Map)
                    for (final assessment
                        in ((item['original_assessment'] as Map)['assessments']
                                    as List? ??
                                [])
                            .whereType<Map>())
                      Text(
                        'Original panel score${'${assessment['title'] ?? ''}'.isEmpty ? '' : ' · ${assessment['title']}'}: ${assessment['score'] ?? 'Not recorded'}%',
                      ),
                  const SizedBox(height: 18),
                  Text(
                    'Required demonstrations',
                    style: DefensysTokens.sectionTitle.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${results.length}/${requirements.length} checked · ${results.values.where((value) => value == 'satisfied').length} satisfied',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  for (final requirement in requirements)
                    _field(
                      '${requirement['text']}',
                      canVerify
                          ? ShadSelect<String>(
                              initialValue: results['${requirement['id']}'],
                              placeholder: const Text('Not checked'),
                              enabled: !busy,
                              options: const [
                                ShadOption(
                                  value: 'not_checked',
                                  child: Text('Not checked'),
                                ),
                                ShadOption(
                                  value: 'satisfied',
                                  child: Text('Satisfied'),
                                ),
                                ShadOption(
                                  value: 'needs_work',
                                  child: Text('Needs work'),
                                ),
                              ],
                              selectedOptionBuilder: (context, value) =>
                                  Text(switch (value) {
                                    'satisfied' => 'Satisfied',
                                    'needs_work' => 'Needs work',
                                    _ => 'Not checked',
                                  }),
                              onChanged: (value) {
                                if (value != null) {
                                  update(() {
                                    if (value == 'not_checked') {
                                      results.remove('${requirement['id']}');
                                    } else {
                                      results['${requirement['id']}'] = value;
                                    }
                                  });
                                }
                              },
                            )
                          : Text(
                              {
                                    'satisfied': 'Satisfied',
                                    'needs_work': 'Needs work',
                                  }[results['${requirement['id']}']] ??
                                  'Awaiting verification',
                            ),
                    ),
                  _field(
                    'Verification remarks',
                    canVerify
                        ? ShadInput(
                            controller: remarks,
                            enabled: !busy,
                            maxLines: 4,
                            maxLength: 5000,
                            onChanged: (_) => update(() {}),
                          )
                        : Text(
                            remarks.text.isEmpty
                                ? 'No remarks recorded.'
                                : remarks.text,
                          ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'All items must be checked. Add remarks for any item that needs work. Other revision requirements remain separate.',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamilyInter,
                          color: DefensysTokens.dangerText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    remarks.dispose();
  }

  Future<void> _operate(Map<String, dynamic> item, String action) async {
    if (action == 'reschedule') {
      await _book(item, existing: item);
      return;
    }
    final reason = TextEditingController();
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => DefensysShadcnScope(
          child: ShadDialog(
            title: Text('${action.replaceAll('_', ' ')} re-demo'),
            actions: [
              ShadButton.outline(
                enabled: !busy,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
              ShadButton(
                enabled: !busy,
                onPressed: () async {
                  update(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await _post('${item['id']}/operate/', {
                      'action': action,
                      'revision': item['revision'],
                      'reason': reason.text.trim(),
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) await _load();
                  } catch (failure) {
                    if (dialogContext.mounted) {
                      update(() {
                        busy = false;
                        error = '$failure';
                      });
                    }
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  'Reason',
                  ShadInput(
                    controller: reason,
                    enabled: !busy,
                    maxLines: 3,
                    maxLength: 2000,
                  ),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
      ),
    );
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Scaffold(
      backgroundColor: DefensysTokens.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: DefensysTokens.surfaceOf(context),
        foregroundColor: DefensysTokens.textPrimaryOf(context),
        title: const Text('Re-demo'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(_error!),
                  ShadButton.outline(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
                if (_eligible.isNotEmpty || _eligibleOffset > 0) ...[
                  Text(
                    'Teams requiring re-demo',
                    style: DefensysTokens.sectionTitle.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final source in _eligible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${source['team_name']} · ${source['stage_label']}',
                          ),
                          ShadButton.outline(
                            onPressed: () => _book(source),
                            child: const Text('Schedule re-demo'),
                          ),
                        ],
                      ),
                    ),
                  if (_eligibleOffset > 0 ||
                      _eligibleOffset + 50 < _eligibleTotal)
                    Wrap(
                      spacing: 10,
                      children: [
                        ShadButton.outline(
                          enabled: _eligibleOffset > 0,
                          onPressed: () {
                            setState(() => _eligibleOffset -= 50);
                            _load();
                          },
                          child: const Text('Previous teams'),
                        ),
                        ShadButton.outline(
                          enabled: _eligibleOffset + 50 < _eligibleTotal,
                          onPressed: () {
                            setState(() => _eligibleOffset += 50);
                            _load();
                          },
                          child: const Text('Next teams'),
                        ),
                      ],
                    ),
                  const Divider(height: 30),
                ],
                if (_items.isNotEmpty)
                  Text(
                    'Re-demo schedule & history',
                    style: DefensysTokens.sectionTitle.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                const SizedBox(height: 14),
                if (_items.isEmpty && _eligible.isEmpty && _error == null)
                  ShadCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          size: 28,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No re-demo required',
                          style: DefensysTokens.sectionTitle.copyWith(
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _canManage
                              ? 'Teams appear here after the panel confirms a re-demo requirement. You can schedule them directly from their defense status.'
                              : 'Your assigned re-demos will appear here when scheduled.',
                        ),
                      ],
                    ),
                  ),
                for (final item in _items) ...[
                  ShadCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${item['team_name']}',
                          style: DefensysTokens.sectionTitle.copyWith(
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${item['stage_label']} · ${item['scheduled_date']} · ${item['start_time']} · ${item['room']}',
                        ),
                        const SizedBox(height: 6),
                        Text(_statusLabel(item)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ShadButton.outline(
                              onPressed: () => _open(item),
                              child: Text(
                                item['can_verify'] == true
                                    ? 'Open verification'
                                    : 'View record',
                              ),
                            ),
                            if (_canManage && item['status'] == 'scheduled')
                              ShadSelect<String>(
                                placeholder: const Text('Manage appointment'),
                                options: [
                                  for (final action in [
                                    'reschedule',
                                    'pause',
                                    'postpone',
                                    'no_show',
                                    'resume',
                                    'cancel',
                                  ])
                                    ShadOption(
                                      value: action,
                                      child: Text(action.replaceAll('_', ' ')),
                                    ),
                                ],
                                selectedOptionBuilder: (context, value) =>
                                    Text(value.replaceAll('_', ' ')),
                                onChanged: (action) {
                                  if (action != null) _operate(item, action);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_offset > 0 || _offset + 50 < _total)
                  Wrap(
                    spacing: 10,
                    children: [
                      ShadButton.outline(
                        enabled: _offset > 0,
                        onPressed: () {
                          setState(() => _offset -= 50);
                          _load();
                        },
                        child: const Text('Previous'),
                      ),
                      ShadButton.outline(
                        enabled: _offset + 50 < _total,
                        onPressed: () {
                          setState(() => _offset += 50);
                          _load();
                        },
                        child: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ),
    ),
  );
}
