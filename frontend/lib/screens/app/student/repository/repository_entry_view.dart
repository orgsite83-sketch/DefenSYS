import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../../services/authenticated_client.dart';
import '../../../../services/repository_review_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../services/auth_provider.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../utils/universal_file_viewer.dart';

import '../../../../models/repository_library.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/repository/repository_video_viewer.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

Future<void> showRepositoryEntryDetails(
  BuildContext context,
  WidgetRef ref,
  VaultEntry entry,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _BookDetailsSheet(
          entry: entry,
          onReadPressed: () {
            Navigator.pop(sheetContext);
            openRepositoryEntry(context, ref, entry);
          },
        ),
      ),
    ),
  );
}

Future<void> openRepositoryEntry(
  BuildContext context,
  WidgetRef ref,
  VaultEntry entry,
) async {
  final file = entry.fileUrl;
  if (file == null || file.isEmpty) {
    showErrorToast(context, 'This output does not have an available file.');
    return;
  }
  final user = ref.read(authProvider).user;
  final service = ref.read(repositoryReviewServiceProvider);
  final client = ref.read(authenticatedHttpClientProvider);
  if (entry.isPdf) {
    final name = '${user?['first_name'] ?? ''} ${user?['last_name'] ?? ''}'
        .trim();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PDFViewerScreen(
          entry: entry,
          fileName: entry.displayTitle,
          fileRef: file,
          teamName: entry.teamName,
          stage: entry.outputLabel,
          studentId: user?['username']?.toString() ?? '',
          studentName: name,
        ),
      ),
    );
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final loading = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  unawaited(navigator.push(loading));
  try {
    final bytes = await client.fetchAuthenticatedFile(file);
    if (loading.isActive) navigator.removeRoute(loading);
    if (!context.mounted) return;
    if (entry.outputKind == 'video') {
      await openRepositoryVideo(
        context: context,
        bytes: bytes,
        fileName: entry.fileName,
        onReady: () {
          service.updateShelfProgress(targetId: entry.id, opened: true);
        },
      );
    } else if (entry.isImage) {
      unawaited(service.updateShelfProgress(targetId: entry.id, opened: true));
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(entry.displayTitle)),
            body: Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  semanticLabel: '${entry.displayTitle} ${entry.outputLabel}',
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      unawaited(service.updateShelfProgress(targetId: entry.id, opened: true));
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: entry.fileName,
      );
    }
  } catch (_) {
    if (loading.isActive) navigator.removeRoute(loading);
    if (context.mounted) {
      showErrorToast(context, 'Could not open this output. Please try again.');
    }
  }
}

// ── Book Details Bottom Sheet / Review Panel ─────────────────────────────────

class _BookDetailsSheet extends ConsumerStatefulWidget {
  final VaultEntry entry;
  final VoidCallback onReadPressed;

  const _BookDetailsSheet({required this.entry, required this.onReadPressed});

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
    _isBookmarked = widget.entry.isSaved;
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

    final payload = await ref
        .read(repositoryReviewServiceProvider)
        .submitReview(
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

  Future<void> _toggleBookmark(bool saved) async {
    final next = !saved;
    final result = await ref
        .read(repositoryReviewServiceProvider)
        .updateShelfProgress(targetId: widget.entry.id, isSaved: next);
    if (!mounted) return;
    if (result == null) {
      showErrorToast(context, 'Could not update your bookmark.');
      return;
    }
    setState(() => _isBookmarked = next);
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final entry = widget.entry;
    final clean = entry.displayTitle;
    final isCapstone = entry.type == 'capstone';
    final avgScore = _reviewsPayload?.averageRating ?? entry.averageRating;
    final totalRatings = _reviewsPayload?.ratingsCount ?? entry.ratingsCount;
    final reviews = _reviewsPayload?.reviews ?? [];
    final saved =
        ref
            .watch(repositoryLibraryActivityProvider)
            .asData
            ?.value
            .saved
            .any((item) => item.id == entry.id) ??
        _isBookmarked;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: const BorderRadius.only(
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
              color: DefensysTokens.borderOf(context),
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
                    SizedBox(
                      width: 92,
                      height: 142,
                      child: LibraryCover(entry: entry),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Track Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isCapstone
                                  ? DefensysTokens.maroon.withValues(alpha: 0.1)
                                  : const Color(
                                      0xFF1E3A8A,
                                    ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              entry.outputLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isCapstone
                                    ? DefensysTokens.maroon
                                    : const Color(0xFF1E3A8A),
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
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Author / Team
                          Text(
                            entry.teamName,
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Academic Year & Stage
                          Text(
                            '${entry.outputLabel} · ${entry.stage} · SY ${entry.academicYear}',
                            style: TextStyle(
                              fontSize: 11,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Rating Scorecard Banner
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFD97706),
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                avgScore > 0
                                    ? avgScore.toStringAsFixed(1)
                                    : 'No ratings',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                              if (totalRatings > 0)
                                Text(
                                  ' ($totalRatings reviews)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
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
                      child: ShadButton(
                        onPressed: widget.onReadPressed,
                        leading: Icon(libraryOutputIcon(entry), size: 18),
                        child: Text(
                          entry.openLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ShadButton.outline(
                      width: 42,
                      padding: EdgeInsets.zero,
                      onPressed: () => _toggleBookmark(saved),
                      child: Semantics(
                        label: saved ? 'Remove saved output' : 'Save output',
                        child: Icon(
                          saved
                              ? Icons.bookmark_added_rounded
                              : Icons.bookmark_add_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Executive Abstract / Summary ──
                ShadCard(
                  padding: const EdgeInsets.all(14),
                  shadows: const [],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                            color: DefensysTokens.maroon,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            entry.isDocument
                                ? entry.overviewLabel
                                : 'Description',
                            style: const TextStyle(
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
                        entry.previewText.isNotEmpty
                            ? entry.previewText
                            : 'Open this published output to explore its content.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      if (entry.previewText.isNotEmpty && entry.isDocument)
                        Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Text(
                            'Source: ${entry.outputLabel}${entry.overviewPage != null ? ' · p. ${entry.overviewPage}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      if (entry.topics.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: entry.topics
                              .map(
                                (t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: DefensysTokens.borderOf(context),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    '#$t',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: DefensysTokens.textSecondaryOf(
                                        context,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
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
                        Icon(
                          Icons.rate_review_rounded,
                          color: DefensysTokens.maroon,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'COMMUNITY REMARKS & REVIEWS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${reviews.length} notes',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Interactive Rate & Remark Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DefensysTokens.maroon.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Rating & Remarks',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
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
                              star <= _selectedStar
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: const Color(0xFFD97706),
                              size: 26,
                            ),
                            onPressed: () =>
                                setState(() => _selectedStar = star),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      // Remark input
                      ShadInput(
                        controller: _remarkController,
                        maxLines: 3,
                        placeholder: const Text(
                          'Share feedback or questions on this output…',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ShadButton(
                          onPressed: _submittingReview ? null : _submitReview,
                          child: _submittingReview
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DefensysTokens.surfaceOf(context),
                                  ),
                                )
                              : const Text(
                                  'Post Remark',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
                      child: CircularProgressIndicator(
                        color: DefensysTokens.maroon,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (reviews.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No peer remarks yet. Be the first to review this manuscript!',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysTokens.borderOf(context), width: 0.8),
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
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.maroon,
                  ),
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
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: DefensysTokens.borderOf(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.userRole,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatDate(r.createdAt),
                      style: TextStyle(
                        fontSize: 9.5,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Stars
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < r.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
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
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
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
  Timer? _progressTimer;
  late RepositoryReviewService _shelfService;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _shelfService = ref.read(repositoryReviewServiceProvider);
    _pdfViewerController = PdfViewerController();
    _formattedDateTime = _formatCurrentDateTime();
    _loadPdf();
  }

  String _formatCurrentDateTime() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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

    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 600), _saveProgress);
  }

  void _saveProgress() {
    if (!_opened) return;
    final progress = _pageCount > 0 ? (_currentPage / _pageCount) * 100.0 : 0.0;
    _shelfService.updateShelfProgress(
      targetId: widget.entry.id,
      status: 'reading',
      lastReadPage: _currentPage,
      totalPages: _pageCount,
      progressPercent: progress,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveProgress();
    _pdfViewerController?.dispose();
    super.dispose();
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reader Theme & Display',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
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
              trailing: isSelected
                  ? const Icon(Icons.check, color: DefensysTokens.maroon)
                  : null,
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
        backgroundColor: _currentTheme == ReaderTheme.night
            ? const Color(0xFF18181B)
            : DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName.length > 25
                  ? '${widget.fileName.substring(0, 25)}...'
                  : widget.fileName,
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
                      Icon(
                        Icons.lock_outline_rounded,
                        color: DefensysTokens.maroon,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Read-Only Document',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: const Text(
                    'This manuscript is available for authenticated reading only. '
                    'Downloading and unauthorized reproduction are disabled.',
                    style: TextStyle(fontSize: 13),
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
              controller: _pdfViewerController,
              canShowScrollHead: true,
              canShowScrollStatus: true,
              enableDoubleTapZooming: true,
              enableTextSelection: false,
              onDocumentLoaded: (details) {
                _pageCount = details.document.pages.count;
                if (!_opened) {
                  _opened = true;
                  _shelfService.updateShelfProgress(
                    targetId: widget.entry.id,
                    opened: true,
                  );
                  final page = widget.entry.lastReadPage.clamp(1, _pageCount);
                  _currentPage = page;
                  if (page > 1) _pdfViewerController?.jumpToPage(page);
                }
              },
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
                      const Icon(
                        Icons.lock,
                        size: 54,
                        color: DefensysTokens.maroon,
                      ),
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
