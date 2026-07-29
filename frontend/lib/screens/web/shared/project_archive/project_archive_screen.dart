import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/widgets/feedback_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'components/project_archive_table.dart';
import 'components/project_archive_summary_cards.dart';
import 'dialogs/archive_resubmission_dialog.dart';

typedef RepositoryAuditScreen = ProjectArchiveScreen;

class ProjectArchiveScreen extends ConsumerStatefulWidget {
  const ProjectArchiveScreen({super.key});

  @override
  ConsumerState<ProjectArchiveScreen> createState() =>
      _ProjectArchiveScreenState();
}

class _ProjectArchiveScreenState
    extends ConsumerState<ProjectArchiveScreen> {
  final _searchController = TextEditingController();
  final _tableHScrollController = ScrollController();
  bool _showTableScrollHint = false;
  bool _showAdvancedFilters = false;

  @override
  void initState() {
    super.initState();
    _tableHScrollController.addListener(_updateTableScrollHint);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryAuditProvider.notifier).fetchEntries();
    });
  }

  @override
  void dispose() {
    _tableHScrollController.removeListener(_updateTableScrollHint);
    _tableHScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateTableScrollHint() {
    if (!_tableHScrollController.hasClients) {
      if (_showTableScrollHint && mounted) {
        setState(() => _showTableScrollHint = false);
      }
      return;
    }
    final show = _tableHScrollController.position.maxScrollExtent > 4;
    if (show != _showTableScrollHint && mounted) {
      setState(() => _showTableScrollHint = show);
    }
  }

  Future<void> _copySuggestedFileName(String? rawName) async {
    final name = rawName?.trim() ?? '';
    if (name.isEmpty) {
      return;
    }
    final copied = await copyTextToClipboard(name);
    if (!mounted) {
      return;
    }
    if (copied) {
      showInfoToast(context, 'Copied $name');
    } else {
      showValidationToast(
        context,
        'Copy failed — select the filename below and copy manually',
      );
    }
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildTypeTabs(RepositoryAuditState state) {
    Widget tab(String label, String typeValue, bool selected) {
      return InkWell(
        onTap: state.isSaving
            ? null
            : () {
                ref.read(repositoryAuditProvider.notifier).fetchEntries(
                      type: typeValue,
                      clearTeam: true,
                      clearDeliverable: true,
                    );
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.maroon : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.maroon : const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE5E7EB),
            width: 1.2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          tab('Capstone', 'capstone', state.type == 'capstone'),
          tab('PIT', 'pit', state.type == 'pit'),
          tab('All records', '', state.type.isEmpty),
        ],
      ),
    );
  }

  Widget _buildDeliverableFilterChip(RepositoryAuditState state) {
    final summary = state.deliverableSummary;
    final label = summary['label']?.toString() ?? state.deliverableId;
    return Row(
      children: [
        Chip(
          avatar: const Icon(
            Icons.filter_alt,
            size: 16,
            color: AppColors.maroon,
          ),
          label: Text('Filtered: $label'),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: state.isSaving
              ? null
              : () {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(clearDeliverable: true);
                },
        ),
        const SizedBox(width: 12),
        if (summary.isNotEmpty)
          Text(
            '${summary['uploaded_count']} uploaded · ${summary['missing_count']} missing',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryAuditProvider);

    final mainContent = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuditSummaryCards(
            state: state,
            onExportCsv: () => StatusOverrideDialog.exportCsv(
              context: context,
              ref: ref,
            ),
            onCopySuggestedFileName: _copySuggestedFileName,
            typeTabs: _buildTypeTabs(state),
            deliverableFilterChip: _buildDeliverableFilterChip(state),
          ),
          const SizedBox(height: 16),
          if (state.error != null) ...[
            _notice(
              Icons.error_outline_rounded,
              state.error!,
              AppColors.danger,
            ),
            const SizedBox(height: 14),
          ],
          if (state.message != null) ...[
            _notice(
              state.lastUploadSkipped.isNotEmpty
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              state.message!,
              state.lastUploadSkipped.isNotEmpty
                  ? const Color(0xFFD97706)
                  : AppColors.success,
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 22),
          ProjectArchiveTable(
            state: state,
            searchController: _searchController,
            tableHScrollController: _tableHScrollController,
            showTableScrollHint: _showTableScrollHint,
            showAdvancedFilters: _showAdvancedFilters,
            onToggleAdvancedFilters: () {
              setState(() {
                _showAdvancedFilters = !_showAdvancedFilters;
              });
            },
            onViewPdf: (fileUrl, fileName) => StatusOverrideDialog.viewPdf(
              context: context,
              ref: ref,
              fileUrl: fileUrl,
              fileName: fileName,
            ),
            onDownloadFile: (fileUrl, fileName) => StatusOverrideDialog.downloadFile(
              context: context,
              ref: ref,
              fileUrl: fileUrl,
              fileName: fileName,
            ),
            onOverrideStatus: (entry) => StatusOverrideDialog.showOverrideDialog(
              context: context,
              ref: ref,
              entry: entry,
            ),
          ),
        ],
      ),
    );

    if (state.isSaving) {
      return Stack(
        children: [
          mainContent,
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    width: 340,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.maroon),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Uploading files to vault...',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: state.uploadProgress,
                            color: AppColors.success,
                            backgroundColor:
                                AppColors.success.withValues(alpha: 0.12),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(state.uploadProgress * 100).toStringAsFixed(0)}% uploaded',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return mainContent;
  }
}
