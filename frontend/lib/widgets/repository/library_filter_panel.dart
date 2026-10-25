import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/library_filters.dart';
import '../../models/repository_library.dart';
import '../../theme/defensys_tokens.dart';
import 'library_components.dart';

/// A searchable facet directory with draft state and a fixed results action.
class LibraryFilterPanel extends StatefulWidget {
  const LibraryFilterPanel({
    super.key,
    required this.entries,
    required this.selection,
    required this.onApply,
  });
  final List<VaultEntry> entries;
  final LibraryFilterSelection selection;
  final ValueChanged<LibraryFilterSelection> onApply;
  @override
  State<LibraryFilterPanel> createState() => _LibraryFilterPanelState();
}

class _LibraryFilterPanelState extends State<LibraryFilterPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _expanded = <LibraryFilterGroup>{};
  late LibraryFilterSelection _draft = widget.selection;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TextStyle get _caption => DefensysTokens.caption.copyWith(
    color: DefensysTokens.textSecondaryOf(context),
  );

  List<LibraryFacetOption> _options(LibraryFilterGroup group) => _draft
      .facets(widget.entries, group)
      .where(
        (option) => option.tag.label.toLowerCase().contains(
          _query.trim().toLowerCase(),
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final years = {
      if (_draft.year.isNotEmpty) _draft.year,
      ...widget.entries
          .where((entry) => _draft.matches(entry, ignoreYear: true))
          .map((entry) => entry.academicYear)
          .where((year) => year.isNotEmpty && year != '—'),
    }.toList()..sort((a, b) => b.compareTo(a));
    final selected =
        (_draft.year.isEmpty ? 0 : 1) +
        LibraryFilterGroup.values.fold(
          0,
          (total, group) => total + _draft.values(group).length,
        );
    final count = widget.entries
        .where(_draft.matches)
        .map((entry) => entry.groupingKey)
        .toSet()
        .length;
    final groups = LibraryFilterGroup.values
        .where((group) => _options(group).isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          key: const ValueKey('library-filter-search'),
          controller: _search,
          placeholder: const Text('Find filter options…'),
          leading: Icon(
            Icons.search_rounded,
            size: 18,
            color: DefensysTokens.textSecondaryOf(context),
          ),
          onChanged: (value) => setState(() => _query = value),
          trailing: _query.isEmpty
              ? null
              : Tooltip(
                  message: 'Clear option search',
                  child: ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    child: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('Select any combination', style: _caption)),
            Text(
              selected == 0 ? 'All research' : '$selected selected',
              style: _caption.copyWith(
                fontWeight: FontWeight.w600,
                color: selected == 0
                    ? DefensysTokens.textSecondaryOf(context)
                    : DefensysTokens.maroonTextOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            thickness: 3,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12, right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _heading(
                    'School year',
                    Icons.calendar_today_outlined,
                    detail: _draft.year.isEmpty
                        ? 'All published years'
                        : 'One year selected',
                    onClear: _draft.year.isEmpty
                        ? null
                        : () => setState(
                            () => _draft = _draft.copyWith(year: ''),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final year in ['', ...years])
                        LibraryChoiceChip(
                          label: year.isEmpty ? 'All years' : 'SY $year',
                          selected: _draft.year == year,
                          onSelected: () => setState(
                            () => _draft = _draft.copyWith(year: year),
                          ),
                        ),
                    ],
                  ),
                  for (final group in groups) _section(group),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        _query.isNotEmpty
                            ? 'No filter options match your search.'
                            : 'No filter options are available in this collection.',
                        style: _caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Technology tags include explicitly proposed choices.',
                          style: _caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$count ${count == 1 ? 'project matches' : 'projects match'}',
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ShadButton.ghost(
              height: 36,
              onPressed: () => setState(() {
                _draft = const LibraryFilterSelection();
                _search.clear();
                _query = '';
                _expanded.clear();
              }),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ShadButton(
          width: double.infinity,
          height: 44,
          trailing: const Icon(Icons.arrow_forward_rounded, size: 16),
          onPressed: () => widget.onApply(_draft),
          child: const Text('Show collection'),
        ),
      ],
    );
  }

  Widget _heading(
    String label,
    IconData icon, {
    String? detail,
    VoidCallback? onClear,
  }) => Row(
    children: [
      Icon(icon, size: 18, color: DefensysTokens.textSecondaryOf(context)),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(detail, style: _caption),
            ],
          ],
        ),
      ),
      if (onClear != null)
        ShadButton.ghost(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: onClear,
          child: const Text('Clear', style: TextStyle(fontSize: 12)),
        ),
    ],
  );

  Widget _section(LibraryFilterGroup group) {
    final options = _options(group);
    final expanded = _query.isNotEmpty || _expanded.contains(group);
    final active = options
        .where((option) => _draft.values(group).contains(option.tag.id))
        .toList();
    final shown = expanded
        ? options
        : [
            ...active,
            ...options
                .where(
                  (option) => !_draft.values(group).contains(option.tag.id),
                )
                .take((6 - active.length).clamp(0, 6)),
          ];
    final count = _draft.values(group).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
        ),
        _heading(
          group.label,
          switch (group) {
            LibraryFilterGroup.subject => Icons.local_library_outlined,
            LibraryFilterGroup.technology => Icons.devices_outlined,
            LibraryFilterGroup.language => Icons.code_rounded,
          },
          detail: count == 0 ? null : '$count selected',
          onClear: count == 0
              ? null
              : () => setState(() => _draft = _draft.clear(group)),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 520 &&
                    MediaQuery.textScalerOf(context).scale(14) < 20
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final option in shown)
                  SizedBox(
                    width: width,
                    child: _LibraryFilterOption(
                      key: ValueKey(
                        'library-filter-${group.name}-${option.tag.id}',
                      ),
                      option: option,
                      selected: _draft.values(group).contains(option.tag.id),
                      onChanged: () => setState(
                        () => _draft = _draft.toggle(group, option.tag),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (options.length > 6 && _query.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.ghost(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => setState(
                () => expanded ? _expanded.remove(group) : _expanded.add(group),
              ),
              child: Text(
                expanded ? 'Show fewer' : 'Show all ${options.length}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _LibraryFilterOption extends StatelessWidget {
  const _LibraryFilterOption({
    super.key,
    required this.option,
    required this.selected,
    required this.onChanged,
  });
  final LibraryFacetOption option;
  final bool selected;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Material(
      color: selected
          ? DefensysTokens.surfaceHigherOf(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              ExcludeFocus(
                child: ShadCheckbox(
                  value: selected,
                  uncheckedColor: DefensysTokens.surfaceOf(context),
                  decoration: const ShadDecoration(
                    border: ShadBorder(
                      radius: BorderRadius.all(Radius.circular(4)),
                    ),
                    focusedBorder: ShadBorder(
                      radius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.tag.label,
                  style: DefensysTokens.tableCell.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${option.count}',
                  textAlign: TextAlign.center,
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
