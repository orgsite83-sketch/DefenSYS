import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import '../models/schedule_session_draft.dart';
import 'scheduler_people_picker.dart';

class SchedulerSessionEditor extends StatelessWidget {
  const SchedulerSessionEditor({
    super.key,
    required this.draft,
    required this.number,
    required this.faculty,
    required this.documenters,
    required this.externals,
    required this.capstone,
    required this.enabled,
    required this.onChanged,
    required this.onCustomize,
    required this.dateField,
    required this.timeField,
    required this.teamSelection,
    required this.onAddBlock,
    required this.onRemoveBlock,
    this.onRemove,
  });

  final ScheduleSessionDraft draft;
  final int number;
  final List<Map<String, dynamic>> faculty, documenters, externals;
  final bool capstone, enabled;
  final VoidCallback onChanged, onCustomize;
  final VoidCallback? onRemove;
  final Widget Function(TextEditingController) dateField, timeField;
  final Widget teamSelection;
  final VoidCallback onAddBlock;
  final ValueChanged<int> onRemoveBlock;

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth < 360
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          )
        : Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Session $number',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: Text(
                '${draft.teamIds.length} selected · ${draft.capacity} available',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: enabled ? onRemove : null,
                tooltip: 'Remove session $number',
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 12),
        teamSelection,
        const SizedBox(height: 16),
        _pair(
          _field('Date *', dateField(draft.date)),
          _field(
            'Room / venue *',
            ShadInput(
              controller: draft.room,
              enabled: enabled,
              placeholder: const Text('e.g. Lab 3'),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Defense time blocks',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          'Teams are scheduled inside these blocks. Gaps are breaks.',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        for (int i = 0; i < draft.blocks.length; i++) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Block ${i + 1}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (i > 0)
                IconButton(
                  onPressed: enabled ? () => onRemoveBlock(i) : null,
                  tooltip: 'Remove time block ${i + 1}',
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _pair(
            _field('Start time *', timeField(draft.blocks[i].start)),
            _field('End time *', timeField(draft.blocks[i].end)),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            key: ValueKey('add-time-block-$number'),
            size: ShadButtonSize.sm,
            enabled: enabled && draft.blocks.length < 20,
            onPressed: enabled && draft.blocks.length < 20 ? onAddBlock : null,
            leading: const Icon(LucideIcons.plus, size: 14),
            child: const Text('Add time block'),
          ),
        ),
        const SizedBox(height: 16),
        _field(
          'Slot duration (minutes) *',
          ShadInput(
            controller: draft.duration,
            enabled: enabled,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            key: ValueKey('customize-staff-$number'),
            size: ShadButtonSize.sm,
            enabled: enabled,
            onPressed: enabled ? onCustomize : null,
            leading: Icon(
              draft.customStaff ? LucideIcons.rotateCcw : LucideIcons.users,
              size: 14,
            ),
            child: Text(
              draft.customStaff
                  ? 'Use shared staff defaults'
                  : 'Customize staff for this session',
            ),
          ),
        ),
        if (draft.customStaff) ...[
          const SizedBox(height: 16),
          _field(
            'Faculty panelists *',
            SchedulerPeoplePicker(
              people: faculty,
              selected: draft.panelists,
              enabled: enabled,
              placeholder: 'Choose session panelists',
              onChanged: (ids) {
                draft.panelists = ids;
                if (!ids.contains(draft.chair)) draft.chair = ids.firstOrNull;
                if (ids.contains(draft.documenter)) draft.documenter = null;
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 16),
          _field(
            'Presiding panel chair',
            SchedulerPeoplePicker(
              people: faculty
                  .where((p) => draft.panelists.contains(p['id']))
                  .toList(),
              selected: {if (draft.chair != null) draft.chair!},
              multiple: false,
              enabled: enabled,
              placeholder: 'Choose session chair',
              onChanged: (ids) {
                draft.chair = ids.firstOrNull;
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 16),
          _field(
            'External evaluators',
            SchedulerPeoplePicker(
              people: externals,
              selected: draft.externals,
              enabled: enabled,
              placeholder: 'Choose session evaluators',
              onChanged: (ids) {
                draft.externals = ids;
                onChanged();
              },
            ),
          ),
          if (capstone) ...[
            const SizedBox(height: 16),
            _field(
              'Documenter',
              SchedulerPeoplePicker(
                people: documenters
                    .where((p) => !draft.panelists.contains(p['id']))
                    .toList(),
                selected: {if (draft.documenter != null) draft.documenter!},
                multiple: false,
                enabled: enabled,
                placeholder: 'Choose session documenter',
                onChanged: (ids) {
                  draft.documenter = ids.firstOrNull;
                  onChanged();
                },
              ),
            ),
          ],
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'Uses the shared faculty, chair, external evaluators${capstone ? ' and documenter' : ''}.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    ),
  );
}
