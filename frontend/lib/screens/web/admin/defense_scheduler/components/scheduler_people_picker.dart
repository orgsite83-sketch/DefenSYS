import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

/// Uses the installed Flutter shadcn components with the portal's own tokens.
class SchedulerShadcnScope extends DefensysShadcnScope {
  const SchedulerShadcnScope({super.key, required super.child});
}

String schedulerPersonName(Map<String, dynamic> person) =>
    person['name']?.toString() ??
    person['full_name']?.toString() ??
    person['username']?.toString() ??
    'Faculty member';

/// Keeps the directory in a searchable popover and only assignments on the page.
class SchedulerPeoplePicker extends StatefulWidget {
  const SchedulerPeoplePicker({
    super.key,
    required this.people,
    required this.selected,
    required this.onChanged,
    required this.placeholder,
    this.searchPlaceholder = 'Search by name or ID',
    this.multiple = true,
    this.enabled = true,
    this.detailBuilder,
    this.emptyMessage = 'No people available.',
  });

  final List<Map<String, dynamic>> people;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final String placeholder;
  final String searchPlaceholder;
  final bool multiple;
  final bool enabled;
  final String? Function(Map<String, dynamic>)? detailBuilder;
  final String emptyMessage;

  @override
  State<SchedulerPeoplePicker> createState() => _SchedulerPeoplePickerState();
}

class _SchedulerPeoplePickerState extends State<SchedulerPeoplePicker> {
  late final ShadSelectController<int> _controller;
  String _query = '';

  int? _id(Map<String, dynamic> person) =>
      int.tryParse(person['id']?.toString() ?? '');

  Set<int> get _validSelection => widget.selected.intersection({
    for (final person in widget.people)
      if (_id(person) != null) _id(person)!,
  });

  @override
  void initState() {
    super.initState();
    _controller = ShadSelectController(initialValue: _validSelection);
  }

  @override
  void didUpdateWidget(covariant SchedulerPeoplePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(_controller.value, _validSelection)) {
      _controller.value = _validSelection;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SchedulerShadcnScope(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final selectedPeople = widget.people
            .where((person) => widget.selected.contains(_id(person)))
            .toList();
        final query = _query.trim().toLowerCase();
        final results = widget.people.where((person) {
          final text =
              '${schedulerPersonName(person)} ${person['username'] ?? ''} '
              '${person['institution'] ?? ''}';
          return _id(person) != null && text.toLowerCase().contains(query);
        });
        final options = <Widget>[
          for (final person in results)
            ShadOption<int>(
              value: _id(person)!,
              child: SizedBox(
                width: (width - 64).clamp(60, 1000).toDouble(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedulerPersonName(person),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.detailBuilder?.call(person)
                        case final String detail)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                query.isEmpty ? widget.emptyMessage : 'No matching people.',
              ),
            ),
        ];
        final enabled = widget.enabled && widget.people.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.multiple)
              ShadSelect<int>.multipleWithSearch(
                controller: _controller,
                enabled: enabled,
                minWidth: width,
                maxWidth: width,
                maxHeight: 300,
                closeOnSelect: false,
                clearSearchOnClose: true,
                placeholder: Text(
                  widget.placeholder,
                  style: const TextStyle(fontSize: 13),
                ),
                searchPlaceholder: Text(widget.searchPlaceholder),
                onSearchChanged: (value) => setState(() => _query = value),
                options: options,
                selectedOptionsBuilder: (_, ids) => Text(
                  '${ids.length} selected',
                  style: const TextStyle(fontSize: 13),
                ),
                onChanged: widget.onChanged,
              )
            else
              ShadSelect<int>.withSearch(
                controller: _controller,
                enabled: enabled,
                minWidth: width,
                maxWidth: width,
                maxHeight: 300,
                clearSearchOnClose: true,
                placeholder: Text(
                  widget.placeholder,
                  style: const TextStyle(fontSize: 13),
                ),
                searchPlaceholder: Text(widget.searchPlaceholder),
                onSearchChanged: (value) => setState(() => _query = value),
                options: options,
                selectedOptionBuilder: (_, id) => Text(
                  schedulerPersonName(
                    widget.people.firstWhere((person) => _id(person) == id),
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                onChanged: (id) => widget.onChanged({if (id != null) id}),
              ),
            if (widget.multiple && selectedPeople.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 184),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final person in selectedPeople)
                        Row(
                          children: [
                            const Icon(LucideIcons.userRound, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                schedulerPersonName(person),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: DefensysTokens.textPrimaryOf(context),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Remove ${schedulerPersonName(person)}',
                              child: ShadButton.ghost(
                                width: 32,
                                height: 32,
                                padding: EdgeInsets.zero,
                                onPressed: widget.enabled
                                    ? () => widget.onChanged(
                                        {...widget.selected}
                                          ..remove(_id(person)),
                                      )
                                    : null,
                                child: const Icon(LucideIcons.x, size: 14),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (!widget.multiple && selectedPeople.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: widget.enabled ? () => widget.onChanged({}) : null,
                  child: const Text('Clear selection'),
                ),
              ),
          ],
        );
      },
    ),
  );
}
