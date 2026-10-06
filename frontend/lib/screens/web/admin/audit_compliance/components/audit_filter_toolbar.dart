import 'package:flutter/material.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditFilterToolbar extends StatelessWidget {
  final SystemAuditState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onActionChanged;
  final VoidCallback onSelectDateRange;
  final VoidCallback onOpenMoreFilters;

  const AuditFilterToolbar({
    super.key,
    required this.state,
    required this.searchController,
    required this.onSearchSubmitted,
    required this.onCategoryChanged,
    required this.onActionChanged,
    required this.onSelectDateRange,
    required this.onOpenMoreFilters,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);

    final categories = (state.options['categories'] as List<dynamic>? ?? [])
        .map((c) => c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{})
        .toList();

    final actions = (state.options['actions'] as List<dynamic>? ?? [])
        .map((a) => a.toString())
        .toList();

    final hasDateFilter = state.startDate.isNotEmpty || state.endDate.isNotEmpty;
    final hasScopeFilter = state.track.isNotEmpty || state.yearLevel.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;

        final searchInput = Container(
          height: 40,
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search audit logs (e.g. rubric, user, action, project...)',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onSubmitted: onSearchSubmitted,
                ),
              ),
              if (searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  onPressed: () {
                    searchController.clear();
                    onSearchSubmitted('');
                  },
                ),
            ],
          ),
        );

        final filterControls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Process Area / Category Dropdown
            _buildDropdown(
              context,
              value: state.category.isEmpty ? '' : state.category,
              items: [
                const DropdownMenuItem(value: '', child: Text('All Process Areas')),
                ...categories.map((c) {
                  final val = c['value']?.toString() ?? '';
                  final lbl = c['label']?.toString() ?? val;
                  return DropdownMenuItem(value: val, child: Text(lbl));
                }),
              ],
              onChanged: (val) => onCategoryChanged(val ?? ''),
            ),

            // Action Dropdown
            _buildDropdown(
              context,
              value: state.action.isEmpty ? '' : state.action,
              items: [
                const DropdownMenuItem(value: '', child: Text('All Actions')),
                ...actions.map((act) => DropdownMenuItem(
                      value: act,
                      child: Text(act),
                    )),
              ],
              onChanged: (val) => onActionChanged(val ?? ''),
            ),

            // Date Range Button
            _buildButton(
              context,
              icon: Icons.calendar_today_outlined,
              label: hasDateFilter ? '${state.startDate} – ${state.endDate}' : 'Date Range',
              isActive: hasDateFilter,
              onTap: onSelectDateRange,
            ),

            // More Filters Button
            _buildButton(
              context,
              icon: Icons.tune_rounded,
              label: 'More Filters',
              isActive: hasScopeFilter,
              badgeText: hasScopeFilter ? 'Active' : null,
              onTap: onOpenMoreFilters,
            ),
          ],
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: searchInput),
              const SizedBox(width: 12),
              filterControls,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchInput,
            const SizedBox(height: 10),
            filterControls,
          ],
        );
      },
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: DefensysTokens.textPrimaryOf(context),
          ),
          dropdownColor: DefensysTokens.surfaceOf(context),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    String? badgeText,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? const Color(0x26800000) : const Color(0xFFFDF2F2))
              : DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          border: Border.all(
            color: isActive ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive
                  ? DefensysTokens.maroonOf(context)
                  : (isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? DefensysTokens.maroonOf(context)
                    : DefensysTokens.textPrimaryOf(context),
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
