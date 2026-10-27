import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../../screens/web/admin/defense_stages/widgets/stage_deliverable_choices.dart';
import '../../screens/web/admin/defense_stages/widgets/stage_deliverable_overview.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'document_policy_editor.dart';
import 'deliverable_timing_fields.dart';
import 'repository_archive_naming_panel.dart';

List<Map<String, dynamic>> sharedDeliverableValues(dynamic value) =>
    (value as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

dynamic _cleanSharedValue(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!entry.key.toString().startsWith('_'))
          entry.key.toString(): _cleanSharedValue(entry.value),
    };
  }
  if (value is List) return value.map(_cleanSharedValue).toList();
  return value;
}

List<Map<String, dynamic>> sharedDeliverablePayload(
  List<Map<String, dynamic>> value,
) => sharedDeliverableValues(jsonDecode(jsonEncode(_cleanSharedValue(value))));

List<Map<String, dynamic>> defaultSharedDeliverables() => [
  {
    'deliverable_id': 'SHARED_CONCEPTS',
    'label': 'Concept papers',
    'deliverable_type': 'pre',
    'required': true,
    'file_format': 'pdf',
    'requirement_timing': 'scheduling',
    'deadline_hours_before': 24,
    'is_defense_material': true,
    'file_policy': {
      'mode': 'concepts',
      'slots': [
        {
          'key': 'paper',
          'label': 'Concept paper',
          'file_format': 'pdf',
          'required': true,
        },
      ],
    },
  },
  {
    'deliverable_id': 'SHARED_FINAL',
    'label': 'Approved concept paper',
    'deliverable_type': 'post',
    'required': true,
    'file_format': 'pdf',
    'requirement_timing': 'scheduling',
    'deadline_hours_before': 24,
    'file_policy': {'mode': 'single', 'purpose': 'approved_concept'},
  },
];

/// The section establishes ownership; the existing document mode establishes
/// repetition. There is no additional enable switch or submission-scope picker.
class SharedDeliverablesEditor extends StatefulWidget {
  const SharedDeliverablesEditor({
    super.key,
    required this.value,
    required this.teamDeliverables,
    required this.deliverableType,
    required this.onChanged,
    this.enabled = true,
    this.conceptsEnabled = false,
    this.isPit = false,
    this.stageLabel = '',
  });

  final List<Map<String, dynamic>> value;
  final List<Map<String, dynamic>> teamDeliverables;
  final String deliverableType;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final bool conceptsEnabled;
  final bool isPit;
  final String stageLabel;

  @override
  State<SharedDeliverablesEditor> createState() =>
      _SharedDeliverablesEditorState();
}

class _SharedDeliverablesEditorState extends State<SharedDeliverablesEditor> {
  Map<String, dynamic>? selectedItem;

  @override
  void didUpdateWidget(covariant SharedDeliverablesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.value.contains(selectedItem)) selectedItem = null;
  }

  String _nextId(List<Map<String, dynamic>> rows) {
    var index = 1;
    while (rows.any((row) => row['deliverable_id'] == 'SHARED_D$index')) {
      index++;
    }
    return 'SHARED_D$index';
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final teamDeliverables = widget.teamDeliverables;
    final deliverableType = widget.deliverableType;
    final onChanged = widget.onChanged;
    final enabled = widget.enabled;
    final conceptsEnabled = widget.conceptsEnabled;
    final isPit = widget.isPit;
    final stageLabel = widget.stageLabel;
    final rows = value
        .where((row) => row['deliverable_type'] == deliverableType)
        .toList();
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StageDeliverableGroupHeader(
            title: 'Whole shared system deliverables',
            description:
                'The PM submits files covering the shared system or entire section. Module teams do not upload these separately.',
            count: rows.length,
            addLabel: 'Add shared system deliverable',
            onAdd: enabled
                ? () {
                    final row = <String, dynamic>{
                      'deliverable_id': _nextId(value),
                      'label': '',
                      'deliverable_type': deliverableType,
                      'required': true,
                      'file_format': 'any',
                      'requirement_timing': 'scheduling',
                      'deadline_hours_before': 24,
                      'file_policy': {'mode': 'single'},
                    };
                    setState(() => selectedItem = row);
                    onChanged([...value, row]);
                  }
                : null,
          ),
          StageDeliverableOverview(
            items: rows,
            isPost: deliverableType == 'post',
            selectedItem: selectedItem,
            onSelect: (item) => setState(() => selectedItem = item),
            showGroupHeading: false,
            showReviewHint: false,
            showDoneEditingButton: false,
            emptyText: 'No shared system deliverables configured.',
            buildEditor: (row, index) => _SharedRequirementEditor(
              key: ValueKey(row['deliverable_id']),
              item: row,
              index: index,
              enabled: enabled && row['is_locked'] != true && row['has_data'] != true,
              conceptsEnabled: conceptsEnabled,
              isPit: isPit,
              stageLabel: stageLabel,
              siblings: rows,
              onChanged: () => onChanged(List.of(value)),
              onDone: () => setState(() => selectedItem = null),
              onRemove: () {
                setState(() => selectedItem = null);
                onChanged(
                  value.where((item) => !identical(item, row)).toList(),
                );
              },
            ),
          ),
          if (enabled &&
              teamDeliverables.any(
                (row) => row['deliverable_type'] == deliverableType,
              ))
            Align(
              alignment: Alignment.centerRight,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: () {
                  final result = List<Map<String, dynamic>>.of(value);
                  final names = rows
                      .map((row) => '${row['label']}'.trim().toLowerCase())
                      .toSet();
                  Map<String, dynamic>? firstCopy;
                  for (final source in teamDeliverables.where(
                    (row) => row['deliverable_type'] == deliverableType,
                  )) {
                    if (!names.add('${source['label']}'.trim().toLowerCase())) {
                      continue;
                    }
                    final copy = sharedDeliverablePayload([source]).single;
                    copy.remove('id');
                    copy.remove('legacy_purpose');
                    copy['deliverable_id'] = _nextId(result);
                    result.add(copy);
                    firstCopy ??= copy;
                  }
                  if (firstCopy != null) {
                    setState(() => selectedItem = firstCopy);
                  }
                  onChanged(result);
                },
                child: const Text('Copy team checklist'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedRequirementEditor extends StatefulWidget {
  const _SharedRequirementEditor({
    super.key,
    required this.item,
    required this.enabled,
    required this.conceptsEnabled,
    required this.onChanged,
    required this.onRemove,
    required this.isPit,
    required this.stageLabel,
    required this.siblings,
    required this.index,
    required this.onDone,
  });
  final Map<String, dynamic> item;
  final bool enabled, conceptsEnabled, isPit;
  final String stageLabel;
  final List<Map<String, dynamic>> siblings;
  final int index;
  final VoidCallback onChanged, onRemove, onDone;
  @override
  State<_SharedRequirementEditor> createState() =>
      _SharedRequirementEditorState();
}

class _SharedRequirementEditorState extends State<_SharedRequirementEditor> {
  final storage = PageStorageBucket();
  late final TextEditingController name;
  late final TextEditingController template;
  bool advanced = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.item['label'] ?? ''}');
    template = TextEditingController(
      text: '${widget.item['archive_file_template'] ?? ''}',
    );
  }

  @override
  void dispose() {
    name.dispose();
    template.dispose();
    super.dispose();
  }

  void change(String key, dynamic value) {
    widget.item[key] = value;
    if (['label', 'file_format'].contains(key)) {
      final policy = widget.item['file_policy'];
      if (policy is Map && policy['mode'] == 'concepts') {
        for (final slot in policy['slots'] as List? ?? []) {
          if (slot is Map) {
            slot['label'] = widget.item['label'];
            slot['file_format'] = widget.item['file_format'];
          }
        }
      }
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final post = item['deliverable_type'] == 'post';
    final format = '${item['file_format'] ?? 'any'}';
    final required = item['required'] == true;
    final border = DefensysTokens.borderOf(context);
    final nameField = TextFormField(
      key: ValueKey('shared-name-${item['deliverable_id']}'),
      controller: name,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: post
            ? 'Post-Defense Deliverable Name *'
            : 'Pre-Defense Requirement Name *',
        isDense: true,
        filled: true,
        fillColor: DefensysTokens.backgroundOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
      ),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: DefensysTokens.textPrimaryOf(context),
      ),
      validator: (value) => value?.trim().isEmpty != false
          ? 'Enter a shared deliverable name.'
          : null,
      onChanged: (value) => change('label', value.trim()),
    );
    final formatField = SizedBox(
      width: 210,
      child: StageFileFormatPicker(
        value: format,
        enabled: widget.enabled,
        onChanged: (value) => change('file_format', value),
      ),
    );
    final requiredField = ShadCheckbox(
      value: required,
      enabled: widget.enabled,
      label: const Text('Required'),
      onChanged: (value) => change('required', value),
    );
    final moreOptions = ShadButton.outline(
      size: ShadButtonSize.sm,
      leading: Icon(
        advanced ? Icons.expand_less_rounded : Icons.tune_rounded,
        size: 14,
      ),
      onPressed: () => setState(() => advanced = !advanced),
      child: Text(advanced ? 'Fewer options' : 'More options'),
    );
    return PageStorage(
      bucket: storage,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DefensysTokens.backgroundOf(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(9),
                ),
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      '#${widget.index}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Deliverable #${widget.index}${name.text.trim().isEmpty ? '' : ' · ${name.text.trim()}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.enabled ? widget.onRemove : null,
                    tooltip: 'Remove shared deliverable',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: widget.enabled
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth < 620
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              nameField,
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  formatField,
                                  requiredField,
                                  moreOptions,
                                ],
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
                              moreOptions,
                            ],
                          ),
                  ),
                  DocumentPolicyEditor(
                    value: Map<String, dynamic>.from(
                      item['file_policy'] as Map? ?? {},
                    ),
                    enabled: widget.enabled,
                    allowConcepts: widget.conceptsEnabled,
                    deliverableLabel: name.text,
                    fileFormat: format,
                    required: true,
                    onChanged: (value) {
                      if (value['mode'] == 'concepts') value.remove('purpose');
                      change('file_policy', value);
                    },
                  ),
                  if (advanced)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DefensysTokens.backgroundOf(context),
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!post)
                            DefenseMaterialToggle(
                              value: item['is_defense_material'] == true,
                              enabled: widget.enabled,
                              onChanged: (value) =>
                                  change('is_defense_material', value),
                            ),
                          if (post) ...[
                            ShadCheckbox(
                              value: item['is_restricted'] == true,
                              enabled: widget.enabled,
                              label: const Text('Restricted archive'),
                              onChanged: (value) =>
                                  change('is_restricted', value),
                            ),
                            const SizedBox(height: 10),
                            const StagePostDefenseReviewNotice(),
                            const SizedBox(height: 10),
                            RepositoryArchiveNamingPanel(
                              templateController: template,
                              deliverableLabel: name.text,
                              fileFormat: format,
                              isLocked: !widget.enabled,
                              isPit: widget.isPit,
                              stageOrEventLabel: widget.stageLabel,
                              siblingDeliverables: widget.siblings,
                              currentIndex: widget.siblings.indexOf(item),
                              onChanged: () => change(
                                'archive_file_template',
                                template.text.trim(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (!advanced)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: DefensysTokens.backgroundOf(context),
                            border: Border.all(color: border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 12),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  post
                                      ? 'Faculty review after defense'
                                      : 'Faculty review before scheduling',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: widget.onDone,
                      leading: const Icon(Icons.check_rounded, size: 14),
                      child: const Text('Done editing'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
