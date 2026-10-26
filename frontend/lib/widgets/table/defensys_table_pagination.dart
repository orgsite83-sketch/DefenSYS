import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_table_tokens.dart';

/// Standardized pagination footer bar for [DefensysDataTable].
class DefensysTablePagination extends StatelessWidget {
  /// Zero-indexed current page.
  final int currentPage;

  /// Total count of all items across all pages.
  final int totalItems;

  /// Current number of rows displayed per page.
  final int rowsPerPage;

  /// Selectable options for rows per page.
  final List<int> rowsPerPageOptions;

  /// Callback when page changes (0-indexed).
  final ValueChanged<int> onPageChanged;

  /// Callback when rows per page changes.
  final ValueChanged<int> onRowsPerPageChanged;

  /// Noun label describing items (e.g., 'items', 'rubrics', 'students').
  final String itemLabel;

  const DefensysTablePagination({
    super.key,
    required this.currentPage,
    required this.totalItems,
    required this.rowsPerPage,
    this.rowsPerPageOptions = const [10, 25, 50, 100],
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    this.itemLabel = 'items',
  });

  @override
  Widget build(BuildContext context) {
    final totalPages = totalItems == 0 ? 1 : (totalItems / rowsPerPage).ceil();
    final safePage = currentPage.clamp(0, totalPages - 1);
    final start = totalItems == 0 ? 0 : safePage * rowsPerPage + 1;
    final end = totalItems == 0
        ? 0
        : (safePage * rowsPerPage + rowsPerPage).clamp(0, totalItems);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;

        final infoText = Text(
          'Showing $start–$end of $totalItems $itemLabel',
          style: DefensysTableTokens.paginationTextStyle.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        );

        final rowsPicker = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rows per page',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                color: DefensysTokens.textSecondaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: DefensysTokens.borderOf(context)),
                borderRadius: BorderRadius.circular(6),
                color: DefensysTokens.surfaceHigherOf(context),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: rowsPerPageOptions.contains(rowsPerPage)
                      ? rowsPerPage
                      : rowsPerPageOptions.first,
                  isDense: true,
                  dropdownColor: DefensysTokens.surfaceOf(context),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: DefensysTokens.textPrimaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  items: rowsPerPageOptions.map((n) {
                    return DropdownMenuItem<int>(value: n, child: Text('$n'));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onRowsPerPageChanged(value);
                    }
                  },
                ),
              ),
            ),
          ],
        );

        final pageNav = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PageNavButton(
              icon: Icons.chevron_left_rounded,
              enabled: safePage > 0,
              onTap: () => onPageChanged(safePage - 1),
            ),
            const SizedBox(width: 6),
            if (totalPages <= 7)
              ...List.generate(totalPages, (index) {
                final isCurrent = safePage == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _PageNumberButton(
                    pageNumber: index + 1,
                    isSelected: isCurrent,
                    onTap: () => onPageChanged(index),
                  ),
                );
              })
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Page ${safePage + 1} of $totalPages',
                  style: DefensysTableTokens.paginationTextStyle.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
            _PageNavButton(
              icon: Icons.chevron_right_rounded,
              enabled: safePage < totalPages - 1,
              onTap: () => onPageChanged(safePage + 1),
            ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [infoText, rowsPicker],
              ),
              const SizedBox(height: 12),
              Center(child: pageNav),
            ],
          );
        }

        return Row(
          children: [
            infoText,
            const SizedBox(width: 16),
            rowsPicker,
            const Spacer(),
            pageNav,
          ],
        );
      },
    );
  }
}

class _PageNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: DefensysTokens.textPrimaryOf(context),
          disabledForegroundColor: DefensysTokens.textSecondaryOf(
            context,
          ).withValues(alpha: .4),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          backgroundColor: DefensysTokens.surfaceOf(context),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  final int pageNumber;
  final bool isSelected;
  final VoidCallback onTap;

  const _PageNumberButton({
    required this.pageNumber,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: isSelected
              ? DefensysTokens.maroonOf(context)
              : DefensysTokens.surfaceOf(context),
          foregroundColor: isSelected
              ? Colors.white
              : DefensysTokens.textPrimaryOf(context),
          side: BorderSide(
            color: isSelected
                ? DefensysTokens.maroonOf(context)
                : DefensysTokens.borderOf(context),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          '$pageNumber',
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamily,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
