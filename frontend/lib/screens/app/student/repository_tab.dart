import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/repository_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../services/auth_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../widgets/feedback_toast.dart';
import '../../../utils/pdf_viewer.dart';


// ── Data models ───────────────────────────────────────────────────────────────

class VaultEntry {
  final String id;
  final String fileName;
  final String? fileUrl;  // Add file URL
  final String teamName;
  final String uploadedBy;
  final String academicYear;
  final String status;
  final String timestamp;
  final String yearLevel;
  final String stage;
  final String type; // 'pit' or 'capstone'
  final String? deliverableLabel;
  final String extractedText;  // PDF content
  final List<String> topics;  // Keywords/topics
  final String summary;  // Summary
  final String category;

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
  });

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
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
      );
}

// ── Tab widget ────────────────────────────────────────────────────────────────

class RepositoryTab extends ConsumerStatefulWidget {
  const RepositoryTab({super.key});

  @override
  ConsumerState<RepositoryTab> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends ConsumerState<RepositoryTab> {
  String _selectedYear = '';
  String _selectedType = ''; // '', 'capstone', 'pit', 'uploader'
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
    final y = allEntries.map((e) => e.academicYear).where((y) => y != '—').toSet().toList()..sort();
    return y.reversed.toList();
  }

  Future<void> _refreshVault() async {
    await Future.wait([
      ref
          .read(repositoryProvider.notifier)
          .fetchForStudent(search: _searchQuery),
      ref
          .read(dashboardProvider('student').notifier)
          .fetchDashboardData(),
    ]);
  }

  Widget _buildErrorPanel(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBanner(
          title: context.l10n.failedToLoadRepository,
          message: message,
          onRetry: _refreshVault,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ErrorBanner(
        title: 'Could not refresh vault',
        message: message,
        onRetry: _refreshVault,
      ),
    );
  }

  Widget _buildEmptyPanel(bool isSearching) {
    return EmptyState(
      icon: Icons.folder_off,
      iconSize: 48,
      message: isSearching
          ? 'No files match "$_searchQuery".'
          : 'No published files yet.',
    );
  }

  Widget _buildScrollableChild({
    required Widget child,
    required double minHeight,
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: child,
      ),
    );
  }

  Widget _buildListBody({
    required bool loading,
    required String? error,
    required List<VaultEntry> allEntries,
    required List<VaultEntry> entries,
    required bool isSearching,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight;

        if (loading && allEntries.isEmpty) {
          return _buildScrollableChild(
            minHeight: minHeight,
            child: const Center(
              child: CircularProgressIndicator(color: DefensysTokens.maroon),
            ),
          );
        }

        if (error != null && allEntries.isEmpty) {
          return _buildScrollableChild(
            minHeight: minHeight,
            child: _buildErrorPanel(error),
          );
        }

        if (entries.isEmpty) {
          return _buildScrollableChild(
            minHeight: minHeight,
            child: _buildEmptyPanel(isSearching),
          );
        }

        // Group entries by stage/milestone
        final Map<String, List<VaultEntry>> grouped = {};
        for (var entry in entries) {
          final stageName = entry.stage.isEmpty || entry.stage == '—' ? 'General' : entry.stage;
          grouped.putIfAbsent(stageName, () => []).add(entry);
        }

        final List<Widget> listItems = [];
        if (error != null) {
          listItems.add(_buildErrorBanner(error));
        }

        grouped.forEach((stage, stageEntries) {
          final isCollapsed = _collapsedStages.contains(stage);
          listItems.add(
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
                margin: const EdgeInsets.only(top: 14, bottom: 8),
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
                        color: DefensysTokens.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200, width: 0.5),
                      ),
                      child: Text(
                        '${stageEntries.length} ${stageEntries.length == 1 ? "file" : "files"}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          if (!isCollapsed) {
            listItems.addAll(stageEntries.map(_entryCard));
          }
        });

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: listItems,
        );
      },
    );
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

  String _cleanFileName(String fileName) {
    var name = fileName;
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1) {
      name = name.substring(0, lastDot);
    }
    name = name.replaceAll(RegExp(r'[._\-]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  Widget _buildSegmentTab({required String label, required String typeValue}) {
    final isSelected = _selectedType == typeValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = typeValue),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? DefensysTokens.maroon : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(repositoryProvider);
    final allEntries = vaultState.entries
        .map((e) => VaultEntry.fromJson(e))
        .toList();
    _applyDefaultYearIfNeeded(allEntries);
    final loading = vaultState.isLoading && allEntries.isEmpty;
    final error = vaultState.error;
    final entries = _filteredEntries(allEntries);
    final isSearching = _searchQuery.isNotEmpty;
    final years = _yearsFor(allEntries);

    return Column(
      children: [
        // ── Header ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_special, color: DefensysTokens.maroon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.repositoryTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: DefensysTokens.maroon,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Smart search: PDF content, topics, file, team...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.auto_awesome, size: 20, color: DefensysTokens.maroon),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: _clearSearch)
                      : const Tooltip(
                          message: 'ML-powered search with PDF content extraction',
                          child: Icon(Icons.psychology, size: 18, color: Colors.grey),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                    borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                    borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              if (!isSearching && years.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All Years', style: TextStyle(fontSize: 12)),
                          selected: _selectedYear.isEmpty,
                          selectedColor: DefensysTokens.maroon,
                          backgroundColor: Colors.grey.shade50,
                          labelStyle: TextStyle(
                            color: _selectedYear.isEmpty ? Colors.white : Colors.grey.shade700,
                            fontWeight: _selectedYear.isEmpty ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedYear = '');
                            }
                          },
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: _selectedYear.isEmpty ? DefensysTokens.maroon : Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                      ...years.map((y) {
                        final isSelected = _selectedYear == y;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('SY $y', style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            selectedColor: DefensysTokens.maroon,
                            backgroundColor: Colors.grey.shade50,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedYear = y);
                              }
                            },
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? DefensysTokens.maroon : Colors.grey.shade200,
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
              const SizedBox(height: 12),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _buildSegmentTab(label: 'All', typeValue: ''),
                    _buildSegmentTab(label: 'Capstone', typeValue: 'capstone'),
                    _buildSegmentTab(label: 'PIT', typeValue: 'pit'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Notice ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: DefensysTokens.maroon.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.15), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded, color: DefensysTokens.maroon, size: 14),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Public repository · View-only access to all team submissions.',
                  style: TextStyle(
                    fontSize: 11,
                    color: DefensysTokens.maroon,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Count ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                loading
                    ? 'Loading...'
                    : isSearching
                        ? '${entries.length} result${entries.length != 1 ? "s" : ""} for "$_searchQuery"'
                        : '${entries.length} file${entries.length != 1 ? "s" : ""} found',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),

        // ── List ──
        Expanded(
          child: RefreshIndicator(
            color: DefensysTokens.maroon,
            onRefresh: _refreshVault,
            child: _buildListBody(
              loading: loading,
              error: error,
              allEntries: allEntries,
              entries: entries,
              isSearching: isSearching,
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryCard(VaultEntry e) {
    final isCapstone = e.type == 'capstone';
    final isUploader = e.type == 'uploader';
    final color = isCapstone ? DefensysTokens.maroon : (isUploader ? DefensysTokens.techBlue : DefensysTokens.maroonLight);
    final label = e.deliverableLabel ?? e.fileName;
    final cleanTitle = (label == e.fileName || e.deliverableLabel == null) 
        ? _cleanFileName(label) 
        : label;
    final hasTopics = e.topics.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEntryDetailsDialog(e),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading Icon Container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  e.fileName.toLowerCase().endsWith('.mp4') ? Icons.videocam_rounded
                    : e.fileName.toLowerCase().endsWith('.zip') ? Icons.folder_zip_rounded
                    : e.fileName.toLowerCase().endsWith('.ppt') || e.fileName.toLowerCase().endsWith('.pptx') ? Icons.slideshow_rounded
                    : e.fileName.toLowerCase().endsWith('.doc') || e.fileName.toLowerCase().endsWith('.docx') ? Icons.description_rounded
                    : Icons.picture_as_pdf_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Main details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleanTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: DefensysTokens.textDark,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.teamName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCapstone ? 'Capstone' : (isUploader ? 'Uploaded' : 'PIT'),
                            style: TextStyle(
                              fontSize: 9,
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (e.stage != '—' && e.stage.isNotEmpty) ...[
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            e.stage,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                        if (e.academicYear != '—' && e.academicYear.isNotEmpty) ...[
                          const Spacer(),
                          Text(
                            'SY ${e.academicYear}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                    if (hasTopics) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: e.topics.take(3).map((topic) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tag_rounded, size: 9, color: Colors.grey),
                              const SizedBox(width: 2),
                              Text(
                                topic.length > 15 ? '${topic.substring(0, 15)}…' : topic,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Trailing View Indicator
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEntryDetailsDialog(VaultEntry e) {
    final isCapstone = e.type == 'capstone';
    final isUploader = e.type == 'uploader';
    final color = isCapstone ? DefensysTokens.maroon : (isUploader ? DefensysTokens.techBlue : DefensysTokens.maroonLight);
    final label = e.deliverableLabel ?? e.fileName;
    final cleanTitle = (label == e.fileName || e.deliverableLabel == null) 
        ? _cleanFileName(label) 
        : label;
    final hasTopics = e.topics.isNotEmpty;
    final hasSummary = e.summary.isNotEmpty && e.summary != '—';

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
          ),
          clipBehavior: Clip.antiAlias,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
              maxWidth: 450,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isCapstone ? 'Capstone' : (isUploader ? 'Uploaded File' : 'PIT Project'),
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Document Title
                        Text(
                          cleanTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Badges/Tags (Academic Year & Stage)
                        Row(
                          children: [
                            if (e.stage != '—' && e.stage.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                ),
                                child: Text(
                                  e.stage,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (e.academicYear != '—') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                ),
                                child: Text(
                                  'SY ${e.academicYear}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Project Details card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
                            border: Border.all(color: Colors.grey.shade100, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PROJECT DETAILS',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildDetailRow(
                                icon: Icons.group_rounded,
                                label: 'Team Name',
                                value: e.teamName,
                              ),
                              const SizedBox(height: 8),
                              _buildDetailRow(
                                icon: Icons.person_rounded,
                                label: 'Uploaded By',
                                value: e.uploadedBy,
                              ),
                              if (e.timestamp.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                  icon: Icons.calendar_today_rounded,
                                  label: 'Date Uploaded',
                                  value: _formatTimestamp(e.timestamp),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Summary Section
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: DefensysTokens.maroon, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Document Summary',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hasSummary ? e.summary : 'No summary details available for this upload.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.grey.shade700,
                            fontStyle: hasSummary ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Topics Section
                        if (hasTopics) ...[
                          const Text(
                            'Keywords & Topics',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: e.topics.map((topic) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.tag_rounded, size: 8, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    topic,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),

                // Action Button footer
                Builder(
                  builder: (context) {
                    final lowerName = e.fileName.toLowerCase();
                    final isPdf = lowerName.endsWith('.pdf');
                    final isPreviewable = isPdf ||
                        lowerName.endsWith('.png') ||
                        lowerName.endsWith('.jpg') ||
                        lowerName.endsWith('.jpeg') ||
                        lowerName.endsWith('.webp') ||
                        lowerName.endsWith('.gif') ||
                        lowerName.endsWith('.mp4') ||
                        lowerName.endsWith('.mov') ||
                        lowerName.endsWith('.avi') ||
                        lowerName.endsWith('.mkv');

                    final buttonIcon = isPreviewable
                        ? (isPdf ? Icons.picture_as_pdf_rounded : Icons.visibility_rounded)
                        : Icons.download_rounded;
                    final buttonLabel = isPreviewable
                        ? (isPdf ? 'Read Document' : 'View File')
                        : 'Download File';

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context); // Close dialog first
                                _showViewer(e); // Then open viewer
                              },
                              icon: Icon(buttonIcon, size: 18),
                              label: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: DefensysTokens.maroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DefensysTokens.textDark),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return ts;
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
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileRef);
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
          showErrorToast(context, 'Could not download or open file: $launchErr');
        }
      }
    }
  }

  void _showViewer(VaultEntry e) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final studentId = user?['username']?.toString() ?? 'Unknown';
    final firstName = user?['first_name']?.toString() ?? '';
    final lastName = user?['last_name']?.toString() ?? '';
    final studentName = '$firstName $lastName'.trim();
    final displayName = studentName.isNotEmpty ? studentName : studentId;
    
    final fileRef = e.fileUrl != null && e.fileUrl!.isNotEmpty
        ? e.fileUrl!
        : e.fileName;

    final lowerName = e.fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _PDFViewerScreen(
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
}

// PDF Viewer Screen
class _PDFViewerScreen extends ConsumerStatefulWidget {
  final String fileName;
  final String fileRef;
  final String teamName;
  final String stage;
  final String studentId;
  final String studentName;

  const _PDFViewerScreen({
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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName.length > 30
                  ? '${widget.fileName.substring(0, 30)}...'
                  : widget.fileName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              '${widget.teamName} · ${widget.stage}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Document info',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.lock, color: DefensysTokens.maroon, size: 20),
                      SizedBox(width: 8),
                      Text('Read-Only Document', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  content: const Text(
                    'This document is available for secure viewing only. '
                    'Downloading and copying are disabled for vault submissions.',
                    style: TextStyle(fontSize: 14),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
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
                    Text(
                      'Failed to load PDF: $_loadError',
                      textAlign: TextAlign.center,
                    ),
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
              canShowScrollHead: true,
              canShowScrollStatus: true,
              enableDoubleTapZooming: true,
              enableTextSelection: false,
            ),
          
          // Watermark Overlay
          IgnorePointer(
            child: Center(
              child: Transform.rotate(
                angle: -0.5, // Diagonal angle (about -30 degrees)
                child: Opacity(
                  opacity: 0.15,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock,
                        size: 60,
                        color: DefensysTokens.maroon,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'PROPERTY OF USTP',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: DefensysTokens.maroon,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'REPOSITORY - READ ONLY',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.maroon,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ID: ${widget.studentId}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.maroon,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formattedDateTime,
                        style: const TextStyle(
                          fontSize: 14,
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
