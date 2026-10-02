import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

String scheduleReviewTimeRange(String start, String end) {
  final first = scheduleReviewTime(start), last = scheduleReviewTime(end);
  final period = RegExp(r' (AM|PM)$').firstMatch(first)?.group(1);
  if (end.isEmpty) return first;
  return '${period != null && last.endsWith(' $period') ? first.replaceFirst(RegExp(r' (AM|PM)$'), '') : first}–$last';
}

typedef ScheduleTimingPreview = ({
  int changed,
  int issueCount,
  List<String> sampleTimes,
});

Future<({int duration, bool reflow})?> showScheduleDurationEditor(
  BuildContext context, {
  required int duration,
  required bool reflow,
  required ScheduleTimingPreview Function(int, bool) preview,
}) => showDialog<({int duration, bool reflow})>(
  context: context,
  builder: (_) => _ScheduleDurationDialog(
    duration: duration,
    reflow: reflow,
    preview: preview,
  ),
);

class _ScheduleDurationDialog extends StatefulWidget {
  const _ScheduleDurationDialog({
    required this.duration,
    required this.reflow,
    required this.preview,
  });

  final int duration;
  final bool reflow;
  final ScheduleTimingPreview Function(int, bool) preview;

  @override
  State<_ScheduleDurationDialog> createState() =>
      _ScheduleDurationDialogState();
}

class _ScheduleDurationDialogState extends State<_ScheduleDurationDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _duration;
  late bool _reflow;

  @override
  void initState() {
    super.initState();
    _duration = TextEditingController(text: '${widget.duration}');
    _reflow = widget.reflow;
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = int.tryParse(_duration.text);
    final valid = duration != null && duration >= 15 && duration <= 240;
    final preview = valid ? widget.preview(duration, _reflow) : null;
    final secondary = DefensysTokens.textSecondaryOf(context);
    return AlertDialog(
      title: const Text('Change slot duration'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set the time allotted to each team.',
                  style: TextStyle(color: secondary),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _duration,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutes per slot',
                    suffixText: 'minutes',
                    helperText: '15–240 minutes',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (_) {
                    final value = int.tryParse(_duration.text);
                    return value != null && value >= 15 && value <= 240
                        ? null
                        : 'Enter 15 to 240 minutes';
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in [30, 45, 60, 90, 120])
                      ChoiceChip(
                        label: Text('$minutes min'),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          fontSize: 13,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                        selectedColor: DefensysTokens.maroonOf(
                          context,
                        ).withValues(alpha: .15),
                        selected: minutes == duration,
                        onSelected: (_) =>
                            setState(() => _duration.text = '$minutes'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Shift later slots',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _reflow
                        ? 'Keep the first start and original breaks in each room/day. Later sessions move too.'
                        : 'Keep spreadsheet start times. Overlapping slots will need attention.',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                  value: _reflow,
                  onChanged: (value) => setState(() => _reflow = value),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Schedule preview',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final time in preview.sampleTimes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              time,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${preview.changed} start times adjusted · ${preview.issueCount} slots need attention',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ),
                  ),
                ],
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
            if (_form.currentState!.validate()) {
              Navigator.pop(context, (
                duration: int.parse(_duration.text),
                reflow: _reflow,
              ));
            }
          },
          child: const Text('Apply duration'),
        ),
      ],
    );
  }
}

/// Summary and import actions for the entire draft, independent of filters.
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
    this.validationFailed = false,
    this.showDraftOptions = true,
    this.savedAt,
  });

  final int totalCount;
  final int readyCount;
  final bool busy;
  final bool validating;
  final bool validationFailed;
  final bool showDraftOptions;
  final DateTime? savedAt;
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
            validating
                ? 'Checking schedule…'
                : validationFailed
                ? 'Schedule validation unavailable'
                : '$readyCount of $totalCount slots ready to import',
            style: TextStyle(
              color: DefensysTokens.textPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (savedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Draft saved in this browser · ${TimeOfDay.fromDateTime(savedAt!).format(context)}',
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          const SizedBox(height: 3),
          Text(
            validating
                ? 'Checking rubrics and existing appointments.'
                : validationFailed
                ? 'Retry validation to finish reviewing this schedule.'
                : totalCount == 0
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
        if (showDraftOptions)
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
          onPressed: busy || validating || validationFailed || readyCount == 0
              ? null
              : onImport,
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
                ? 'Checking schedule...'
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
          padding: EdgeInsets.symmetric(
            horizontal: showDraftOptions ? 24 : 0,
            vertical: 14,
          ),
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
    this.restored = false,
    this.onDismissRestored,
  });

  final String? fileName;
  final int slotCount;
  final bool busy;
  final DateTime? savedAt;
  final bool restored;
  final VoidCallback? onDismissRestored;
  final VoidCallback onReplace;
  final VoidCallback onViewGuide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
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
                      '${restored ? ' · Draft restored.' : ''}'
                      '${savedAt == null ? '' : ' · Saved at ${DateFormat.jm().format(savedAt!.toLocal())}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (restored)
                IconButton(
                  tooltip: 'Dismiss draft notification',
                  onPressed: busy ? null : onDismissRestored,
                  icon: const Icon(Icons.close_rounded, size: 16),
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
    final tabs = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tab in [
          (false, 'All ($totalCount)'),
          (true, 'Needs attention ($issueCount)'),
        ])
          ChoiceChip(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            backgroundColor: DefensysTokens.surfaceOf(context),
            label: Text(tab.$2),
            showCheckmark: false,
            labelStyle: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              color: DefensysTokens.textPrimaryOf(context),
              fontSize: 12,
              fontWeight: issuesOnly == tab.$1
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
            selectedColor: DefensysTokens.surfaceHigherOf(context),
            selected: issuesOnly == tab.$1,
            onSelected: enabled ? (_) => onIssuesOnlyChanged(tab.$1) : null,
          ),
        if (hasFilters)
          TextButton(
            onPressed: enabled ? onClear : null,
            child: const Text('Clear filters'),
          ),
      ],
    );
    final search = TextField(
      controller: searchController,
      enabled: enabled,
      onChanged: onSearchChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search teams, projects or faculty',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
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
          horizontal: 12,
          vertical: 13,
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
        _dropdown(context, 'Room', rooms, selectedRoom, onRoomChanged),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1180) {
          return Row(
            children: [
              tabs,
              const SizedBox(width: 20),
              Expanded(child: search),
              for (final filter in filters) ...[
                const SizedBox(width: 12),
                filter,
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabs,
            const SizedBox(height: 12),
            if (constraints.maxWidth >= 750)
              Row(
                children: [
                  Expanded(child: search),
                  for (final filter in filters) ...[
                    const SizedBox(width: 12),
                    filter,
                  ],
                ],
              )
            else ...[
              search,
              if (filters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: filters),
              ],
            ],
          ],
        );
      },
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
      width: 155,
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
    this.onDateChanged,
    this.onRoomChanged,
    required this.table,
    this.committeeVaries = false,
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
  final ValueChanged<String>? onDateChanged;
  final ValueChanged<String>? onRoomChanged;
  final Widget table;
  final bool committeeVaries;

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<({String date, String room})>(
      context: context,
      builder: (_) =>
          _SessionDetailsDialog(date: date, room: room, slotCount: totalCount),
    );
    if (result == null || !context.mounted) return;
    if (result.date != date) onDateChanged?.call(result.date);
    if (result.room != room) onRoomChanged?.call(result.room);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final primary = DefensysTokens.textPrimaryOf(context);
    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
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
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Session $index  ${room.isEmpty || room == 'Unassigned' ? 'Room not assigned' : room} · ${date.isEmpty ? 'Date not set' : scheduleReviewDate(date)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: primary,
                            ),
                          ),
                          Text(
                            timeSpan,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            '$totalCount teams',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                          if (issueCount > 0)
                            Text(
                              '$issueCount need attention',
                              style: TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.goldOf(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onDateChanged != null || onRoomChanged != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: secondary),
                        onPressed: enabled ? () => _edit(context) : null,
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Edit session'),
                      ),
                  ],
                ),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 52, top: 2),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 4,
                      children: [
                        if (committeeVaries)
                          Text(
                            'Committee varies by team · See assignments below',
                            style: TextStyle(color: secondary, fontSize: 12),
                          ),
                        if (!committeeVaries)
                          Text(
                            'Chair: ${chair.isEmpty ? 'Not assigned' : chair}',
                            style: TextStyle(color: secondary, fontSize: 12),
                          ),
                        if (!committeeVaries)
                          Text(
                            'Panel: ${panelMembers.isEmpty ? 'Not assigned' : panelMembers.join(', ')}',
                            style: TextStyle(color: secondary, fontSize: 12),
                          ),
                        if (documenter != null && !committeeVaries)
                          Text(
                            'Documenter: ${documenter!.isEmpty ? 'Not assigned' : documenter}',
                            style: TextStyle(color: secondary, fontSize: 12),
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
