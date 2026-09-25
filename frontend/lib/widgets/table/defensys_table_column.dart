import 'package:flutter/material.dart';
import 'defensys_table_tokens.dart';

/// Declarative specification for a column in a [DefensysDataTable].
class DefensysTableColumn<T> {
  /// The uppercase column label displayed in the table header.
  final String title;

  /// Proportional flex factor when the table fits comfortably without horizontal scrolling.
  final double flex;

  /// Guaranteed minimum pixel width for this column when scrolling horizontally.
  final double minWidth;

  /// Alignment of both the header and row cells for this column.
  final Alignment alignment;

  /// Padding applied to each row cell in this column.
  final EdgeInsetsGeometry padding;

  /// Padding applied to the header cell in this column.
  final EdgeInsetsGeometry headerPadding;

  /// Builder for rendering each item's cell widget.
  final Widget Function(BuildContext context, T item, int index) cellBuilder;

  /// Optional custom widget builder for the column header.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Whether this column header indicates sortability.
  final bool isSortable;

  /// Callback when the column header is clicked to toggle sorting.
  final VoidCallback? onSort;

  /// Current sorting direction: `true` for ascending, `false` for descending, or `null` if unsorted.
  final bool? sortAscending;

  const DefensysTableColumn({
    required this.title,
    this.flex = 1.0,
    required this.minWidth,
    this.alignment = Alignment.centerLeft,
    this.padding = DefensysTableTokens.cellPaddingStandard,
    this.headerPadding = DefensysTableTokens.headerPaddingStandard,
    required this.cellBuilder,
    this.headerBuilder,
    this.isSortable = false,
    this.onSort,
    this.sortAscending,
  });
}

/// Dedicated sticky action column pinned to the right edge of a [DefensysDataTable].
class DefensysActionColumn<T> {
  /// Fixed pixel width of the sticky action column (defaults to 80.0 px).
  final double width;

  /// Header title for the action column (defaults to 'ACTION').
  final String title;

  /// Alignment of the action button inside the cell.
  final Alignment alignment;

  /// Builder for the action button/menu on each row.
  final Widget Function(BuildContext context, T item, int index) builder;

  /// Optional custom header builder for the action column.
  final Widget Function(BuildContext context)? headerBuilder;

  const DefensysActionColumn({
    this.width = DefensysTableTokens.actionColumnWidth,
    this.title = 'ACTION',
    this.alignment = Alignment.center,
    required this.builder,
    this.headerBuilder,
  });
}
