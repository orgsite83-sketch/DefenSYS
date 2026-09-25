import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_table_tokens.dart';

/// Outer card shell providing the standardized command bar, dividers,
/// scroll hint indicator, and pagination footer for DefenSYS tables.
class DefensysTableCard extends StatelessWidget {
  /// The main table child widget (typically [DefensysDataTable]).
  final Widget child;

  /// Optional search field controller.
  final TextEditingController? searchController;

  /// Placeholder text for the search input.
  final String searchHint;

  /// Callback when the search input value is submitted or changed.
  final ValueChanged<String>? onSearchSubmitted;

  /// Callback when the clear search button is clicked.
  final VoidCallback? onSearchCleared;

  /// Filter widgets (such as [DefensysSegmentedControl] or dropdowns) placed next to search.
  final List<Widget> filterControls;

  /// Trailing action buttons on the top right (e.g., Export, Refresh, Add).
  final List<Widget> headerActions;

  /// Whether the search field is currently enabled.
  final bool isSearchEnabled;

  /// Whether to display the horizontal scroll hint banner at the bottom.
  final bool showScrollHint;

  /// Optional pagination widget placed at the card bottom.
  final Widget? pagination;

  /// Inner padding for the filter command bar.
  final EdgeInsetsGeometry toolbarPadding;

  const DefensysTableCard({
    super.key,
    required this.child,
    this.searchController,
    this.searchHint = 'Search...',
    this.onSearchSubmitted,
    this.onSearchCleared,
    this.filterControls = const [],
    this.headerActions = const [],
    this.isSearchEnabled = true,
    this.showScrollHint = false,
    this.pagination,
    this.toolbarPadding = DefensysTableTokens.cardPadding,
  });

  @override
  Widget build(BuildContext context) {
    final hasToolbar = searchController != null ||
        filterControls.isNotEmpty ||
        headerActions.isNotEmpty;

    return Container(
      decoration: DefensysTableTokens.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Command Bar
          if (hasToolbar) ...[
            Padding(
              padding: toolbarPadding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 720;

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (searchController != null) _buildSearchField(context),
                        if (filterControls.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: filterControls
                                  .map((f) => Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: f,
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                        if (headerActions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: headerActions
                                .map((a) => Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: a,
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      if (searchController != null)
                        Expanded(flex: 3, child: _buildSearchField(context)),
                      if (filterControls.isNotEmpty) ...[
                        if (searchController != null) const SizedBox(width: 14),
                        ...filterControls.map((f) => Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: f,
                            )),
                      ],
                      if (headerActions.isNotEmpty) ...[
                        const Spacer(),
                        ...headerActions.map((a) => Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: a,
                            )),
                      ],
                    ],
                  );
                },
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: DefensysTableTokens.rowBorderOf(context),
            ),
          ],

          // Table Body
          child,

          // Horizontal Scroll Hint
          if (showScrollHint) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: DefensysTableTokens.rowBorderOf(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: const [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Scroll horizontally to view all table columns',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamily,
                      color: Color(0xFF94A3B8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Pagination Footer
          if (pagination != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: DefensysTableTokens.rowBorderOf(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: pagination!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = DefensysTableTokens.isDark(context);
    return SizedBox(
      height: DefensysTableTokens.controlHeight,
      child: TextField(
        controller: searchController,
        enabled: isSearchEnabled,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          fontSize: 13,
          color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
            size: 18,
          ),
          suffixIcon: (searchController?.text.isNotEmpty ?? false)
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF94A3B8),
                  ),
                  onPressed: () {
                    searchController?.clear();
                    onSearchCleared?.call();
                    onSearchSubmitted?.call('');
                  },
                )
              : null,
          hintText: searchHint,
          hintStyle: TextStyle(
            fontFamily: DefensysTokens.fontFamily,
            color: isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
            fontSize: 13,
          ),
          filled: true,
          fillColor: DefensysTableTokens.searchFieldBackgroundOf(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: DefensysTableTokens.cardBorderOf(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: DefensysTableTokens.cardBorderOf(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon,
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: onSearchSubmitted,
      ),
    );
  }
}
