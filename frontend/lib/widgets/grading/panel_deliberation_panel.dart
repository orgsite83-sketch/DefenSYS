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
import '../defense/re_demo_workspace.dart';
import '../shadcn/defensys_shadcn_scope.dart';

class DefenseDecisionSummary extends StatelessWidget {
  const DefenseDecisionSummary({super.key, required this.decision});
  final Map<String, dynamic> decision;

  @override
  Widget build(BuildContext context) {
    final areas = (decision['revision_entries'] as List? ?? [])
        .whereType<Map>();
    final requirements = (decision['demo_requirements'] as List? ?? [])
        .whereType<Map>();
    const severities = {
      'none': 'No revision',
      'minor': 'Minor revision',
      'major': 'Major revision',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          defenseVerdictLabel('${decision['verdict']}'),
          style: DefensysTokens.sectionTitle.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        if ('${decision['selected_title'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Selected concept: ${decision['selected_title']}'),
          ),
        for (final area in areas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${area['label']}')),
                    Expanded(
                      child: Text(
                        severities[area['severity']] ?? 'Not recorded',
                      ),
                    ),
                  ],
                ),
                if ('${area['instructions'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${area['instructions']}'),
                ],
              ],
            ),
          ),
        if ('${decision['reason'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('${decision['reason']}'),
        ],
        if ('${decision['instructions'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('${decision['instructions']}'),
        ],
        if (requirements.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Required demonstrations',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final item in requirements)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• ${item['text']}'),
            ),
        ],
        if (decision['confirmed_by_name'] != null) ...[
          const SizedBox(height: 12),
          Text(
            'Confirmed by ${decision['confirmed_by_name']}',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: DefensysTokens.textSecondaryOf(context),
              fontSize: 12,
            ),
          ),
        ],
        if (decision['recording_method'] == 'documenter_minutes') ...[
          const SizedBox(height: 12),
          Text(
            decision['recorded_by_name'] != null
                ? 'Panel decision recorded by ${decision['recorded_by_name']}'
                : 'Panel decision recorded in the minutes',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

class PanelDeliberationPanel extends ConsumerStatefulWidget {
  const PanelDeliberationPanel({
    super.key,
    required this.grade,
    required this.isChair,
    this.onUpdated,
  });
  final Map<String, dynamic> grade;
  final bool isChair;
  final VoidCallback? onUpdated;

  @override
  ConsumerState<PanelDeliberationPanel> createState() =>
      _PanelDeliberationPanelState();
}

class _DemoEntry {
  _DemoEntry(this.areaId);
  String areaId;
  final text = TextEditingController();
}

class _RevisionEntry {
  _RevisionEntry({String? id}) : id = id ?? newOperationRequestId();
  final String id;
  final label = TextEditingController();
  final instructions = TextEditingController();
  String severity = '';

  void dispose() {
    label.dispose();
    instructions.dispose();
  }
}

class _PanelDeliberationPanelState
    extends ConsumerState<PanelDeliberationPanel> {
  late Map<String, dynamic> _grade;
  final _instructions = TextEditingController();
  final _reason = TextEditingController();
  final _amendmentReason = TextEditingController();
  final Map<String, String> _levels = {};
  final List<_DemoEntry> _requirements = [];
  final List<_RevisionEntry> _revisions = [];
  String _verdict = 'approved_with_revisions';
  String _selectedKey = '';
  String _requestId = newOperationRequestId();
  bool _demo = false, _busy = false, _amending = false;
  String? _error;

  Map get _workflow => _grade['workflow'] as Map? ?? {};
  Map get _policy => _workflow['deliberation'] as Map? ?? {};
  Map get _rule => _workflow['outcome_rule'] as Map? ?? {};
  bool get _chairRevisions => _policy['revision_mode'] == 'chair';
  List<Map> get _areas => _chairRevisions
      ? [
          for (var i = 0; i < _revisions.length; i++)
            {
              'id': _revisions[i].id,
              'label': _revisions[i].label.text.trim().isEmpty
                  ? 'Revision area ${i + 1}'
                  : _revisions[i].label.text.trim(),
              'allows_demo': true,
            },
        ]
      : (_policy['revision_areas'] as List? ?? []).whereType<Map>().toList();
  List<Map> get _qualifiers => (_rule['assessments'] as List? ?? [])
      .whereType<Map>()
      .where((row) => row['qualifies'] == true)
      .toList();

  @override
  void initState() {
    super.initState();
    _grade = widget.grade;
    _sync();
  }

  void _sync() {
    final allowed = (_rule['allowed_verdicts'] as List? ?? []).cast<String>();
    if (allowed.isNotEmpty && !allowed.contains(_verdict)) {
      _verdict = allowed.first;
    }
    if (_qualifiers.length == 1) _selectedKey = '${_qualifiers.single['key']}';
    if (!_qualifiers.any((row) => '${row['key']}' == _selectedKey)) {
      _selectedKey = '';
    }
    for (final area in _areas) {
      _levels.putIfAbsent('${area['id']}', () => '');
    }
  }

  @override
  void didUpdateWidget(covariant PanelDeliberationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _grade = widget.grade;
    if (oldWidget.grade['schedule_id'] != widget.grade['schedule_id']) {
      _levels.clear();
      _selectedKey = '';
      _instructions.clear();
      _reason.clear();
      _amendmentReason.clear();
      _amending = false;
      _error = null;
      for (final item in _revisions) {
        item.dispose();
      }
      _revisions.clear();
      for (final item in _requirements) {
        item.text.dispose();
      }
      _requirements.clear();
      _demo = false;
      _requestId = newOperationRequestId();
    }
    _sync();
  }

  @override
  void dispose() {
    _instructions.dispose();
    _reason.dispose();
    _amendmentReason.dispose();
    for (final item in _revisions) {
      item.dispose();
    }
    for (final item in _requirements) {
      item.text.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (_chairRevisions &&
        _verdict == 'approved_with_revisions' &&
        (_revisions.isEmpty ||
            _revisions.any(
              (item) =>
                  item.label.text.trim().isEmpty ||
                  item.severity.isEmpty ||
                  item.instructions.text.trim().isEmpty,
            ))) {
      setState(
        () => _error =
            'Add each revision area, choose Minor or Major, and describe the corrections.',
      );
      return;
    }
    setState(() => _error = null);
    final decision = {
      'request_id': _requestId,
      'review_token': _rule['review_token'],
      'verdict': _verdict,
      'selected_key': _verdict == 'for_redefense' ? '' : _selectedKey,
      'reason': _reason.text.trim(),
      'instructions': _instructions.text.trim(),
      'revision_entries': [
        if (_chairRevisions) ...[
          if (_verdict == 'approved_with_revisions')
            for (final entry in _revisions)
              {
                'area_id': entry.id,
                'label': entry.label.text.trim(),
                'severity': entry.severity,
                'instructions': entry.instructions.text.trim(),
              },
        ] else ...[
          for (final entry in _levels.entries)
            if (entry.value.isNotEmpty && _verdict != 'for_redefense')
              {'area_id': entry.key, 'severity': entry.value},
        ],
      ],
      're_demo_required': _verdict == 'approved_with_revisions' && _demo,
      'demo_requirements': [
        if (_verdict == 'approved_with_revisions' && _demo)
          for (final item in _requirements)
            {'area_id': item.areaId, 'text': item.text.text.trim()},
      ],
    };
    final data = _amending
        ? {
            'reason': _amendmentReason.text.trim(),
            'expected_updated_at': _grade['updated_at'],
            'changes': {
              'panel_decision': {
                ...(Map<String, dynamic>.from(decision)..remove('request_id')),
                'source_revision': (_policy['decision'] as Map)['revision'],
              },
            },
          }
        : decision;
    setState(() => _busy = true);
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse(
              '${ApiConfig.gradeCenterUrl}/${_grade['id']}/panel-decision/${_amending ? 'correction/' : ''}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final body = jsonDecode(response.body) as Map;
      if (response.statusCode != 200) {
        showErrorToast(
          context,
          '${body['detail'] ?? 'Unable to confirm the panel decision.'}',
        );
        return;
      }
      final wasAmending = _amending;
      setState(() {
        if (body['grade'] is Map) {
          _grade = Map<String, dynamic>.from(body['grade'] as Map);
        }
        _amending = false;
      });
      showSuccessToast(
        context,
        wasAmending
            ? 'Decision amendment requested for administrator review.'
            : 'Panel decision confirmed.',
      );
      widget.onUpdated?.call();
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Unable to confirm. Refresh to check whether the decision was recorded before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(label), const SizedBox(height: 7), child],
    ),
  );

  Widget _revisionFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 20),
      Text(
        'Required corrections',
        style: DefensysTokens.sectionTitle.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      for (final item in _revisions)
        Padding(
          key: ValueKey('chair-revision-${item.id}'),
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 1, color: DefensysTokens.borderOf(context)),
              _label(
                'Revision area',
                ShadInput(
                  key: ValueKey('chair-area-${item.id}'),
                  controller: item.label,
                  enabled: !_busy,
                  maxLength: 80,
                  placeholder: const Text('For example: System or Manuscript'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _label(
                'Revision level',
                ShadSelect<String>(
                  key: ValueKey('chair-severity-${item.id}-${item.severity}'),
                  initialValue: item.severity.isEmpty ? null : item.severity,
                  enabled: !_busy,
                  placeholder: const Text('Choose Minor or Major'),
                  options: const [
                    ShadOption(value: 'minor', child: Text('Minor revision')),
                    ShadOption(value: 'major', child: Text('Major revision')),
                  ],
                  selectedOptionBuilder: (_, value) => Text(
                    value == 'minor' ? 'Minor revision' : 'Major revision',
                  ),
                  onChanged: (value) {
                    if (value != null) setState(() => item.severity = value);
                  },
                ),
              ),
              _label(
                'Required corrections',
                ShadInput(
                  key: ValueKey('chair-instructions-${item.id}'),
                  controller: item.instructions,
                  enabled: !_busy,
                  maxLines: 3,
                  maxLength: 2000,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.ghost(
                  enabled: !_busy,
                  onPressed: () => setState(() {
                    _revisions.remove(item);
                    final removed = _requirements
                        .where((row) => row.areaId == item.id)
                        .toList();
                    _requirements.removeWhere((row) => row.areaId == item.id);
                    if (_revisions.isEmpty) _demo = false;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      item.dispose();
                      for (final row in removed) {
                        row.text.dispose();
                      }
                    });
                  }),
                  child: const Text('Remove revision area'),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      ShadButton.outline(
        enabled: !_busy && _revisions.length < 12,
        onPressed: () => setState(() => _revisions.add(_RevisionEntry())),
        child: const Text('Add revision area'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final official = _policy['decision'] as Map?;
    if (_policy['revision_mode'] == 'documenter') {
      return DefensysShadcnScope(
        child: official != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DefenseDecisionSummary(
                    decision: Map<String, dynamic>.from(official),
                  ),
                  if (official['re_demo_required'] == true) ...[
                    const SizedBox(height: 14),
                    ShadButton.outline(
                      onPressed: () => showReDemoWorkspace(
                        context,
                        sourceScheduleId: (_grade['schedule_id'] as num)
                            .toInt(),
                      ),
                      child: const Text('Re-demo requirements & schedule'),
                    ),
                  ],
                ],
              )
            : const Text('Awaiting the documenter’s recorded panel outcome.'),
      );
    }
    final allowed = _rule['allowed_verdicts'] as List? ?? [];
    final complete = _rule['panel_complete'] == true;
    final needsReason =
        _verdict == 'for_redefense' && _rule['outcome'] == 'approved';
    final demoAreas = _areas
        .where((area) => area['allows_demo'] == true)
        .toList();
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (official != null && !_amending) ...[
            DefenseDecisionSummary(
              decision: Map<String, dynamic>.from(official),
            ),
            if (widget.isChair &&
                _policy['can_request_correction'] == true) ...[
              const SizedBox(height: 14),
              ShadButton.outline(
                onPressed: () => setState(() {
                  _amending = true;
                  _verdict = '${official['verdict']}';
                  _selectedKey = '${official['selected_key'] ?? ''}';
                  _reason.text = '${official['reason'] ?? ''}';
                  _instructions.text = '${official['instructions'] ?? ''}';
                  for (final item in _revisions) {
                    item.dispose();
                  }
                  _revisions.clear();
                  _levels.clear();
                  for (final area
                      in (official['revision_entries'] as List? ?? [])
                          .whereType<Map>()) {
                    _levels['${area['area_id']}'] = '${area['severity']}';
                    if (_chairRevisions) {
                      _revisions.add(
                        _RevisionEntry(id: '${area['area_id']}')
                          ..label.text = '${area['label']}'
                          ..severity = '${area['severity']}'
                          ..instructions.text = '${area['instructions'] ?? ''}',
                      );
                    }
                  }
                  _demo = official['re_demo_required'] == true;
                  for (final item in _requirements) {
                    item.text.dispose();
                  }
                  _requirements.clear();
                  for (final item
                      in (official['demo_requirements'] as List? ?? [])
                          .whereType<Map>()) {
                    _requirements.add(
                      _DemoEntry('${item['area_id']}')
                        ..text.text = '${item['text']}',
                    );
                  }
                }),
                child: const Text('Request decision amendment'),
              ),
            ],
            if (official['re_demo_required'] == true) ...[
              const SizedBox(height: 14),
              ShadButton.outline(
                onPressed: () => showReDemoWorkspace(
                  context,
                  sourceScheduleId: (_grade['schedule_id'] as num).toInt(),
                ),
                child: const Text('Re-demo requirements & schedule'),
              ),
            ],
          ] else ...[
            Text(
              !complete
                  ? 'Awaiting panel evaluations'
                  : _rule['outcome'] == 'for_redefense'
                  ? 'Re-defense required · Awaiting chair confirmation'
                  : 'Awaiting panel decision',
              style: DefensysTokens.sectionTitle.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Panel qualifying score: ${_rule['qualifying_score']}%',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            if (!widget.isChair) ...[
              const SizedBox(height: 12),
              const Text(
                'The assigned panel chair records the decision agreed during in-person deliberation.',
              ),
            ] else ...[
              if (_amending) ...[
                _label(
                  'Amendment reason',
                  ShadInput(
                    controller: _amendmentReason,
                    maxLength: 2000,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The current decision remains official until the administrator approves this amendment.',
                ),
              ],
              _label(
                'Panel decision',
                ShadRadioGroup<String>(
                  key: ValueKey('panel-decision-$_verdict-${allowed.join()}'),
                  initialValue: _verdict,
                  enabled: !_busy && complete,
                  spacing: 12,
                  items: [
                    for (final value in [
                      'approved',
                      'approved_with_revisions',
                      'for_redefense',
                    ])
                      ShadRadio(
                        value: value,
                        enabled: allowed.contains(value),
                        label: Text(defenseVerdictLabel(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _verdict = value;
                        _error = null;
                      });
                    }
                  },
                ),
              ),
              if (_verdict != 'for_redefense' && _rule['per_concept'] == true)
                _label(
                  'Official concept',
                  ShadSelect<String>(
                    key: ValueKey('panel-concept-$_selectedKey'),
                    initialValue: _selectedKey.isEmpty ? null : _selectedKey,
                    placeholder: const Text('Choose a qualifying concept'),
                    enabled: !_busy,
                    options: [
                      for (final row in _qualifiers)
                        ShadOption(
                          value: '${row['key']}',
                          child: Text('${row['title']}'),
                        ),
                    ],
                    selectedOptionBuilder: (context, value) => Text(
                      '${_qualifiers.firstWhere((row) => '${row['key']}' == value)['title']}',
                    ),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedKey = value);
                    },
                  ),
                ),
              if (_chairRevisions && _verdict == 'approved_with_revisions')
                _revisionFields(),
              if (!_chairRevisions && _verdict != 'for_redefense')
                for (final area in _areas)
                  _label(
                    '${area['label']}',
                    ShadSelect<String>(
                      key: ValueKey(
                        'revision-${area['id']}-${_levels['${area['id']}']}',
                      ),
                      initialValue: (_levels['${area['id']}'] ?? '').isEmpty
                          ? null
                          : _levels['${area['id']}'],
                      placeholder: const Text('Select revision requirement'),
                      enabled: !_busy,
                      options: const [
                        ShadOption(value: 'none', child: Text('No revision')),
                        ShadOption(
                          value: 'minor',
                          child: Text('Minor revision'),
                        ),
                        ShadOption(
                          value: 'major',
                          child: Text('Major revision'),
                        ),
                      ],
                      selectedOptionBuilder: (context, value) => Text(
                        {
                          'none': 'No revision',
                          'minor': 'Minor revision',
                          'major': 'Major revision',
                        }[value]!,
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _levels['${area['id']}'] = value);
                        }
                      },
                    ),
                  ),
              if (needsReason)
                _label(
                  'Reason for re-defense despite the qualifying score',
                  ShadInput(
                    controller: _reason,
                    enabled: !_busy,
                    maxLines: 3,
                    maxLength: 2000,
                  ),
                ),
              _label(
                _verdict == 'for_redefense'
                    ? 'Required next action'
                    : 'Panel instructions',
                ShadInput(
                  controller: _instructions,
                  enabled: !_busy,
                  maxLines: 4,
                  maxLength: 5000,
                ),
              ),
              if (_verdict == 'approved_with_revisions' &&
                  demoAreas.isNotEmpty) ...[
                const SizedBox(height: 16),
                ShadCheckbox(
                  value: _demo,
                  enabled: !_busy,
                  onChanged: (value) => setState(() {
                    _demo = value;
                    if (value && _requirements.isEmpty) {
                      _requirements.add(_DemoEntry('${demoAreas.first['id']}'));
                    }
                  }),
                  label: const Text('Re-demo required · Verification only'),
                ),
                if (_demo) ...[
                  for (final item in _requirements)
                    _label(
                      'Required demonstration',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (demoAreas.length > 1)
                            ShadSelect<String>(
                              key: ValueKey(
                                'demo-area-${item.areaId}-${demoAreas.map((area) => area['id']).join()}',
                              ),
                              initialValue: item.areaId,
                              enabled: !_busy,
                              options: [
                                for (final area in demoAreas)
                                  ShadOption(
                                    value: '${area['id']}',
                                    child: Text('${area['label']}'),
                                  ),
                              ],
                              selectedOptionBuilder: (context, value) => Text(
                                '${demoAreas.firstWhere((area) => area['id'] == value)['label']}',
                              ),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => item.areaId = value);
                                }
                              },
                            ),
                          const SizedBox(height: 6),
                          ShadInput(
                            controller: item.text,
                            enabled: !_busy,
                            maxLines: 2,
                            maxLength: 1000,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ShadButton.ghost(
                              enabled: !_busy,
                              onPressed: () => setState(() {
                                _requirements.remove(item);
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => item.text.dispose(),
                                );
                              }),
                              child: const Text('Remove'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  ShadButton.outline(
                    enabled: !_busy && _requirements.length < 40,
                    onPressed: () => setState(
                      () => _requirements.add(
                        _DemoEntry('${demoAreas.first['id']}'),
                      ),
                    ),
                    child: const Text('Add demonstration requirement'),
                  ),
                ],
              ],
              const SizedBox(height: 22),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        color: DefensysTokens.isDark(context)
                            ? DefensysTokens.danger
                            : DefensysTokens.dangerText,
                      ),
                    ),
                  ),
                ),
              if ('${_policy['unavailable_reason'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('${_policy['unavailable_reason']}'),
                ),
              ShadButton(
                enabled:
                    !_busy && (_amending || _policy['can_confirm'] == true),
                onPressed: _confirm,
                backgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: Colors.white,
                child: Text(
                  _busy
                      ? 'Saving…'
                      : _amending
                      ? 'Request decision amendment'
                      : 'Confirm panel decision',
                ),
              ),
              if (_amending)
                ShadButton.ghost(
                  onPressed: () => setState(() => _amending = false),
                  child: const Text('Cancel amendment'),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
