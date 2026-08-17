import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Item representation for rich entity displays
class EntityPickerItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? badge;
  final String? avatarText;
  final Color? avatarColor;
  final IconData? icon;
  final Map<String, dynamic>? meta;

  const EntityPickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
    this.avatarText,
    this.avatarColor,
    this.icon,
    this.meta,
  });
}

/// A modern, searchable dropdown/entity picker for DefenSYS.
/// Handles high cardinality lists (hundreds of students/teams) with
/// live instant filtering, avatar initials, rich tags, and keyboard accessibility.
class SearchableEntityPicker<T> extends StatefulWidget {
  final List<EntityPickerItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T?>? onChanged;
  final String hintText;
  final String searchHintText;
  final bool enabled;
  final bool isRequired;
  final double maxHeight;
  final bool Function(EntityPickerItem<T> item, String query)? searchMatcher;
  final Widget Function(BuildContext context, EntityPickerItem<T> item, bool isSelected)? itemBuilder;

  const SearchableEntityPicker({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.hintText = 'Select candidate...',
    this.searchHintText = 'Type name, ID, team, or section to search...',
    this.enabled = true,
    this.isRequired = false,
    this.maxHeight = 320,
    this.searchMatcher,
    this.itemBuilder,
  });

  @override
  State<SearchableEntityPicker<T>> createState() => _SearchableEntityPickerState<T>();
}

class _SearchableEntityPickerState<T> extends State<SearchableEntityPicker<T>> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SearchableEntityPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isOpen && _overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _closeDropdown();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && !_searchFocusNode.hasFocus) {
      // Defer closing slightly in case user clicked inside overlay
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focusNode.hasFocus && !_searchFocusNode.hasFocus) {
          _closeDropdown();
        }
      });
    }
  }

  void _toggleDropdown() {
    if (!widget.enabled) return;
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_isOpen || !widget.enabled) return;
    _searchQuery = '';
    _searchController.clear();

    final overlay = Overlay.of(context);
    _overlayEntry = _createOverlayEntry();
    overlay.insert(_overlayEntry!);

    setState(() {
      _isOpen = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeDropdown() {
    if (!_isOpen) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _isOpen = false;
      });
    }
  }

  EntityPickerItem<T>? get _selectedItem {
    if (widget.selectedValue == null) return null;
    try {
      return widget.items.firstWhere((item) => item.value == widget.selectedValue);
    } catch (_) {
      return null;
    }
  }

  List<EntityPickerItem<T>> _filterItems() {
    if (_searchQuery.trim().isEmpty) {
      return widget.items;
    }
    final q = _searchQuery.trim().toLowerCase();
    return widget.items.where((item) {
      if (widget.searchMatcher != null) {
        return widget.searchMatcher!(item, q);
      }
      final labelMatch = item.label.toLowerCase().contains(q);
      final subtitleMatch = item.subtitle?.toLowerCase().contains(q) ?? false;
      final badgeMatch = item.badge?.toLowerCase().contains(q) ?? false;
      return labelMatch || subtitleMatch || badgeMatch;
    }).toList();
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(300, 48);

    return OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Click outside detector
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeDropdown,
              ),
            ),
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0.0, size.height + 6.0),
                child: Material(
                  elevation: 10,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                      border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.25), width: 1.2),
                    ),
                    child: StatefulBuilder(
                      builder: (context, setOverlayState) {
                        final filteredList = _filterItems();

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Search bar header
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(DefensysTokens.radiusLg - 1),
                                  topRight: Radius.circular(DefensysTokens.radiusLg - 1),
                                ),
                                border: Border(bottom: BorderSide(color: DefensysTokens.border)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search_rounded, size: 18, color: DefensysTokens.maroon),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      style: const TextStyle(fontSize: 13, color: DefensysTokens.textDark),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                        hintText: widget.searchHintText,
                                        hintStyle: const TextStyle(
                                          fontSize: 12.5,
                                          color: DefensysTokens.steelGrey,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (val) {
                                        setOverlayState(() {
                                          _searchQuery = val;
                                        });
                                      },
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16, color: DefensysTokens.steelGrey),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setOverlayState(() {
                                          _searchController.clear();
                                          _searchQuery = '';
                                        });
                                      },
                                    ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                                      border: Border.all(color: DefensysTokens.border),
                                    ),
                                    child: Text(
                                      '${filteredList.length} ${filteredList.length == 1 ? 'item' : 'items'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: DefensysTokens.steelGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Items List
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: widget.maxHeight),
                              child: filteredList.isEmpty
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_search_outlined,
                                            size: 32,
                                            color: DefensysTokens.steelGrey.withValues(alpha: 0.5),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'No matching records found',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: DefensysTokens.steelGrey.withValues(alpha: 0.9),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Try searching by Student ID, name, or team',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: DefensysTokens.steelGrey.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      itemCount: filteredList.length,
                                      separatorBuilder: (_, __) => const Divider(
                                        height: 1,
                                        color: Color(0xFFF1F5F9),
                                      ),
                                      itemBuilder: (context, idx) {
                                        final item = filteredList[idx];
                                        final isSelected = item.value == widget.selectedValue;

                                        if (widget.itemBuilder != null) {
                                          return widget.itemBuilder!(context, item, isSelected);
                                        }

                                        return InkWell(
                                          onTap: () {
                                            widget.onChanged?.call(item.value);
                                            _closeDropdown();
                                          },
                                          child: Container(
                                            color: isSelected
                                                ? DefensysTokens.maroon.withValues(alpha: 0.06)
                                                : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            child: Row(
                                              children: [
                                                // Left Selection Indicator Bar
                                                Container(
                                                  width: 3,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: isSelected ? DefensysTokens.maroon : Colors.transparent,
                                                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // Avatar / Initials / Icon
                                                _buildAvatar(item, isSelected),
                                                const SizedBox(width: 12),

                                                // Title & Subtitle
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              item.label,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                                                color: isSelected ? DefensysTokens.maroon : DefensysTokens.textDark,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                          if (item.badge != null) ...[
                                                            const SizedBox(width: 8),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: isSelected
                                                                    ? DefensysTokens.maroon.withValues(alpha: 0.12)
                                                                    : const Color(0xFFF1F5F9),
                                                                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                                border: Border.all(
                                                                  color: isSelected
                                                                      ? DefensysTokens.maroon.withValues(alpha: 0.25)
                                                                      : const Color(0xFFE2E8F0),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                item.badge!,
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.w700,
                                                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      if (item.subtitle != null) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          item.subtitle!,
                                                          style: const TextStyle(
                                                            fontSize: 11.5,
                                                            color: DefensysTokens.steelGrey,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),

                                                if (isSelected)
                                                  const Padding(
                                                    padding: EdgeInsets.only(left: 8),
                                                    child: Icon(
                                                      Icons.check_circle_rounded,
                                                      size: 18,
                                                      color: DefensysTokens.maroon,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatar(EntityPickerItem<T> item, bool isSelected) {
    if (item.icon != null) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? DefensysTokens.maroon : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
        child: Icon(
          item.icon,
          size: 16,
          color: isSelected ? Colors.white : DefensysTokens.steelGrey,
        ),
      );
    }

    final initials = item.avatarText ?? (item.label.isNotEmpty ? item.label.substring(0, 1).toUpperCase() : '?');
    final color = item.avatarColor ?? (isSelected ? DefensysTokens.maroon : const Color(0xFF64748B));

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(
          color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedItem;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        focusNode: _focusNode,
        child: InkWell(
          onTap: widget.enabled ? _toggleDropdown : null,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              border: Border.all(
                color: _isOpen
                    ? DefensysTokens.maroon
                    : (selected != null ? const Color(0xFFCBD5E1) : DefensysTokens.border),
                width: _isOpen ? 1.5 : 1.0,
              ),
              boxShadow: _isOpen
                  ? [
                      BoxShadow(
                        color: DefensysTokens.maroon.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                if (selected != null) ...[
                  _buildAvatar(selected, true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                selected.label,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: DefensysTokens.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selected.badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                ),
                                child: Text(
                                  selected.badge!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: DefensysTokens.maroon,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (selected.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            selected.subtitle!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: DefensysTokens.steelGrey,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.search_rounded, size: 18, color: DefensysTokens.steelGrey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.hintText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DefensysTokens.steelGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (selected != null && widget.enabled)
                  InkWell(
                    onTap: () => widget.onChanged?.call(null),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE2E8F0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: DefensysTokens.steelGrey),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: _isOpen ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
