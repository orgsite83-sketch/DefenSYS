import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:defensys/theme/defensys_tokens.dart';

String scheduleReviewDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat.yMMMd().format(date);
}

String scheduleReviewTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return value;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return value;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}

/// Remains outside the review scroll view so actions are always reachable.
class ScheduleImportActionBar extends StatelessWidget {
  const ScheduleImportActionBar({
    super.key,
    required this.totalCount,
    required this.readyCount,
    required this.busy,
    required this.onSave,
    required this.onImport,
    required this.onDiscard,
    this.validating = false,
  });

  final int totalCount;
  final int readyCount;
  final bool busy;
  final bool validating;
  final VoidCallback onSave;
  final VoidCallback onImport;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final excluded = totalCount - readyCount;
    final summary = Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$readyCount of $totalCount slots ready to import',
            style: TextStyle(
              color: DefensysTokens.textPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            totalCount == 0
                ? 'No slots found. Check the spreadsheet format and replace the file.'
                : excluded > 0
                ? '$excluded ${excluded == 1 ? 'slot needs' : 'slots need'} attention and will stay in your draft.'
                : 'All slots passed validation. Review assignments before importing.',
            style: TextStyle(
              color: excluded > 0
                  ? DefensysTokens.goldOf(context)
                  : DefensysTokens.textSecondaryOf(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Draft options',
          enabled: !busy,
          onSelected: (_) => onDiscard(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'discard', child: Text('Discard draft')),
          ],
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onSave,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save draft'),
        ),
        ElevatedButton.icon(
          onPressed: busy || validating || readyCount == 0 ? null : onImport,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: busy || validating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            validating && !busy
                ? 'Checking rubrics...'
                : busy
                ? 'Importing slots...'
                : 'Import $readyCount ${readyCount == 1 ? 'slot' : 'slots'}',
          ),
        ),
      ],
    );

    return Container(
      key: const ValueKey('schedule_import_action_bar'),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 850
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [summary, const SizedBox(height: 12), actions],
                  )
                : Row(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 20),
                      actions,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class ScheduleImportFileSummary extends StatelessWidget {
  const ScheduleImportFileSummary({
    super.key,
    required this.fileName,
    required this.slotCount,
    required this.busy,
    required this.onReplace,
    required this.onViewGuide,
    this.savedAt,
  });

  final String? fileName;
  final int slotCount;
  final bool busy;
  final DateTime? savedAt;
  final VoidCallback onReplace;
  final VoidCallback onViewGuide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: DefensysTokens.textSecondaryOf(context),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName ?? 'Restored schedule',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$slotCount ${slotCount == 1 ? 'slot' : 'slots'} staged'
                      '${savedAt == null ? '' : ' · Saved at ${DateFormat.jm().format(savedAt!.toLocal())}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                ),
                onPressed: busy ? null : onViewGuide,
                icon: const Icon(Icons.help_outline_rounded, size: 16),
                label: const Text('View format guide'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onReplace,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Replace file'),
              ),
            ],
          );
          return constraints.maxWidth < 700
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 12), actions],
                )
              : Row(
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
        },
      ),
    );
  }
}

class ScheduleImportFilterBar extends StatelessWidget {
  const ScheduleImportFilterBar({
    super.key,
    required this.totalCount,
    required this.issueCount,
    required this.issuesOnly,
    required this.searchController,
    required this.onSearchChanged,
    required this.onIssuesOnlyChanged,
    required this.dates,
    required this.rooms,
    required this.selectedDate,
    required this.selectedRoom,
    required this.onDateChanged,
    required this.onRoomChanged,
    required this.onClear,
    required this.enabled,
  });

  final int totalCount;
  final int issueCount;
  final bool issuesOnly;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onIssuesOnlyChanged;
  final List<String> dates;
  final List<String> rooms;
  final String? selectedDate;
  final String? selectedRoom;
  final ValueChanged<String?> onDateChanged;
  final ValueChanged<String?> onRoomChanged;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        issuesOnly ||
        searchController.text.isNotEmpty ||
        selectedDate != null ||
        selectedRoom != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text('All ($totalCount)'),
                labelStyle: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  color: DefensysTokens.textPrimaryOf(context),
                  fontSize: 13,
                ),
                selectedColor: DefensysTokens.maroonOf(
                  context,
                ).withValues(alpha: 0.12),
                checkmarkColor: DefensysTokens.textPrimaryOf(context),
                selected: !issuesOnly,
                onSelected: enabled ? (_) => onIssuesOnlyChanged(false) : null,
              ),
              ChoiceChip(
                label: Text('Needs attention ($issueCount)'),
                labelStyle: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  color: DefensysTokens.textPrimaryOf(context),
                  fontSize: 13,
                ),
                selectedColor: DefensysTokens.maroonOf(
                  context,
                ).withValues(alpha: 0.12),
                checkmarkColor: DefensysTokens.textPrimaryOf(context),
                selected: issuesOnly,
                onSelected: enabled ? (_) => onIssuesOnlyChanged(true) : null,
              ),
              if (hasFilters)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.textSecondaryOf(context),
                  ),
                  onPressed: enabled ? onClear : null,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: searchController,
                enabled: enabled,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search teams, projects, advisers or panelists',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                ),
              );
              final filters = [
                if (dates.length > 1)
                  _dropdown(
                    context,
                    'Date',
                    dates,
                    selectedDate,
                    onDateChanged,
                    format: scheduleReviewDate,
                  ),
                if (rooms.length > 1)
                  _dropdown(
                    context,
                    'Room',
                    rooms,
                    selectedRoom,
                    onRoomChanged,
                  ),
              ];
              if (filters.isEmpty) return search;
              if (constraints.maxWidth < 750) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 12, children: filters),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  for (final filter in filters) ...[
                    const SizedBox(width: 12),
                    filter,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    BuildContext context,
    String label,
    List<String> values,
    String? selected,
    ValueChanged<String?> onChanged, {
    String Function(String)? format,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        // Refresh the FormField state when Clear filters resets its value.
        key: ValueKey('$label:$selected'),
        initialValue: values.contains(selected) ? selected : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          DropdownMenuItem(
            value: null,
            child: Text('All ${label.toLowerCase()}s'),
          ),
          for (final value in values)
            DropdownMenuItem(
              value: value,
              child: Text(
                format?.call(value) ?? value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class ScheduleImportSessionCard extends StatelessWidget {
  const ScheduleImportSessionCard({
    super.key,
    required this.index,
    required this.date,
    required this.room,
    required this.timeSpan,
    required this.chair,
    required this.panelMembers,
    required this.documenter,
    required this.totalCount,
    required this.issueCount,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.onDateChanged,
    required this.onRoomChanged,
    required this.table,
  });

  final int index;
  final String date;
  final String room;
  final String timeSpan;
  final String chair;
  final List<String> panelMembers;
  final String? documenter;
  final int totalCount;
  final int issueCount;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onRoomChanged;
  final Widget table;

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<({String date, String room})>(
      context: context,
      builder: (_) =>
          _SessionDetailsDialog(date: date, room: room, slotCount: totalCount),
    );
    if (result == null || !context.mounted) return;
    if (result.date != date) onDateChanged(result.date);
    if (result.room != room) onRoomChanged(result.room);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final primary = DefensysTokens.textPrimaryOf(context);
    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: expanded
                          ? 'Collapse session $index'
                          : 'Expand session $index',
                      onPressed: enabled ? onToggle : null,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${room.isEmpty || room == 'Unassigned' ? 'Room not assigned' : room} · ${date.isEmpty ? 'Date not set' : scheduleReviewDate(date)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: secondary),
                      onPressed: enabled ? () => _edit(context) : null,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit session'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Session $index · $timeSpan',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                      Text(
                        '$totalCount ${totalCount == 1 ? 'team' : 'teams'}',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                      if (issueCount > 0)
                        Text(
                          '$issueCount ${issueCount == 1 ? 'slot needs' : 'slots need'} attention',
                          style: TextStyle(
                            color: DefensysTokens.goldOf(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Chair: ${chair.isEmpty || chair == '-' ? 'Not assigned' : chair}',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                      Text(
                        'Panel: ${panelMembers.isEmpty ? 'Not assigned' : panelMembers.join(', ')}',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                      if (documenter != null)
                        Text(
                          'Documenter: ${documenter!.isEmpty || documenter == '-' ? 'Not assigned' : documenter}',
                          style: TextStyle(color: secondary, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            table,
          ],
        ],
      ),
    );
  }
}

class _SessionDetailsDialog extends StatefulWidget {
  const _SessionDetailsDialog({
    required this.date,
    required this.room,
    required this.slotCount,
  });

  final String date;
  final String room;
  final int slotCount;

  @override
  State<_SessionDetailsDialog> createState() => _SessionDetailsDialogState();
}

class _SessionDetailsDialogState extends State<_SessionDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _room;
  late final TextEditingController _date;

  @override
  void initState() {
    super.initState();
    _room = TextEditingController(
      text: widget.room == 'Unassigned' ? '' : widget.room,
    );
    _date = TextEditingController(text: widget.date);
  }

  @override
  void dispose() {
    _room.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date.text) ?? now;
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 3, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() => _date.text = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit session'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Changes apply to all ${widget.slotCount} slots in this session.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _date,
                  readOnly: true,
                  onTap: _pickDate,
                  decoration: const InputDecoration(
                    labelText: 'Session date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  validator: (value) => DateTime.tryParse(value ?? '') == null
                      ? 'Choose a session date'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: 'Room / venue'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a room or venue'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, (
                date: _date.text,
                room: _room.text.trim(),
              ));
            }
          },
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}
