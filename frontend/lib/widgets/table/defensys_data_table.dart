import 'package:flutter/material.dart';
import '../../widgets/feedback/empty_state.dart';
import 'defensys_table_column.dart';
import 'defensys_table_tokens.dart';

/// Centralized, responsive, anti-slop data table component for DefenSYS.
///
/// Features:
/// - Proportional `flex` column scaling on wide displays.
/// - Deterministic `minWidth` horizontal scrolling on compact displays.
/// - Optional sticky right-hand action column pinned during horizontal scrolling.
/// - Subtle row hover effects and clean divider lines.
/// - Built-in skeleton loading and empty state presentation.
class DefensysDataTable<T> extends StatefulWidget {
  final List<T> items;
  final List<DefensysTableColumn<T>> columns;
  final DefensysActionColumn<T>? stickyActionColumn;
  final bool isLoading;
  final int skeletonRowCount;
  final Widget? emptyState;
  final double rowMinHeight;
  final double headerHeight;
  final ValueChanged<T>? onRowTap;
  final ScrollController? horizontalScrollController;
  final ValueChanged<bool>? onScrollHintChanged;

  const DefensysDataTable({
    super.key,
    required this.items,
    required this.columns,
    this.stickyActionColumn,
    this.isLoading = false,
    this.skeletonRowCount = 5,
    this.emptyState,
    this.rowMinHeight = DefensysTableTokens.rowHeightMultiline,
    this.headerHeight = DefensysTableTokens.headerHeight,
    this.onRowTap,
    this.horizontalScrollController,
    this.onScrollHintChanged,
  });

  @override
  State<DefensysDataTable<T>> createState() => _DefensysDataTableState<T>();
}

class _DefensysDataTableState<T> extends State<DefensysDataTable<T>> {
  late ScrollController _scrollController;
  bool _ownsScrollController = false;
  bool _hasScrollOverflow = false;

  double get _totalDataMinWidth => widget.columns.fold(
        0.0,
        (sum, col) => sum + col.minWidth,
      );

  double get _actionColumnWidth => widget.stickyActionColumn?.width ?? 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.horizontalScrollController != null) {
      _scrollController = widget.horizontalScrollController!;
      _ownsScrollController = false;
    } else {
      _scrollController = ScrollController();
      _ownsScrollController = true;
    }
    _scrollController.addListener(_checkScrollHint);
  }

  @override
  void didUpdateWidget(DefensysDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.horizontalScrollController != oldWidget.horizontalScrollController) {
      if (_ownsScrollController) {
        _scrollController.removeListener(_checkScrollHint);
        _scrollController.dispose();
      }
      if (widget.horizontalScrollController != null) {
        _scrollController = widget.horizontalScrollController!;
        _ownsScrollController = false;
      } else {
        _scrollController = ScrollController();
        _ownsScrollController = true;
      }
      _scrollController.addListener(_checkScrollHint);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkScrollHint);
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _checkScrollHint() {
    if (!_scrollController.hasClients) return;
    final canScroll = _scrollController.position.maxScrollExtent > 4;
    if (canScroll != _hasScrollOverflow) {
      setState(() => _hasScrollOverflow = canScroll);
      widget.onScrollHintChanged?.call(canScroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return _buildSkeletonLoader();
    }

    if (widget.items.isEmpty) {
      return widget.emptyState ??
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: DefensysEmptyState(
              icon: Icons.table_rows_outlined,
              title: 'No records found',
              description: 'There are no items to display matching the current criteria.',
            ),
          );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableDataWidth =
            (constraints.maxWidth - _actionColumnWidth).clamp(0.0, double.infinity);
        final needsHorizontalScroll = availableDataWidth < _totalDataMinWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkScrollHint();
        });

        Widget dataPane = _buildDataColumnPane(useFlexibleColumns: !needsHorizontalScroll);

        if (needsHorizontalScroll) {
          dataPane = Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _totalDataMinWidth,
                child: dataPane,
              ),
            ),
          );
        }

        if (widget.stickyActionColumn == null) {
          return dataPane;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dataPane),
            _buildActionPane(),
          ],
        );
      },
    );
  }

  Widget _buildDataColumnPane({required bool useFlexibleColumns}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderRow(useFlexibleColumns: useFlexibleColumns),
        ...List.generate(widget.items.length, (index) {
          final item = widget.items[index];
          return _TableRowWidget(
            key: ValueKey('defensys_row_$index'),
            minHeight: widget.rowMinHeight,
            onTap: widget.onRowTap != null ? () => widget.onRowTap!(item) : null,
            child: useFlexibleColumns
                ? Row(
                    children: widget.columns.map((col) {
                      return Expanded(
                        flex: (col.flex * 100).round(),
                        child: Container(
                          padding: col.padding,
                          alignment: col.alignment,
                          child: col.cellBuilder(context, item, index),
                        ),
                      );
                    }).toList(),
                  )
                : Row(
                    children: widget.columns.map((col) {
                      return SizedBox(
                        width: col.minWidth,
                        child: Container(
                          padding: col.padding,
                          alignment: col.alignment,
                          child: col.cellBuilder(context, item, index),
                        ),
                      );
                    }).toList(),
                  ),
          );
        }),
      ],
    );
  }

  Widget _buildHeaderRow({required bool useFlexibleColumns}) {
    return Container(
      height: widget.headerHeight,
      decoration: BoxDecoration(
        color: DefensysTableTokens.headerBackgroundOf(context),
        border: Border(
          bottom: BorderSide(color: DefensysTableTokens.headerBorderOf(context)),
        ),
      ),
      child: useFlexibleColumns
          ? Row(
              children: widget.columns.map((col) {
                return Expanded(
                  flex: (col.flex * 100).round(),
                  child: _buildHeaderCell(col),
                );
              }).toList(),
            )
          : Row(
              children: widget.columns.map((col) {
                return SizedBox(
                  width: col.minWidth,
                  child: _buildHeaderCell(col),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildHeaderCell(DefensysTableColumn<T> col) {
    if (col.headerBuilder != null) {
      return col.headerBuilder!(context);
    }

    final isDark = DefensysTableTokens.isDark(context);

    Widget content = Container(
      padding: col.headerPadding,
      alignment: col.alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              col.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DefensysTableTokens.headerTextStyleOf(context),
            ),
          ),
          if (col.isSortable) ...[
            const SizedBox(width: 4),
            Icon(
              col.sortAscending == true
                  ? Icons.arrow_upward_rounded
                  : (col.sortAscending == false
                      ? Icons.arrow_downward_rounded
                      : Icons.unfold_more_rounded),
              size: 13,
              color: col.sortAscending != null
                  ? (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF1E293B))
                  : (isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8)),
            ),
          ],
        ],
      ),
    );

    if (col.isSortable && col.onSort != null) {
      return InkWell(
        onTap: col.onSort,
        child: content,
      );
    }

    return content;
  }

  Widget _buildActionPane() {
    final actionCol = widget.stickyActionColumn!;
    return Container(
      width: actionCol.width,
      decoration: BoxDecoration(
        color: DefensysTableTokens.cardBackgroundOf(context),
        border: Border(
          left: BorderSide(color: DefensysTableTokens.headerBorderOf(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action Header Cell
          Container(
            height: widget.headerHeight,
            alignment: actionCol.alignment,
            decoration: BoxDecoration(
              color: DefensysTableTokens.headerBackgroundOf(context),
              border: Border(
                bottom: BorderSide(color: DefensysTableTokens.headerBorderOf(context)),
              ),
            ),
            child: actionCol.headerBuilder != null
                ? actionCol.headerBuilder!(context)
                : Text(
                    actionCol.title,
                    style: DefensysTableTokens.headerTextStyleOf(context),
                  ),
          ),
          // Action Row Cells
          ...List.generate(widget.items.length, (index) {
            final item = widget.items[index];
            return Container(
              constraints: BoxConstraints(minHeight: widget.rowMinHeight),
              alignment: actionCol.alignment,
              decoration: BoxDecoration(
                color: DefensysTableTokens.cardBackgroundOf(context),
                border: Border(
                  bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context)),
                ),
              ),
              child: actionCol.builder(context, item, index),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    final isDark = DefensysTableTokens.isDark(context);
    final blockColor = isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9);
    final blockSubColor = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF8FAFC);

    return Column(
      children: [
        Container(
          height: widget.headerHeight,
          decoration: BoxDecoration(
            color: DefensysTableTokens.headerBackgroundOf(context),
            border: Border(
              bottom: BorderSide(color: DefensysTableTokens.headerBorderOf(context)),
            ),
          ),
        ),
        ...List.generate(widget.skeletonRowCount, (i) {
          return Container(
            height: widget.rowMinHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 180,
                        decoration: BoxDecoration(
                          color: blockColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 10,
                        width: 100,
                        decoration: BoxDecoration(
                          color: blockSubColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 22,
                  width: 68,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TableRowWidget extends StatefulWidget {
  final Widget child;
  final double minHeight;
  final VoidCallback? onTap;

  const _TableRowWidget({
    super.key,
    required this.child,
    required this.minHeight,
    this.onTap,
  });

  @override
  State<_TableRowWidget> createState() => _TableRowWidgetState();
}

class _TableRowWidgetState extends State<_TableRowWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: _isHovered
            ? DefensysTableTokens.rowHoverOf(context)
            : DefensysTableTokens.cardBackgroundOf(context),
        child: InkWell(
          onTap: widget.onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context)),
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
