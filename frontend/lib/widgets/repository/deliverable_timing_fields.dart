import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../shadcn/defensys_workflow_widgets.dart';

class DefenseMaterialToggle extends StatelessWidget {
  const DefenseMaterialToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadCheckbox(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      label: const Text('Defense material for panelists'),
    ),
  );
}

/// Timing is independent of required status and visibility to panelists.
class DeliverableTimingFields extends StatelessWidget {
  const DeliverableTimingFields({
    super.key,
    required this.timing,
    required this.hoursBefore,
    required this.onTimingChanged,
    required this.onHoursChanged,
    this.enabled = true,
    this.showTimingChoices = false,
    this.isDefenseMaterial = false,
  });

  final String timing;
  final int hoursBefore;
  final bool enabled;
  final bool showTimingChoices;
  final bool isDefenseMaterial;
  final ValueChanged<String> onTimingChanged;
  final ValueChanged<int> onHoursChanged;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: showTimingChoices ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: showTimingChoices
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTimingChoices) ...[
            Text(
              'When should students submit this file?',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (isDefenseMaterial) ...[
              const SizedBox(height: 4),
              Text(
                'Panelists use this file. Marking it as defense material does not change its due time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final schedulingChoice = _timingChoice(
                  context,
                  value: 'scheduling',
                  title: 'Before endorsement',
                  description:
                      'If required, this file must be cleared before scheduling.',
                  icon: Icons.fact_check_outlined,
                );
                final defenseChoice = _timingChoice(
                  context,
                  value: 'defense',
                  title: 'Before scheduled defense',
                  description:
                      'Students may submit it after endorsement until its deadline.',
                  icon: Icons.event_outlined,
                );
                return constraints.maxWidth < 540
                    ? Column(
                        children: [
                          schedulingChoice,
                          const SizedBox(height: 8),
                          defenseChoice,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: schedulingChoice),
                          const SizedBox(width: 8),
                          Expanded(child: defenseChoice),
                        ],
                      );
              },
            ),
          ] else
            WorkflowSelect(
              label: 'Needed by',
              value: timing,
              enabled: enabled,
              searchable: false,
              options: const {
                'scheduling': 'Before endorsement / scheduling',
                'defense': 'Before scheduled defense',
              },
              onChanged: onTimingChanged,
            ),
          if (timing == 'defense') ...[
            if (showTimingChoices) const SizedBox(height: 12),
            if (showTimingChoices)
              _StageDeadlineChoices(
                hoursBefore: hoursBefore,
                enabled: enabled,
                onChanged: onHoursChanged,
              )
            else
              WorkflowSelect(
                label: 'Submission deadline',
                value: hoursBefore.toString(),
                enabled: enabled,
                searchable: false,
                options: {
                  for (final hours in {
                    0,
                    1,
                    6,
                    12,
                    24,
                    48,
                    72,
                    168,
                    hoursBefore,
                  }.toList()..sort())
                    hours.toString(): hours == 0
                        ? 'At defense start'
                        : '$hours hours before defense',
                },
                onChanged: (value) => onHoursChanged(int.parse(value)),
              ),
            Text(
              'Students can upload and replace this file after endorsement until its deadline. '
              'It does not block scheduling.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (!showTimingChoices)
            Text(
              'Required items must be cleared before endorsement. Approved files lock when the team is endorsed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
  );

  Widget _timingChoice(
    BuildContext context, {
    required String value,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final selected = timing == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: enabled ? () => onTimingChanged(value) : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: selected
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageDeadlineChoices extends StatefulWidget {
  const _StageDeadlineChoices({
    required this.hoursBefore,
    required this.enabled,
    required this.onChanged,
  });

  final int hoursBefore;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_StageDeadlineChoices> createState() => _StageDeadlineChoicesState();
}

class _StageDeadlineChoicesState extends State<_StageDeadlineChoices> {
  static const _presets = [12, 24, 48];
  late final TextEditingController _customHours;
  late bool _customSelected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customSelected = !_presets.contains(widget.hoursBefore);
    _customHours = TextEditingController(text: widget.hoursBefore.toString());
  }

  @override
  void didUpdateWidget(covariant _StageDeadlineChoices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoursBefore != widget.hoursBefore &&
        int.tryParse(_customHours.text) != widget.hoursBefore) {
      _customHours.text = widget.hoursBefore.toString();
      _customSelected = !_presets.contains(widget.hoursBefore);
      _error = null;
    }
  }

  @override
  void dispose() {
    _customHours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How long before defense?',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hours in _presets)
              _option(
                context,
                label: '$hours hours',
                selected: !_customSelected && widget.hoursBefore == hours,
                onPressed: () {
                  setState(() {
                    _customSelected = false;
                    _error = null;
                  });
                  widget.onChanged(hours);
                },
              ),
            _option(
              context,
              label: 'Custom',
              selected: _customSelected,
              onPressed: () => setState(() {
                _customSelected = true;
                _customHours.text = widget.hoursBefore.toString();
              }),
            ),
          ],
        ),
        if (_customSelected) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 180,
            child: ShadInput(
              key: const ValueKey('stage-custom-deadline-hours'),
              controller: _customHours,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              placeholder: const Text('Hours before defense'),
              onChanged: (value) {
                final hours = int.tryParse(value);
                setState(() {
                  _error = hours == null || hours < 0 || hours > 720
                      ? 'Enter 0 to 720 hours.'
                      : null;
                });
                if (_error == null) widget.onChanged(hours!);
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _option(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return selected
        ? ShadButton(
            size: ShadButtonSize.sm,
            enabled: widget.enabled,
            onPressed: onPressed,
            child: Text(label),
          )
        : ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: widget.enabled,
            onPressed: onPressed,
            child: Text(label),
          );
  }
}
