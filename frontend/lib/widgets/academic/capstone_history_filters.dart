import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';

/// The same compact dropdown styling as the existing Current Term/History filter.
class CapstoneHistoryFilters extends StatelessWidget {
  const CapstoneHistoryFilters({
    super.key,
    required this.options,
    required this.intake,
    required this.phase,
    required this.stage,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<String, dynamic> options;
  final String intake, phase, stage;
  final bool enabled;
  final void Function(String intake, String phase, String stage) onChanged;

  List<Map> _rows(String key) =>
      (options[key] as List? ?? []).whereType<Map>().toList();

  Widget _picker(
    BuildContext context,
    String label,
    String value,
    List<MapEntry<String, String>> items,
    ValueChanged<String> onSelect, {
    double width = 220,
  }) {
    return AcademicHistoryDropdown(
      label: label,
      value: value,
      items: items,
      onChanged: onSelect,
      enabled: enabled,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 400 ? constraints.maxWidth : 280.0;
      return Wrap(
        spacing: 10,
        runSpacing: 12,
        children: [
          _picker(
            context,
            'Capstone intake',
            intake,
            _rows(
              'intakes',
            ).map((r) => MapEntry('${r['id']}', '${r['label']}')).toList(),
            (v) => onChanged(v, '', ''),
            width: width,
          ),
          _picker(
            context,
            'Phase',
            phase,
            [
              const MapEntry('', 'All phases'),
              ..._rows(
                'phases',
              ).map((r) => MapEntry('${r['value']}', '${r['label']}')),
            ],
            (v) => onChanged(intake, v, ''),
            width: width,
          ),
          _picker(
            context,
            'Stage',
            stage,
            [
              const MapEntry('', 'All stages'),
              ..._rows(
                'stages',
              ).map((r) => MapEntry('${r['value']}', '${r['label']}')),
            ],
            (v) => onChanged(intake, phase, v),
            width: width,
          ),
        ],
      );
    },
  );
}

class AcademicHistoryDropdown extends StatelessWidget {
  const AcademicHistoryDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.width = 280,
  });
  final String label, value;
  final List<MapEntry<String, String>> items;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    final selected = items.any((i) => i.key == value)
        ? value
        : items.firstOrNull?.key;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                dropdownColor: DefensysTokens.surfaceOf(context),
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 12.5,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
                items: items
                    .map(
                      (i) => DropdownMenuItem(
                        value: i.key,
                        child: Text(i.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: enabled
                    ? (v) {
                        if (v != null) onChanged(v);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
