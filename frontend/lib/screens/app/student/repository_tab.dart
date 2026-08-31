import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/repository_provider.dart';
import '../../../services/repository_review_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../widgets/book_cover_widget.dart';
import '../../../services/auth_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../utils/pdf_viewer.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class VaultEntry {
  final String id;
  final String fileName;
  final String? fileUrl;
  final String teamName;
  final String uploadedBy;
  final String academicYear;
  final String status;
  final String timestamp;
  final String yearLevel;
  final String stage;
  final String type; // 'pit', 'capstone', 'uploader'
  final String? deliverableLabel;
  final String extractedText;
  final List<String> topics;
  final String summary;
  final String category;
  final double averageRating;
  final int ratingsCount;
  final int reviewsCount;
  final int? userRating;
  final String? userRemark;
  final String? shelfStatus;
  final int lastReadPage;
  final int totalPages;
  final double readingProgress;

  const VaultEntry({
    required this.id,
    required this.fileName,
    this.fileUrl,
    required this.teamName,
    required this.uploadedBy,
    required this.academicYear,
    required this.status,
    required this.timestamp,
    required this.yearLevel,
    required this.stage,
    required this.type,
    this.deliverableLabel,
    this.extractedText = '',
    this.topics = const [],
    this.summary = '',
    this.category = '',
    this.averageRating = 0.0,
    this.ratingsCount = 0,
    this.reviewsCount = 0,
    this.userRating,
    this.userRemark,
    this.shelfStatus,
    this.lastReadPage = 1,
    this.totalPages = 1,
    this.readingProgress = 0.0,
  });

  factory VaultEntry.fromJson(Map<String, dynamic> j) {
    return VaultEntry(
      id: j['id']?.toString() ?? '',
      fileName: (j['file_name'] ?? j['fileName'])?.toString() ?? '',
      fileUrl: j['file_url']?.toString(),
      teamName: (j['team_name'] ?? j['teamName'])?.toString() ?? '—',
      uploadedBy: (j['uploaded_by'] ?? j['uploadedBy'])?.toString() ?? '—',
      academicYear: (j['academic_year'] ?? j['academicYear'])?.toString() ?? '—',
      status: j['status']?.toString() ?? 'Approved',
      timestamp: (j['uploaded_at'] ?? j['timestamp'])?.toString() ?? '',
      yearLevel: (j['year_level'] ?? j['yearLevel'])?.toString() ?? '—',
      stage: j['stage']?.toString() ?? '—',
      type: j['type']?.toString() ?? 'pit',
      deliverableLabel: (j['deliverable_label'] ?? j['deliverableLabel'])?.toString(),
      extractedText: j['extracted_text']?.toString() ?? '',
      topics: (j['topics'] as List?)?.map((e) => e.toString()).toList() ?? [],
      summary: j['summary']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      averageRating: (j['average_rating'] is num)
          ? (j['average_rating'] as num).toDouble()
          : double.tryParse(j['average_rating']?.toString() ?? '0.0') ?? 0.0,
      ratingsCount: j['ratings_count'] is int
          ? j['ratings_count']
          : int.tryParse(j['ratings_count']?.toString() ?? '0') ?? 0,
      reviewsCount: j['reviews_count'] is int
          ? j['reviews_count']
          : int.tryParse(j['reviews_count']?.toString() ?? '0') ?? 0,
      userRating: j['user_rating'] is int
          ? j['user_rating']
          : int.tryParse(j['user_rating']?.toString() ?? ''),
      userRemark: j['user_remark']?.toString(),
      shelfStatus: j['shelf_status']?.toString(),
      lastReadPage: j['last_read_page'] is int
          ? j['last_read_page']
          : int.tryParse(j['last_read_page']?.toString() ?? '1') ?? 1,
      totalPages: j['total_pages'] is int
          ? j['total_pages']
          : int.tryParse(j['total_pages']?.toString() ?? '1') ?? 1,
      readingProgress: (j['reading_progress'] is num)
          ? (j['reading_progress'] as num).toDouble()
          : double.tryParse(j['reading_progress']?.toString() ?? '0.0') ?? 0.0,
    );
  }

  VaultEntry copyWith({
    double? averageRating,
    int? ratingsCount,
    int? reviewsCount,
    int? userRating,
    String? userRemark,
    String? shelfStatus,
    int? lastReadPage,
    int? totalPages,
    double? readingProgress,
  }) {
    return VaultEntry(
      id: id,
      fileName: fileName,
      fileUrl: fileUrl,
      teamName: teamName,
      uploadedBy: uploadedBy,
      academicYear: academicYear,
      status: status,
      timestamp: timestamp,
      yearLevel: yearLevel,
      stage: stage,
      type: type,
      deliverableLabel: deliverableLabel,
      extractedText: extractedText,
      topics: topics,
      summary: summary,
      category: category,
      averageRating: averageRating ?? this.averageRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      userRating: userRating ?? this.userRating,
      userRemark: userRemark ?? this.userRemark,
      shelfStatus: shelfStatus ?? this.shelfStatus,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      totalPages: totalPages ?? this.totalPages,
      readingProgress: readingProgress ?? this.readingProgress,
    );
  }
}

// ── Tab widget ────────────────────────────────────────────────────────────────

class RepositoryTab extends ConsumerStatefulWidget {
  const RepositoryTab({super.key});

  @override
  ConsumerState<RepositoryTab> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends ConsumerState<RepositoryTab> {
  String _selectedYear = '';
  String _selectedType = ''; // '', 'capstone', 'pit'
  bool _isGridView = true; // true = Bookshelf Grid, false = List
  final Set<String> _collapsedStages = {};
  bool _defaultYearApplied = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryProvider.notifier).fetchForStudent();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    setState(() => _searchQuery = query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(repositoryProvider.notifier).fetchForStudent(search: query);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    ref.read(repositoryProvider.notifier).fetchForStudent(search: '');
  }

  List<VaultEntry> _filteredEntries(List<VaultEntry> allEntries) {
    return allEntries.where((e) {
      final matchYear = _selectedYear.isEmpty || e.academicYear == _selectedYear;
      final matchType = _selectedType.isEmpty || e.type == _selectedType;
      return matchYear && matchType;
    }).toList();
  }

  List<String> _yearsFor(List<VaultEntry> allEntries) {
    final y = allEntries
        .map((e) => e.academicYear)
        .where((y) => y != '—' && y.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return y.reversed.toList();
  }

  Future<void> _refreshVault() async {
    await Future.wait([
      ref.read(repositoryProvider.notifier).fetchForStudent(search: _searchQuery),
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
    ]);
  }

  void _applyDefaultYearIfNeeded(List<VaultEntry> allEntries) {
    if (_defaultYearApplied || allEntries.isEmpty) {
      return;
    }
    final years = allEntries
        .map((e) => e.academicYear)
        .where((y) => y.isNotEmpty && y != '—')
        .toSet()
        .toList()
      ..sort();
    if (years.isNotEmpty) {
      _defaultYearApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedYear = years.last);
        }
      });
    }
  }

  String _cleanTitle(String raw) {
    var name = raw;
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1) {
      name = name.substring(0, lastDot);
    }
    name = name.replaceAll(RegExp(r'[._\-]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(repositoryProvider);
    final allEntries = vaultState.entries.map((e) => VaultEntry.fromJson(e)).toList();
    _applyDefaultYearIfNeeded(allEntries);
    final loading = vaultState.isLoading && allEntries.isEmpty;
    final error = vaultState.error;
    final entries = _filteredEntries(allEntries);
    final isSearching = _searchQuery.isNotEmpty;
    final years = _yearsFor(allEntries);

    // Identify "Continue Reading" manuscripts
    final continueReadingEntries = allEntries
        .where((e) => e.readingProgress > 0 || e.shelfStatus == 'reading')
        .take(3)
        .toList();

    // Identify "Featured & Top Rated" manuscripts
    final featuredEntries = allEntries
        .where((e) => e.averageRating >= 4.0 || e.type == 'capstone')
        .take(6)
        .toList();

    return Column(
      children: [
        // ── Library Header & Search Bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_library_rounded, color: DefensysTokens.maroon, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'USTP Research Library',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: DefensysTokens.maroon,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Digital Manuscripts & Defense Archives',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // View Toggle Button (Grid vs List)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Bookshelf Grid',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.grid_view_rounded,
                            size: 16,
                            color: _isGridView ? DefensysTokens.maroon : Colors.grey.shade500,
                          ),
                          onPressed: () => setState(() => _isGridView = true),
                        ),
                        IconButton(
                          tooltip: 'Classic List',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.view_list_rounded,
                            size: 18,
                            color: !_isGridView ? DefensysTokens.maroon : Colors.grey.shade500,
                          ),
                          onPressed: () => setState(() => _isGridView = false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search by title, team, abstract topics, PDF text...',
                  hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.auto_stories_rounded, size: 18, color: DefensysTokens.maroon),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: _clearSearch,
                        )
                      : const Tooltip(
                          message: 'Full-text ML indexed e-library search',
                          child: Icon(Icons.psychology_rounded, size: 18, color: Colors.grey),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFFBF9F5),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                    borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                    borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
              ),

              // Year Filter Chips
              if (!isSearching && years.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('All Years', style: TextStyle(fontSize: 11)),
                          selected: _selectedYear.isEmpty,
                          selectedColor: DefensysTokens.maroon,
                          backgroundColor: Colors.grey.shade50,
                          labelStyle: TextStyle(
                            color: _selectedYear.isEmpty ? Colors.white : Colors.grey.shade700,
                            fontWeight: _selectedYear.isEmpty ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (s) => setState(() => _selectedYear = ''),
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: _selectedYear.isEmpty ? DefensysTokens.maroon : Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                      ...years.map((y) {
                        final isSel = _selectedYear == y;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('SY $y', style: const TextStyle(fontSize: 11)),
                            selected: isSel,
                            selectedColor: DefensysTokens.maroon,
                            backgroundColor: Colors.grey.shade50,
                            labelStyle: TextStyle(
                              color: isSel ? Colors.white : Colors.grey.shade700,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (s) => setState(() => _selectedYear = y),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSel ? DefensysTokens.maroon : Colors.grey.shade300,
                                width: 1,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Type Tabs (All, Capstone, PIT)
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2.5),
                child: Row(
                  children: [
                    _buildSegmentTab(label: 'All Shelves', typeValue: ''),
                    _buildSegmentTab(label: '📘 Capstone', typeValue: 'capstone'),
                    _buildSegmentTab(label: '📗 PIT Projects', typeValue: 'pit'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Notice Banner ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF7F0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEADBCE), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: DefensysTokens.maroon, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Open Student Library · Read manuscripts, view peer remarks & leave reviews.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.brown.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Main Content List / Shelves ──
        Expanded(
          child: RefreshIndicator(
            color: DefensysTokens.maroon,
            onRefresh: _refreshVault,
            child: _buildLibraryBody(
              loading: loading,
              error: error,
              allEntries: allEntries,
              entries: entries,
              isSearching: isSearching,
              continueReadingEntries: continueReadingEntries,
              featuredEntries: featuredEntries,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentTab({required String label, required String typeValue}) {
    final isSelected = _selectedType == typeValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = typeValue),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? DefensysTokens.maroon : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryBody({
    required bool loading,
    required String? error,
    required List<VaultEntry> allEntries,
    required List<VaultEntry> entries,
    required bool isSearching,
    required List<VaultEntry> continueReadingEntries,
    required List<VaultEntry> featuredEntries,
  }) {
    if (loading && allEntries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (error != null && allEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorBanner(
            title: context.l10n.failedToLoadRepository,
            message: error,
            onRetry: _refreshVault,
          ),
        ),
      );
    }

    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.auto_stories_rounded,
        iconSize: 48,
        message: isSearching
            ? 'No manuscripts match "$_searchQuery".'
            : 'No published submissions in this shelf.',
      );
    }

    // Group entries by stage/milestone
    final Map<String, List<VaultEntry>> grouped = {};
    for (var entry in entries) {
      final stageName = entry.stage.isEmpty || entry.stage == '—' ? 'General' : entry.stage;
      grouped.putIfAbsent(stageName, () => []).add(entry);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ErrorBanner(
              title: 'Could not refresh repository',
              message: error,
              onRetry: _refreshVault,
            ),
          ),

        // ── 1. "Continue Reading" Shelf (if available & not searching) ──
        if (!isSearching && continueReadingEntries.isNotEmpty) ...[
          _buildContinueReadingSection(continueReadingEntries.first),
          const SizedBox(height: 16),
        ],

        // ── 2. "Featured & Top-Rated Manuscripts" Carousel ──
        if (!isSearching && featuredEntries.isNotEmpty) ...[
          _buildFeaturedCarousel(featuredEntries),
          const SizedBox(height: 18),
        ],

        // ── 3. Main Catalog Section Header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isSearching
                  ? 'SEARCH RESULTS (${entries.length})'
                  : 'ALL PUBLICATIONS (${entries.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: DefensysTokens.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── 4. Catalog Sections (Grouped by Stage) ──
        ...grouped.entries.map((group) {
          final stage = group.key;
          final stageEntries = group.value;
          final isCollapsed = _collapsedStages.contains(stage);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Accordion Header
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isCollapsed) {
                      _collapsedStages.remove(stage);
                    } else {
                      _collapsedStages.add(stage);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isCollapsed ? Icons.keyboard_arrow_right_rounded : Icons.keyboard_arrow_down_rounded,
                        color: DefensysTokens.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        stage.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: DefensysTokens.textDark,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300, width: 0.6),
                        ),
                        child: Text(
                          '${stageEntries.length} ${stageEntries.length == 1 ? "book" : "books"}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (!isCollapsed)
                _isGridView
                    ? _buildBookshelfGrid(stageEntries)
                    : Column(children: stageEntries.map(_buildBookListItem).toList()),
            ],
          );
        }),
      ],
    );
  }

  // ── Continue Reading Ribbon Widget ──
  Widget _buildContinueReadingSection(VaultEntry entry) {
    final title = entry.deliverableLabel ?? entry.fileName;
    final clean = _cleanTitle(title);
    final percent = (entry.readingProgress).clamp(0.0, 100.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F2),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: const Color(0xFFE2D6C5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bookmark_added_rounded, color: DefensysTokens.maroon, size: 15),
              const SizedBox(width: 6),
              const Text(
                'CONTINUE READING',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.maroon,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              if (percent > 0)
                Text(
                  '${percent.toInt()}% completed',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.brown.shade700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCoverWidget(
                title: clean,
                authorOrTeam: entry.teamName,
                type: entry.type,
                stage: entry.stage,
                category: entry.category,
                size: BookCoverSize.small,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clean,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: DefensysTokens.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.teamName} · ${entry.stage}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent > 0 ? percent / 100.0 : 0.35,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: const AlwaysStoppedAnimation<Color>(DefensysTokens.maroon),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => _showBookDetailsSheet(entry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  elevation: 0,
                ),
                child: const Text('Resume', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Featured Books Carousel ──
  Widget _buildFeaturedCarousel(List<VaultEntry> featured) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 16),
            SizedBox(width: 6),
            Text(
              'FEATURED & TOP-RATED',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: DefensysTokens.textDark,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            itemBuilder: (context, index) {
              final entry = featured[index];
              final label = entry.deliverableLabel ?? entry.fileName;
              final clean = _cleanTitle(label);

              return GestureDetector(
                onTap: () => _showBookDetailsSheet(entry),
                child: Container(
                  width: 112,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BookCoverWidget(
                        title: clean,
                        authorOrTeam: entry.teamName,
                        type: entry.type,
                        stage: entry.stage,
                        category: entry.category,
                        rating: entry.averageRating > 0 ? entry.averageRating : null,
                        size: BookCoverSize.medium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        clean,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textDark,
                        ),
                      ),
                      Text(
                        entry.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
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
  }

  // ── Bookshelf Grid View ──
  Widget _buildBookshelfGrid(List<VaultEntry> entries) {
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = constraints.maxWidth > 600 ? 4 : (constraints.maxWidth > 380 ? 3 : 2);
      final itemWidth = (constraints.maxWidth - ((crossAxisCount - 1) * 12)) / crossAxisCount;
      final itemHeight = itemWidth * 1.85;

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: itemWidth / itemHeight,
        ),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final label = entry.deliverableLabel ?? entry.fileName;
          final clean = _cleanTitle(label);

          return GestureDetector(
            onTap: () => _showBookDetailsSheet(entry),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: BookCoverWidget(
                      title: clean,
                      authorOrTeam: entry.teamName,
                      type: entry.type,
                      stage: entry.stage,
                      category: entry.category,
                      academicYear: entry.academicYear,
                      rating: entry.averageRating > 0 ? entry.averageRating : null,
                      size: BookCoverSize.medium,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clean,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textDark,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (entry.averageRating > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 11, color: Color(0xFFD97706)),
                      const SizedBox(width: 2),
                      Text(
                        entry.averageRating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                      ),
                      if (entry.reviewsCount > 0)
                        Text(
                          ' (${entry.reviewsCount})',
                          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      );
    });
  }

  // ── Classic List View ──
  Widget _buildBookListItem(VaultEntry e) {
    final isCapstone = e.type == 'capstone';
    final label = e.deliverableLabel ?? e.fileName;
    final clean = _cleanTitle(label);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showBookDetailsSheet(e),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover thumbnail
              BookCoverWidget(
                title: clean,
                authorOrTeam: e.teamName,
                type: e.type,
                stage: e.stage,
                category: e.category,
                size: BookCoverSize.small,
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clean,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: DefensysTokens.textDark,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.teamName,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCapstone
                                ? DefensysTokens.maroon.withValues(alpha: 0.08)
                                : const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isCapstone ? 'Capstone' : 'PIT',
                            style: TextStyle(
                              fontSize: 9,
                              color: isCapstone ? DefensysTokens.maroon : const Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (e.averageRating > 0) ...[
                          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFD97706)),
                          const SizedBox(width: 2),
                          Text(
                            e.averageRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (e.academicYear.isNotEmpty && e.academicYear != '—')
                          Text(
                            'SY ${e.academicYear}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Book Details Bottom Sheet / Dialog ──
  void _showBookDetailsSheet(VaultEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookDetailsSheet(
        entry: entry,
        onReadPressed: () {
          Navigator.pop(context);
          _openReader(entry);
        },
      ),
    );
  }

  void _openReader(VaultEntry e) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final studentId = user?['username']?.toString() ?? 'Unknown';
    final firstName = user?['first_name']?.toString() ?? '';
    final lastName = user?['last_name']?.toString() ?? '';
    final studentName = '$firstName $lastName'.trim();
    final displayName = studentName.isNotEmpty ? studentName : studentId;

    final fileRef = e.fileUrl != null && e.fileUrl!.isNotEmpty ? e.fileUrl! : e.fileName;
    final lowerName = e.fileName.toLowerCase();

    if (lowerName.endsWith('.pdf')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _PDFViewerScreen(
            entry: e,
            fileName: e.deliverableLabel ?? e.fileName,
            fileRef: fileRef,
            teamName: e.teamName,
            stage: e.stage,
            studentId: studentId,
            studentName: displayName,
          ),
        ),
      );
    } else {
      _viewOrDownloadNonPdf(fileRef, e.fileName);
    }
  }

  Future<void> _viewOrDownloadNonPdf(String fileRef, String fileName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      ),
    );

    try {
      final bytes = await ref.read(authenticatedHttpClientProvider).fetchAuthenticatedFile(fileRef);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e. Downloading file instead.');
        try {
          final uri = Uri.parse(fileRef);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (launchErr) {
          if (mounted) {
            showErrorToast(context, 'Could not download or open file: $launchErr');
          }
        }
      }
    }
  }
}

// ── Book Details Bottom Sheet / Review Panel ─────────────────────────────────

class _BookDetailsSheet extends ConsumerStatefulWidget {
  final VaultEntry entry;
  final VoidCallback onReadPressed;

  const _BookDetailsSheet({
    required this.entry,
    required this.onReadPressed,
  });

  @override
  ConsumerState<_BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends ConsumerState<_BookDetailsSheet> {
  ReviewsPayload? _reviewsPayload;
  bool _loadingReviews = true;
  int _selectedStar = 5;
  final TextEditingController _remarkController = TextEditingController();
  bool _submittingReview = false;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _isBookmarked = widget.entry.shelfStatus == 'want_to_read' || widget.entry.shelfStatus == 'favorited';
    _loadReviews();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    final payload = await ref
        .read(repositoryReviewServiceProvider)
        .fetchReviews(widget.entry.id);
    if (!mounted) return;
    setState(() {
      _reviewsPayload = payload;
      _loadingReviews = false;
      if (payload?.userReview != null) {
        _selectedStar = payload!.userReview!.rating;
        _remarkController.text = payload.userReview!.remark;
      }
    });
  }

  Future<void> _submitReview() async {
    final remarkText = _remarkController.text.trim();
    setState(() => _submittingReview = true);

    final payload = await ref.read(repositoryReviewServiceProvider).submitReview(
      targetId: widget.entry.id,
      rating: _selectedStar,
      remark: remarkText,
    );

    if (!mounted) return;
    setState(() {
      _submittingReview = false;
      if (payload != null) {
        _reviewsPayload = payload;
        showSuccessToast(context, 'Remark and rating submitted!');
      }
    });
  }

  Future<void> _toggleBookmark() async {
    setState(() => _isBookmarked = !_isBookmarked);
    await ref.read(repositoryReviewServiceProvider).updateShelfProgress(
      targetId: widget.entry.id,
      status: _isBookmarked ? 'want_to_read' : 'none',
    );
  }

  String _cleanTitle(String raw) {
    var name = raw;
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1) {
      name = name.substring(0, lastDot);
    }
    name = name.replaceAll(RegExp(r'[._\-]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final label = entry.deliverableLabel ?? entry.fileName;
    final clean = _cleanTitle(label);
    final isCapstone = entry.type == 'capstone';
    final hasSummary = entry.summary.isNotEmpty && entry.summary != '—';
    final avgScore = _reviewsPayload?.averageRating ?? entry.averageRating;
    final totalRatings = _reviewsPayload?.ratingsCount ?? entry.ratingsCount;
    final reviews = _reviewsPayload?.reviews ?? [];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              children: [
                // ── Hero Section with Book Cover ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCoverWidget(
                      title: clean,
                      authorOrTeam: entry.teamName,
                      type: entry.type,
                      stage: entry.stage,
                      category: entry.category,
                      academicYear: entry.academicYear,
                      size: BookCoverSize.large,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Track Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCapstone
                                  ? DefensysTokens.maroon.withValues(alpha: 0.1)
                                  : const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCapstone ? 'CAPSTONE MANUSCRIPT' : 'PIT RESEARCH',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isCapstone ? DefensysTokens.maroon : const Color(0xFF1E3A8A),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Title
                          Text(
                            clean,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.textDark,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Author / Team
                          Text(
                            entry.teamName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Academic Year & Stage
                          Text(
                            '${entry.stage} · SY ${entry.academicYear}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 8),

                          // Rating Scorecard Banner
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 18),
                              const SizedBox(width: 4),
                              Text(
                                avgScore > 0 ? avgScore.toStringAsFixed(1) : 'No ratings',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                              if (totalRatings > 0)
                                Text(
                                  ' ($totalRatings reviews)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Action Buttons ──
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: widget.onReadPressed,
                        icon: const Icon(Icons.auto_stories_rounded, size: 18),
                        label: const Text('Read Manuscript', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DefensysTokens.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _isBookmarked ? 'Saved in Shelf' : 'Add to Shelf',
                      icon: Icon(
                        _isBookmarked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        color: _isBookmarked ? DefensysTokens.maroon : Colors.grey.shade700,
                      ),
                      onPressed: _toggleBookmark,
                      style: IconButton.styleFrom(
                        backgroundColor: _isBookmarked ? const Color(0xFFFBF1E8) : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Executive Abstract / Summary ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF9F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.psychology_rounded, color: DefensysTokens.maroon, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'EXECUTIVE ABSTRACT',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.maroon,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasSummary
                            ? entry.summary
                            : (entry.extractedText.isNotEmpty
                                ? (entry.extractedText.length > 250
                                    ? '${entry.extractedText.substring(0, 250)}...'
                                    : entry.extractedText)
                                : 'No abstract generated for this upload.'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (entry.topics.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: entry.topics.map((t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300, width: 0.7),
                            ),
                            child: Text(
                              '#$t',
                              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                            ),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Community Rating & Remarks Section ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.rate_review_rounded, color: DefensysTokens.maroon, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'COMMUNITY REMARKS & REVIEWS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${reviews.length} notes',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Interactive Rate & Remark Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.2), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Rating & Remarks',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: DefensysTokens.textDark),
                      ),
                      const SizedBox(height: 6),
                      // Star Selector
                      Row(
                        children: List.generate(5, (index) {
                          final star = index + 1;
                          return IconButton(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              star <= _selectedStar ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: const Color(0xFFD97706),
                              size: 26,
                            ),
                            onPressed: () => setState(() => _selectedStar = star),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      // Remark input
                      TextField(
                        controller: _remarkController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Share feedback, critique, or questions on this manuscript...',
                          hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          isDense: true,
                          contentPadding: const EdgeInsets.all(10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: DefensysTokens.maroon),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: _submittingReview ? null : _submitReview,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DefensysTokens.maroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            elevation: 0,
                          ),
                          child: _submittingReview
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Post Remark', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Review remarks list
                if (_loadingReviews)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: DefensysTokens.maroon, strokeWidth: 2),
                    ),
                  )
                else if (reviews.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No peer remarks yet. Be the first to review this manuscript!',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                      ),
                    ),
                  )
                else
                  ...reviews.map((r) => _buildReviewCard(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ReviewItem r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                child: Text(
                  r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysTokens.maroon),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          r.userName,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: DefensysTokens.textDark),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.userRole,
                            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatDate(r.createdAt),
                      style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              // Stars
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFD97706),
                    size: 13,
                  );
                }),
              ),
            ],
          ),
          if (r.remark.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.remark,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey.shade800),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ── PDF E-Reader Screen with Reading Themes & Progress ────────────────────────

enum ReaderTheme {
  day(name: 'Day', bg: Colors.white, fg: Colors.black87),
  sepia(name: 'Sepia', bg: Color(0xFFFBF0D9), fg: Color(0xFF3E2723)),
  night(name: 'Night', bg: Color(0xFF18181B), fg: Color(0xFFF4F4F5));

  final String name;
  final Color bg;
  final Color fg;

  const ReaderTheme({required this.name, required this.bg, required this.fg});
}

class _PDFViewerScreen extends ConsumerStatefulWidget {
  final VaultEntry entry;
  final String fileName;
  final String fileRef;
  final String teamName;
  final String stage;
  final String studentId;
  final String studentName;

  const _PDFViewerScreen({
    required this.entry,
    required this.fileName,
    required this.fileRef,
    required this.teamName,
    required this.stage,
    required this.studentId,
    required this.studentName,
  });

  @override
  ConsumerState<_PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends ConsumerState<_PDFViewerScreen> {
  Uint8List? _pdfBytes;
  String? _loadError;
  bool _loading = true;
  late final String _formattedDateTime;
  PdfViewerController? _pdfViewerController;
  int _currentPage = 1;
  int _pageCount = 1;
  ReaderTheme _currentTheme = ReaderTheme.day;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _formattedDateTime = _formatCurrentDateTime();
    _loadPdf();
  }

  String _formatCurrentDateTime() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[now.month - 1];
    final day = now.day;
    final year = now.year;

    int hour = now.hour;
    final amPm = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    return '$month $day, $year $hour:$minute:$second $amPm';
  }

  Future<void> _loadPdf() async {
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(widget.fileRef);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    setState(() {
      _currentPage = details.newPageNumber;
      _pageCount = _pdfViewerController?.pageCount ?? 1;
    });

    // Save reading progress in background
    final progress = _pageCount > 0 ? (_currentPage / _pageCount) * 100.0 : 0.0;
    ref.read(repositoryReviewServiceProvider).updateShelfProgress(
      targetId: widget.entry.id,
      status: 'reading',
      lastReadPage: _currentPage,
      totalPages: _pageCount,
      progressPercent: progress,
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reader Theme & Display', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ReaderTheme.values.map((t) {
            final isSelected = _currentTheme == t;
            return ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: t.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 1),
                ),
              ),
              title: Text(t.name, style: const TextStyle(fontSize: 13)),
              trailing: isSelected ? const Icon(Icons.check, color: DefensysTokens.maroon) : null,
              onTap: () {
                setState(() => _currentTheme = t);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _currentTheme.bg,
      appBar: AppBar(
        backgroundColor: _currentTheme == ReaderTheme.night ? const Color(0xFF18181B) : DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName.length > 25 ? '${widget.fileName.substring(0, 25)}...' : widget.fileName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              '${widget.teamName} · Page $_currentPage of $_pageCount',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reading theme',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _showThemeDialog,
          ),
          IconButton(
            tooltip: 'Document security notice',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: DefensysTokens.maroon, size: 20),
                      SizedBox(width: 8),
                      Text('Read-Only Document', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: const Text(
                    'This manuscript is available for authenticated reading only. '
                    'Downloading and unauthorized reproduction are disabled.',
                    style: TextStyle(fontSize: 13),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: DefensysTokens.maroon),
            )
          else if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load PDF: $_loadError', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _loadError = null;
                        });
                        _loadPdf();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_pdfBytes != null)
            SfPdfViewer.memory(
              _pdfBytes!,
              controller: _pdfViewerController,
              canShowScrollHead: true,
              canShowScrollStatus: true,
              enableDoubleTapZooming: true,
              enableTextSelection: false,
              onPageChanged: _onPageChanged,
            ),

          // Security Watermark Overlay
          IgnorePointer(
            child: Center(
              child: Transform.rotate(
                angle: -0.5,
                child: Opacity(
                  opacity: 0.12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, size: 54, color: DefensysTokens.maroon),
                      const SizedBox(height: 8),
                      const Text(
                        'PROPERTY OF USTP',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: DefensysTokens.maroon,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'REPOSITORY - READ ONLY',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.maroon,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'ID: ${widget.studentId}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.maroon,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formattedDateTime,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
