import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import '../models/schedule_session_draft.dart';

/// Edits a local copy inline. Capacity and assignments change only on Save.
class SchedulerTimeBlocksEditor extends StatefulWidget {
  const SchedulerTimeBlocksEditor({
    super.key,
    required this.draft,
    required this.enabled,
    required this.onSaved,
    this.onEditingChanged,
  });

  final ScheduleSessionDraft draft;
  final bool enabled;
  final VoidCallback onSaved;
  final ValueChanged<bool>? onEditingChanged;

  @override
  State<SchedulerTimeBlocksEditor> createState() =>
      _SchedulerTimeBlocksEditorState();
}

class _SchedulerTimeBlocksEditorState extends State<SchedulerTimeBlocksEditor> {
  List<ScheduleSessionBlock>? _editingBlocks;
  final _duration = TextEditingController();
  bool get _editing => _editingBlocks != null;
  int get _minutes => int.tryParse(_duration.text.trim()) ?? 0;
  int get _capacity => scheduleBlocksCapacity(_editingBlocks!, _minutes);

  @override
  void dispose() {
    for (final block in _editingBlocks ?? <ScheduleSessionBlock>[]) {
      block.dispose();
    }
    _duration.dispose();
    super.dispose();
  }

  void _begin() {
    _duration.text = widget.draft.duration.text;
    setState(
      () => _editingBlocks = [
        for (final block in widget.draft.blocks)
          ScheduleSessionBlock(
            start: TextEditingController(text: block.start.text),
            end: TextEditingController(text: block.end.text),
          ),
      ],
    );
    widget.onEditingChanged?.call(true);
  }

  void _finish({bool save = false}) {
    if (save && _capacity == 0) return;
    final editing = _editingBlocks!;
    if (save) {
      final old = widget.draft.blocks.skip(1).toList();
      widget.draft.blocks.first.start.text = editing.first.start.text.trim();
      widget.draft.blocks.first.end.text = editing.first.end.text.trim();
      widget.draft.blocks.removeRange(1, widget.draft.blocks.length);
      widget.draft.blocks.addAll([
        for (final block in editing.skip(1))
          ScheduleSessionBlock(
            start: TextEditingController(text: block.start.text.trim()),
            end: TextEditingController(text: block.end.text.trim()),
          ),
      ]);
      widget.draft.duration.text = _duration.text.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final block in old) {
          block.dispose();
        }
      });
    }
    setState(() => _editingBlocks = null);
    widget.onEditingChanged?.call(false);
    if (save) widget.onSaved();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final block in editing) {
        block.dispose();
      }
    });
  }

  int _slots(ScheduleSessionBlock block, int duration) {
    final start = scheduleTimeMinutes(block.start.text.trim());
    final end = scheduleTimeMinutes(block.end.text.trim());
    return duration >= 15 && duration <= 240 && start >= 0 && end > start
        ? (end - start) ~/ duration
        : 0;
  }

  Widget _badge(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
    ),
    child: Text(
      value,
      style: DefensysTokens.caption.copyWith(
        color: DefensysTokens.textPrimaryOf(context),
      ),
    ),
  );

  Widget _break(List<ScheduleSessionBlock> blocks, int index) {
    if (index >= blocks.length - 1) return const SizedBox.shrink();
    final end = scheduleTimeMinutes(blocks[index].end.text.trim());
    final next = scheduleTimeMinutes(blocks[index + 1].start.text.trim());
    if (end < 0 || next <= end) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: DefensysTokens.borderOf(context))),
          const SizedBox(width: 10),
          Flexible(
            flex: 5,
            child: Text(
              'Break · ${blocks[index].end.text}–${blocks[index + 1].start.text} · ${next - end} min',
              textAlign: TextAlign.center,
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: DefensysTokens.borderOf(context))),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: DefensysTokens.caption.copyWith(
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _summary() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < widget.draft.blocks.length; i++) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final block = widget.draft.blocks[i];
              final count = _badge(
                '${_slots(block, int.tryParse(widget.draft.duration.text) ?? 0)} slots',
              );
              final time = Text(
                '${block.start.text} – ${block.end.text}',
                style: DefensysTokens.body.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              );
              final title = Text(
                'Block ${i + 1}',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              );
              return constraints.maxWidth < 350
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: time),
                            count,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(width: 80, child: title),
                        const SizedBox(width: 12),
                        Expanded(child: time),
                        const SizedBox(width: 12),
                        count,
                      ],
                    );
            },
          ),
        ),
        _break(widget.draft.blocks, i),
      ],
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              'Slot duration · ${widget.draft.duration.text} min / team',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            Text(
              '${widget.draft.capacity} slots total',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _editor() {
    final blocks = _editingBlocks!;
    final lastEnd = scheduleTimeMinutes(blocks.last.end.text.trim());
    final canAddBlock =
        widget.enabled &&
        blocks.length < 20 &&
        lastEnd >= 0 &&
        _minutes >= 15 &&
        _minutes <= 240 &&
        lastEnd + _minutes <= 1439;
    final overflow = (widget.draft.teamIds.length - _capacity).clamp(
      0,
      widget.draft.teamIds.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < blocks.length; i++) ...[
          Container(
            key: ValueKey('time-block-${widget.draft.key}-$i'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Block ${i + 1}',
                      style: DefensysTokens.body.copyWith(
                        color: DefensysTokens.textPrimaryOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _badge('${_slots(blocks[i], _minutes)} slots'),
                        if (i > 0)
                          ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            enabled: widget.enabled,
                            onPressed: () {
                              final removed = blocks.removeAt(i);
                              setState(() {});
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => removed.dispose(),
                              );
                            },
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (_, constraints) {
                    Widget input(
                      TextEditingController controller,
                      String edge,
                    ) => ShadInput(
                      key: ValueKey('time-block-$edge-${widget.draft.key}-$i'),
                      controller: controller,
                      enabled: widget.enabled,
                      placeholder: const Text('HH:mm'),
                      keyboardType: TextInputType.datetime,
                      onChanged: (_) => setState(() {}),
                    );
                    final start = _field(
                      'Start time (24-hour)',
                      input(blocks[i].start, 'start'),
                    );
                    final end = _field(
                      'End time (24-hour)',
                      input(blocks[i].end, 'end'),
                    );
                    return constraints.maxWidth < 360
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [start, const SizedBox(height: 16), end],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: start),
                              const SizedBox(width: 16),
                              Expanded(child: end),
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
          _break(blocks, i),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            key: ValueKey('add-time-block-${widget.draft.key}'),
            size: ShadButtonSize.sm,
            enabled: canAddBlock,
            onPressed: () {
              final start = scheduleTimeMinutes(blocks.last.end.text.trim());
              if (start < 0 ||
                  _minutes < 15 ||
                  _minutes > 240 ||
                  start + _minutes > 1439) {
                return;
              }
              setState(
                () => blocks.add(
                  ScheduleSessionBlock(
                    start: TextEditingController(
                      text: scheduleTimeLabel(start),
                    ),
                    end: TextEditingController(
                      text: scheduleTimeLabel(start + _minutes),
                    ),
                  ),
                ),
              );
            },
            leading: const Icon(LucideIcons.plus, size: 14),
            child: const Text('Add time block'),
          ),
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 200,
              child: _field(
                'Slot duration (minutes)',
                ShadInput(
                  key: ValueKey('session-slot-duration-${widget.draft.key}'),
                  controller: _duration,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session capacity',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_capacity slots',
                    style: DefensysTokens.body.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            _capacity == 0
                ? 'Use ordered, non-overlapping blocks that each fit a complete 15–240 minute slot.'
                : overflow > 0
                ? 'Saving returns $overflow ${overflow == 1 ? 'team' : 'teams'} to Unassigned.'
                : '${widget.draft.teamIds.length} teams assigned · ${_capacity - widget.draft.teamIds.length} slots available',
            style: DefensysTokens.caption.copyWith(
              color: _capacity == 0
                  ? Theme.of(context).colorScheme.error
                  : DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              enabled: widget.enabled,
              onPressed: () => _finish(),
              child: const Text('Cancel'),
            ),
            ShadButton(
              key: ValueKey('save-time-blocks-${widget.draft.key}'),
              enabled: widget.enabled && _capacity > 0,
              onPressed: () => _finish(save: true),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Time blocks',
            style: DefensysTokens.body.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          ShadButton.outline(
            key: ValueKey('edit-time-blocks-${widget.draft.key}'),
            enabled: widget.enabled && !_editing,
            onPressed: _begin,
            child: const Text('Edit time blocks'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_editing) _editor() else _summary(),
    ],
  );
}
