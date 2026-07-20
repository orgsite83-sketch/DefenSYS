import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

int _count(CapstoneDeliverablesState state, String key) {
  return _asInt(state.counts[key]);
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

Widget _iconBox(IconData icon, Color color) {
  return Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color),
  );
}

Widget _stat(String label, int count, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        _iconBox(icon, color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget buildDeliverablesStats(CapstoneDeliverablesState state) {
  final teamLabel = state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams';
  final items = [
    _stat(teamLabel, _count(state, 'teams'), Icons.groups_2_outlined, AppColors.maroon),
    _stat('Ready', _count(state, 'ready'), Icons.verified_outlined, AppColors.success),
    _stat('Pending', _count(state, 'pending_review'), Icons.rate_review_outlined, Colors.orange),
    _stat('Missing', _count(state, 'missing_requirements'), Icons.warning_amber_outlined, AppColors.warning),
    _stat('Files', _count(state, 'submitted_files'), Icons.folder_copy_outlined, Colors.blue),
    _stat('Archive Files', _count(state, 'archive_files'), Icons.inventory_2_outlined, AppColors.gold),
  ];

  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((widget) {
            final calculatedWidth = (constraints.maxWidth - 12) / 2;
            final itemWidth = calculatedWidth.clamp(0.0, double.infinity);
            return SizedBox(
              width: itemWidth > 180 ? itemWidth : double.infinity,
              child: widget,
            );
          }).toList(),
        );
      }
      return Row(
        children: List.generate(items.length, (index) {
          final isFirst = index == 0;
          final isLast = index == items.length - 1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: isFirst ? 0 : 8,
                right: isLast ? 0 : 8,
              ),
              child: items[index],
            ),
          );
        }),
      );
    },
  );
}

class DeliverablesFilterBar extends ConsumerStatefulWidget {
  final CapstoneDeliverablesState state;
  final TextEditingController searchController;
  final bool isAdviser;

  const DeliverablesFilterBar({
    super.key,
    required this.state,
    required this.searchController,
    required this.isAdviser,
  });

  @override
  ConsumerState<DeliverablesFilterBar> createState() => _DeliverablesFilterBarState();
}

class _DeliverablesFilterBarState extends ConsumerState<DeliverablesFilterBar> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  InputDecoration _toolbarInputDec({required String label, IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
    );
  }

  List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> stageOptions = _uniqueStrings(widget.state.stageOptions);
    final selectedStage = stageOptions.contains(widget.state.selectedStage)
        ? widget.state.selectedStage
        : null;
    final List<Map<String, dynamic>> statuses = widget.state.statuses.isEmpty
        ? const <Map<String, dynamic>>[
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
          ]
        : widget.state.statuses;

    final searchField = TextField(
      controller: widget.searchController,
      decoration: _toolbarInputDec(
        label: widget.isAdviser ? 'Search team, project' : 'Search team, project, adviser',
        prefixIcon: Icons.search,
      ),
      style: const TextStyle(
        fontSize: 13,
      ),
      onChanged: (value) {
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          ref
              .read(capstoneDeliverablesProvider.notifier)
              .fetchDeliverables(search: value);
        });
      },
      onSubmitted: (value) {
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: value);
      },
    );

    final stageDropdown = DropdownButtonFormField<String>(
      initialValue: selectedStage,
      isExpanded: true,
      decoration: _toolbarInputDec(
        label: widget.state.scope == 'pit' ? 'PIT Event' : 'Stage View',
      ),
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      hint: Text(
        stageOptions.isEmpty
            ? (widget.state.scope == 'pit' ? 'No events configured' : 'No stages configured')
            : 'Select stage',
        style: const TextStyle(fontSize: 13),
      ),
      items: stageOptions
          .map(
            (stage) => DropdownMenuItem(
              value: stage,
              child: Text(
                stage,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: stageOptions.isEmpty
          ? null
          : (value) => ref
                .read(capstoneDeliverablesProvider.notifier)
                .fetchDeliverables(
                  selectedStage: value ?? selectedStage ?? '',
                ),
    );

    final statusDropdown = DropdownButtonFormField<String>(
      initialValue: widget.state.status,
      decoration: _toolbarInputDec(label: 'Status'),
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      isExpanded: true,
      items: statuses
          .map(
            (item) => DropdownMenuItem(
              value: item['value']?.toString() ?? '',
              child: Text(
                item['label']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (value) => ref
          .read(capstoneDeliverablesProvider.notifier)
          .fetchDeliverables(status: value ?? ''),
    );

    final clearButton = OutlinedButton.icon(
      onPressed: () {
        widget.searchController.clear();
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: '', status: '');
      },
      icon: const Icon(Icons.clear_all_rounded, size: 18),
      label: const Text(
        'Clear Filters',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF64748B),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                stageDropdown,
                const SizedBox(height: 12),
                statusDropdown,
                const SizedBox(height: 12),
                clearButton,
              ],
            );
          } else if (constraints.maxWidth < 900) {
            final calculatedWidth = (constraints.maxWidth - 48) / 2;
            final dropdownWidth = calculatedWidth.clamp(0.0, double.infinity);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: double.infinity, child: searchField),
                SizedBox(width: dropdownWidth, child: stageDropdown),
                SizedBox(width: dropdownWidth, child: statusDropdown),
                SizedBox(width: double.infinity, child: clearButton),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: stageDropdown),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: statusDropdown),
              const SizedBox(width: 16),
              clearButton,
            ],
          );
        },
      ),
    );
  }
}
