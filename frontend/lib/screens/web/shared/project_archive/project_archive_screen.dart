import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'components/project_archive_table.dart';
import 'components/project_archive_summary_cards.dart';
import 'dialogs/archive_resubmission_dialog.dart';
import 'dialogs/stage_access_management_dialog.dart';

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
    Widget segment(String label, String typeValue, bool selected) {
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
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: const Color(0xFFE2E8F0))
                : Border.all(color: Colors.transparent),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.maroon : const Color(0xFF64748B),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('Capstone', 'capstone', state.type == 'capstone'),
          const SizedBox(width: 4),
          segment('PIT', 'pit', state.type == 'pit'),
          const SizedBox(width: 4),
          segment('All records', '', state.type.isEmpty),
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
            onManageProgramStageAccess: () {
              final scopeKey = state.scope['scope']?.toString() ?? 'admin';
              final programScope = (scopeKey == 'pit_lead' || state.type.toLowerCase() == 'pit') ? 'pit' : 'capstone';
              // For PIT Leads use their backend-assigned year level, not the filter
              final pitYearLevel = state.scope['pit_year_level']?.toString() ?? '';
              final effectiveYearLevel = pitYearLevel.isNotEmpty
                  ? pitYearLevel
                  : (state.yearLevel.isNotEmpty ? state.yearLevel : null);
              StageAccessManagementDialog.show(
                context: context,
                ref: ref,
                scope: 'global',
                programScope: programScope,
                yearLevel: effectiveYearLevel,
                state: state,
              );
            },
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
