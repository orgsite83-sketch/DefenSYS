import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense/template_configuration.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/repository/deliverable_template.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

Map<String, dynamic> weeklyTemplateDraft(Map<String, dynamic>? stage) {
  final saved = stage?['weekly_template'];
  final managed = (stage?['system_deliverables'] as List? ?? [])
      .whereType<Map>()
      .where((item) => item['source'] == 'weekly_reports')
      .firstOrNull;
  return {
    'deliverable_id': 'WPR',
    'label': 'Weekly Accomplishment Reports',
    if (saved is Map) ...Map<String, dynamic>.from(saved),
    if (saved == null && managed?['template'] != null)
      'template': managed!['template'],
  };
}

Map<String, dynamic> initialWeeklySettings(
  Map? saved,
  Iterable<Map<String, dynamic>> stages,
) {
  if (saved?['enabled'] == true) return Map<String, dynamic>.from(saved!);
  final shared = stages
      .map((stage) => stage['weekly_reporting'])
      .whereType<Map>()
      .where((config) => config['enabled'] == true)
      .firstOrNull;
  return _clampRequiredWeeks({
    if (shared != null) ...Map<String, dynamic>.from(shared),
    'enabled': false,
    'required_start': 1,
    'required_end': 8,
    if (saved != null) ...Map<String, dynamic>.from(saved),
  });
}

Map<String, dynamic> _clampRequiredWeeks(Map<String, dynamic> config) {
  final total = int.tryParse('${config['total_weeks']}');
  if (total == null || total < 1 || total > 53) return config;
  return {
    ...config,
    for (final key in ['required_start', 'required_end'])
      if (int.tryParse('${config[key]}') case final int week)
        key: week.clamp(1, total),
  };
}

String? weeklySettingsError(
  Map<String, dynamic> config,
  Map<String, dynamic> template, {
  bool requireTemplate = true,
}) {
  if (config['enabled'] != true) return null;
  final start = DateTime.tryParse('${config['starts_on'] ?? ''}');
  final total = int.tryParse('${config['total_weeks']}') ?? 0;
  final first = int.tryParse('${config['required_start']}') ?? 0;
  final last = int.tryParse('${config['required_end']}') ?? 0;
  final day = int.tryParse('${config['due_weekday']}') ?? -1;
  final time = RegExp(
    r'^(\d{2}):(\d{2})$',
  ).firstMatch('${config['due_time'] ?? ''}');
  if (start == null ||
      total < 1 ||
      total > 53 ||
      first < 1 ||
      last < first ||
      last > total ||
      day < 0 ||
      day > 6 ||
      time == null ||
      int.parse(time[1]!) > 23 ||
      int.parse(time[2]!) > 59) {
    return 'Choose a start date, a report count that fits the saved schedule, '
        'and a weekly due time.';
  }
  final selection = templateSelectionError(template);
  if (selection != null) return selection;
  final name = template['template_action'] == 'replace'
      ? '${template['template_selection_name'] ?? ''}'
      : template['template_action'] == 'remove'
      ? ''
      : '${(template['template'] as Map?)?['original_name'] ?? ''}';
  if (requireTemplate && name.isEmpty) {
    return 'Attach a weekly report template.';
  }
  if (name.isNotEmpty &&
      !templateExtensions.contains(name.split('.').last.toLowerCase())) {
    return 'Choose a supported weekly report template file.';
  }
  return null;
}

class StageWeeklySettings extends StatefulWidget {
  const StageWeeklySettings({
    super.key,
    required this.value,
    required this.template,
    required this.enabled,
    required this.onChanged,
    required this.onTemplateChanged,
    this.semesterLabel,
    this.compact = false,
  });

  final Map<String, dynamic> value;
  final Map<String, dynamic> template;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onTemplateChanged;
  final String? semesterLabel;
  final bool compact;

  @override
  State<StageWeeklySettings> createState() => _StageWeeklySettingsState();
}

class _StageWeeklySettingsState extends State<StageWeeklySettings> {
  final _controllers = <String, TextEditingController>{};
  String _reportCountText = '';
  bool _expanded = false;

  int? _number(String key) => int.tryParse('${widget.value[key]}');
  int? get _count => int.tryParse(_reportCountText);

  String _displayValue(String key) {
    if (key == 'report_count') return _reportCountText;
    final raw = '${widget.value[key] ?? ''}';
    if (key == 'starts_on') {
      final date = DateTime.tryParse(raw);
      return date == null ? '' : DateFormat('d MMM yyyy').format(date);
    }
    if (key == 'due_time') {
      final parts = raw.split(':');
      final hour = int.tryParse(parts.first);
      final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
      if (hour != null && minute != null && hour < 24 && minute < 60) {
        return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
      }
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _syncReportCount();
  }

  void _syncReportCount() {
    final first = _number('required_start');
    final last = _number('required_end');
    if (first != null && last != null) {
      _reportCountText = '${last - first + 1}';
    }
  }

  @override
  void didUpdateWidget(covariant StageWeeklySettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncReportCount();
    for (final entry in _controllers.entries) {
      final text = _displayValue(entry.key);
      if (entry.value.text != text) {
        entry.value.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: entry.value.selection.extentOffset.clamp(0, text.length),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _update(String key, dynamic data) {
    final updated = {...widget.value, key: data};
    if (key == 'report_count') {
      updated.remove(key);
      _reportCountText = '$data';
      final count = int.tryParse('$data');
      final first = _number('required_start') ?? 1;
      updated['required_end'] = count == null ? '' : first + count - 1;
    }
    // Grow a new schedule to fit the report count. Keep saved schedules stable
    // so existing report dates and deadlines do not change.
    if (widget.value['period_id'] == null && key == 'report_count') {
      final last = int.tryParse('${updated['required_end']}');
      final total = _number('total_weeks') ?? 16;
      if (last != null && last > total) updated['total_weeks'] = last;
    }
    widget.onChanged(updated);
  }

  Widget _pickerTheme(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return child!;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          surfaceContainerHighest: DefensysTokens.background,
          primaryContainer: DefensysTokens.background,
          onPrimaryContainer: DefensysTokens.maroon,
        ),
        datePickerTheme: theme.datePickerTheme.copyWith(
          backgroundColor: Colors.white,
          headerBackgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        timePickerTheme: theme.timePickerTheme.copyWith(
          backgroundColor: Colors.white,
          dialBackgroundColor: DefensysTokens.background,
          dayPeriodColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? DefensysTokens.maroon
                : Colors.white,
          ),
          dayPeriodTextColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : DefensysTokens.textPrimary,
          ),
        ),
      ),
      child: child!,
    );
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse('${widget.value['starts_on']}') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      builder: _pickerTheme,
    );
    if (chosen != null && mounted) {
      _update('starts_on', DateFormat('yyyy-MM-dd').format(chosen));
    }
  }

  Future<void> _chooseTime() async {
    final parts = '${widget.value['due_time'] ?? '23:59'}'.split(':');
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (int.tryParse(parts.first) ?? 23).clamp(0, 23),
        minute: (int.tryParse(parts.last) ?? 59).clamp(0, 59),
      ),
      builder: _pickerTheme,
    );
    if (chosen != null && mounted) {
      _update(
        'due_time',
        '${chosen.hour.toString().padLeft(2, '0')}:'
            '${chosen.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final enabled = widget.enabled;
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final body = DefensysTokens.body.copyWith(color: primary);
    final description = DefensysTokens.subtitle.copyWith(color: secondary);
    final label = body.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
    final active = value['enabled'] == true;
    final first = _number('required_start') ?? 0;
    final last = _number('required_end');
    final total = _number('total_weeks') ?? 0;
    final count = _count;
    final day = _number('due_weekday');
    final start = DateTime.tryParse('${value['starts_on']}');
    final validRange =
        count != null &&
        count > 0 &&
        first > 0 &&
        last != null &&
        last <= total &&
        total <= 53;
    String? countError;
    if (count == null || count < 1 || count > 53) {
      countError = 'Enter a number from 1 to 53.';
    } else if (last != null && last > total) {
      countError =
          'This saved schedule supports up to '
          '${(total - first + 1).clamp(0, 53)} reports.';
    }
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    InputDecoration decoration({
      String? hint,
      IconData? icon,
      String? error,
    }) => InputDecoration(
      hintText: hint,
      hintStyle: description,
      errorText: error,
      errorStyle: DefensysTokens.caption.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
      errorMaxLines: 3,
      filled: true,
      fillColor: DefensysTokens.surfaceOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: icon == null ? null : Icon(icon, size: 18, color: secondary),
    );

    Widget labelled(String text, Widget child, {String? help}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: label),
        const SizedBox(height: 8),
        Semantics(label: text, child: child),
        if (help != null) ...[
          const SizedBox(height: 6),
          Text(help, style: description),
        ],
      ],
    );

    Widget field(
      String key,
      String text, {
      String? help,
      String? error,
      String? hint,
      bool numeric = false,
      IconData? icon,
      VoidCallback? onTap,
    }) => labelled(
      text,
      TextFormField(
        key: ValueKey('weekly-$key'),
        controller: _controllers.putIfAbsent(
          key,
          () => TextEditingController(text: _displayValue(key)),
        ),
        enabled: enabled,
        style: body,
        readOnly: onTap != null,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: decoration(hint: hint, icon: icon, error: error),
        onTap: onTap,
        onChanged: (text) =>
            _update(key, numeric ? int.tryParse(text) ?? text : text),
      ),
      help: help,
    );

    Widget grid(List<Widget> children, {int maxColumns = 2}) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? maxColumns : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 18,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );

    DateTime? due(int week) =>
        start == null || day == null || day < 0 || day > 6
        ? null
        : start.add(
            Duration(days: ((day - (start.weekday - 1)) % 7) + 7 * (week - 1)),
          );
    Widget previewItem(String title, String text, {String? detail}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: description),
        const SizedBox(height: 4),
        Text(text, style: body),
        if (detail != null) Text(detail, style: description),
      ],
    );
    final firstDue = validRange ? due(first) : null;
    final lastDue = validRange ? due(last) : null;
    final time = _displayValue('due_time');
    final weeks = first == last ? 'Week $first' : 'Weeks $first–$last';

    void toggle(bool checked) {
      if (checked) setState(() => _expanded = true);
      widget.onChanged(_clampRequiredWeeks({
        'total_weeks': 16, 'due_weekday': 6, 'due_time': '23:59',
        'required_start': 1, 'required_end': 8,
        ...value, 'enabled': checked,
      }));
    }

    return DefensysShadcnScope(child: DefaultTextStyle.merge(
      style: body,
      child: Container(
        key: const ValueKey('weekly-report-policy'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.backgroundOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.compact) ...[
              Row(children: [
                Expanded(child: Text('Weekly reports required',
                  style: DefensysTokens.sectionTitle.copyWith(color: primary))),
                const SizedBox(width: 12),
                ShadSwitch(value: active, enabled: enabled, onChanged: toggle,
                  checkedTrackColor: DefensysTokens.maroon),
              ]),
              const SizedBox(height: 6),
              Text(active && validRange && day != null && day >= 0 && day < 7
                  ? '$count ${count == 1 ? 'report' : 'reports'} · Every ${weekdays[day]}, $time'
                  : active ? 'Configure the report schedule and template.'
                  : 'Require signed weekly reports before adviser endorsement.',
                style: description),
              if (active) ...[
                if (start != null) ...[
                  const SizedBox(height: 4),
                  Text('Week 1 starts ${DateFormat('d MMM yyyy').format(start)} · Philippine time', style: description),
                ],
                const SizedBox(height: 10),
                ShadButton.outline(
                  key: const ValueKey('configure-weekly-reports'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Hide report settings' : 'Configure reports'),
                ),
                if (!_expanded)
                  if (weeklySettingsError(value, widget.template) case final String error)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(error,
                      style: description.copyWith(color: Theme.of(context).colorScheme.error))),
              ],
            ] else
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Weekly reports required',
                style: DefensysTokens.sectionTitle.copyWith(color: primary),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Students submit one signed report each week. '
                  'The adviser accepts the required reports before endorsement.',
                  style: description,
                ),
              ),
              value: active,
              onChanged: enabled ? toggle : null,
            ),
            if (active && (!widget.compact || _expanded)) ...[
              const SizedBox(height: 16),
              if (widget.semesterLabel != null) ...[
                Text('For ${widget.semesterLabel}', style: description),
                const SizedBox(height: 16),
              ],
              grid([
                field(
                  'report_count',
                  'Number of weekly reports',
                  numeric: true,
                  hint: 'e.g. 8',
                  error: countError,
                  help: 'One report per week, required for this stage.',
                ),
                field(
                  'starts_on',
                  'Week 1 starts on',
                  hint: 'Choose a date',
                  icon: Icons.calendar_today_outlined,
                  onTap: _chooseDate,
                  help: 'Start date for the first reporting week.',
                ),
                labelled(
                  'Due every',
                  DropdownButtonFormField<int>(
                    key: ValueKey('weekly-due-weekday-$day'),
                    initialValue: day != null && day >= 0 && day <= 6
                        ? day
                        : null,
                    style: body,
                    decoration: decoration(),
                    items: [
                      for (var i = 0; i < weekdays.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(weekdays[i], style: body),
                        ),
                    ],
                    onChanged: enabled
                        ? (day) => _update('due_weekday', day)
                        : null,
                  ),
                ),
                field(
                  'due_time',
                  'Due at',
                  icon: Icons.access_time,
                  onTap: _chooseTime,
                  help: 'Philippine time (Asia/Manila).',
                ),
              ]),
              const Divider(height: 24),
              Text('Schedule preview', style: label),
              const SizedBox(height: 8),
              if (validRange) ...[
                Text(
                  '$count ${count == 1 ? 'report' : 'reports'} required · $weeks',
                  key: const ValueKey('weekly-range-summary'),
                  style: body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                if (start != null && firstDue != null && lastDue != null)
                  grid([
                    previewItem(
                      'Reports cover',
                      '${DateFormat('d MMM yyyy').format(start.add(Duration(days: 7 * (first - 1))))} – '
                          '${DateFormat('d MMM yyyy').format(start.add(Duration(days: 7 * (last - 1) + 6)))}',
                    ),
                    previewItem(
                      count == 1 ? 'Report due' : 'First report due',
                      DateFormat('EEE, d MMM yyyy').format(firstDue),
                      detail: '$time · Philippine time',
                    ),
                    if (count > 1)
                      previewItem(
                        'Last report due',
                        DateFormat('EEE, d MMM yyyy').format(lastDue),
                        detail: '$time · Philippine time',
                      ),
                  ], maxColumns: count == 1 ? 2 : 3)
                else
                  Text(
                    'Choose a start date to see the report dates and deadlines.',
                    style: description,
                  ),
              ] else
                Text(
                  'Enter a valid report count to preview the schedule.',
                  style: description,
                ),
              const SizedBox(height: 14),
              Text(
                'Late reports can still be uploaded and accepted.',
                style: description,
              ),
              const Divider(height: 28),
              DeliverableTemplateEditor(
                item: widget.template,
                enabled: enabled,
                label: 'Report template',
                requiredTemplate: true,
                onChanged: widget.onTemplateChanged,
              ),
              const SizedBox(height: 12),
              Text(
                'Students use the template to prepare their report, get the adviser’s physical signature, '
                'then upload the signed PDF.',
                style: description,
              ),
            ],
          ],
        ),
      ),
    ));
  }
}

class StageWeeklyRequirementRow extends StatelessWidget {
  const StageWeeklyRequirementRow({
    super.key,
    required this.config,
    required this.onEdit,
  });
  final Map<String, dynamic> config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: const Icon(Icons.assignment_outlined, size: 20),
    title: const Text('Weekly Accomplishment Reports'),
    subtitle: Text(
      'Weeks ${config['required_start'] ?? 1}-${config['required_end'] ?? 8} · '
      'PDF · Required before endorsement · Adviser acceptance',
    ),
    trailing: TextButton(onPressed: onEdit, child: const Text('Edit settings')),
    onTap: onEdit,
  );
}
