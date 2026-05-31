import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/digital_vault_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../services/auth_provider.dart';


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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(digitalVaultProvider.notifier).fetchForStudent();
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
      ref.read(digitalVaultProvider.notifier).fetchForStudent(search: query);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    ref.read(digitalVaultProvider.notifier).fetchForStudent(search: '');
  }

  List<VaultEntry> _filteredEntries(List<VaultEntry> allEntries) {
    return allEntries.where((e) {
      final matchYear = _selectedYear.isEmpty || e.academicYear == _selectedYear;
      return matchYear;
    }).toList();
  }

  List<String> _yearsFor(List<VaultEntry> allEntries) {
    final y = allEntries.map((e) => e.academicYear).where((y) => y != '—').toSet().toList()..sort();
    return y.reversed.toList();
  }

  Future<void> _refreshVault() async {
    await ref
        .read(digitalVaultProvider.notifier)
        .fetchForStudent(search: _searchQuery);
  }

  Widget _buildErrorPanel(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBanner(
          title: context.l10n.failedToLoadVault,
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

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (error != null) _buildErrorBanner(error),
            ...entries.map(_entryCard),
          ],
        );
      },
    );
  }

  void _applyDefaultYearIfNeeded(List<VaultEntry> allEntries) {
    if (_selectedYear.isNotEmpty || allEntries.isEmpty) {
      return;
    }
    final years = allEntries
        .map((e) => e.academicYear)
        .where((y) => y.isNotEmpty && y != '—')
        .toSet()
        .toList()
      ..sort();
    if (years.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedYear = years.last);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(digitalVaultProvider);
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
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_special, color: DefensysTokens.maroon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.digitalVaultTitle,
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
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: const Icon(Icons.auto_awesome, size: 20, color: DefensysTokens.gold),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              if (!isSearching && years.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedYear.isEmpty ? null : _selectedYear,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Academic Year',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: years.map((y) => DropdownMenuItem(
                    value: y,
                    child: Text('SY $y', style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedYear = v ?? ''),
                ),
              ],
            ],
          ),
        ),

        // ── Notice ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock, color: Colors.amber, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Public vault - view-only access to all team submissions.',
                  style: TextStyle(fontSize: 11, color: Colors.brown),
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
    final color = isCapstone ? DefensysTokens.maroon : (isUploader ? Colors.blue : DefensysTokens.gold);
    final label = e.deliverableLabel ?? e.fileName;
    final shortName = label.length > 40 ? '${label.substring(0, 40)}…' : label;
    final hasTopics = e.topics.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            e.fileName.toLowerCase().endsWith('.mp4') ? Icons.videocam
              : e.fileName.toLowerCase().endsWith('.zip') ? Icons.folder_zip
              : e.fileName.toLowerCase().endsWith('.ppt') || e.fileName.toLowerCase().endsWith('.pptx') ? Icons.slideshow
              : e.fileName.toLowerCase().endsWith('.doc') || e.fileName.toLowerCase().endsWith('.docx') ? Icons.description
              : Icons.picture_as_pdf,
            color: color, size: 22,
          ),
        ),
        title: Text(shortName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(e.teamName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCapstone ? 'Capstone' : (isUploader ? 'Uploaded' : 'PIT'),
                    style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                if (e.stage != '—' && e.stage.isNotEmpty)
                  Text(e.stage, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const Spacer(),
                if (e.academicYear != '—')
                  Text(e.academicYear, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            // Display topics as chips
            if (hasTopics) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: e.topics.take(3).map((topic) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DefensysTokens.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DefensysTokens.gold.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.label, size: 8, color: DefensysTokens.gold),
                      const SizedBox(width: 2),
                      Text(
                        topic.length > 15 ? '${topic.substring(0, 15)}…' : topic,
                        style: const TextStyle(fontSize: 8, color: DefensysTokens.gold, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.visibility, color: DefensysTokens.maroon, size: 20),
          tooltip: 'View',
          onPressed: () => _showViewer(e),
        ),
      ),
    );
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
                        'DIGITAL VAULT - READ ONLY',
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
