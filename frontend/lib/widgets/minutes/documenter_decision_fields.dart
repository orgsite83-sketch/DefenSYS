import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../../utils/operation_request_id.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Local draft only. The minutes submission is the single official write.
class DocumenterDecisionFields extends StatefulWidget {
  const DocumenterDecisionFields({
    super.key,
    required this.value,
    required this.contextData,
    required this.onChanged,
    this.enabled = true,
  });
  final Map<String, dynamic> value, contextData;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;
  @override
  State<DocumenterDecisionFields> createState() =>
      _DocumenterDecisionFieldsState();
}

class _Area {
  _Area({String? id, String label = '', this.severity = ''})
    : id = id ?? newOperationRequestId(),
      label = TextEditingController(text: label);
  final String id;
  final TextEditingController label;
  String severity;
}

class _DocumenterDecisionFieldsState extends State<DocumenterDecisionFields> {
  late final String _requestId;
  String _verdict = '', _selectedKey = '';
  bool _demo = false;
  final _reason = TextEditingController(),
      _nextAction = TextEditingController();
  final _areas = <_Area>[];
  final _tasks = <TextEditingController>[];
  Map get _rule => widget.contextData['outcome_rule'] as Map? ?? {};
  @override
  void initState() {
    super.initState();
    final draft = widget.value;
    _requestId = draft['request_id']?.toString() ?? newOperationRequestId();
    _verdict = '${draft['verdict'] ?? ''}';
    _selectedKey = '${draft['selected_key'] ?? ''}';
    _reason.text = '${draft['reason'] ?? ''}';
    _nextAction.text = '${draft['instructions'] ?? ''}';
    _demo = draft['re_demo_required'] == true;
    for (final row
        in (draft['revision_entries'] as List? ?? []).whereType<Map>()) {
      _areas.add(
        _Area(
          id: '${row['area_id']}',
          label: '${row['label'] ?? ''}',
          severity: '${row['severity'] ?? ''}',
        ),
      );
    }
    for (final row
        in (draft['demo_requirements'] as List? ?? []).whereType<Map>()) {
      _tasks.add(TextEditingController(text: '${row['text'] ?? ''}'));
    }
  }

  void _change() {
    final revisions = _verdict == 'approved_with_revisions';
    widget.onChanged({
      'request_id': _requestId,
      'review_token': _rule['review_token'] ?? '',
      'verdict': _verdict,
      'selected_key': _verdict == 'for_redefense' ? '' : _selectedKey,
      'reason': _verdict == 'for_redefense' ? _reason.text : '',
      'instructions': _verdict == 'for_redefense' ? _nextAction.text : '',
      'revision_entries': [
        if (revisions)
          for (final area in _areas)
            {
              'area_id': area.id,
              'label': area.label.text,
              'severity': area.severity,
            },
      ],
      're_demo_required': revisions && _demo,
      'demo_requirements': [
        if (revisions && _demo)
          for (final task in _tasks) {'text': task.text},
      ],
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    _nextAction.dispose();
    for (final area in _areas) {
      area.label.dispose();
    }
    for (final task in _tasks) {
      task.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: DefensysTokens.body.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      const SizedBox(height: 7),
      control,
    ],
  );
  @override
  Widget build(BuildContext context) {
    final allowed = (_rule['allowed_verdicts'] as List? ?? []).cast<String>();
    final enabled = widget.enabled;
    final qualifiers = ((_rule['assessments'] as List?) ?? [])
        .whereType<Map>()
        .where((row) => row['qualifies'] == true)
        .toList();
    const labels = {
      'approved': 'Approved',
      'approved_with_revisions': 'Approved with revisions',
      'for_redefense': 'For re-defense',
    };
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Panel decision',
            style: DefensysTokens.sectionTitle.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Record the outcome announced by the assigned panel chair.',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          _field(
            'Verdict',
            ShadSelect<String>(
              key: ValueKey('documenter-verdict-$_verdict'),
              initialValue: labels.containsKey(_verdict) ? _verdict : null,
              enabled: enabled && allowed.isNotEmpty,
              placeholder: const Text('Select announced verdict'),
              options: [
                for (final entry in labels.entries)
                  if (allowed.contains(entry.key))
                    ShadOption(value: entry.key, child: Text(entry.value)),
              ],
              selectedOptionBuilder: (_, value) => Text(labels[value]!),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _verdict = value);
                  _change();
                }
              },
            ),
          ),
          if (allowed.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_rule['reason'] ?? ''}'.isNotEmpty
                    ? '${_rule['reason']}'
                    : 'Complete the required panel evaluations before recording the outcome.',
              ),
            ),
          if (_rule['per_concept'] == true &&
              _verdict.isNotEmpty &&
              _verdict != 'for_redefense') ...[
            const SizedBox(height: 16),
            _field(
              'Selected concept',
              ShadSelect<String>(
                key: ValueKey('documenter-concept-$_selectedKey'),
                initialValue:
                    qualifiers.any((row) => row['key'] == _selectedKey)
                    ? _selectedKey
                    : null,
                enabled: enabled,
                placeholder: const Text('Select the panel’s chosen concept'),
                options: [
                  for (final row in qualifiers)
                    ShadOption(
                      value: '${row['key']}',
                      child: Text('${row['title']}'),
                    ),
                ],
                selectedOptionBuilder: (_, value) => Text(
                  '${qualifiers.firstWhere((row) => row['key'] == value)['title']}',
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedKey = value);
                    _change();
                  }
                },
              ),
            ),
          ],
          if (_verdict == 'approved_with_revisions') ...[
            const SizedBox(height: 20),
            const Text('Revision summary'),
            const SizedBox(height: 10),
            for (final area in _areas)
              Padding(
                key: ValueKey('documenter-area-row-${area.id}'),
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final areaField = _field(
                          'Area',
                          ShadInput(
                            key: ValueKey('documenter-area-${area.id}'),
                            controller: area.label,
                            enabled: enabled,
                            maxLength: 80,
                            placeholder: const Text(
                              'For example: Manuscript or System',
                            ),
                            onChanged: (_) => _change(),
                          ),
                        );
                        final levelField = _field(
                          'Revision level',
                          ShadSelect<String>(
                            key: ValueKey(
                              'documenter-level-${area.id}-${area.severity}',
                            ),
                            initialValue: area.severity.isEmpty
                                ? null
                                : area.severity,
                            enabled: enabled,
                            placeholder: const Text('Choose Minor or Major'),
                            options: const [
                              ShadOption(
                                value: 'minor',
                                child: Text('Minor revision'),
                              ),
                              ShadOption(
                                value: 'major',
                                child: Text('Major revision'),
                              ),
                            ],
                            selectedOptionBuilder: (_, value) => Text(
                              value == 'minor'
                                  ? 'Minor revision'
                                  : 'Major revision',
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => area.severity = value);
                                _change();
                              }
                            },
                          ),
                        );
                        return constraints.maxWidth >= 460
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: areaField),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: levelField),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  areaField,
                                  const SizedBox(height: 8),
                                  levelField,
                                ],
                              );
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ShadButton.ghost(
                        enabled: enabled,
                        onPressed: () {
                          setState(() => _areas.remove(area));
                          _change();
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => area.label.dispose(),
                          );
                        },
                        child: const Text('Remove area'),
                      ),
                    ),
                  ],
                ),
              ),
            ShadButton.outline(
              enabled: enabled && _areas.length < 12,
              onPressed: () {
                setState(() => _areas.add(_Area()));
                _change();
              },
              child: const Text('Add revision area'),
            ),
            const SizedBox(height: 16),
            ShadCheckbox(
              value: _demo,
              enabled: enabled,
              label: const Text('Re-demo required'),
              onChanged: (value) {
                setState(() {
                  _demo = value;
                  if (value && _tasks.isEmpty) {
                    _tasks.add(TextEditingController());
                  }
                });
                _change();
              },
            ),
            if (_demo) ...[
              const SizedBox(height: 16),
              const Text('Required demonstrations'),
              const SizedBox(height: 6),
              Text(
                'These items appear in the next verification appointment.',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              for (final task in _tasks)
                Padding(
                  key: ObjectKey(task),
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShadInput(
                        controller: task,
                        enabled: enabled,
                        maxLength: 1000,
                        maxLines: 2,
                        placeholder: const Text(
                          'Describe what the panel must verify',
                        ),
                        onChanged: (_) => _change(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ShadButton.ghost(
                          enabled: enabled,
                          onPressed: () {
                            setState(() => _tasks.remove(task));
                            _change();
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => task.dispose(),
                            );
                          },
                          child: const Text('Remove demonstration'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              ShadButton.outline(
                enabled: enabled && _tasks.length < 40,
                onPressed: () {
                  setState(() => _tasks.add(TextEditingController()));
                  _change();
                },
                child: const Text('Add demonstration'),
              ),
            ],
          ],
          if (_verdict == 'for_redefense') ...[
            if (_rule['outcome'] == 'approved') ...[
              const SizedBox(height: 16),
              _field(
                'Panel’s reason for re-defense',
                ShadInput(
                  controller: _reason,
                  enabled: enabled,
                  maxLength: 2000,
                  maxLines: 2,
                  onChanged: (_) => _change(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _field(
              'Required next action',
              ShadInput(
                controller: _nextAction,
                enabled: enabled,
                maxLength: 5000,
                maxLines: 3,
                onChanged: (_) => _change(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
