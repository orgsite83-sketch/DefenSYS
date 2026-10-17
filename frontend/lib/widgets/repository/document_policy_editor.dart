import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

void ensureConceptPapers(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> config,
) {
  if (config['enabled'] != true ||
      items.any((d) => (d['file_policy'] as Map?)?['mode'] == 'concepts')) {
    return;
  }
  var number = 'CONCEPT_PAPERS';
  var suffix = 1;
  while (items.any((d) => d['deliverable_id'] == number)) {
    number = 'CONCEPT_PAPERS_${++suffix}';
  }
  items.add({
    'deliverable_id': number,
    'label': 'Concept Papers',
    'deliverable_type': 'pre',
    'required': true,
    'requirement_timing': 'scheduling',
    'deadline_hours_before': 24,
    'display_order': items.length + 1,
    'file_format': 'pdf',
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
  });
}

class WorkflowChoice extends StatelessWidget {
  const WorkflowChoice({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
      return ShadSelect<String>(
        key: ValueKey(value),
        initialValue: value,
        enabled: enabled,
        minWidth: width,
        maxWidth: width,
        selectedOptionBuilder: (_, value) => Text(
          options[value] ?? value,
          overflow: TextOverflow.ellipsis,
        ),
        options: options.entries.map(
          (e) => ShadOption(value: e.key, child: Text(e.value)),
        ),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    },
  );
}

class ConceptSettings extends StatelessWidget {
  const ConceptSettings({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.isPit = false,
  });
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;
  final bool isPit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = DefensysTokens.borderOf(context);
    final secondaryColor = DefensysTokens.textSecondaryOf(context);
    final requiredCount = value['required_count'] is int
        ? value['required_count'] as int
        : 3;
    final customCount = requiredCount > 3;

    Widget policyField(String label, Widget choice) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        choice,
      ],
    );

    return DefensysShadcnScope(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: DefensysTokens.backgroundOf(context),
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ShadCheckbox(
                      value: value['enabled'] == true,
                      enabled: enabled,
                      label: Text(
                        'Concept selection',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      sublabel: Text(
                        'Review proposed or assigned concepts and keep each defense attempt.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryColor,
                        ),
                      ),
                      onChanged: (v) =>
                          onChanged({'required_count': 3, ...value, 'enabled': v}),
                    ),
                  ),
                  if (value['enabled'] == true) ...[
                    const SizedBox(width: 8),
                    ShadBadge.secondary(
                      child: Text(
                        isPit ? 'PIT Track' : 'Stage Workflow',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value['enabled'] == true) ...[
              Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1080
                        ? 3
                        : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                    final fieldWidth =
                        (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 18,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: policyField(
                            'Concepts required per hearing',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                WorkflowChoice(
                                  value: customCount
                                      ? 'custom'
                                      : '$requiredCount',
                                  enabled: enabled,
                                  options: {
                                    '1': '1 concept',
                                    '2': '2 concepts',
                                    '3': '3 concepts',
                                    'custom': customCount
                                        ? '$requiredCount concepts (custom)'
                                        : 'Custom count…',
                                  },
                                  onChanged: (choice) => onChanged({
                                    ...value,
                                    'required_count': choice == 'custom'
                                        ? (customCount ? requiredCount : 4)
                                        : int.parse(choice),
                                  }),
                                ),
                                if (customCount) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.surfaceOf(context),
                                      borderRadius: BorderRadius.circular(
                                        DefensysTokens.radiusMd,
                                      ),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Custom count · 4–10',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: secondaryColor),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Fewer concepts',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: enabled && requiredCount > 4
                                              ? () => onChanged({
                                                  ...value,
                                                  'required_count':
                                                      requiredCount - 1,
                                                })
                                              : null,
                                          icon: const Icon(
                                            Icons.remove_rounded,
                                            size: 18,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 28,
                                          child: Text(
                                            '$requiredCount',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'More concepts',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: enabled && requiredCount < 10
                                              ? () => onChanged({
                                                  ...value,
                                                  'required_count':
                                                      requiredCount + 1,
                                                })
                                              : null,
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: policyField(
                            isPit
                                ? 'Instructor clearance before re-defense'
                                : 'Adviser clearance before re-defense',
                            WorkflowChoice(
                              value:
                                  value['review_policy']?.toString() ??
                                  'replacement',
                              enabled: enabled,
                              options: const {
                                'replacement': 'When concepts are replaced',
                                'always': 'Every re-defense',
                                'panel_requested':
                                    'Not required unless the panel requests it',
                              },
                              onChanged: (v) =>
                                  onChanged({...value, 'review_policy': v}),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: policyField(
                            isPit
                                ? 'Peer scores on repeat attempts'
                                : 'Adviser and peer scores on repeat attempts',
                            WorkflowChoice(
                              value:
                                  value['score_carryover']?.toString() ??
                                  'reassess',
                              enabled: enabled,
                              options: {
                                'reassess': 'Require fresh assessments',
                                'retain': isPit
                                    ? 'Retain peer scores'
                                    : 'Retain adviser and peer scores',
                              },
                              onChanged: (v) =>
                                  onChanged({...value, 'score_carryover': v}),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ShadAlert(
                  icon: const Icon(LucideIcons.info, size: 16),
                  description: Text(
                    isPit
                        ? 'Automatically adds required concept papers. Assigned projects/modules need one concept; other teams use the default count. Instructor review and panel approval remain required.'
                        : 'Automatically adds required concept papers. Teams submit the default number of concepts, or one concept when a project/module is assigned. Adviser review and panel approval remain required.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryColor,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DocumentPolicyEditor extends StatelessWidget {
  const DocumentPolicyEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowConcepts = false,
  });
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled, allowConcepts;
  @override
  Widget build(BuildContext context) {
    final mode = value['mode']?.toString() ?? 'single';
    final slots = (value['slots'] as List? ?? [])
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    void updateSlot(int index, String field, dynamic val) {
      final updated = slots.map((s) => Map<String, dynamic>.from(s)).toList();
      updated[index][field] = val;
      onChanged({...value, 'slots': updated});
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
    final secondaryColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 540;
                final choiceWidget = SizedBox(
                  width: isCompact ? double.infinity : 220,
                  child: WorkflowChoice(
                    value: mode,
                    enabled: enabled,
                    options: {
                      'single': 'One file',
                      'named': 'Named documents',
                      'multiple': 'Multiple attachments',
                      if (allowConcepts || mode == 'concepts')
                        'concepts': 'Documents for each concept',
                    },
                    onChanged: (mode) => onChanged({
                      'mode': mode,
                      if (mode == 'multiple') ...{'min_files': 1, 'max_files': 10},
                      if (mode == 'named' || mode == 'concepts')
                        'slots': [
                          {
                            'key': 'paper',
                            'label': mode == 'concepts'
                                ? 'Concept paper'
                                : 'Document',
                            'required': true,
                            'file_format': 'pdf',
                          },
                        ],
                    }),
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Documents in this deliverable',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      choiceWidget,
                    ],
                  );
                }

                return Row(
                  children: [
                    Text(
                      'Documents in this deliverable:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    choiceWidget,
                    if (mode == 'single') ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '(Single uploaded file)',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (mode == 'multiple') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  WorkflowChoice(
                    value: '${value['min_files'] ?? 1}',
                    enabled: enabled,
                    options: {
                      for (var i = 1; i <= 50; i++) '$i': 'At least $i',
                    },
                    onChanged: (v) =>
                        onChanged({...value, 'min_files': int.parse(v)}),
                  ),
                  WorkflowChoice(
                    value: '${value['max_files'] ?? 10}',
                    enabled: enabled,
                    options: {for (var i = 1; i <= 50; i++) '$i': 'Up to $i'},
                    onChanged: (v) =>
                        onChanged({...value, 'max_files': int.parse(v)}),
                  ),
                ],
              ),
            ],
            if (mode == 'named' || mode == 'concepts') ...[
              const SizedBox(height: 8),
              if (mode == 'concepts')
                const Text(
                  'These document slots repeat for each required concept.',
                ),
              for (var i = 0; i < slots.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShadInput(
                        key: ValueKey(slots[i]['key']),
                        initialValue: '${slots[i]['label'] ?? ''}',
                        enabled: enabled,
                        placeholder: const Text('Document name'),
                        onChanged: (v) => updateSlot(i, 'label', v),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          WorkflowChoice(
                            value: '${slots[i]['file_format'] ?? 'pdf'}',
                            enabled: enabled,
                            options: const {
                              'pdf': 'PDF',
                              'presentation': 'Pitch deck',
                              'document': 'Word / PDF',
                              'archive': 'Archive',
                              'image': 'Image',
                              'video': 'Video',
                              'spreadsheet': 'Spreadsheet',
                              'audio': 'Audio',
                              'any': 'Any format',
                            },
                            onChanged: (v) => updateSlot(i, 'file_format', v),
                          ),
                          ShadCheckbox(
                            value: slots[i]['required'] != false,
                            enabled: enabled,
                            label: const Text('Required'),
                            onChanged: (v) => updateSlot(i, 'required', v),
                          ),
                          ShadButton.ghost(
                            enabled: enabled && slots.length > 1,
                            child: const Text('Remove'),
                            onPressed: () {
                              final updated = [...slots]..removeAt(i);
                              onChanged({...value, 'slots': updated});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              ShadButton.outline(
                enabled: enabled && slots.length < 20,
                child: const Text('Add document slot'),
                onPressed: () => onChanged({
                  ...value,
                  'slots': [
                    ...slots,
                    {
                      'key': 'doc_${DateTime.now().microsecondsSinceEpoch}',
                      'label': 'Supporting document',
                      'required': true,
                      'file_format': 'pdf',
                    },
                  ],
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
