import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';
import '../shared/team_deliverables/deliverables_view_types.dart';

class FacultyDashboardColumns extends StatelessWidget {
  final Widget left;
  final Widget topRight;
  final Widget bottomRight;

  const FacultyDashboardColumns({
    super.key,
    required this.left,
    required this.topRight,
    required this.bottomRight,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1000) {
        return Column(
          children: [
            left,
            const SizedBox(height: 16),
            topRight,
            const SizedBox(height: 16),
            bottomRight,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [topRight, const SizedBox(height: 16), bottomRight],
            ),
          ),
        ],
      );
    },
  );
}

class FacultyTeamAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const FacultyTeamAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class FacultyTeamMenu extends StatelessWidget {
  final String teamName;
  final List<FacultyTeamAction> actions;

  const FacultyTeamMenu({
    super.key,
    required this.teamName,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final surface = DefensysTokens.surfaceOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final hover = DefensysTokens.surfaceHigherOf(context);
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: hover,
        highlightColor: hover,
        splashColor: Colors.transparent,
      ),
      child: PopupMenuButton<int>(
        tooltip: 'Actions for $teamName',
        icon: Icon(Icons.more_horiz_rounded, size: 20, color: ink),
        padding: const EdgeInsets.all(6),
        borderRadius: BorderRadius.circular(6),
        menuPadding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 196, maxWidth: 240),
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        onSelected: (index) => actions[index].onTap(),
        itemBuilder: (context) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(actions[i].icon, size: 16, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      actions[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FacultyTeamPager extends StatelessWidget {
  final int total;
  final int page;
  final int pageSize;
  final String viewAllLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onViewAll;

  const FacultyTeamPager({
    super.key,
    required this.total,
    required this.page,
    this.pageSize = 4,
    required this.viewAllLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final lastPage = total == 0 ? 0 : (total - 1) ~/ pageSize;
    final current = page > lastPage ? lastPage : page;
    final first = total == 0 ? 0 : current * pageSize + 1;
    final last = (current + 1) * pageSize > total
        ? total
        : (current + 1) * pageSize;
    final border = DefensysTokens.borderOf(context);
    final style = facultyDashboardOutlineStyle(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: total > pageSize
              ? WrapAlignment.spaceBetween
              : WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (total > pageSize)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: OutlinedButton(
                      key: const Key('team-page-previous'),
                      onPressed: current == 0 ? null : onPrevious,
                      style: style.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        side: WidgetStatePropertyAll(BorderSide(color: border)),
                      ),
                      child: const Icon(Icons.chevron_left_rounded, size: 17),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      '$first–$last of $total',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: OutlinedButton(
                      key: const Key('team-page-next'),
                      onPressed: current == lastPage ? null : onNext,
                      style: style.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        side: WidgetStatePropertyAll(BorderSide(color: border)),
                      ),
                      child: const Icon(Icons.chevron_right_rounded, size: 17),
                    ),
                  ),
                ],
              ),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: onViewAll,
                style: style,
                child: Text(viewAllLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle facultyDashboardOutlineStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      side: BorderSide(color: DefensysTokens.borderOf(context)),
      foregroundColor: DefensysTokens.textPrimaryOf(context),
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    );

/// A team-level summary. Defense files already present in the stage's pre
/// requirements are counted once, even when materials_readiness also lists them.
class TeamRequirementSummary {
  final int missingForEndorsement;
  final int pendingDefenseFiles;
  final int awaitingReview;
  final bool overdue;
  final bool awaitingSchedule;
  final bool configured;
  final bool needsAttention;

  const TeamRequirementSummary({
    required this.missingForEndorsement,
    required this.pendingDefenseFiles,
    required this.awaitingReview,
    required this.overdue,
    required this.awaitingSchedule,
    required this.configured,
    required this.needsAttention,
  });

  int get missing => missingForEndorsement + pendingDefenseFiles;

  factory TeamRequirementSummary.fromTeam(Map<String, dynamic>? team) {
    final stage = team == null
        ? null
        : DeliverablesTriageHelper.resolveActiveStage(team);
    if (stage == null) {
      return const TeamRequirementSummary(
        missingForEndorsement: 0,
        pendingDefenseFiles: 0,
        awaitingReview: 0,
        overdue: false,
        awaitingSchedule: false,
        configured: false,
        needsAttention: false,
      );
    }

    final endorsementIds = <String>{};
    final defenseIds = <String>{};
    var overdue = false;
    for (final item in DeliverablesTriageHelper.items(stage)) {
      if (item['required'] != true ||
          item['is_waived'] == true ||
          item['type'] == 'post') {
        continue;
      }
      final submission = item['submission'];
      final status =
          (submission is Map ? submission['status'] : item['submission_status'])
              ?.toString()
              .toLowerCase();
      final isMaterial = item['requirement_timing'] == 'defense';
      final submitted = isMaterial && item['materials_submitted'] is bool
          ? item['materials_submitted'] == true
          : item['uploaded'] == true &&
                status != 'rejected' &&
                status != 'needs revision' &&
                status != 'needs_revision';
      if (!submitted) {
        final ids = isMaterial ? defenseIds : endorsementIds;
        ids.add(
          item['id']?.toString() ??
              item['label']?.toString() ??
              'requirement-${ids.length}',
        );
        if (item['materials_status'] == 'overdue') overdue = true;
      }
    }

    final materials = stage['materials_readiness'];
    if (materials is Map) {
      for (final item
          in (materials['missing'] as List? ?? []).whereType<Map>()) {
        defenseIds.add(
          item['id']?.toString() ??
              item['label']?.toString() ??
              'material-${defenseIds.length}',
        );
        if (item['materials_status'] == 'overdue') overdue = true;
      }
      overdue = overdue || materials['status'] == 'overdue';
    }

    return TeamRequirementSummary(
      missingForEndorsement: endorsementIds.length,
      pendingDefenseFiles: defenseIds.length,
      awaitingReview: DeliverablesTriageHelper.pendingReviewCount(team!),
      overdue: overdue,
      awaitingSchedule:
          materials is Map && materials['status'] == 'awaiting_schedule',
      configured:
          stage['deliverables_configured'] == true ||
          stage['is_presentation_only'] == true ||
          DeliverablesTriageHelper.items(stage).isNotEmpty,
      needsAttention: stage['required_complete'] == false,
    );
  }

  String get label {
    if (overdue && pendingDefenseFiles > 0) {
      return '$pendingDefenseFiles overdue';
    }
    if (missingForEndorsement > 0) {
      return '$missingForEndorsement to endorse';
    }
    if (awaitingReview > 0) return '$awaitingReview to review';
    if (needsAttention) return 'Needs attention';
    if (pendingDefenseFiles > 0) {
      return awaitingSchedule
          ? '$pendingDefenseFiles due later'
          : '$pendingDefenseFiles before defense';
    }
    return configured ? 'Ready' : 'No requirements';
  }
}

class TeamRequirementBadge extends StatelessWidget {
  final Map<String, dynamic>? team;

  const TeamRequirementBadge({super.key, required this.team});

  @override
  Widget build(BuildContext context) {
    if (team == null) return const SizedBox.shrink();
    final summary = TeamRequirementSummary.fromTeam(team);
    final colors = Theme.of(context).colorScheme;
    final color = summary.overdue && summary.pendingDefenseFiles > 0
        ? colors.error
        : summary.missingForEndorsement > 0 || summary.needsAttention
        ? const Color(0xFF9A6700)
        : summary.awaitingReview > 0
        ? const Color(0xFF2853A4)
        : summary.pendingDefenseFiles > 0
        ? DefensysTokens.textSecondaryOf(context)
        : summary.configured
        ? const Color(0xFF25704A)
        : DefensysTokens.textSecondaryOf(context);
    return Tooltip(
      message:
          '${summary.missingForEndorsement} files needed before endorsement; '
          '${summary.pendingDefenseFiles} defense files due later. '
          'Defense files do not block endorsement or scheduling. '
          '${summary.awaitingReview} submissions awaiting review.',
      child: Container(
        key: const Key('team-requirement-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          summary.label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class DefenseScheduleCalendar extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> schedules;
  final Map<int, String> teamNames;
  final bool loading;
  final bool hasError;
  final void Function(int? teamId, String stageLabel) onOpenDefense;

  const DefenseScheduleCalendar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.schedules,
    required this.teamNames,
    required this.loading,
    required this.hasError,
    required this.onOpenDefense,
  });

  @override
  State<DefenseScheduleCalendar> createState() =>
      _DefenseScheduleCalendarState();
}

class _DefenseScheduleCalendarState extends State<DefenseScheduleCalendar> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  late DateTime _selectedDay;
  bool _monthView = false;
  bool _userSelected = false;
  bool _showAll = false;

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime? _scheduleDay(Map<String, dynamic> schedule) =>
      DateTime.tryParse(schedule['scheduled_date']?.toString() ?? '');

  DateTime _firstDay(List<Map<String, dynamic>> schedules) {
    final today = _day(DateTime.now());
    final dates =
        schedules
            .map(_scheduleDay)
            .whereType<DateTime>()
            .where((date) => !date.isBefore(today))
            .toList()
          ..sort();
    return dates.isEmpty ? today : _day(dates.first);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _firstDay(widget.schedules);
  }

  @override
  void didUpdateWidget(covariant DefenseScheduleCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userSelected && oldWidget.schedules != widget.schedules) {
      _selectedDay = _firstDay(widget.schedules);
    }
  }

  List<Map<String, dynamic>> _eventsOn(DateTime day) =>
      widget.schedules
          .where((schedule) => _scheduleDay(schedule) == day)
          .toList()
        ..sort(
          (a, b) => (a['start_time']?.toString() ?? '').compareTo(
            b['start_time']?.toString() ?? '',
          ),
        );

  void _select(DateTime day) => setState(() {
    _selectedDay = _day(day);
    _userSelected = true;
    _showAll = false;
  });

  String _time(BuildContext context, Map<String, dynamic> schedule) {
    final raw = schedule['start_time']?.toString() ?? '';
    final parts = raw.split(':');
    final hour = parts.isEmpty ? null : int.tryParse(parts[0]);
    final minute = parts.length < 2 ? null : int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return 'Time pending';
    }
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));
  }

  Widget _outlinedButton({
    required String tooltip,
    required Widget child,
    required VoidCallback onPressed,
    double? width,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: width,
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
          foregroundColor: DefensysTokens.textPrimaryOf(context),
          backgroundColor: DefensysTokens.surfaceOf(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        child: child,
      ),
    ),
  );

  Widget _dateCell(DateTime day, {bool month = false}) {
    final selected = day == _selectedDay;
    final count = _eventsOn(day).length;
    final today = day == _day(DateTime.now());
    final maroon = DefensysTokens.maroonOf(context);
    return Semantics(
      button: true,
      label:
          '${MaterialLocalizations.of(context).formatMediumDate(day)}, '
          '$count ${count == 1 ? 'defense' : 'defenses'}',
      child: InkWell(
        key: Key('defense-calendar-day-${day.year}-${day.month}-${day.day}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => _select(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? maroon : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? maroon
                  : today
                  ? DefensysTokens.borderOf(context)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!month)
                Text(
                  _weekdays[day.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    color: selected
                        ? Colors.white
                        : DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: month ? 12 : 14,
                  fontWeight: selected || today
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : DefensysTokens.textPrimaryOf(context),
                ),
              ),
              if (count > 0)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : maroon,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendar() {
    final start = _monthView
        ? DateTime(_selectedDay.year, _selectedDay.month, 1)
        : _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));
    final gridStart = start.subtract(Duration(days: start.weekday - 1));
    if (!_monthView) {
      return SizedBox(
        height: 66,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: _dateCell(gridStart.add(Duration(days: i)))),
          ],
        ),
      );
    }
    final last = DateTime(_selectedDay.year, _selectedDay.month + 1, 0);
    final cells = ((last.day + start.weekday - 2) ~/ 7 + 1) * 7;
    return Column(
      children: [
        Row(
          children: [
            for (final weekday in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 10,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 40,
          ),
          itemCount: cells,
          itemBuilder: (context, index) {
            final day = gridStart.add(Duration(days: index));
            return Opacity(
              opacity: day.month == _selectedDay.month ? 1 : 0.42,
              child: _dateCell(day, month: true),
            );
          },
        ),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> schedule) {
    final teamId = int.tryParse(schedule['team_id']?.toString() ?? '');
    final teamName =
        widget.teamNames[teamId] ?? schedule['team_name']?.toString() ?? 'Team';
    final stage = schedule['stage_label']?.toString() ?? 'Defense';
    final room = schedule['room']?.toString() ?? '';
    final materials = schedule['materials_readiness'];
    final required = materials is Map
        ? int.tryParse('${materials['required_total'] ?? 0}') ?? 0
        : 0;
    final submitted = materials is Map
        ? int.tryParse('${materials['submitted_total'] ?? 0}') ?? 0
        : 0;
    final details = [
      stage,
      _time(context, schedule),
      if (room.isNotEmpty) room,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      isThreeLine: required > 0,
      leading: Icon(
        Icons.event_outlined,
        color: DefensysTokens.maroonOf(context),
      ),
      title: Text(
        teamName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        required > 0
            ? '$details\n$submitted/$required defense materials uploaded'
            : details,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => widget.onOpenDefense(teamId, stage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _eventsOn(_selectedDay);
    final month = MaterialLocalizations.of(
      context,
    ).formatMonthYear(_selectedDay);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(_selectedDay);
    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  month,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _outlinedButton(
                tooltip: _monthView ? 'Previous month' : 'Previous week',
                width: 32,
                onPressed: () => _select(
                  _monthView
                      ? DateTime(
                          _selectedDay.year,
                          _selectedDay.month - 1,
                          _selectedDay.day.clamp(
                            1,
                            DateTime(
                              _selectedDay.year,
                              _selectedDay.month,
                              0,
                            ).day,
                          ),
                        )
                      : _selectedDay.subtract(const Duration(days: 7)),
                ),
                child: const Icon(Icons.chevron_left_rounded, size: 17),
              ),
              const SizedBox(width: 5),
              _outlinedButton(
                tooltip: _monthView ? 'Next month' : 'Next week',
                width: 32,
                onPressed: () => _select(
                  _monthView
                      ? DateTime(_selectedDay.year, _selectedDay.month + 1, 1)
                      : _selectedDay.add(const Duration(days: 7)),
                ),
                child: const Icon(Icons.chevron_right_rounded, size: 17),
              ),
              const SizedBox(width: 7),
              _outlinedButton(
                tooltip: _monthView
                    ? 'Show week calendar'
                    : 'Show month calendar',
                onPressed: () => setState(() => _monthView = !_monthView),
                child: Text(_monthView ? 'Week view' : 'Month view'),
              ),
            ],
          ),
          _calendar(),
          const Divider(height: 24),
          Text(
            date,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (widget.loading && widget.schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.hasError && widget.schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Unable to load defense schedules. Refresh to try again.',
              ),
            )
          else if (widget.schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No defenses scheduled for your teams yet.'),
            )
          else if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No defenses on this day. Select a marked date.'),
            )
          else ...[
            for (final event in _showAll ? events : events.take(3))
              _eventTile(event),
            if (events.length > 3)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll
                      ? 'Show fewer'
                      : 'Show all ${events.length} defenses',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
