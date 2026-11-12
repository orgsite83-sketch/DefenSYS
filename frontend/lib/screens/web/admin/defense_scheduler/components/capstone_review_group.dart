import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import '../models/capstone_planning_draft.dart';

/// Review-only presentation; people setup keeps its own expansion state.
/// Keep hover overlays outside these movable rows: a fast native drop can
/// reparent a live tooltip portal during the responsive list's layout pass.
class CapstoneReviewGroup extends StatefulWidget {
  const CapstoneReviewGroup({
    super.key,
    required this.group,
    required this.teams,
    required this.slots,
    required this.rosters,
    required this.index,
    required this.count,
    required this.expanded,
    required this.enabled,
    required this.keyboardActive,
    required this.updating,
    required this.onToggle,
    required this.onPickUp,
    required this.onDrop,
    required this.onCancel,
    required this.onMove,
    required this.onAccessibleMove,
    required this.onPointerCancel,
    required this.onMoveTeam,
    required this.facultyName,
    required this.externalName,
    this.intake,
  });

  final CapstoneAdviserGroup group;
  final List<Map<String, dynamic>> teams, slots;
  final Map<int, Map<String, dynamic>> rosters;
  final int index, count;
  final bool expanded, enabled, keyboardActive, updating;
  final String? intake;
  final VoidCallback onToggle, onPickUp, onDrop, onCancel, onPointerCancel;
  final ValueChanged<int> onMove, onAccessibleMove;
  final void Function(int teamId, int delta) onMoveTeam;
  final String Function(int) facultyName, externalName;

  @override
  State<CapstoneReviewGroup> createState() => _CapstoneReviewGroupState();
}

class _CapstoneReviewGroupState extends State<CapstoneReviewGroup> {
  final _focus = FocusNode();
  bool _focused = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  TextStyle get _muted => TextStyle(
    fontFamily: DefensysTokens.fontFamilyInter,
    fontSize: 12,
    color: DefensysTokens.textSecondaryOf(context),
  );
  static const _nameStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamilyInter,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent) {
      widget.keyboardActive ? widget.onDrop() : widget.onPickUp();
      return KeyEventResult.handled;
    }
    if (widget.keyboardActive) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        widget.onMove(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.tab) {
        widget.onCancel();
        return key == LogicalKeyboardKey.tab
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _grip() => Semantics(
    label:
        'Reorder ${widget.group.name}, position ${widget.index + 1} of ${widget.count}',
    hint:
        'Press Space or Enter to pick up, arrow keys to move, and Space or Enter to drop. Escape cancels.',
    selected: widget.keyboardActive,
    customSemanticsActions: widget.enabled
        ? {
            if (widget.index > 0)
              const CustomSemanticsAction(label: 'Move earlier'): () =>
                  widget.onAccessibleMove(-1),
            if (widget.index < widget.count - 1)
              const CustomSemanticsAction(label: 'Move later'): () =>
                  widget.onAccessibleMove(1),
          }
        : null,
    child: Focus(
      key: ValueKey('review-handle-${widget.group.key}'),
      focusNode: _focus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _key,
      onFocusChange: (value) {
        if (mounted) setState(() => _focused = value);
      },
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        onPointerCancel: (_) => widget.onPointerCancel(),
        child: ReorderableDragStartListener(
          index: widget.index,
          enabled: widget.enabled && !widget.keyboardActive,
          child: MouseRegion(
            cursor: widget.enabled
                ? SystemMouseCursors.grab
                : SystemMouseCursors.basic,
            child: Container(
              width: 34,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _focused
                      ? DefensysTokens.maroonOf(context)
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 19,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String _range() {
    if (widget.slots.isEmpty) return 'Not allocated';
    final first = widget.slots.first, last = widget.slots.last;
    String day(dynamic value) =>
        DateFormat('EEE, MMM d').format(DateTime.parse('$value'));
    String time(dynamic value) =>
        DateFormat.jm().format(DateTime.parse('2000-01-01 $value'));
    return first['scheduled_date'] == last['scheduled_date']
        ? '${day(first['scheduled_date'])} · ${time(first['start_time'])} – ${time(last['end_time'])}'
        : '${day(first['scheduled_date'])}, ${time(first['start_time'])} → ${day(last['scheduled_date'])}, ${time(last['end_time'])}';
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      border: Border.all(
        color: widget.keyboardActive
            ? DefensysTokens.maroonOf(context)
            : DefensysTokens.borderOf(context),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _grip(),
              const SizedBox(width: 4),
              SizedBox(
                width: 30,
                child: Text(
                  '${widget.index + 1}'.padLeft(2, '0'),
                  style: _muted.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.group.name, style: _nameStyle),
                    const SizedBox(height: 5),
                    Text(
                      '${widget.teams.length} ${widget.teams.length == 1 ? 'team' : 'teams'}${widget.updating ? ' · Updating times…' : ''}${widget.intake == null ? '' : ' · ${widget.intake}'}',
                      style: _muted,
                    ),
                    const SizedBox(height: 4),
                    Text(_range(), style: _muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.ghost(
                key: ValueKey('review-expand-${widget.group.key}'),
                size: ShadButtonSize.sm,
                enabled: widget.enabled && !widget.keyboardActive,
                onPressed: widget.onToggle,
                child: Semantics(
                  label:
                      '${widget.expanded ? 'Hide' : 'View'} teams for ${widget.group.name}',
                  expanded: widget.expanded,
                  child: Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: _details(),
          ),
      ],
    ),
  );

  Widget _details() {
    final signatures = widget.rosters.values
        .map((roster) => CapstoneRosterDraft.fromJson(roster).signature)
        .toSet();
    final shared = signatures.length == 1;
    final days =
        widget.slots.map((slot) => '${slot['scheduled_date']}').toSet().toList()
          ..sort();
    final allocated = widget.slots
        .map((slot) => capstoneId(slot['team_id']))
        .toSet();
    final unallocated = widget.teams
        .where((team) => !allocated.contains(capstoneId(team['id'])))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 16),
        for (final day in days) ...[
          Text(
            DateFormat('EEEE, MMM d').format(DateTime.parse(day)),
            style: _muted,
          ),
          const SizedBox(height: 8),
          for (final slot in widget.slots.where(
            (slot) => slot['scheduled_date'] == day,
          ))
            _team(
              capstoneId(slot['team_id'])!,
              '${slot['team_name']}',
              '${_clock(slot['start_time'])} – ${_clock(slot['end_time'])}',
              shared ? null : widget.rosters[capstoneId(slot['team_id'])],
            ),
        ],
        for (final team in unallocated)
          _team(
            capstoneId(team['id'])!,
            '${team['name']}',
            'Not allocated',
            shared ? null : widget.rosters[capstoneId(team['id'])],
          ),
        if (shared && widget.rosters.isNotEmpty) ...[
          const SizedBox(height: 6),
          Divider(color: DefensysTokens.borderOf(context), height: 20),
          _people(widget.rosters.values.first),
        ],
      ],
    );
  }

  String _clock(dynamic value) =>
      DateFormat.jm().format(DateTime.parse('2000-01-01 $value'));

  Widget _team(
    int teamId,
    String name,
    String time,
    Map<String, dynamic>? roster,
  ) => Padding(
    key: ValueKey('review-team-$teamId'),
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: constraints.maxWidth < 520
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: _nameStyle.copyWith(fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(time, style: _muted),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: _nameStyle.copyWith(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(time, style: _muted),
                        ],
                      ),
              ),
              if (widget.teams.length > 1) ...[
                const SizedBox(width: 12),
                _teamMoveButton(teamId, name, -1),
                _teamMoveButton(teamId, name, 1),
              ],
            ],
          ),
        ),
        if (roster != null) ...[const SizedBox(height: 12), _people(roster)],
      ],
    ),
  );

  Widget _teamMoveButton(int teamId, String name, int delta) {
    final index = widget.teams.indexWhere(
      (team) => capstoneId(team['id']) == teamId,
    );
    final enabled =
        widget.enabled &&
        !widget.keyboardActive &&
        !widget.updating &&
        index >= 0 &&
        index + delta >= 0 &&
        index + delta < widget.teams.length;
    return Semantics(
      label: 'Move $name ${delta < 0 ? 'earlier' : 'later'}',
      child: ShadButton.ghost(
        key: ValueKey('review-team-$teamId-${delta < 0 ? 'up' : 'down'}'),
        size: ShadButtonSize.sm,
        width: 24,
        height: 18,
        padding: EdgeInsets.zero,
        enabled: enabled,
        onPressed: enabled ? () => widget.onMoveTeam(teamId, delta) : null,
        child: Icon(
          delta < 0 ? LucideIcons.arrowUp : LucideIcons.arrowDown,
          size: 14,
        ),
      ),
    );
  }

  Widget _people(Map<String, dynamic> roster) {
    String faculty(dynamic id) => capstoneId(id) == null
        ? 'Not assigned'
        : widget.facultyName(capstoneId(id)!);
    final panels = (roster['panelist_ids'] as List? ?? []).where(
      (id) => capstoneId(id) != capstoneId(roster['chair_panelist_id']),
    );
    final external = (roster['external_evaluator_ids'] as List? ?? [])
        .map(capstoneId)
        .whereType<int>()
        .toList();
    final fields = <(String, String)>[
      ('Panel chair', faculty(roster['chair_panelist_id'])),
      (
        'Panel members',
        panels.isEmpty ? 'None' : panels.map(faculty).join(', '),
      ),
      if (external.isNotEmpty)
        ('External panelists', external.map(widget.externalName).join(', ')),
      ('Documenter', faculty(roster['documenter_id'])),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640
            ? 3
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field.$1, style: _muted),
                    const SizedBox(height: 4),
                    Text(
                      field.$2,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
