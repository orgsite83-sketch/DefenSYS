import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_timing.dart';
import 'package:defensys/utils/import/schedule_import_workspace.dart';
import '../../defense_scheduler/models/schedule_import_models.dart';
import 'schedule_import_review_widgets.dart';

class ScheduleImportSettingsResult {
  const ScheduleImportSettingsResult({
    required this.rows,
    required this.stageId,
    required this.eventName,
    required this.date,
    required this.room,
    required this.duration,
    this.clearDraft = false,
  });
  final List<ParsedScheduleImportRow> rows;
  final int? stageId;
  final String eventName;
  final String date;
  final String room;
  final int duration;
  final bool clearDraft;
}

class ScheduleImportSettingsDialog extends StatefulWidget {
  const ScheduleImportSettingsDialog({
    super.key,
    required this.title,
    required this.files,
    required this.rows,
    required this.previewRows,
    required this.targets,
    required this.isPit,
    required this.stageId,
    required this.eventName,
    required this.date,
    required this.room,
    required this.duration,
    required this.gradingSummaries,
    required this.onViewGrading,
    required this.timingIssues,
    this.selectedFileId,
  });
  final String title;
  final List<ScheduleImportSourceFile> files;
  final List<ParsedScheduleImportRow> rows;
  final List<ScheduleImportPreviewRow> previewRows;
  final List<Map<String, dynamic>> targets;
  final bool isPit;
  final int? stageId;
  final String eventName;
  final String date;
  final String room;
  final int duration;
  final List<String> gradingSummaries;
  final VoidCallback onViewGrading;
  final List<String> Function(List<ParsedScheduleImportRow>) timingIssues;
  final String? selectedFileId;
  @override
  State<ScheduleImportSettingsDialog> createState() =>
      _ScheduleImportSettingsDialogState();
}

class _ScheduleImportSettingsDialogState
    extends State<ScheduleImportSettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _room, _duration;
  late final String _initialDraftDate, _initialDraftRoom;
  late final int _initialDraftDuration;
  late String _scope, _sessionScope;
  late int? _stageId;
  late String _eventName;
  var _tab = 0;
  final _checked = <String>{};
  List<_SessionFields> _sessions = [];
  List<String> _selectedIds = [];
  String? _error;
  var _draftActions = false;
  var _quickSetupExpanded = true;
  final _expandedSessions = <_SessionFields>{};

  @override
  void initState() {
    super.initState();
    _stageId = widget.stageId;
    _eventName = widget.eventName;
    _scope = widget.selectedFileId ?? 'missing';
    _sessionScope = widget.selectedFileId ?? 'all';
    final scopedRows = widget.previewRows.where(
      (row) =>
          widget.selectedFileId == null ||
          row.source.sourceFileId == widget.selectedFileId,
    );
    final firstWithDate = scopedRows
        .where((r) => r.date.trim().isNotEmpty)
        .firstOrNull;
    final firstWithRoom = scopedRows
        .where((r) => r.room.trim().isNotEmpty)
        .firstOrNull;
    final firstWithDuration = scopedRows
        .where((r) => r.duration > 0)
        .firstOrNull;

    _initialDraftDate = widget.date.trim().isNotEmpty
        ? widget.date.trim()
        : firstWithDate?.date.trim() ?? '';
    _initialDraftRoom = widget.room.trim().isNotEmpty
        ? widget.room.trim()
        : firstWithRoom?.room.trim() ?? '';
    _initialDraftDuration = widget.duration > 0
        ? widget.duration
        : firstWithDuration?.duration ?? 60;

    _date = TextEditingController(text: _initialDraftDate);
    _room = TextEditingController(text: _initialDraftRoom);
    _duration = TextEditingController(text: '$_initialDraftDuration');
    _initializeSessions();
  }

  @override
  void dispose() {
    for (final controller in [_date, _room, _duration]) {
      controller.dispose();
    }
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  List<ParsedScheduleImportRow> get _effectiveRows => widget.previewRows
      .map(
        (row) => row.source.copyWith(
          date: row.date,
          room: row.room,
          startTime: row.effectiveStartTime,
          endTime: row.effectiveEndTime,
          slotDuration: row.duration,
        ),
      )
      .toList();

  void _initializeSessions() {
    final rows = _effectiveRows
        .where(
          (row) => _sessionScope == 'all' || row.sourceFileId == _sessionScope,
        )
        .toList();
    final groups = scheduleImportSessionGroups(rows, duration: widget.duration);
    _selectedIds = groups
        .expand((group) => group.map((row) => row.importRowId))
        .toList();
    for (final session in _sessions) {
      session.dispose();
    }
    _sessions = [
      for (final group in groups)
        _SessionFields(
          count: group.length,
          start: group.first.startTime,
          duration: group.first.slotDuration ?? widget.duration,
          date: group.first.date,
          room: group.first.room,
        ),
    ];
    _expandedSessions.clear();
  }

  ({
    int firstIdx,
    int secondIdx,
    String date,
    String room,
    int firstEnd,
    int secondStart,
  })?
  _findSessionOverlap() {
    for (var i = 0; i < _sessions.length; i++) {
      final s1 = _sessions[i];
      final start1 = scheduleTimeMinutes(s1.start.text);
      final count1 = int.tryParse(s1.count.text) ?? 0;
      final dur1 = int.tryParse(s1.duration.text) ?? 0;
      final date1 = s1.date.text.trim();
      final room1 = s1.room.text.trim();
      if (start1 == null || count1 <= 0 || dur1 <= 0) continue;
      final end1 = start1 + count1 * dur1;

      for (var j = i + 1; j < _sessions.length; j++) {
        final s2 = _sessions[j];
        final start2 = scheduleTimeMinutes(s2.start.text);
        final count2 = int.tryParse(s2.count.text) ?? 0;
        final dur2 = int.tryParse(s2.duration.text) ?? 0;
        final date2 = s2.date.text.trim();
        final room2 = s2.room.text.trim();
        if (start2 == null || count2 <= 0 || dur2 <= 0) continue;
        final end2 = start2 + count2 * dur2;

        if (date1.isNotEmpty &&
            room1.isNotEmpty &&
            date1.toLowerCase() == date2.toLowerCase() &&
            room1.toLowerCase() == room2.toLowerCase()) {
          if (scheduleIntervalsOverlap(start1, end1, start2, end2)) {
            return (
              firstIdx: i,
              secondIdx: j,
              date: date1,
              room: room1,
              firstEnd: end1,
              secondStart: start2,
            );
          }
        }
      }
    }
    return null;
  }

  List<ScheduleImportSessionPlan> get _morningAfternoonPlans {
    final byId = {for (final row in _effectiveRows) row.importRowId: row};
    return morningAfternoonSessionPlans([
      for (final id in _selectedIds) byId[id]!,
    ], fallbackDuration: widget.duration);
  }

  void _redistribute(int count, {bool morningAfternoon = false}) {
    if (count < 1 || count > _selectedIds.length) {
      setState(() => _error = 'Use 1 to ${_selectedIds.length} sessions.');
      return;
    }
    final old = _sessions;
    if (morningAfternoon) {
      _sessions = [
        for (final plan in _morningAfternoonPlans)
          _SessionFields(
            count: plan.count,
            start: plan.start,
            duration: plan.duration,
            date: plan.date,
            room: plan.room,
          ),
      ];
    } else {
      final byId = {for (final row in _effectiveRows) row.importRowId: row};
      var offset = 0;
      _sessions = List.generate(count, (index) {
        final teams =
            _selectedIds.length ~/ count +
            (index < _selectedIds.length % count ? 1 : 0);
        final first = byId[_selectedIds[offset]]!;
        offset += teams;
        return _SessionFields(
          count: teams,
          start: index < old.length ? old[index].start.text : first.startTime,
          duration: index < old.length
              ? int.tryParse(old[index].duration.text) ?? widget.duration
              : first.slotDuration ?? widget.duration,
          date: index < old.length ? old[index].date.text : first.date,
          room: index < old.length ? old[index].room.text : first.room,
        );
      });
    }
    _expandedSessions.clear();
    for (final session in old) {
      session.dispose();
    }
    setState(() => _error = null);
  }

  String get _sessionSummary {
    final durations = _sessions
        .map((session) => int.tryParse(session.duration.text))
        .toSet();
    final timing = durations.length == 1 && durations.first != null
        ? '${durations.first} minutes per team'
        : 'Mixed slot durations';
    return '${_selectedIds.length} teams · $timing';
  }

  String get _sessionDistribution {
    final counts = _sessions
        .map((session) => int.tryParse(session.count.text) ?? 0)
        .toList();
    if (counts.isEmpty) return 'No teams in this selection';
    if (counts.every((count) => count == counts.first)) {
      return '${counts.first} ${counts.first == 1 ? 'team' : 'teams'} in each session';
    }
    return '${counts.join(' + ')} teams across ${_sessions.length} sessions';
  }

  String _sessionRange(String start, int count, int duration) {
    final minutes = scheduleTimeMinutes(start);
    if (minutes == null || count <= 0 || duration <= 0) return 'Set timing';
    return '${scheduleReviewTime(scheduleTimeFromMinutes(minutes))}–${scheduleReviewTime(scheduleTimeFromMinutes(minutes + count * duration))}';
  }

  int get _allocated => _sessions.fold(
    0,
    (sum, session) => sum + (int.tryParse(session.count.text) ?? 0),
  );

  List<ParsedScheduleImportRow> _plannedRows() =>
      applyScheduleImportSessionPlans(
        widget.rows,
        _selectedIds,
        _sessions
            .map(
              (session) => ScheduleImportSessionPlan(
                count: int.tryParse(session.count.text) ?? 0,
                start: session.start.text,
                duration: int.tryParse(session.duration.text) ?? 0,
                date: session.date.text,
                room: session.room.text,
              ),
            )
            .toList(),
        sessionPrefix: 'session-${DateTime.now().microsecondsSinceEpoch}',
      );

  String? get _planError {
    if (_sessions.isEmpty) return 'No imported teams to assign.';
    if (_allocated != _selectedIds.length) {
      final remaining = _selectedIds.length - _allocated;
      return remaining > 0
          ? '$remaining teams still need a session.'
          : '${-remaining} slots exceed the imported team count.';
    }
    try {
      final issues = widget.timingIssues(_plannedRows());
      return issues.isEmpty ? null : issues.first;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String get _impact {
    if (_checked.isEmpty) return 'Only checked fields change.';
    if (_scope == 'missing') {
      final count = widget.rows
          .where(
            (row) =>
                _checked.contains('date') && row.date.trim().isEmpty ||
                _checked.contains('room') && row.room.trim().isEmpty ||
                _checked.contains('duration') && row.slotDuration == null,
          )
          .length;
      return count == 0
          ? 'No current slots need these values. Saved defaults will fill gaps in added files.'
          : '$count slots use these defaults. Spreadsheet and session values are preserved.';
    }
    final rows = widget.rows
        .where((row) => _scope == 'all' || row.sourceFileId == _scope)
        .toList();
    final files = rows.map((row) => row.sourceFileId).toSet().length;
    return '${rows.length} slots will be updated across $files ${files == 1 ? 'file' : 'files'}.';
  }

  void _save({bool clear = false}) {
    if (!clear && !(_form.currentState?.validate() ?? true)) return;
    var rows = widget.rows,
        date = widget.date,
        room = widget.room,
        duration = widget.duration;
    if (!clear && _tab == 1) {
      final error = _planError;
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      rows = _plannedRows();
    } else if (!clear && _checked.isNotEmpty) {
      if (_scope == 'missing') {
        if (_checked.contains('date')) date = _date.text.trim();
        if (_checked.contains('room')) room = _room.text.trim();
        if (_checked.contains('duration')) duration = int.parse(_duration.text);
      } else {
        rows = updateScheduleImportValues(
          widget.rows,
          widget.rows
              .where((row) => _scope == 'all' || row.sourceFileId == _scope)
              .map((row) => row.importRowId)
              .toSet(),
          date: _checked.contains('date') ? _date.text.trim() : null,
          room: _checked.contains('room') ? _room.text.trim() : null,
          duration: _checked.contains('duration')
              ? int.parse(_duration.text)
              : null,
          fallbackDate: widget.date,
          fallbackRoom: widget.room,
          fallbackDuration: widget.duration,
        );
      }
    }
    Navigator.pop(
      context,
      ScheduleImportSettingsResult(
        rows: rows,
        stageId: _tab == 0 ? _stageId : widget.stageId,
        eventName: _tab == 0 ? _eventName : widget.eventName,
        date: date,
        room: room,
        duration: duration,
        clearDraft: clear,
      ),
    );
  }

  InputDecoration _input({Widget? suffix}) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DefensysTokens.surfaceOf(context),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    ),
  );

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 7),
      child,
    ],
  );

  Widget _text(
    TextEditingController controller, {
    String? kind,
    bool enabled = true,
    Key? key,
  }) => TextFormField(
    key: key,
    controller: controller,
    enabled: enabled,
    style: const TextStyle(fontSize: 13),
    keyboardType: kind == 'count' || kind == 'duration'
        ? TextInputType.number
        : TextInputType.text,
    decoration: _input(
      suffix: kind == 'date'
          ? IconButton(
              tooltip: 'Choose date',
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              onPressed: !enabled
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            (scheduleImportDateIsValid(controller.text) &&
                                    int.parse(
                                          controller.text.substring(0, 4),
                                        ) >=
                                        2000 &&
                                    int.parse(
                                          controller.text.substring(0, 4),
                                        ) <=
                                        2100
                                ? DateTime.parse(controller.text)
                                : null) ??
                            DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) {
                        setState(
                          () => controller.text = formatScheduleDate(picked),
                        );
                      }
                    },
            )
          : kind == 'start'
          ? IconButton(
              tooltip: 'Choose start time',
              icon: const Icon(Icons.schedule_outlined, size: 16),
              onPressed: () async {
                final minutes = scheduleTimeMinutes(controller.text) ?? 480;
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: minutes ~/ 60,
                    minute: minutes % 60,
                  ),
                );
                if (picked != null && mounted) {
                  setState(
                    () => controller.text = scheduleTimeFromMinutes(
                      picked.hour * 60 + picked.minute,
                    ),
                  );
                }
              },
            )
          : null,
    ),
    onChanged: (_) => setState(() => _error = null),
    validator: !enabled
        ? null
        : (value) {
            final text = value?.trim() ?? '';
            if (kind == 'duration') {
              final number = int.tryParse(text);
              return number == null || number < 15 || number > 240
                  ? 'Enter 15 to 240 minutes'
                  : null;
            }
            if (kind == 'count') {
              final number = int.tryParse(text);
              return number == null || number < 1
                  ? 'Enter at least 1 team'
                  : null;
            }
            if (kind == 'date') {
              return scheduleImportDateIsValid(text) ? null : 'Use YYYY-MM-DD';
            }
            if (kind == 'start') {
              return scheduleTimeMinutes(text) == null ? 'Use HH:mm' : null;
            }
            return text.isEmpty ? 'Enter a room or venue' : null;
          },
  );

  Widget _dropdown(
    String value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String?> onChanged, {
    Key? key,
  }) => DropdownButtonFormField<String>(
    key: key,
    initialValue: items.any((item) => item.value == value) ? value : null,
    isExpanded: true,
    decoration: _input(),
    style: TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
      color: DefensysTokens.textPrimaryOf(context),
    ),
    items: items,
    onChanged: onChanged,
  );

  Widget _helper(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: DefensysTokens.textSecondaryOf(context),
      ),
    ),
  );

  Widget _checkedField(
    String name,
    String label,
    TextEditingController controller, {
    String? kind,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          SizedBox(
            width: 24,
            height: 30,
            child: Checkbox(
              key: ValueKey('set_$name'),
              value: _checked.contains(name),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _checked.add(name);
                  if (controller.text.trim().isEmpty) {
                    if (name == 'date') controller.text = _initialDraftDate;
                    if (name == 'room') controller.text = _initialDraftRoom;
                    if (name == 'duration') {
                      controller.text = '$_initialDraftDuration';
                    }
                  }
                } else {
                  _checked.remove(name);
                }
              }),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
      const SizedBox(height: 6),
      _text(
        controller,
        kind: kind,
        enabled: _checked.contains(name),
        key: ValueKey('schedule_$name'),
      ),
    ],
  );

  Widget _stagePanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(
        widget.isPit ? 'PIT event' : 'Defense stage',
        _dropdown(
          widget.isPit ? _eventName : _stageId?.toString() ?? '',
          widget.targets
              .map(
                (target) => DropdownMenuItem(
                  value: widget.isPit
                      ? target['event_name'].toString()
                      : target['id'].toString(),
                  child: Text(
                    (widget.isPit ? target['event_name'] : target['label'])
                            ?.toString() ??
                        '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          (value) => setState(() {
            if (widget.isPit) {
              _eventName = value ?? '';
            } else {
              _stageId = int.tryParse(value ?? '');
            }
          }),
        ),
      ),
      _helper(
        'The ${widget.isPit ? 'event' : 'defense stage'} is shared by all files in this draft.',
      ),
      const SizedBox(height: 22),
      const Text(
        'Schedule values',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 14),
      _field(
        'Apply to',
        _dropdown(
          _scope,
          [
            const DropdownMenuItem(
              value: 'missing',
              child: Text('Missing values only · all files'),
            ),
            DropdownMenuItem(
              value: 'all',
              child: Text('All slots · ${widget.rows.length} slots'),
            ),
            for (final file in widget.files)
              DropdownMenuItem(
                value: file.id,
                child: Text(
                  '${file.name} · ${file.parsed.rows.length} slots',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          (value) => setState(() => _scope = value!),
          key: const ValueKey('stage_schedule_scope'),
        ),
      ),
      _helper(
        _scope == 'missing'
            ? 'Fill only missing spreadsheet values. Session edits take priority.'
            : _scope == 'all'
            ? 'Replace checked values across every file in this draft.'
            : 'Replace checked values in this file. Other files keep their values.',
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, constraints) {
          final date = _checkedField('date', 'Set date', _date, kind: 'date'),
              room = _checkedField('room', 'Set room / venue', _room);
          return constraints.maxWidth < 460
              ? Column(children: [date, const SizedBox(height: 14), room])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: date),
                    const SizedBox(width: 16),
                    Expanded(child: room),
                  ],
                );
        },
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 180,
          child: _checkedField(
            'duration',
            'Set slot duration (minutes)',
            _duration,
            kind: 'duration',
          ),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(_impact, style: const TextStyle(fontSize: 12)),
        ),
      ),
      if (_checked.contains('duration'))
        _helper(
          'Times recalculate within each session. Later sessions in the same room automatically follow consecutively.',
        ),
      const SizedBox(height: 18),
      Divider(color: DefensysTokens.borderOf(context)),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (final summary in widget.gradingSummaries)
              Text(summary, style: const TextStyle(fontSize: 12, height: 1.5)),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: () {
            Navigator.pop(context);
            widget.onViewGrading();
          },
          child: const Text('View grading setup'),
        ),
      ),
      Divider(color: DefensysTokens.borderOf(context)),
      Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: () => setState(() => _draftActions = !_draftActions),
          leading: Icon(
            _draftActions ? Icons.expand_less : Icons.expand_more,
            size: 16,
          ),
          child: const Text('Draft actions'),
        ),
      ),
      if (_draftActions)
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Remove all ${widget.rows.length} staged slots from this draft.',
              style: const TextStyle(fontSize: 12),
            ),
            ShadButton.destructive(
              size: ShadButtonSize.sm,
              onPressed: () => _save(clear: true),
              child: const Text('Clear draft'),
            ),
          ],
        ),
    ],
  );

  Widget _sessionPanel() {
    final error = _planError;
    final overlap = _findSessionOverlap();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.files.length > 1) ...[
          _field(
            'Apply to',
            _dropdown(
              _sessionScope,
              [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Entire draft'),
                ),
                for (final file in widget.files)
                  DropdownMenuItem(
                    value: file.id,
                    child: Text(file.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              (value) => setState(() {
                _sessionScope = value!;
                _initializeSessions();
                _error = null;
              }),
              key: const ValueKey('sessions_source_scope'),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            const Expanded(
              child: Text('How many sessions?', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 84,
              child: InputDecorator(
                decoration: _input().copyWith(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: const ValueKey('session_count'),
                    value: _sessions.isEmpty ? null : _sessions.length,
                    isDense: true,
                    isExpanded: true,
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 13,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    items: [
                      for (var count = 1; count <= _selectedIds.length; count++)
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                    onChanged: _selectedIds.isEmpty
                        ? null
                        : (count) {
                            if (count != null && count != _sessions.length) {
                              _redistribute(count);
                            }
                          },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            _sessionDistribution,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < _sessions.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _sessionCard(index, _sessions[index]),
          ),
        const SizedBox(height: 4),
        if (overlap == null)
          Text(
            'No overlapping session times',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          )
        else
          _sessionOverlapNotice(
            overlap.firstIdx,
            overlap.secondIdx,
            overlap.firstEnd,
          ),
        if (error != null &&
            (overlap == null || !error.startsWith('Time overlap')))
          _errorBanner(error),
        if (_selectedIds.length >= 2) ...[
          const SizedBox(height: 20),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          const SizedBox(height: 12),
          _quickSetup(),
        ],
      ],
    );
  }

  Widget _sessionOverlapNotice(int first, int second, int firstEnd) {
    final dark = DefensysTokens.isDark(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF451A03) : DefensysTokens.warningBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session ${second + 1} starts before Session ${first + 1} ends.',
            style: TextStyle(
              fontSize: 12,
              color: dark
                  ? const Color(0xFFFDE68A)
                  : DefensysTokens.warningText,
            ),
          ),
          const SizedBox(height: 8),
          ShadButton.outline(
            key: const ValueKey('session_overlap_fix'),
            size: ShadButtonSize.sm,
            height: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: firstEnd >= 1440
                ? null
                : () => setState(() {
                    _sessions[second].start.text = scheduleTimeFromMinutes(
                      firstEnd,
                    );
                    _error = null;
                  }),
            child: Flexible(
              child: Text(
                'Start Session ${second + 1} at ${scheduleReviewTime(scheduleTimeFromMinutes(firstEnd))}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickSetup() {
    final plans = _morningAfternoonPlans;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('session_quick_setup'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              foregroundColor: DefensysTokens.textSecondaryOf(context),
            ),
            onPressed: () =>
                setState(() => _quickSetupExpanded = !_quickSetupExpanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _quickSetupExpanded
                      ? Icons.arrow_drop_down
                      : Icons.arrow_right,
                  size: 18,
                ),
                const Text('Quick setup', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        if (_quickSetupExpanded)
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 400;
              return Padding(
                padding: EdgeInsets.only(
                  left: compact ? 0 : 18,
                  top: 18,
                  bottom: 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Split into morning and afternoon',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < plans.length;
                            index++
                          ) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                color: DefensysTokens.borderOf(context),
                              ),
                            _presetSessionRow(
                              index == 0 ? 'Morning' : 'Afternoon',
                              plans[index],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ShadButton.outline(
                        key: const ValueKey('session_morning_afternoon'),
                        size: ShadButtonSize.sm,
                        width: compact ? double.infinity : null,
                        height: compact ? 44 : null,
                        expands: compact,
                        onPressed: () =>
                            _redistribute(2, morningAfternoon: true),
                        child: const Text(
                          'Use these two sessions',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _presetSessionRow(String label, ScheduleImportSessionPlan plan) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final period = Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            );
            final teams = Text(
              '${plan.count} teams',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            );
            final range = Text(
              _sessionRange(plan.start, plan.count, plan.duration),
              style: const TextStyle(fontSize: 12),
            );
            if (constraints.maxWidth < 350) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: period),
                      teams,
                    ],
                  ),
                  const SizedBox(height: 4),
                  range,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 88, child: period),
                const SizedBox(width: 16),
                SizedBox(width: 64, child: teams),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: range),
                ),
              ],
            );
          },
        ),
      );

  Widget _sessionCard(int index, _SessionFields session) {
    final count = int.tryParse(session.count.text) ?? 0;
    final duration = int.tryParse(session.duration.text) ?? 0;
    final expanded = _expandedSessions.contains(session);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Material(
        color: DefensysTokens.surfaceOf(context),
        child: Column(
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              child: InkWell(
                key: ValueKey('session_${index}_card'),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedSessions.remove(session);
                  } else {
                    _expandedSessions.add(session);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Session ${index + 1}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '$count ${count == 1 ? 'team' : 'teams'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _sessionRange(
                                session.start.text,
                                count,
                                duration,
                              ),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              expanded ? 'Close editor' : 'Edit time',
                              style: TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              Divider(height: 1, color: DefensysTokens.borderOf(context)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 330
                        ? 1
                        : constraints.maxWidth < 520
                        ? 2
                        : 3;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        SizedBox(
                          width: width,
                          child: _field(
                            'Teams / slots',
                            _text(
                              session.count,
                              kind: 'count',
                              key: ValueKey('session_${index}_teams'),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _field(
                            'Start time (HH:mm)',
                            _text(
                              session.start,
                              kind: 'start',
                              key: ValueKey('session_${index}_start'),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _field(
                            'Minutes per slot',
                            _text(
                              session.duration,
                              kind: 'duration',
                              key: ValueKey('session_${index}_duration'),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _field(
                            'Date',
                            _text(
                              session.date,
                              kind: 'date',
                              key: ValueKey('session_${index}_date'),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: columns == 3 ? width * 2 + 12 : width,
                          child: _field(
                            'Room / venue',
                            _text(
                              session.room,
                              key: ValueKey('session_${index}_room'),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: DefensysTokens.dangerText),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 500;
    return ShadTheme(
      data: ShadThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        textTheme: ShadTextTheme(family: DefensysTokens.fontFamilyInter),
        colorScheme: isDark
            ? const ShadZincColorScheme.dark()
            : const ShadZincColorScheme.light(),
      ),
      child: Dialog(
        backgroundColor: DefensysTokens.surfaceOf(context),
        surfaceTintColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 20,
          vertical: 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 636,
            maxHeight: math.max(200, MediaQuery.sizeOf(context).height - 48),
          ),
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 12 : 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tab == 1 ? 'Sessions' : '${widget.title} settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close settings',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                _helper(
                  _tab == 1
                      ? _sessionSummary
                      : '${widget.rows.length} staged slots · ${widget.files.length} ${widget.files.length == 1 ? 'file' : 'files'}',
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < 2; i++)
                        Expanded(
                          child: TextButton(
                            key: ValueKey(
                              i == 0
                                  ? 'settings_stage_tab'
                                  : 'settings_sessions_tab',
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: _tab == i
                                  ? DefensysTokens.surfaceOf(context)
                                  : Colors.transparent,
                              foregroundColor: _tab == i
                                  ? DefensysTokens.textPrimaryOf(context)
                                  : DefensysTokens.textSecondaryOf(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            onPressed: () => setState(() {
                              _tab = i;
                              _error = null;
                            }),
                            child: Text(i == 0 ? 'Stage' : 'Sessions'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _form,
                      child: _tab == 0 ? _stagePanel() : _sessionPanel(),
                    ),
                  ),
                ),
                if (_error != null) _errorBanner(_error!),
                const SizedBox(height: 18),
                if (_tab == 1) ...[
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  alignment: _tab == 1
                      ? WrapAlignment.spaceBetween
                      : WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_tab == 1)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '$_allocated of ${_selectedIds.length} teams assigned',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      )
                    else
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ShadButton(
                      size: ShadButtonSize.sm,
                      backgroundColor: DefensysTokens.maroonOf(context),
                      foregroundColor: Colors.white,
                      onPressed: _tab == 1 && _planError != null ? null : _save,
                      child: Text(
                        _tab == 0 ? 'Save settings' : 'Apply session plan',
                        style: _tab == 1 ? const TextStyle(fontSize: 12) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionFields {
  _SessionFields({
    required int count,
    required String start,
    required int duration,
    required String date,
    required String room,
  }) : count = TextEditingController(text: '$count'),
       start = TextEditingController(text: start),
       duration = TextEditingController(text: '$duration'),
       date = TextEditingController(text: date),
       room = TextEditingController(text: room);
  final TextEditingController count, start, duration, date, room;
  void dispose() {
    for (final controller in [count, start, duration, date, room]) {
      controller.dispose();
    }
  }
}
