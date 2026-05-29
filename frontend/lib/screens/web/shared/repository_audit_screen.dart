import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../services/authenticated_client.dart';
import '../../../services/repository_audit_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/clipboard_copy.dart';
import '../../../utils/pdf_viewer.dart';
import '../../../widgets/defensys_skeleton.dart';
import '../../../widgets/feedback_toast.dart';

class RepositoryAuditScreen extends ConsumerStatefulWidget {
  const RepositoryAuditScreen({super.key});

  @override
  ConsumerState<RepositoryAuditScreen> createState() =>
      _RepositoryAuditScreenState();
}

class _RepositoryAuditScreenState extends ConsumerState<RepositoryAuditScreen> {
  static const _kRepoMinTableWidth = 1515.0;
  static const _kRepoActionColumnWidth = 140.0;
  static const _kRepoDataTableWidth =
      _kRepoMinTableWidth - _kRepoActionColumnWidth;
  static const _kDeliverableMinTableWidth = 1100.0;

  final _searchController = TextEditingController();
  final _tableHScrollController = ScrollController();
  bool _showTableScrollHint = false;

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryAuditProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(state),
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
          _buildVaultSummarySection(state),
          const SizedBox(height: 22),
          _buildUploadQueueSection(state),
          const SizedBox(height: 22),
          _repositoryTableCard(state),
        ],
      ),
    );
  }

  String _scopeKey(RepositoryAuditState state) =>
      state.scope['scope']?.toString() ?? 'admin';

  String _headerSubtitle(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    final year = state.scope['pit_year_level']?.toString() ?? '';
    switch (scope) {
      case 'pit_lead':
        if (state.scope['has_assigned_assistant'] == true) {
          return 'Monitor PIT vault entries for $year. Your assigned Repository Assistant handles uploads.';
        }
        return 'Archive passed PIT projects for $year after the event is officially complete in Grade Center.';
      case 'repo_assistant':
        return 'Upload passed PIT project files for $year after the PIT lead marks the event officially complete.';
      default:
        return 'Browse pre-defense uploads, digital vault items, and final archive PDFs by team or deliverable (e.g. D1 across all teams).';
    }
  }

  bool _showCapstoneUploadQueue(RepositoryAuditState state) {
    if (_scopeKey(state) != 'admin') {
      return false;
    }
    final queue = state.capstoneUploadWindow['queue'];
    return queue is List && queue.isNotEmpty;
  }

  bool _showUploadQueue(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    if (scope != 'pit_lead' && scope != 'repo_assistant') {
      return false;
    }
    final queue = state.uploadWindow['queue'];
    return queue is List && queue.isNotEmpty;
  }

  Widget _buildEmptyQueueBanner(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    if (scope != 'pit_lead' && scope != 'repo_assistant') {
      return const SizedBox.shrink();
    }
    final open = state.uploadWindow['open'] == true;
    final queue = state.uploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (!open || hasQueue) {
      return const SizedBox.shrink();
    }

    final diagnostics = state.uploadWindow['diagnostics'];
    if (diagnostics is! Map) {
      return _notice(
        Icons.info_outline_rounded,
        'No teams are ready to archive yet. Mark the PIT event officially complete in Grade Center so passed teams become ready to archive.',
        const Color(0xFFD97706),
      );
    }

    final diag = Map<String, dynamic>.from(diagnostics);
    final parts = <String>[
      'No teams are ready to archive for your year level.',
    ];
    final forYear = diag['completed_events_for_year'];
    if (forYear is List && forYear.isNotEmpty) {
      parts.add('Completed events for your year: ${forYear.join(', ')}.');
    } else {
      parts.add('No officially complete PIT event matches your year yet.');
    }
    final other = diag['completed_events_other_years'];
    if (other is List && other.isNotEmpty) {
      parts.add('Other completed events: ${other.join(', ')}.');
    }
    final stages = diag['pit_stage_labels'];
    if (stages is List && stages.isNotEmpty) {
      parts.add('Grade event names in use: ${stages.join(', ')}.');
    }
    final unpublished = diag['unpublished_passed_count'];
    if (unpublished is int && unpublished > 0) {
      parts.add(
        '$unpublished team(s) passed but are not published — mark their PIT event officially complete.',
      );
    }
    return _notice(
      Icons.warning_amber_rounded,
      parts.join(' '),
      const Color(0xFFD97706),
    );
  }

  Widget _buildUploadWindowBanner(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    if (scope == 'admin') {
      return const SizedBox.shrink();
    }
    final open = state.uploadWindow['open'] == true;
    final queue = state.uploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (open || hasQueue) {
      return const SizedBox.shrink();
    }
    final hasAssistant = state.scope['has_assigned_assistant'] == true;
    String message;
    if (scope == 'pit_lead' && hasAssistant) {
      message =
          'Uploads are handled by your Repository Assistant. Mark events officially complete in Grade Center, then ask them to post passed team files.';
    } else if (scope == 'repo_assistant') {
      message =
          'Uploads open after the PIT lead marks your year\'s PIT event officially complete in Grade Center (passed teams become ready to archive).';
    } else {
      message =
          'Mark your year\'s PIT event officially complete in Grade Center. Upload PDFs here while teams are ready to archive; Grade Center shows Published after vault save.';
    }
    return _notice(
      Icons.info_outline_rounded,
      message,
      const Color(0xFF2563EB),
    );
  }

  Widget _buildCapstoneEmptyQueueBanner(RepositoryAuditState state) {
    final open = state.capstoneUploadWindow['open'] == true;
    final queue = state.capstoneUploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (open || hasQueue) {
      return const SizedBox.shrink();
    }

    final diagnostics = state.capstoneUploadWindow['diagnostics'];
    if (diagnostics is! Map) {
      return _notice(
        Icons.info_outline_rounded,
        'No Capstone teams are ready to archive yet. Mark a Capstone defense stage officially complete in Grade Center so passed teams become ready to archive.',
        const Color(0xFFD97706),
      );
    }

    final diag = Map<String, dynamic>.from(diagnostics);
    final parts = <String>['No Capstone teams are ready to archive.'];
    final stages = diag['completed_stages'];
    if (stages is List && stages.isNotEmpty) {
      parts.add('Officially complete stages: ${stages.join(', ')}.');
    } else {
      parts.add('No Capstone stage is officially complete yet.');
    }
    final unpublished = diag['unpublished_passed_count'];
    if (unpublished is int && unpublished > 0) {
      parts.add(
        '$unpublished team(s) passed but are not ready for archive — mark the stage officially complete in Grade Center.',
      );
    }
    return _notice(
      Icons.warning_amber_rounded,
      parts.join(' '),
      const Color(0xFFD97706),
    );
  }

  Widget _buildCapstoneUploadWindowBanner(RepositoryAuditState state) {
    final open = state.capstoneUploadWindow['open'] == true;
    final queue = state.capstoneUploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (open || hasQueue) {
      return const SizedBox.shrink();
    }
    return _notice(
      Icons.info_outline_rounded,
      'Capstone archive uploads open after you mark a defense stage officially complete in Grade Center (passed teams at 75% or above become ready to archive).',
      const Color(0xFF2563EB),
    );
  }

  Widget _buildCapstoneUploadQueuePanel(RepositoryAuditState state) {
    final queue = (state.capstoneUploadWindow['queue'] as List?) ?? [];
    final stages =
        (state.capstoneUploadWindow['completed_stages'] as List?)
            ?.map((e) => e.toString())
            .join(', ') ??
        '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capstone ready to archive${stages.isNotEmpty ? ' · $stages' : ''}',
            style: const TextStyle(
              color: AppColors.maroon,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Awaiting PDF means the team passed and still needs a correctly named archive upload.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...queue.map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['team_name']?.toString() ?? 'Team',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          row['project_title']?.toString() ?? '',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          row['stage_label']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          row['suggested_file_name']?.toString() ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Text(
                      'Awaiting PDF',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if ((row['suggested_file_name']?.toString() ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy filename',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => _copySuggestedFileName(
                        row['suggested_file_name']?.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUploadQueuePanel(RepositoryAuditState state) {
    final queue = (state.uploadWindow['queue'] as List?) ?? [];
    final events =
        (state.uploadWindow['completed_events'] as List?)
            ?.map((e) => e.toString())
            .join(', ') ??
        '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to archive${events.isNotEmpty ? ' · $events' : ''}',
            style: const TextStyle(
              color: AppColors.maroon,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Awaiting PDF means the team passed and still needs a correctly named upload—not that Grade Center is incomplete.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...queue.map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final pending = row['vault_status'] == 'pending';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['team_name']?.toString() ?? 'Team',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${row['event_name'] ?? ''} · ${row['project_title'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        SelectableText(
                          row['suggested_file_name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    pending ? 'Awaiting PDF' : 'In vault',
                    style: TextStyle(
                      color: pending
                          ? const Color(0xFFD97706)
                          : const Color(0xFF059669),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (pending &&
                      (row['suggested_file_name']?.toString() ?? '')
                          .isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy filename',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => _copySuggestedFileName(
                        row['suggested_file_name']?.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader(RepositoryAuditState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Repository Vault',
                style: TextStyle(
                  color: AppColors.maroon,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _headerSubtitle(state),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_scopeKey(state) == 'pit_lead' &&
                  state.scope['has_assigned_assistant'] != true) ...[
                const SizedBox(height: 8),
                const Text(
                  'Assign a Repository Assistant on your dashboard to delegate uploads.',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_can(state, 'can_upload_pit')) ...[
              _secondaryButton(
                icon: Icons.cloud_upload_outlined,
                label: 'Upload PIT',
                onTap: state.isSaving ? null : () => _showUploadDialog(state),
              ),
              const SizedBox(width: 12),
            ],
            if (_can(state, 'can_upload_capstone')) ...[
              _secondaryButton(
                icon: Icons.cloud_upload_outlined,
                label: 'Upload Capstone',
                onTap: state.isSaving
                    ? null
                    : () => _showCapstoneUploadDialog(state),
              ),
              const SizedBox(width: 12),
            ],
            _primaryButton(
              icon: Icons.file_download_rounded,
              label: 'Export Vault Records',
              onTap: state.isSaving ? null : _exportCsv,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStats(RepositoryAuditState state) {
    if (_scopeKey(state) == 'admin' &&
        (state.type.isEmpty || state.type == 'capstone')) {
      return Row(
        children: [
          Expanded(
            child: _metricCard(
              title: state.deliverableId.isNotEmpty
                  ? 'Matching records'
                  : 'Total records',
              value: _count(state, 'total'),
              valueColor: const Color(0xFF0F2743),
              icon: Icons.folder_copy_outlined,
              iconTint: const Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: 'Pre-defense',
              value: _count(state, 'pre_defense'),
              valueColor: const Color(0xFF2563EB),
              icon: Icons.upload_file_outlined,
              iconTint: const Color(0xFFBFDBFE),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: 'Vault items',
              value: _count(state, 'vault_submissions'),
              valueColor: const Color(0xFF7C3AED),
              icon: Icons.lock_outline_rounded,
              iconTint: const Color(0xFFDDD6FE),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: state.deliverableId.isNotEmpty
                  ? 'Missing'
                  : 'Archive PDFs',
              value: state.deliverableId.isNotEmpty
                  ? _count(state, 'missing_required')
                  : _count(state, 'archive_pdf'),
              valueColor: const Color(0xFFD97706),
              icon: Icons.archive_outlined,
              iconTint: const Color(0xFFFDE68A),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'Total Managed Records',
            value: _count(state, 'total'),
            valueColor: const Color(0xFF0F2743),
            icon: Icons.folder_copy_outlined,
            iconTint: const Color(0xFFCBD5E1),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Needs Revision',
            value: _count(state, 'needs_revision'),
            valueColor: const Color(0xFFD97706),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFFDE68A),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Approved Vault Entries',
            value: _count(state, 'approved'),
            valueColor: const Color(0xFF059669),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFA7F3D0),
          ),
        ),
      ],
    );
  }

  Widget _buildVaultSummarySection(RepositoryAuditState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Repository Vault Summary',
          'Current archive readiness, vault status, and record counts for your scope.',
        ),
        const SizedBox(height: 12),
        _buildStats(state),
        if (_scopeKey(state) == 'admin') ...[
          const SizedBox(height: 18),
          _buildTypeTabs(state),
          const SizedBox(height: 14),
          _buildKindChips(state),
          if (state.deliverableId.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDeliverableFilterChip(state),
          ],
        ],
      ],
    );
  }

  Widget _buildUploadQueueSection(RepositoryAuditState state) {
    final children = <Widget>[
      _buildUploadWindowBanner(state),
      _buildEmptyQueueBanner(state),
    ];
    if (_showUploadQueue(state)) {
      children
        ..add(const SizedBox(height: 16))
        ..add(_buildUploadQueuePanel(state));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Upload Queue',
          'Teams and files that are ready for PIT or Capstone archive upload.',
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.maroon,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required int value,
    required Color valueColor,
    required IconData icon,
    required Color iconTint,
  }) {
    return Container(
      height: 107,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -26,
            child: Icon(
              icon,
              size: 76,
              color: iconTint.withValues(alpha: 0.34),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repositoryTableCard(RepositoryAuditState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Repository Vault Records',
              style: TextStyle(
                color: AppColors.maroon,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _clearFiltersButton(),
            ],
          ),
          const SizedBox(height: 16),
          if (_scopeKey(state) == 'admin') ...[
            Row(
              children: [
                Expanded(
                  child: _filterFromStrings(
                    value: state.stage,
                    label: 'All Stages',
                    items: _stringList(state.options['stage_options']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(stage: value ?? ''),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: _filterFromMaps(
                    value: state.deliverableId,
                    label: 'All Deliverables',
                    items: _mapList(state.options['deliverable_options']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(
                          deliverableId: value ?? '',
                          clearDeliverable: (value ?? '').isEmpty,
                          clearTeam: (value ?? '').isNotEmpty,
                        ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _filterFromMaps(
                    value: state.status,
                    label: 'All Statuses',
                    items: _mapList(state.options['status_options']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(status: value ?? ''),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _filterFromMaps(
                    value: state.teamId,
                    label: 'All Teams',
                    items: _mapList(state.options['team_counts']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(teamId: value ?? ''),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _filterFromStrings(
                    value: state.stage,
                    label: 'All Stages',
                    items: _stringList(state.options['stage_options']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(stage: value ?? ''),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _filterFromMaps(
                    value: state.status,
                    label: 'All Statuses',
                    items: _mapList(state.options['status_options']),
                    onChanged: (value) => ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(status: value ?? ''),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (state.isLoading && state.entries.isEmpty)
            DefensysSkeleton.list(count: 6, rowHeight: 48)
          else if (state.entries.isEmpty)
            _emptyRepositoryTable()
          else
            _buildEntriesBody(state),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,

            child: Text(
              state.deliverableId.isNotEmpty
                  ? 'Showing ${state.entries.length} teams for ${state.deliverableSummary['label'] ?? state.deliverableId}'
                  : 'Showing ${state.entries.length} records',
              style: const TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(RepositoryAuditState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 19,
          ),
          hintText: 'Search by file name, course, or semester...',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.maroon),
          ),
        ),
        onSubmitted: (value) {
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(search: value);
        },
      ),
    );
  }

  Widget _clearFiltersButton() {
    return SizedBox(
      height: 43,
      child: OutlinedButton.icon(
        onPressed: () {
          _searchController.clear();
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(
                search: '',
                type: '',
                yearLevel: '',
                academicYear: '',
                status: '',
                semester: '',
                teamId: '',
                stage: '',
                deliverableId: '',
                submissionKind: '',
                viewMode: '',
                clearDeliverable: true,
                clearTeam: true,
              );
        },
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Clear Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _filterFromMaps({
    required String value,
    required String label,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty
        ? [
            {'value': '', 'label': label},
          ]
        : [
            {'value': '', 'label': label},
            ...items.where(
              (item) => (item['value']?.toString() ?? '').isNotEmpty,
            ),
          ];

    final values = options
        .map((item) => item['value']?.toString() ?? '')
        .toSet();
    final selected = values.contains(value) ? value : '';

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item['value']?.toString() ?? '',
                  child: Text(
                    item['label']?.toString() ?? label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterFromStrings({
    required String value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = ['', ...items];
    final selected = options.contains(value) ? value : '';

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.isEmpty ? label : item,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterShell({required Widget child}) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: child,
    );
  }

  Widget _tableScrollHint() {
    if (!_showTableScrollHint) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Scroll horizontally for more columns',
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.85),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _wrapWithHorizontalScroll({
    required double minDataWidth,
    required Widget dataPane,
    required Widget? actionColumn,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = actionColumn == null
            ? 0.0
            : _kRepoActionColumnWidth;
        final dataAreaWidth = (constraints.maxWidth - actionWidth).clamp(
          0.0,
          double.infinity,
        );
        final needsHorizontalScroll = dataAreaWidth < minDataWidth;

        Widget pane = dataPane;
        if (needsHorizontalScroll) {
          pane = Scrollbar(
            controller: _tableHScrollController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _tableHScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minDataWidth, child: dataPane),
            ),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateTableScrollHint();
          });
        } else if (_showTableScrollHint && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _showTableScrollHint = false);
          });
        }

        if (actionColumn == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pane, _tableScrollHint()],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pane),
                actionColumn,
              ],
            ),
            _tableScrollHint(),
          ],
        );
      },
    );
  }

  Widget _repositoryTable(RepositoryAuditState state) {
    final compact = state.teamId.isNotEmpty;
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(compactColumns: compact),
          ...entries.map(
            (entry) => _repositoryRowData(entry, compactColumns: compact),
          ),
        ],
      ),
      actionColumn: _repositoryActionColumn(
        entries.map(_repositoryRowAction).toList(),
      ),
    );
  }

  Widget _repositoryHeaderData({bool compactColumns = false}) {
    return Container(
      height: 51,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
      ),
      child: Row(
        children: [
          _tableHeaderCell('File Name', flex: 3.45),
          if (!compactColumns) ...[
            _tableHeaderCell('Year Level', flex: 0.74),
            _tableHeaderCell('Academic Year', flex: 0.94),
            _tableHeaderCell('Course', flex: 0.62),
          ],
          _tableHeaderCell('Semester', flex: 0.78),
          _tableHeaderCell('Status', flex: 0.95),
          _tableHeaderCell('Uploaded', flex: 0.74),
        ],
      ),
    );
  }

  Widget _repositoryActionColumn(
    List<Widget> actionRows, {
    double headerHeight = 51,
  }) {
    return SizedBox(
      width: _kRepoActionColumnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryActionHeader(height: headerHeight),
          ...actionRows,
        ],
      ),
    );
  }

  Widget _repositoryActionHeader({double height = 51}) {
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
        border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: const Text(
        'Action',
        style: TextStyle(
          color: Color(0xFF5D6678),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _repositoryActionSpacer({double height = 40}) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
  }

  Widget _emptyRepositoryTable() {
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(),
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: const Text(
              'No digital vault files found.',
              style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
            ),
          ),
        ],
      ),
      actionColumn: _repositoryActionColumn([
        _repositoryActionSpacer(height: 96),
      ]),
    );
  }

  Widget _repositoryRowData(
    Map<String, dynamic> entry, {
    bool compactColumns = false,
  }) {
    final isPit = entry['type'] == 'pit';
    final isMissing = entry['is_missing'] == true;
    final title = isPit
        ? entry['file_name']?.toString() ?? ''
        : entry['deliverable_label']?.toString() ??
              entry['file_name']?.toString() ??
              '';
    final uploadedBy = entry['uploaded_by']?.toString() ?? 'System';
    final deliverableId = entry['deliverable_id']?.toString() ?? '';

    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deliverableId.isNotEmpty
                            ? '$deliverableId · ${title.isEmpty ? '—' : title}'
                            : (title.isEmpty ? '-' : title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isMissing
                            ? (entry['vault_note']?.toString().isNotEmpty ==
                                      true
                                  ? entry['vault_note'].toString()
                                  : 'No file uploaded yet')
                            : 'By $uploadedBy',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flex: 3.45,
          ),
          if (!compactColumns) ...[
            _tableCell(
              _yearBadge(entry['year_level']?.toString() ?? ''),
              flex: 0.74,
            ),
            _tableCell(
              _bodyText(entry['academic_year']?.toString() ?? ''),
              flex: 0.94,
            ),
            _tableCell(
              _bodyText(entry['course']?.toString() ?? ''),
              flex: 0.62,
            ),
          ],
          _tableCell(
            _bodyText(entry['semester']?.toString() ?? ''),
            flex: 0.78,
          ),
          _tableCell(
            Row(
              children: [
                _kindBadge(entry['submission_kind']?.toString()),
                const SizedBox(width: 6),
                Flexible(
                  child: _statusBadge(entry['status']?.toString() ?? ''),
                ),
              ],
            ),
            flex: 0.95,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.74),
        ],
      ),
    );
  }

  Widget _repositoryRowAction(Map<String, dynamic> entry) {
    final isMissing = entry['is_missing'] == true;
    final hasFile = entry['has_file'] == true && !isMissing;
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: hasFile ? _rowActions(entry) : const SizedBox.shrink(),
    );
  }

  Widget _tableHeaderCell(String label, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _yearBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    final icon = switch (status) {
      'Approved' || 'Vault Submission' => Icons.check_circle_rounded,
      'Needs Revision' => Icons.warning_rounded,
      'Pre-Defense' => Icons.school_rounded,
      _ => Icons.hourglass_empty_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.isEmpty ? 'Approved' : status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> entry) {
    final fileUrl = entry['file_url']?.toString() ?? '';
    final fileName = entry['file_name']?.toString() ?? '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // View button
        _actionIcon(
          tooltip: 'View PDF',
          icon: Icons.visibility_outlined,
          color: const Color(0xFF2563EB),
          onTap: () => _viewPdf(fileUrl, fileName),
        ),
        const SizedBox(width: 3),
        // Download button
        _actionIcon(
          tooltip: 'Download',
          icon: Icons.download_rounded,
          color: const Color(0xFF059669),
          onTap: () => _downloadFile(fileUrl, fileName),
        ),
        if (entry['can_override'] == true) ...[
          const SizedBox(width: 3),
          _actionIcon(
            tooltip: 'Override status',
            icon: Icons.lock_rounded,
            color: AppColors.textSecondary,
            onTap: () => _showOverrideDialog(entry),
          ),
        ],
      ],
    );
  }

  Widget _actionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.maroon,
          foregroundColor: AppColors.gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _prettyDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return _date(value);
    }

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

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Future<void> _showUploadDialog(RepositoryAuditState state) async {
    final yearLevel =
        state.scope['pit_year_level']?.toString().isNotEmpty == true
        ? state.scope['pit_year_level'].toString()
        : '3rd Year';
    final academicYear = state.academicYear.isNotEmpty
        ? state.academicYear
        : (_stringList(state.options['academic_years']).isNotEmpty
              ? _stringList(state.options['academic_years']).first
              : '');
    final pendingNames = _pendingSuggestedFileNames(state);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload PIT PDF'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Each PDF must use this exact pattern (no spaces):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _pitFilenameExample(yearLevel),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF374151),
                ),
              ),
              if (pendingNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Use these names from the archive queue:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...pendingNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
              if (pendingNames.length == 1) ...[
                const SizedBox(height: 10),
                const Text(
                  'A single PDF will be renamed automatically to the queue filename.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose PDFs'),
          ),
        ],
      ),
    );
    if (!mounted || proceed != true) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final autoRename = pendingNames.length == 1 && picked.files.length == 1
        ? pendingNames.first
        : null;

    final multipartFiles = <http.MultipartFile>[];
    for (final platformFile in picked.files) {
      final bytes = platformFile.bytes;
      final originalName = platformFile.name;
      if (bytes == null || !originalName.toLowerCase().endsWith('.pdf')) {
        continue;
      }
      final uploadName = autoRename ?? originalName;
      multipartFiles.add(
        http.MultipartFile.fromBytes('files', bytes, filename: uploadName),
      );
    }

    if (multipartFiles.isEmpty) {
      if (mounted) {
        showValidationToast(context, 'Select at least one PDF file.');
      }
      return;
    }

    final result = await ref
        .read(repositoryAuditProvider.notifier)
        .uploadPit(
          multipartFiles: multipartFiles,
          yearLevel: yearLevel,
          academicYear: academicYear,
        );
    if (!mounted) {
      return;
    }
    if (result.skipped.isNotEmpty) {
      await _showUploadSkippedDialog(result);
    }
  }

  List<String> _pendingSuggestedFileNames(RepositoryAuditState state) {
    final queue = state.uploadWindow['queue'];
    if (queue is! List) {
      return const [];
    }
    return queue
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((row) => row['vault_status'] == 'pending')
        .map((row) => row['suggested_file_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  List<String> _pendingCapstoneSuggestedFileNames(RepositoryAuditState state) {
    final queue = state.capstoneUploadWindow['queue'];
    if (queue is! List) {
      return const [];
    }
    return queue
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .map((row) => row['suggested_file_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> _showCapstoneUploadDialog(RepositoryAuditState state) async {
    final academicYear = state.academicYear.isNotEmpty
        ? state.academicYear
        : (_stringList(state.options['academic_years']).isNotEmpty
              ? _stringList(state.options['academic_years']).first
              : '');
    final pendingNames = _pendingCapstoneSuggestedFileNames(state);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload Capstone PDF'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Each PDF must use this exact pattern (no spaces):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '3rdYear.CAP301.ProjectTitle.1stSemester.pdf',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF374151),
                ),
              ),
              if (pendingNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Use these names from the archive queue:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...pendingNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
              if (pendingNames.length == 1) ...[
                const SizedBox(height: 10),
                const Text(
                  'A single PDF will be renamed automatically to the queue filename.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose PDFs'),
          ),
        ],
      ),
    );
    if (!mounted || proceed != true) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final autoRename = pendingNames.length == 1 && picked.files.length == 1
        ? pendingNames.first
        : null;

    final multipartFiles = <http.MultipartFile>[];
    for (final platformFile in picked.files) {
      final bytes = platformFile.bytes;
      final originalName = platformFile.name;
      if (bytes == null || !originalName.toLowerCase().endsWith('.pdf')) {
        continue;
      }
      final uploadName = autoRename ?? originalName;
      multipartFiles.add(
        http.MultipartFile.fromBytes('files', bytes, filename: uploadName),
      );
    }

    if (multipartFiles.isEmpty) {
      if (mounted) {
        showValidationToast(context, 'Select at least one PDF file.');
      }
      return;
    }

    final result = await ref
        .read(repositoryAuditProvider.notifier)
        .uploadCapstoneMultipart(
          multipartFiles: multipartFiles,
          academicYear: academicYear,
        );
    if (!mounted) {
      return;
    }
    if (result.skipped.isNotEmpty) {
      await _showUploadSkippedDialog(result);
    }
  }

  String _pitFilenameExample(String yearLevel) {
    switch (yearLevel) {
      case '1st Year':
        return '1stYear.PIT101.ProjectTitle.1stSemester.pdf';
      case '2nd Year':
        return '2ndYear.PIT201.ProjectTitle.1stSemester.pdf';
      default:
        return '3rdYear.PIT301.ProjectTitle.1stSemester.pdf';
    }
  }

  Future<void> _showUploadSkippedDialog(UploadPitResult result) async {
    final lines = result.skipped
        .map((item) {
          final name = item['file_name']?.toString() ?? 'File';
          final reason = item['reason']?.toString() ?? 'Unknown reason';
          return '$name\n$reason';
        })
        .join('\n\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.savedAny ? 'Some files were not saved' : 'Upload failed',
        ),
        content: SingleChildScrollView(child: Text(lines)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOverrideDialog(Map<String, dynamic> entry) async {
    String status = entry['status']?.toString() ?? 'Approved';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Override PIT Status'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => _dialogDropdown(
            label: 'Status',
            value: status,
            items: const ['Approved', 'Needs Revision'],
            onChanged: (value) =>
                setDialogState(() => status = value ?? status),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || saved != true) {
      return;
    }
    await ref
        .read(repositoryAuditProvider.notifier)
        .overrideStatus(entry['id'].toString(), status);
  }

  Future<void> _viewPdf(String fileUrl, String fileName) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      await viewPdfInDialog(
        context: context,
        pdfBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  Future<void> _downloadFile(String fileUrl, String fileName) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      await downloadBytesFile(bytes: bytes, fileName: fileName);
      if (!mounted) return;
      showSuccessToast(
        context,
        'Downloaded $fileName',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Download failed: $e');
    }
  }

  Future<void> _exportCsv() async {
    final csv = await ref.read(repositoryAuditProvider.notifier).exportCsv();
    if (!mounted || csv == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repository Vault CSV'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(csv)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _dialogDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty ? [value] : items;
    final selected = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: options
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
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

  Color _statusColor(String status) {
    if (status == 'Approved' || status == 'Vault Submission') {
      return AppColors.success;
    }
    if (status == 'Needs Revision') {
      return AppColors.danger;
    }
    if (status == 'Missing required') {
      return const Color(0xFFD97706);
    }
    if (status == 'Locked') {
      return const Color(0xFF6B7280);
    }
    if (status == 'Pre-Defense') {
      return Colors.blue;
    }
    return AppColors.warning;
  }

  bool _isAdminCapstoneView(RepositoryAuditState state) {
    return _scopeKey(state) == 'admin' &&
        (state.type.isEmpty || state.type == 'capstone');
  }

  bool _isAdminBrowseLayout(RepositoryAuditState state) {
    return _scopeKey(state) == 'admin' && state.type != 'pit';
  }

  bool _isPitEntry(Map<String, dynamic> entry) {
    return entry['type'] == 'pit' || entry['submission_kind'] == 'pit';
  }

  bool _isCapstoneEntry(Map<String, dynamic> entry) {
    return !_isPitEntry(entry);
  }

  String _teamTrack(Map<String, dynamic> team) {
    final track = team['track']?.toString() ?? '';
    if (track == 'pit') return 'pit';
    if (track == 'capstone') return 'capstone';
    final level = team['level']?.toString() ?? '';
    if (level.contains('PIT')) return 'pit';
    if (level.contains('Capstone')) return 'capstone';
    return '';
  }

  Map<String, dynamic>? _selectedTeamMeta(RepositoryAuditState state) {
    if (state.teamId.isEmpty) return null;
    final teams = _mapList(state.options['team_counts']);
    for (final team in teams) {
      if (team['id']?.toString() == state.teamId) {
        return team;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _entriesForTeam(
    RepositoryAuditState state, {
    required String track,
  }) {
    return state.entries.where((entry) {
      if (entry['team_id']?.toString() != state.teamId) return false;
      return track == 'pit' ? _isPitEntry(entry) : _isCapstoneEntry(entry);
    }).toList();
  }

  Widget _browseModeTip(RepositoryAuditState state) {
    if (state.deliverableId.isNotEmpty || state.teamId.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Pick a deliverable to compare all teams. Pick a team to see that team\'s full file list.',
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.9),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTypeTabs(RepositoryAuditState state) {
    Widget tab(String label, String typeValue, bool selected) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: state.isSaving
              ? null
              : (_) {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(
                        type: typeValue,
                        clearTeam: true,
                        clearDeliverable: true,
                      );
                },
          selectedColor: AppColors.maroon,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Capstone', 'capstone', state.type == 'capstone'),
        tab('PIT', 'pit', state.type == 'pit'),
        tab('All records', '', state.type.isEmpty),
      ],
    );
  }

  Widget _buildKindChips(RepositoryAuditState state) {
    if (!_isAdminCapstoneView(state)) {
      return const SizedBox.shrink();
    }
    const kinds = [
      ('', 'All kinds'),
      ('pre', 'Pre-defense'),
      ('vault', 'Digital vault'),
      ('archive', 'Archive PDF'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kinds.map((item) {
        final selected = state.submissionKind == item.$1;
        return FilterChip(
          label: Text(item.$2),
          selected: selected,
          onSelected: state.isSaving
              ? null
              : (_) {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(submissionKind: item.$1);
                },
          selectedColor: AppColors.maroon.withValues(alpha: 0.15),
          checkmarkColor: AppColors.maroon,
        );
      }).toList(),
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
            '${_asInt(summary['uploaded_count'])} uploaded · ${_asInt(summary['missing_count'])} missing',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildEntriesBody(RepositoryAuditState state) {
    if (!_isAdminBrowseLayout(state)) {
      return _repositoryTable(state);
    }
    if (state.deliverableId.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_browseModeTip(state), _repositoryDeliverableTable(state)],
      );
    }
    if (state.teamId.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 260, child: _buildTeamSidebar(state)),
          const SizedBox(width: 18),
          Expanded(child: _buildTeamDetailPanel(state)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 260, child: _buildTeamSidebar(state)),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_browseModeTip(state), _buildAllTeamsBrowsePanel(state)],
          ),
        ),
      ],
    );
  }

  Widget _buildTeamSidebar(RepositoryAuditState state) {
    final teams = _mapList(state.options['team_counts']);
    final capstoneTeams = teams
        .where((team) => _teamTrack(team) == 'capstone')
        .toList();
    final pitTeams = teams.where((team) => _teamTrack(team) == 'pit').toList();
    final showCapstone = state.type.isEmpty || state.type == 'capstone';
    final showPit = state.type.isEmpty;

    Widget teamSection(String title, List<Map<String, dynamic>> sectionTeams) {
      if (sectionTeams.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          ...sectionTeams.map((team) {
            final id = team['id']?.toString() ?? '';
            final name = team['name']?.toString() ?? 'Team';
            final level = team['level']?.toString() ?? '';
            final project =
                _teamProjectFromEntries(state, id) ??
                team['name']?.toString() ??
                '';
            final track = _teamTrack(team);
            final pre = _asInt(team['pre']);
            final vault = _asInt(team['vault']);
            final archive = _asInt(team['archive']);
            final counts = track == 'pit'
                ? '$archive archive'
                : '$pre pre · $vault vault · $archive archive';
            final subtitle = [
              if (level.isNotEmpty) level,
              if (project.isNotEmpty && project != name) project,
              counts,
            ].join(' · ');
            return _sidebarTeamTile(state, id, name, subtitle, track: track);
          }),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEAMS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          _sidebarTeamTile(state, null, 'All teams', null),
          if (showCapstone) teamSection('CAPSTONE TEAMS', capstoneTeams),
          if (showPit) teamSection('PIT TEAMS', pitTeams),
        ],
      ),
    );
  }

  String? _teamProjectFromEntries(RepositoryAuditState state, String teamId) {
    for (final entry in state.entries) {
      if (entry['team_id']?.toString() == teamId) {
        final project = entry['project_title']?.toString() ?? '';
        if (project.isNotEmpty) return project;
      }
    }
    return null;
  }

  Widget _sidebarTeamTile(
    RepositoryAuditState state,
    String? teamId,
    String label,
    String? subtitle, {
    String track = '',
  }) {
    final selected = (teamId ?? '') == state.teamId;
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: state.isSaving
            ? null
            : () {
                if (teamId == null) {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(clearTeam: true);
                } else {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(teamId: teamId, clearDeliverable: true);
                }
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.maroon : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: selected
                        ? AppColors.maroon
                        : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: selected
                            ? AppColors.maroon
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (track.isNotEmpty) _trackBadge(track),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackBadge(String track) {
    final isPit = track == 'pit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isPit ? const Color(0xFF2563EB) : AppColors.maroon).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isPit ? 'PIT' : 'Capstone',
        style: TextStyle(
          color: isPit ? const Color(0xFF2563EB) : AppColors.maroon,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _teamDetailHeader(RepositoryAuditState state) {
    final team = _selectedTeamMeta(state);
    if (team == null) return const SizedBox.shrink();
    final name = team['name']?.toString() ?? 'Team';
    final level = team['level']?.toString() ?? '';
    final track = _teamTrack(team);
    final project = _teamProjectFromEntries(state, state.teamId) ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.maroon,
                ),
              ),
              const SizedBox(width: 8),
              _trackBadge(track),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (level.isNotEmpty) level,
              if (project.isNotEmpty) 'Project: $project',
            ].join(' · '),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Showing files for this team only.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamDetailPanel(RepositoryAuditState state) {
    final team = _selectedTeamMeta(state);
    final track = team == null ? '' : _teamTrack(team);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _teamDetailHeader(state),
        if (track == 'pit')
          _buildPitGroupedPanel(
            _entriesForTeam(state, track: 'pit'),
            compactColumns: true,
          )
        else
          _buildCapstoneGroupedPanel(
            state,
            entries: _entriesForTeam(state, track: 'capstone'),
            compactColumns: true,
          ),
      ],
    );
  }

  Widget _buildAllTeamsBrowsePanel(RepositoryAuditState state) {
    if (state.type == 'capstone') {
      return _buildCapstoneGroupedPanel(
        state,
        entries: state.entries.where(_isCapstoneEntry).toList(),
      );
    }
    final capstoneEntries = state.entries.where(_isCapstoneEntry).toList();
    final pitEntries = state.entries.where(_isPitEntry).toList();
    if (capstoneEntries.isEmpty && pitEntries.isEmpty) {
      return _emptyRepositoryTable();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capstoneEntries.isNotEmpty) ...[
          _trackSectionTitle('CAPSTONE', AppColors.maroon),
          _buildCapstoneGroupedPanel(state, entries: capstoneEntries),
          const SizedBox(height: 20),
        ],
        if (pitEntries.isNotEmpty) ...[
          _trackSectionTitle('PIT', const Color(0xFF2563EB)),
          _buildPitGroupedPanel(pitEntries),
        ],
      ],
    );
  }

  Widget _trackSectionTitle(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapstoneGroupedPanel(
    RepositoryAuditState state, {
    required List<Map<String, dynamic>> entries,
    bool compactColumns = false,
  }) {
    final groups = state.teamId.isNotEmpty && state.groupedByStage.isNotEmpty
        ? state.groupedByStage
        : _clientGroupByStage(entries, capstoneOnly: true);
    if (groups.isEmpty) {
      if (entries.isNotEmpty) {
        return _wrapWithHorizontalScroll(
          minDataWidth: _kRepoDataTableWidth,
          dataPane: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _repositoryHeaderData(compactColumns: compactColumns),
              ...entries.map(
                (entry) =>
                    _repositoryRowData(entry, compactColumns: compactColumns),
              ),
            ],
          ),
          actionColumn: _repositoryActionColumn(
            entries.map(_repositoryRowAction).toList(),
          ),
        );
      }
      return _wrapGroupedTable(
        dataChildren: [
          _repositoryHeaderData(compactColumns: compactColumns),
          if (entries.isEmpty)
            Container(
              height: 72,
              alignment: Alignment.center,
              child: const Text(
                'No Capstone files found.',
                style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
              ),
            ),
        ],
        actionChildren: entries.isEmpty
            ? [_repositoryActionSpacer(height: 72)]
            : [],
      );
    }
    return _buildCapstoneGroupsContent(groups, compactColumns: compactColumns);
  }

  Widget _buildCapstoneGroupsContent(
    List<Map<String, dynamic>> groups, {
    bool compactColumns = false,
  }) {
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];
    final actionChildren = <Widget>[];
    const subsectionHeight = 40.0;

    for (final group in groups) {
      final stage = group['stage']?.toString() ?? '';
      final preRows = _mapList(group['pre_defense']);
      final vaultRows = _mapList(group['vault']);
      final archiveRows = _mapList(group['archive']);
      if (preRows.isEmpty && vaultRows.isEmpty && archiveRows.isEmpty) {
        continue;
      }

      dataChildren.add(_stageTitle(stage));
      actionChildren.add(_repositoryActionSpacer(height: 32));

      void addSubsection(
        String title,
        Color color,
        List<Map<String, dynamic>> rows,
      ) {
        if (rows.isEmpty) return;
        dataChildren.add(_subsectionHeader(title, color));
        actionChildren.add(_repositoryActionSpacer(height: subsectionHeight));
        for (final row in rows) {
          dataChildren.add(
            _repositoryRowData(row, compactColumns: compactColumns),
          );
          actionChildren.add(_repositoryRowAction(row));
        }
      }

      addSubsection(
        'Pre-defense deliverables',
        const Color(0xFFEFF6FF),
        preRows,
      );
      addSubsection(
        'Digital vault deliverables',
        const Color(0xFFF5F3FF),
        vaultRows,
      );
      addSubsection('Final archive PDF', const Color(0xFFFFF7ED), archiveRows);
      dataChildren.add(const SizedBox(height: 12));
      actionChildren.add(_repositoryActionSpacer(height: 12));
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      actionChildren: actionChildren,
    );
  }

  Widget _buildPitGroupedPanel(
    List<Map<String, dynamic>> entries, {
    bool compactColumns = false,
  }) {
    final groups = _clientGroupByPitCourse(entries);
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];
    final actionChildren = <Widget>[];
    const subsectionHeight = 40.0;

    if (groups.isEmpty) {
      dataChildren.add(
        Container(
          height: 72,
          alignment: Alignment.center,
          child: const Text(
            'No PIT archive files found.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
          ),
        ),
      );
      actionChildren.add(_repositoryActionSpacer(height: 72));
      return _wrapGroupedTable(
        dataChildren: dataChildren,
        actionChildren: actionChildren,
      );
    }

    for (final group in groups) {
      final course = group['stage']?.toString() ?? 'PIT';
      final rows = _mapList(group['pit_archive']);
      if (rows.isEmpty) continue;

      dataChildren.add(_stageTitle(course, color: const Color(0xFF2563EB)));
      actionChildren.add(_repositoryActionSpacer(height: 32));
      dataChildren.add(
        _subsectionHeader('PIT archive', const Color(0xFFFFF7ED)),
      );
      actionChildren.add(_repositoryActionSpacer(height: subsectionHeight));
      for (final row in rows) {
        dataChildren.add(
          _repositoryRowData(row, compactColumns: compactColumns),
        );
        actionChildren.add(_repositoryRowAction(row));
      }
      dataChildren.add(const SizedBox(height: 12));
      actionChildren.add(_repositoryActionSpacer(height: 12));
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      actionChildren: actionChildren,
    );
  }

  Widget _wrapGroupedTable({
    required List<Widget> dataChildren,
    required List<Widget> actionChildren,
  }) {
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: dataChildren,
      ),
      actionColumn: _repositoryActionColumn(actionChildren),
    );
  }

  Widget _stageTitle(String stage, {Color color = AppColors.maroon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        stage.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _clientGroupByStage(
    List<Map<String, dynamic>> entries, {
    bool capstoneOnly = false,
  }) {
    final scoped = capstoneOnly
        ? entries.where(_isCapstoneEntry).toList()
        : entries;
    final stages = <String>{};
    for (final entry in scoped) {
      final stage = entry['stage']?.toString() ?? '';
      if (stage.isNotEmpty) stages.add(stage);
    }
    return stages.map((stage) {
      final stageEntries = scoped
          .where((entry) => entry['stage'] == stage)
          .toList();
      return {
        'stage': stage,
        'pre_defense': stageEntries
            .where((entry) => entry['submission_kind'] == 'pre')
            .toList(),
        'vault': stageEntries
            .where((entry) => entry['submission_kind'] == 'vault')
            .toList(),
        'archive': stageEntries
            .where((entry) => entry['submission_kind'] == 'archive')
            .toList(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _clientGroupByPitCourse(
    List<Map<String, dynamic>> entries,
  ) {
    final pitEntries = entries.where(_isPitEntry).toList();
    final courses = <String>{};
    for (final entry in pitEntries) {
      final course =
          entry['stage']?.toString() ?? entry['course_code']?.toString() ?? '';
      if (course.isNotEmpty) courses.add(course);
    }
    return courses.map((course) {
      final courseEntries = pitEntries.where((entry) {
        final stage = entry['stage']?.toString() ?? '';
        final code = entry['course_code']?.toString() ?? '';
        return stage == course || code == course;
      }).toList();
      return {'stage': course, 'pit_archive': courseEntries};
    }).toList();
  }

  Widget _subsectionHeader(String title, Color background) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _repositoryDeliverableTable(RepositoryAuditState state) {
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minDataWidth: _kDeliverableMinTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _deliverableFocusHeader(state),
          const SizedBox(height: 12),
          _deliverableTableHeaderData(),
          ...entries.map(_repositoryDeliverableRowData),
        ],
      ),
      actionColumn: _repositoryActionColumn(
        entries.map(_repositoryDeliverableRowAction).toList(),
        headerHeight: 44,
      ),
    );
  }

  Widget _deliverableFocusHeader(RepositoryAuditState state) {
    final summary = state.deliverableSummary;
    final label = summary['label']?.toString() ?? state.deliverableId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.maroon,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'One row per Capstone team for this deliverable. Use Stage to narrow by defense phase.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _deliverableTableHeaderData() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
      ),
      child: Row(
        children: [
          _tableHeaderCell('Team', flex: 1.2),
          _tableHeaderCell('Project', flex: 1.4),
          _tableHeaderCell('Stage', flex: 0.9),
          _tableHeaderCell('File', flex: 1.6),
          _tableHeaderCell('Status', flex: 0.8),
          _tableHeaderCell('Uploaded', flex: 0.7),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowData(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            _bodyText(entry['team_name']?.toString() ?? ''),
            flex: 1.2,
          ),
          _tableCell(
            _bodyText(entry['project_title']?.toString() ?? ''),
            flex: 1.4,
          ),
          _tableCell(_bodyText(entry['stage']?.toString() ?? ''), flex: 0.9),
          _tableCell(
            _bodyText(hasFile ? (entry['file_name']?.toString() ?? '') : '—'),
            flex: 1.6,
          ),
          _tableCell(
            _statusBadge(entry['status']?.toString() ?? ''),
            flex: 0.8,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.7),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowAction(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: hasFile ? _rowActions(entry) : const SizedBox.shrink(),
    );
  }

  Widget _kindBadge(String? kind) {
    final label = switch (kind) {
      'pre' => 'Pre-defense',
      'vault' => 'Vault',
      'archive' => 'Archive',
      'pit' => 'PIT',
      _ => 'File',
    };
    final color = switch (kind) {
      'pre' => const Color(0xFF2563EB),
      'vault' => const Color(0xFF7C3AED),
      'archive' => AppColors.maroon,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  bool _can(RepositoryAuditState state, String key) {
    return state.scope[key] == true;
  }

  String _date(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '-';
    return text.split('T').first;
  }

  int _count(RepositoryAuditState state, String key) {
    return _asInt(state.counts[key]);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }
}
