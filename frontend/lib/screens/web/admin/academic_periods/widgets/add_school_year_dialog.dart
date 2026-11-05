import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';

class AddSchoolYearDialog extends StatefulWidget {
  const AddSchoolYearDialog({super.key, required this.existingLabels});

  final Iterable<String> existingLabels;

  @override
  State<AddSchoolYearDialog> createState() => _AddSchoolYearDialogState();
}

class _AddSchoolYearDialogState extends State<AddSchoolYearDialog> {
  late final List<int> _years;
  late int _lastYear;
  late int _selectedYear;

  String _label(int year) => '$year-${year + 1}';

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    final existing = widget.existingLabels.toSet();
    var firstYear = currentYear - 1;
    _lastYear = currentYear + 3;
    for (final label in existing) {
      final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(label);
      if (match == null) continue;
      final year = int.parse(match.group(1)!);
      if (year < firstYear) firstYear = year;
      // Always offer a year after the latest saved academic year.
      if (year >= _lastYear) _lastYear = year + 1;
    }
    _years = [
      for (var year = firstYear; year <= _lastYear; year++)
        if (!existing.contains(_label(year))) year,
    ];
    _selectedYear = _years.firstWhere(
      (year) => year >= currentYear,
      orElse: () => _years.first,
    );
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    maroonActions: true,
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 464),
      title: const Text('Add School Year'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: () => Navigator.pop(context, _label(_selectedYear)),
          child: const Text('Add Year'),
        ),
      ],
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: WorkflowField(
            label: 'School Year',
            child: LayoutBuilder(
              builder: (context, constraints) => ShadSelect<int>(
                key: ValueKey('school-year-$_selectedYear'),
                initialValue: _selectedYear,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                maxHeight: 260,
                selectedOptionBuilder: (context, year) => Text(_label(year)),
                options: [
                  for (final year in _years)
                    ShadOption(value: year, child: Text(_label(year))),
                  const ShadOption(
                    value: -1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 8),
                        Text('Add another'),
                      ],
                    ),
                  ),
                ],
                onChanged: (year) {
                  if (year == null) return;
                  setState(() {
                    if (year == -1) {
                      _lastYear++;
                      _years.add(_lastYear);
                      _selectedYear = _lastYear;
                    } else {
                      _selectedYear = year;
                    }
                  });
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
