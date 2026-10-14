import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../config/api_config.dart';
import '../../../services/network/authenticated_client.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// Dashboard calendar shared by the administrator and PIT lead workspaces.
class DashboardSchedulePlanner extends ConsumerStatefulWidget {
  const DashboardSchedulePlanner({
    super.key,
    required this.workspace,
    this.refreshToken,
  });

  final String workspace;
  final Object? refreshToken;

  @override
  ConsumerState<DashboardSchedulePlanner> createState() =>
      _DashboardSchedulePlannerState();
}

class _DashboardSchedulePlannerState
    extends ConsumerState<DashboardSchedulePlanner> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _pit = Color(0xFF0284C7);
  static const _capstone = DefensysTokens.maroon;

  late DateTime _focusDay;
  bool _monthView = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusDay = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant DashboardSchedulePlanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.workspace != widget.workspace) {
      _load();
    }
  }

  DateTime get _periodStart {
    if (!_monthView) {
      return _focusDay.subtract(Duration(days: _focusDay.weekday - 1));
    }
    final first = DateTime(_focusDay.year, _focusDay.month);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  DateTime get _periodEnd {
    if (!_monthView) return _periodStart.add(const Duration(days: 6));
    final last = DateTime(_focusDay.year, _focusDay.month + 1, 0);
    return last.add(Duration(days: 7 - last.weekday));
  }

  String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${ApiConfig.dashboardsUrl}/schedule-planner/')
          .replace(
            queryParameters: {
              'start': _iso(_periodStart),
              'end': _iso(_periodEnd),
            },
          );
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      if (!mounted || version != _requestVersion) return;
      if (response.statusCode != 200) {
        throw Exception('The calendar could not be loaded.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final sessions = (payload['sessions'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = 'The calendar could not be loaded.';
      });
    }
  }

  void _changePeriod(int direction) {
    setState(() {
      _focusDay = _monthView
          ? DateTime(_focusDay.year, _focusDay.month + direction, 1)
          : _focusDay.add(Duration(days: direction * 7));
    });
    _load();
  }

  void _setMode(bool month) {
    if (_monthView == month) return;
    setState(() => _monthView = month);
    _load();
  }

  void _selectDay(DateTime day) {
    final previousStart = _iso(_periodStart);
    final previousEnd = _iso(_periodEnd);
    setState(() => _focusDay = DateTime(day.year, day.month, day.day));
    if (previousStart != _iso(_periodStart) ||
        previousEnd != _iso(_periodEnd)) {
      _load();
    }
  }

  void _openSession(Map<String, dynamic> session) {
    context.go(
      Uri(
        path: '/${widget.workspace}/defense-board',
        queryParameters: {
          'date': session['date'].toString(),
          'session': session['session_id'].toString(),
          'scope': session['scope'].toString(),
        },
      ).toString(),
    );
  }

  List<Map<String, dynamic>> _onDay(DateTime day) =>
      _sessions.where((session) => session['date'] == _iso(day)).toList();

  String _dayLabel(DateTime day) =>
      '${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}, ${day.year}';

  String _timeLabel(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minutes = ':${parsed.minute.toString().padLeft(2, '0')}';
    final suffix = parsed.hour < 12 ? 'AM' : 'PM';
    return '$hour$minutes $suffix';
  }

  String _timeBlocks(Map<String, dynamic> session) {
    final blocks = (session['time_blocks'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (blocks.isEmpty) return 'at a time to be confirmed';
    return blocks
        .map((block) {
          final start = block['start']?.toString() ?? '';
          final end = block['end']?.toString() ?? '';
          final nextDay =
              start.isNotEmpty &&
              end.isNotEmpty &&
              start.substring(0, 10) != end.substring(0, 10);
          return '${_timeLabel(start)} to ${_timeLabel(end)}${nextDay ? ' the next day' : ''}';
        })
        .join(', then ');
  }

  Widget _dayCell(DateTime day, {required bool outsideMonth}) {
    final sessions = _onDay(day);
    final scopes = sessions.map((session) => session['scope']).toSet();
    final today = DateTime.now();
    final isToday = _iso(day) == _iso(today);
    final isFocusDay = _iso(day) == _iso(_focusDay);
    final dark = DefensysTokens.isDark(context);
    final border = DefensysTokens.borderOf(context);
    final eventColor = scopes.length == 1
        ? (scopes.contains('pit') ? _pit : _capstone)
        : null;
    return Expanded(
      child: Semantics(
        button: true,
        label:
            '${_dayLabel(day)}, ${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'}. Show session summaries',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('planner-day-${_iso(day)}'),
            onTap: () => _selectDay(day),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: _monthView ? 56 : 58,
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: eventColor != null
                    ? eventColor.withValues(alpha: dark ? 0.18 : 0.09)
                    : (isToday || isFocusDay)
                    ? (dark ? const Color(0xFF27272A) : const Color(0xFFF8FAFC))
                    : null,
                border: Border.all(
                  color:
                      eventColor?.withValues(alpha: 0.7) ??
                      (isFocusDay
                          ? DefensysTokens.textSecondaryOf(context)
                          : border),
                  width: isFocusDay ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      color: outsideMonth
                          ? DefensysTokens.textSecondaryOf(
                              context,
                            ).withValues(alpha: 0.55)
                          : DefensysTokens.textPrimaryOf(context),
                      fontSize: 13,
                      fontWeight: isToday || isFocusDay
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (sessions.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (scopes.contains('pit')) _dot(_pit),
                        if (scopes.contains('capstone')) _dot(_capstone),
                        const SizedBox(width: 3),
                        Text(
                          '${sessions.length}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.only(right: 3),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final days = List.generate(
      _periodEnd.difference(_periodStart).inDays + 1,
      (index) => _periodStart.add(Duration(days: index)),
    );
    final daySessions = _onDay(_focusDay);
    final teams = daySessions.fold<int>(
      0,
      (sum, session) => sum + ((session['team_count'] as num?)?.toInt() ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: DefensysShadcnScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _monthView
                        ? '${_months[_focusDay.month - 1]} ${_focusDay.year}'
                        : '${_months[_periodStart.month - 1]} ${_periodStart.day}–${_months[_periodEnd.month - 1]} ${_periodEnd.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () {
                    setState(() {
                      final now = DateTime.now();
                      _focusDay = DateTime(now.year, now.month, now.day);
                    });
                    _load();
                  },
                  child: const Text('Today'),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => _changePeriod(-1),
                  child: const Icon(Icons.chevron_left, size: 17),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => _changePeriod(1),
                  child: const Icon(Icons.chevron_right, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                (_monthView ? ShadButton.outline : ShadButton.secondary)(
                  size: ShadButtonSize.sm,
                  onPressed: () => _setMode(false),
                  child: const Text('Week'),
                ),
                const SizedBox(width: 6),
                (_monthView ? ShadButton.secondary : ShadButton.outline)(
                  size: ShadButtonSize.sm,
                  onPressed: () => _setMode(true),
                  child: const Text('Month'),
                ),
                const Spacer(),
                _dot(_pit),
                Text('PIT', style: TextStyle(color: muted, fontSize: 11)),
                if (widget.workspace == 'admin') ...[
                  const SizedBox(width: 8),
                  _dot(_capstone),
                  Text(
                    'Capstone',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final weekday in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekday,
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < days.length; index += 7)
              Row(
                children: [
                  for (final day in days.skip(index).take(7))
                    _dayCell(
                      day,
                      outsideMonth: _monthView && day.month != _focusDay.month,
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Divider(color: DefensysTokens.borderOf(context), height: 1),
            const SizedBox(height: 12),
            Text(
              _loading
                  ? 'Loading sessions for ${_dayLabel(_focusDay)}…'
                  : _error != null
                  ? 'Schedule for ${_dayLabel(_focusDay)} is unavailable.'
                  : '${_dayLabel(_focusDay)}: ${daySessions.length} ${daySessions.length == 1 ? 'session is' : 'sessions are'} scheduled${daySessions.isEmpty ? '.' : ' for $teams ${teams == 1 ? 'team' : 'teams'}.'}',
              style: TextStyle(
                color: ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: muted)),
                  ),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (daySessions.isEmpty)
              Text(
                'No sessions scheduled for this day.',
                style: TextStyle(color: muted, fontSize: 12),
              )
            else
              for (final session in daySessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: dark
                        ? DefensysTokens.mistInputFill
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: ValueKey('planner-session-${session['session_id']}'),
                      onTap: () => _openSession(session),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: session['scope'] == 'pit'
                                  ? _pit
                                  : _capstone,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${session['event_name']} has ${session['team_count']} ${session['team_count'] == 1 ? 'team' : 'teams'} scheduled in ${session['room']} from ${_timeBlocks(session)}.',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
