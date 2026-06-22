import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/weekly_progress_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_toast.dart';
import '../../../utils/progress_upload.dart';
import '../../../services/auth_provider.dart';
import '../../../utils/pdf_viewer.dart';

String _formatUploadFailureMessage(int statusCode, String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) {
        return 'Upload failed: $detail';
      }
      final lines = <String>[];
      decoded.forEach((key, value) {
        if (value is List) {
          for (final item in value) {
            lines.add('$key: $item');
          }
        } else {
          lines.add('$key: $value');
        }
      });
      if (lines.isNotEmpty) {
        return 'Upload failed: ${lines.join(' ')}';
      }
    }
  } catch (_) {
    // Not JSON (e.g. legacy HTML error page).
  }
  if (responseBody.contains('<!DOCTYPE html>') ||
      responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Check backend logs or try again.';
  }
  final trimmed = responseBody.trim();
  if (trimmed.isEmpty) {
    return 'Upload failed (status $statusCode).';
  }
  return 'Upload failed: $trimmed';
}

class TeamDeliverablesScreen extends ConsumerStatefulWidget {
  final String? initialScope;
  const TeamDeliverablesScreen({super.key, this.initialScope});

  @override
  ConsumerState<TeamDeliverablesScreen> createState() =>
      _TeamDeliverablesScreenState();
}

class _TeamDeliverablesScreenState
    extends ConsumerState<TeamDeliverablesScreen> {
  final _searchController = TextEditingController();
  Timer? _pendingRemoveTimer;
  bool _pendingRemoveCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
        scope: widget.initialScope,
      );
    });
  }

  @override
  void dispose() {
    _pendingRemoveTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.scope == 'pit' ? 'PIT Deliverables' : 'Capstone Deliverables'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: state.isSaving
                  ? null
                  : () => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .fetchDeliverables(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () =>
              ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(state),
                    const SizedBox(height: 20),
                    _buildStats(state),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      _notice(
                        Icons.error_outline,
                        state.error!,
                        AppColors.danger,
                      ),
                    ],
                    if (state.message != null) ...[
                      const SizedBox(height: 12),
                      _notice(
                        Icons.check_circle_outline,
                        state.message!,
                        AppColors.success,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.textSecondary,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.maroon,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.maroon.withValues(alpha: 0.20),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Deliverables'),
                          Tab(text: 'Teams & Grades'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Consumer(
                      builder: (context, ref, _) {
                        final tabController = DefaultTabController.of(context);
                        return AnimatedBuilder(
                          animation: tabController,
                          builder: (context, _) {
                            final index = tabController.index;
                            if (index == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildToolbar(state),
                                  if (_stageNotConfigured(state)) ...[
                                    const SizedBox(height: 12),
                                    _notice(
                                      Icons.info_outline,
                                      state.scope == 'pit'
                                          ? 'No deliverables configured for ${state.selectedStage}. '
                                            'Add them in PIT Event Settings.'
                                          : 'No deliverables configured for ${state.selectedStage}. '
                                            'Add them in Defense Stages so Required progress can be tracked.',
                                      AppColors.gold,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  if (state.isLoading)
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(32),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else
                                    _buildTeamList(state),
                                ],
                              );
                            } else {
                              return _buildTeamsAndGradesTab(state);
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(CapstoneDeliverablesState state) {
    final title = state.scope == 'pit' ? 'PIT Deliverables' : 'Capstone Deliverables';
    final defaultSubtitle = state.scope == 'pit'
        ? 'Upload pre-event requirements and complete deliverables for PIT events.'
        : 'Upload pre-defense requirements and unlock vault submissions after defense.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.activeSemester?['display_name']?.toString() ?? defaultSubtitle,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStats(CapstoneDeliverablesState state) {
    final teamLabel = state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams';
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _stat(
          teamLabel,
          _count(state, 'teams'),
          Icons.groups_2_outlined,
          AppColors.maroon,
        ),
        _stat(
          'Ready',
          _count(state, 'ready'),
          Icons.verified_outlined,
          AppColors.success,
        ),
        _stat(
          'Missing',
          _count(state, 'missing_requirements'),
          Icons.warning_amber_outlined,
          AppColors.warning,
        ),
        _stat(
          'Files',
          _count(state, 'submitted_files'),
          Icons.folder_copy_outlined,
          Colors.blue,
        ),
        _stat(
          'Vault Files',
          _count(state, 'vault_files'),
          Icons.inventory_2_outlined,
          AppColors.gold,
        ),
      ],
    );
  }

  Widget _stat(String label, int count, IconData icon, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _iconBox(icon, color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _toolbarInputDec({required String label, IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
    );
  }

  Widget _buildToolbar(CapstoneDeliverablesState state) {
    final List<String> stageOptions = _uniqueStrings(state.stageOptions);
    final selectedStage = stageOptions.contains(state.selectedStage)
        ? state.selectedStage
        : null;
    final List<Map<String, dynamic>> statuses = state.statuses.isEmpty
        ? const <Map<String, dynamic>>[
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
          ]
        : state.statuses;

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _searchController,
              decoration: _toolbarInputDec(
                label: 'Search team, project, adviser',
                prefixIcon: Icons.search,
              ),
              style: const TextStyle(
                fontSize: 13,
              ),
              onSubmitted: (value) => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .fetchDeliverables(search: value),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: selectedStage,
              decoration: _toolbarInputDec(
                label: state.scope == 'pit' ? 'PIT Event' : 'Stage View',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              hint: Text(
                stageOptions.isEmpty
                    ? (state.scope == 'pit' ? 'No events configured' : 'No stages configured')
                    : 'Select stage',
                style: const TextStyle(fontSize: 13),
              ),
              items: stageOptions
                  .map(
                    (stage) => DropdownMenuItem(
                      value: stage,
                      child: Text(
                        stage,
                        style: const TextStyle(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: stageOptions.isEmpty
                  ? null
                  : (value) => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .fetchDeliverables(
                          selectedStage: value ?? selectedStage ?? '',
                        ),
            ),
          ),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String>(
              initialValue: state.status,
              decoration: _toolbarInputDec(label: 'Status'),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              isExpanded: true,
              items: statuses
                  .map(
                    (item) => DropdownMenuItem(
                      value: item['value']?.toString() ?? '',
                      child: Text(
                        item['label']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .fetchDeliverables(status: value ?? ''),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              _searchController.clear();
              ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .fetchDeliverables(search: '', status: '');
            },
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text(
              'Clear Filters',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  Widget _buildTeamList(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      final emptyTitle = state.scope == 'pit' ? 'No PIT teams found' : 'No Capstone teams found';
      final emptySubtitle = state.scope == 'pit'
          ? 'Assign PIT teams first.'
          : 'Assign Capstone teams and advisers first.';
      return Container(
        decoration: _cardDecoration(),
        width: double.infinity,
        padding: const EdgeInsets.all(34),
        child: Column(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 42,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 10),
              Text(
                emptyTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
      );
    }

    return Column(
      children: state.teams.map((team) => _teamCard(state, team)).toList(),
    );
  }

  Widget _teamCard(CapstoneDeliverablesState state, Map<String, dynamic> team) {
    final selectedStage = Map<String, dynamic>.from(
      team['selected_stage'] as Map? ?? const {},
    );
    final requiredUploaded = _asInt(selectedStage['required_uploaded']);
    final requiredTotal = _asInt(selectedStage['required_total']);
    final configured = selectedStage['deliverables_configured'] == true;
    final complete = selectedStage['required_complete'] == true;
    final endorsed = selectedStage['endorsed'] == true;
    final canEndorse = configured && complete && !endorsed;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Team details & status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team['project_title']?.toString() ?? '',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(
                            team['year_level']?.toString() ?? '',
                            AppColors.gold,
                          ),
                          _chip(
                            'Adviser: ${team['adviser_name'] ?? 'Unassigned'}',
                            AppColors.maroon,
                          ),
                          _chip(
                            '${team['submitted_count'] ?? 0} submitted',
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _statusChip(complete, endorsed),
              ],
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(color: Color(0xFFF1F5F9), height: 1),
            ),
            
            // Progress blocks layout (Two columns wrapped in Row/Wrap)
            LayoutBuilder(
              builder: (context, constraints) {
                final useVerticalLayout = constraints.maxWidth < 600;
                
                final reqBlock = Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: _requiredProgressBlock(
                    configured: configured,
                    done: requiredUploaded,
                    total: requiredTotal,
                  ),
                );
                
                final vaultBlock = Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: _vaultProgressBlock(selectedStage),
                );

                if (useVerticalLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      reqBlock,
                      const SizedBox(height: 12),
                      vaultBlock,
                    ],
                  );
                }
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: reqBlock),
                    const SizedBox(width: 14),
                    Expanded(child: vaultBlock),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 18),
            
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canEndorse) ...[
                  ElevatedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Endorse Team'),
                                content: Text(
                                  'Endorse ${team['name']} for ${state.selectedStage}? '
                                  'This confirms all required deliverables are complete '
                                  'and the team is ready for defense scheduling.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('Endorse'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted) {
                              await ref
                                  .read(capstoneDeliverablesProvider.notifier)
                                  .endorseTeam(
                                    _asInt(team['id']),
                                    state.selectedStage,
                                  );
                            }
                          },
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text(
                      'Endorse Team',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                ElevatedButton.icon(
                  onPressed: state.isSaving
                      ? null
                      : () => _showTeamDialog(team),
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text(
                    'Manage Files',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.maroon,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _stageNotConfigured(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      return false;
    }
    final stage = state.teams.first['selected_stage'];
    if (stage is! Map) {
      return false;
    }
    return stage['deliverables_configured'] != true;
  }

  Widget _requiredProgressBlock({
    required bool configured,
    required int done,
    required int total,
  }) {
    final emptyLabel = configured
        ? 'Required — No required items'
        : 'Required — Not configured';
    return _progressBlock(
      'Required',
      done,
      total,
      AppColors.success,
      emptyLabel: emptyLabel,
    );
  }

  Widget _vaultProgressBlock(Map<String, dynamic> selectedStage) {
    final unlocked = selectedStage['vault_unlocked'] == true;
    final done = _asInt(selectedStage['vault_required_uploaded']);
    final total = _asInt(selectedStage['vault_required_total']);

    if (!unlocked) {
      return _progressBlock(
        'Vault',
        0,
        0,
        AppColors.gold,
        emptyLabel: 'Vault — Locked until defense done',
      );
    }
    if (total == 0) {
      return _progressBlock(
        'Vault',
        0,
        0,
        AppColors.gold,
        emptyLabel: 'Vault — No required items',
      );
    }
    return _progressBlock('Vault', done, total, AppColors.gold);
  }

  Widget _progressBlock(
    String label,
    int done,
    int total,
    Color color, {
    String? emptyLabel,
  }) {
    if (total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emptyLabel ?? '$label — Not configured',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: 0,
              color: color.withValues(alpha: 0.35),
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      );
    }

    final pct = done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label ($done/$total)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: pct,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  void _showTeamDialog(Map<String, dynamic> team) {
    final teamId = team['id'];
    String selectedStage = ref.read(capstoneDeliverablesProvider).selectedStage;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, child) {
            final state = ref.watch(capstoneDeliverablesProvider);
            final currentTeam = state.teams.firstWhere(
              (t) => t['id'] == teamId,
              orElse: () => team,
            );
            final stages = _stageList(currentTeam);

            return StatefulBuilder(
              builder: (context, setDialogState) {
                final stage = _stagePayload(stages, selectedStage);
                final pre = _deliverables(stage, 'pre');
                final vault = _deliverables(stage, 'vault');
                final configured = stage['deliverables_configured'] == true;
                final complete = stage['required_complete'] == true;
                final endorsed = stage['endorsed'] == true;
                final canEndorse = configured && complete && !endorsed;

                return AlertDialog(
                  title: Text('Deliverables - ${currentTeam['name'] ?? ''}'),
                  content: SizedBox(
                    width: 780,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: stages.map((item) {
                              final label =
                                  item['stage_label']?.toString() ?? '';
                              final active = label == selectedStage;
                              return ChoiceChip(
                                label: Text(label),
                                selected: active,
                                onSelected: (_) {
                                  setDialogState(() {
                                    selectedStage = label;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          _sectionTitle('Pre-Defense Requirements'),
                          ...pre.map(
                            (item) => _deliverableRow(
                              currentTeam,
                              selectedStage,
                              item,
                              setDialogState,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _sectionTitle('Post-Defense Vault Submissions'),
                          if (stage['vault_unlocked'] != true)
                            _lockedVaultNotice(selectedStage)
                          else
                            ...vault.map(
                              (item) => _deliverableRow(
                                currentTeam,
                                selectedStage,
                                item,
                                setDialogState,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                    ElevatedButton.icon(
                      onPressed: canEndorse
                          ? () async {
                              await ref
                                  .read(capstoneDeliverablesProvider.notifier)
                                  .endorseTeam(
                                    _asInt(currentTeam['id']),
                                    selectedStage,
                                  );
                              // We don't pop the dialogContext here, but wait, the plan says we can pop here because it's the "endorse" action which is complete.
                              // Actually, if we pop, that's fine or we don't have to pop. Wait, line 725 in original popped. So keeping pop on endorse is okay.
                              if (context.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(
                        endorsed
                            ? 'Already Endorsed'
                            : (configured
                                  ? 'Endorse'
                                  : 'Configure Stage First'),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _deliverableRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    void Function(void Function()) setDialogState,
  ) {
    final uploaded = item['uploaded'] == true;
    final locked = item['locked'] == true;
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final isWPR =
        item['id'] == 'WPR'; // Check if this is Weekly Progress Report

    final suggestedFile = item['suggested_file_name']?.toString() ?? '';

    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isFaculty = user?['role'] == 'faculty';
    final isAdmin = user?['role'] == 'admin';
    final stages = _stageList(team);
    final stage = _stagePayload(stages, stageLabel);
    final endorsed = stage['endorsed'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
          ),
          child: Row(
            children: [
              Icon(
                uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
                color: uploaded ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['label']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (uploaded) ...[
                      Text(
                        isWPR
                            ? 'All weekly reports approved - ${submission['uploaded_by_name'] ?? ''}'
                            : '${submission['file_name'] ?? ''} - ${submission['uploaded_by_name'] ?? ''}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (submission['reviewed_by_name'] != null && (submission['reviewed_by_name']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Reviewed by: ${submission['reviewed_by_name']}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (submission['status'] == 'rejected' && (submission['feedback']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Remarks: ${submission['feedback']}',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      if (submission['status'] == 'accepted' && (submission['feedback']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Remarks: ${submission['feedback']}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ] else if ((item['vault_note']?.toString() ?? '').isNotEmpty)
                      Text(
                        item['vault_note'].toString(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      )
                    else if (isWPR)
                      Text(
                        'Click "View & Approve" to review all weekly reports',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              if (item['required'] == true) _chip('Required', AppColors.danger),
              const SizedBox(width: 8),
              if (isFaculty && !isAdmin) ...[
                if (isWPR) ...[
                  OutlinedButton.icon(
                    onPressed: () => _showApproveWPRDialog(
                      team,
                      stageLabel,
                      uploaded,
                      setDialogState,
                    ),
                    icon: Icon(
                      uploaded ? Icons.visibility : Icons.check_circle_outline,
                    ),
                    label: Text(uploaded ? 'View Reports' : 'View & Approve'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: uploaded ? Colors.blue : AppColors.success,
                      side: BorderSide(
                        color: uploaded ? Colors.blue : AppColors.success,
                      ),
                    ),
                  ),
                ] else ...[
                  if (uploaded) ...[
                    OutlinedButton.icon(
                      onPressed: () => _viewPdf(
                        submission['file_url'] ?? '',
                        submission['file_name'] ?? 'document.pdf',
                      ),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('View PDF'),
                    ),
                    const SizedBox(width: 8),
                    if (submission['status'] == 'pending') ...[
                      OutlinedButton.icon(
                        onPressed: () => _reviewSubmission(
                          _asInt(team['id']),
                          stageLabel,
                          item['id'],
                          'accepted',
                          setDialogState,
                        ),
                        icon: const Icon(Icons.check, color: AppColors.success),
                        label: const Text('Accept'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: const BorderSide(color: AppColors.success),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _promptRejectionFeedback(
                          _asInt(team['id']),
                          stageLabel,
                          item['id'],
                          setDialogState,
                          isEndorsed: endorsed,
                        ),
                        icon: const Icon(Icons.close, color: AppColors.danger),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                      ),
                    ] else if (submission['status'] == 'accepted') ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                          const SizedBox(width: 6),
                          const Text(
                            'Accepted',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _promptRejectionFeedback(
                              _asInt(team['id']),
                              stageLabel,
                              item['id'],
                              setDialogState,
                              isEndorsed: endorsed,
                            ),
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                          ),
                        ],
                      ),
                    ] else if (submission['status'] == 'rejected') ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cancel, color: AppColors.danger, size: 20),
                          const SizedBox(width: 6),
                          const Text(
                            'Rejected',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _reviewSubmission(
                              _asInt(team['id']),
                              stageLabel,
                              item['id'],
                              'accepted',
                              setDialogState,
                            ),
                            icon: const Icon(Icons.check, size: 14),
                            label: const Text('Accept'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.success,
                              side: const BorderSide(color: AppColors.success),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    const Text(
                      'Awaiting Student Upload',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ] else ...[
                if (uploaded && !isWPR)
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => _removeFile(team, stageLabel, item),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                  ),
                if (isWPR)
                  OutlinedButton.icon(
                    onPressed: () => _showApproveWPRDialog(
                      team,
                      stageLabel,
                      uploaded,
                      setDialogState,
                    ),
                    icon: Icon(
                      uploaded ? Icons.visibility : Icons.check_circle_outline,
                    ),
                    label: Text(uploaded ? 'View Reports' : 'View & Approve'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: uploaded ? Colors.blue : AppColors.success,
                      side: BorderSide(
                        color: uploaded ? Colors.blue : AppColors.success,
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: locked
                        ? null
                        : () => _promptUploadOrReplace(team, stageLabel, item),
                    icon: Icon(uploaded ? Icons.swap_horiz : Icons.upload_file),
                    label: Text(uploaded ? 'Replace' : 'Upload'),
                  ),
              ],
            ],
          ),
        ),
        if (suggestedFile.isNotEmpty && !uploaded)
          Container(
            margin: const EdgeInsets.only(bottom: 12, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.info_outline,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Awaiting PDF: Please use this exact filename to automatically satisfy the archive requirement.',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.2),
                              ),
                            ),
                            child: SelectableText(
                              suggestedFile,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: suggestedFile),
                              );
                              showSuccessToast(
                                context,
                                'Filename copied to clipboard!',
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: AppColors.textSecondary,
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
          ),
      ],
    );
  }

  Future<void> _reviewSubmission(
    int teamId,
    String stageLabel,
    String deliverableId,
    String status,
    void Function(void Function()) setDialogState, {
    String? feedback,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );

    try {
      final success = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .reviewDeliverable(
            teamId: teamId,
            stageLabel: stageLabel,
            deliverableId: deliverableId,
            status: status,
            feedback: feedback,
          );

      if (mounted) Navigator.pop(context);

      if (success) {
        showSuccessToast(context, 'Deliverable review status updated.');
        setDialogState(() {});
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      showErrorToast(context, 'Failed to update review status: $e');
    }
  }

  Future<void> _promptRejectionFeedback(
    int teamId,
    String stageLabel,
    String deliverableId,
    void Function(void Function()) setDialogState, {
    bool isEndorsed = false,
  }) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject Deliverable & Request Revision'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEndorsed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WARNING: This team is currently endorsed. Rejecting this required pre-defense deliverable will automatically revoke their endorsement.',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Text(
              'Please provide feedback or remarks explaining why this deliverable is rejected.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Feedback / Remarks',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                showValidationToast(context, 'Remarks are required for rejection.');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _reviewSubmission(
        teamId,
        stageLabel,
        deliverableId,
        'rejected',
        setDialogState,
        feedback: controller.text.trim(),
      );
    }
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

  Future<void> _promptUploadOrReplace(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    if (item['uploaded'] == true) {
      final ok = await confirmDestructive(
        context,
        title: 'Replace file?',
        message: 'The current upload will be replaced. This cannot be undone.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    await _showUploadDialog(team, stageLabel, item);
  }

  Future<void> _showUploadDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    String? selectedFileName;
    String? selectedFileSize;
    List<int>? selectedFileBytes;
    bool isUploading = false;
    double uploadProgress = 0.0;
    String? uploadError;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissal during upload
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Upload ${item['id']}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['label']?.toString() ?? ''),
                const SizedBox(height: 14),
                if (!isUploading)
                  OutlinedButton.icon(
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform
                          .pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf'],
                            withData: true, // Load file bytes
                          );

                      if (result != null &&
                          result.files.single.name.isNotEmpty) {
                        setState(() {
                          selectedFileName = result.files.single.name;
                          selectedFileBytes =
                              result.files.single.bytes; // Store file bytes
                          // Convert bytes to KB
                          final bytes = result.files.single.size;
                          selectedFileSize =
                              '${(bytes / 1024).toStringAsFixed(2)} KB';
                          uploadError = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose PDF File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                const SizedBox(height: 16),
                if (selectedFileName != null && !isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFileName!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedFileSize ?? '',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No file selected. Click "Choose PDF File" to select a file.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isUploading) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            color: AppColors.success,
                            backgroundColor: AppColors.success.withValues(
                              alpha: 0.12,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading ${selectedFileName ?? "file"}...',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (uploadError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    uploadError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedFileName != null && !isUploading)
                  ? () async {
                      final suggestedName =
                          item['suggested_file_name']?.toString() ?? '';
                      if (item['type'] == 'vault' && suggestedName.isNotEmpty) {
                        if (selectedFileName!.trim().toLowerCase() !=
                            suggestedName.trim().toLowerCase()) {
                          setState(() {
                            uploadError =
                                "File name must match the naming convention exactly.\nExpected: '$suggestedName'";
                          });
                          return;
                        }
                      }

                      setState(() {
                        isUploading = true;
                        uploadProgress = 0.0;
                        uploadError = null;
                      });

                      try {
                        final client = ref.read(
                          authenticatedHttpClientProvider,
                        );
                        final uri = Uri.parse(
                          '${ApiConfig.capstoneDeliverablesUrl}/upload/',
                        );

                        final request = MultipartRequestWithProgress(
                          'POST',
                          uri,
                          onProgress: (bytesSent, totalBytes) {
                            if (totalBytes > 0) {
                              setState(() {
                                uploadProgress = bytesSent / totalBytes;
                              });
                            }
                          },
                        );

                        // Add form fields
                        request.fields['team_id'] = team['id'].toString();
                        request.fields['stage_label'] = stageLabel;
                        request.fields['deliverable_id'] = item['id']
                            .toString();
                        request.fields['file_name'] = selectedFileName!;
                        request.fields['file_size'] = selectedFileSize ?? '';

                        // Add file
                        request.files.add(
                          http.MultipartFile.fromBytes(
                            'file',
                            selectedFileBytes!,
                            filename: selectedFileName!,
                          ),
                        );

                        final response = await client.sendAuthenticated(
                          request,
                        );

                        if (response.statusCode == 200) {
                          // Refresh deliverables list
                          await ref
                              .read(capstoneDeliverablesProvider.notifier)
                              .fetchDeliverables(
                                successMessage:
                                    'Deliverable file uploaded successfully.',
                              );
                          if (context.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } else {
                          final responseBody = await response.stream
                              .bytesToString();
                          setState(() {
                            isUploading = false;
                            uploadError = _formatUploadFailureMessage(
                              response.statusCode,
                              responseBody,
                            );
                          });
                        }
                      } catch (e) {
                        setState(() {
                          isUploading = false;
                          uploadError = 'Upload error: $e';
                        });
                      }
                    }
                  : null,
              child: const Text('Save Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final label =
        item['label']?.toString() ?? item['id']?.toString() ?? 'this file';
    final teamName = team['name']?.toString();
    final message = teamName != null && teamName.isNotEmpty
        ? 'Remove $label for $teamName? This cannot be undone.'
        : 'Remove $label? This cannot be undone.';

    final ok = await confirmDestructive(
      context,
      title: 'Remove file?',
      message: message,
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;

    _pendingRemoveTimer?.cancel();
    _pendingRemoveCancelled = false;
    final payload = {
      'team_id': _asInt(team['id']),
      'stage_label': stageLabel,
      'deliverable_id': item['id'],
    };

    showUndoToast(
      context,
      context.l10n.fileRemoved,
      undoLabel: context.l10n.undo,
      onUndo: () {
        _pendingRemoveCancelled = true;
        _pendingRemoveTimer?.cancel();
      },
    );

    _pendingRemoveTimer = Timer(const Duration(seconds: 5), () async {
      if (_pendingRemoveCancelled || !mounted) return;
      final removed = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .removeDeliverable(payload);
      if (mounted && !removed) {
        showErrorToast(context, context.l10n.fileRemoveFailed);
      }
    });
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _lockedVaultNotice(String stageLabel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vault uploads unlock after the $stageLabel defense is marked done.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool complete, bool endorsed) {
    if (endorsed) {
      return _chip('Endorsed', AppColors.success, icon: Icons.verified);
    }
    if (complete) {
      return _chip('Complete', Colors.blue, icon: Icons.check_circle);
    }
    return _chip('Missing Files', AppColors.warning, icon: Icons.warning_amber);
  }

  Widget _chip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
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

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  List<Map<String, dynamic>> _stageList(Map<String, dynamic> team) {
    final stages = team['stages'];
    if (stages is! List) {
      return [];
    }
    return stages
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _stagePayload(
    List<Map<String, dynamic>> stages,
    String stageLabel,
  ) {
    return stages.firstWhere(
      (stage) => stage['stage_label'] == stageLabel,
      orElse: () => stages.isEmpty ? <String, dynamic>{} : stages.first,
    );
  }

  List<Map<String, dynamic>> _deliverables(
    Map<String, dynamic> stage,
    String type,
  ) {
    final rows = stage['deliverables'];
    if (rows is! List) {
      return [];
    }
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['type'] == type)
        .toList();
  }

  int _count(CapstoneDeliverablesState state, String key) {
    return _asInt(state.counts[key]);
  }

  Future<void> _showApproveWPRDialog(
    Map<String, dynamic> team,
    String stageLabel,
    bool alreadyApproved,
    void Function(void Function()) setDialogState,
  ) async {
    final teamId = team['id']?.toString() ?? '';

    if (teamId.isEmpty) {
      showValidationToast(context, 'Invalid team ID.');
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch fresh weekly progress reports from database for this team
      await ref.read(weeklyProgressProvider.notifier).fetchReports();

      // Get the updated state
      final progressState = ref.read(weeklyProgressProvider);

      // Filter reports for this specific team
      final teamReports = progressState.reports
          .where((r) => r['team'].toString() == teamId)
          .toList();

      // Close loading indicator
      if (mounted) Navigator.pop(context);

      if (teamReports.isEmpty) {
        if (mounted) {
          showValidationToast(
            context,
            'No weekly progress reports found for ${team['name']}. Students must submit reports first.',
          );
        }
        return;
      }

      // Show approval dialog
      if (mounted) {
        final approved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  alreadyApproved
                      ? Icons.visibility
                      : Icons.check_circle_outline,
                  color: alreadyApproved ? Colors.blue : AppColors.success,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alreadyApproved
                        ? 'Weekly Reports - ${team['name']}'
                        : 'Approve Weekly Reports - ${team['name']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team: ${team['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stage: $stageLabel',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: alreadyApproved
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: alreadyApproved
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFBAE6FD),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          alreadyApproved
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: alreadyApproved
                              ? const Color(0xFF166534)
                              : const Color(0xFF0369A1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            alreadyApproved
                                ? 'PDF compilation of all weekly reports has been generated and submitted. You can view the reports below or download them again.'
                                : 'Review the ${teamReports.length} weekly progress reports submitted by this team. Click "Generate & Submit PDF" to compile all reports into a single PDF document and submit it as the WPR deliverable.',
                            style: TextStyle(
                              color: alreadyApproved
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF0369A1),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weekly reports submitted (${teamReports.length}):',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showCompileWPRDialog(team);
                        },
                        icon: const Icon(Icons.folder_zip_outlined, size: 16),
                        label: const Text('Download All'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.maroon,
                          side: const BorderSide(color: AppColors.maroon),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: teamReports.length,
                      itemBuilder: (context, index) {
                        final report = teamReports[index];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Week ${report['week_number'] ?? 0}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Date: ${report['report_date'] ?? 'N/A'} • Submitted by: ${report['student_name'] ?? 'Unknown'}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Week ${report['week_number']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close'),
              ),
              if (!alreadyApproved)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                    'Generate & Submit PDF (${teamReports.length} reports)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        );

        // If approved, generate PDF and save to database
        if (approved == true && mounted) {
          // Show loading indicator
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );

          try {
            // Call backend API to generate PDF and save as deliverable
            final success = await _generateAndSubmitPDF(
              _asInt(team['id']),
              stageLabel,
            );

            // Close loading indicator
            if (mounted) Navigator.pop(context);

            if (success && mounted) {
              // Refresh the dialog to show updated status
              setDialogState(() {});

              showSuccessToast(
                context,
                'Weekly Progress Reports PDF generated and submitted for ${team['name']}!',
              );
            }
          } catch (e) {
            // Close loading indicator
            if (mounted) Navigator.pop(context);

            if (mounted) {
              showErrorToast(context, 'Error generating PDF: $e');
            }
          }
        }
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        showErrorToast(context, 'Error fetching weekly reports: $e');
      }
    }
  }

  Future<void> _showCompileWPRDialog(Map<String, dynamic> team) async {
    final teamId = team['id']?.toString() ?? '';

    if (teamId.isEmpty) {
      showValidationToast(context, 'Invalid team ID.');
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch fresh weekly progress reports from database for this team
      await ref.read(weeklyProgressProvider.notifier).fetchReports();

      // Get the updated state
      final progressState = ref.read(weeklyProgressProvider);

      // Filter reports for this specific team
      final teamReports = progressState.reports
          .where((r) => r['team'].toString() == teamId)
          .toList();

      // Close loading indicator
      if (mounted) Navigator.pop(context);

      if (teamReports.isEmpty) {
        if (mounted) {
          showValidationToast(
            context,
            'No weekly progress reports found for ${team['name']}.',
          );
        }
        return;
      }

      // Show compilation dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.folder_zip, color: AppColors.maroon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compile Weekly Reports - ${team['name']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team: ${team['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF0369A1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This will generate a compilation report of all ${teamReports.length} weekly progress reports for this team from the database.',
                            style: const TextStyle(
                              color: Color(0xFF0369A1),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Weekly reports to compile:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: teamReports.length,
                      itemBuilder: (context, index) {
                        final report = teamReports[index];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Week ${report['week_number'] ?? 0}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Date: ${report['report_date'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Week ${report['week_number']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _downloadWPRCompilation(team, teamReports);
                },
                icon: const Icon(Icons.download),
                label: const Text('Download Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        showErrorToast(context, 'Error fetching weekly reports: $e');
      }
    }
  }

  void _downloadWPRCompilation(
    Map<String, dynamic> team,
    List<Map<String, dynamic>> reports,
  ) {
    // Generate a simple text report
    final buffer = StringBuffer();
    buffer.writeln('=' * 60);
    buffer.writeln('WEEKLY PROGRESS REPORTS COMPILATION');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('Team: ${team['name']}');
    buffer.writeln('Project: ${team['project_title'] ?? 'N/A'}');
    buffer.writeln('Section: ${team['year_level'] ?? 'N/A'}');
    buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('WEEKLY REPORTS (${reports.length})');
    buffer.writeln('=' * 60);
    buffer.writeln();

    for (var i = 0; i < reports.length; i++) {
      final report = reports[i];
      final weekNumber = report['week_number'] ?? 0;
      final reportDate = report['report_date'] ?? 'N/A';
      final studentName = report['student_name'] ?? 'Unknown';
      final submittedAt = report['submitted_at'] ?? 'N/A';

      buffer.writeln('${i + 1}. WEEK $weekNumber');
      buffer.writeln('   Date: $reportDate');
      buffer.writeln('   Submitted by: $studentName');
      buffer.writeln('   Submitted at: $submittedAt');
      buffer.writeln();

      // Accomplishments
      final accomplishments =
          (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      if (accomplishments.isNotEmpty) {
        buffer.writeln('   Accomplishments:');
        for (var acc in accomplishments) {
          buffer.writeln('   - Task: ${acc['task'] ?? 'N/A'}');
          buffer.writeln('     Description: ${acc['description'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Contributions
      final contributions =
          (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      if (contributions.isNotEmpty) {
        buffer.writeln('   Individual Contributions:');
        for (var contrib in contributions) {
          buffer.writeln(
            '   - ${contrib['member'] ?? 'N/A'}: ${contrib['contribution'] ?? 'N/A'}',
          );
        }
        buffer.writeln();
      }

      // Issues
      final issues =
          (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (issues.isNotEmpty) {
        buffer.writeln('   Issues & Actions:');
        for (var issue in issues) {
          buffer.writeln('   - Issue: ${issue['issue'] ?? 'N/A'}');
          buffer.writeln('     Action: ${issue['action'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Plans
      final plans =
          (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (plans.isNotEmpty) {
        buffer.writeln('   Plans for Next Week:');
        for (var plan in plans) {
          buffer.writeln('   - Task: ${plan['task'] ?? 'N/A'}');
          buffer.writeln('     Expected Output: ${plan['output'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      buffer.writeln('-' * 60);
      buffer.writeln();
    }

    buffer.writeln('=' * 60);
    buffer.writeln('END OF COMPILATION');
    buffer.writeln('=' * 60);

    // Show success message with view action
    showSuccessToast(
      context,
      'Compilation report generated for ${team['name']}\n'
      '${reports.length} weekly reports compiled.',
      duration: const Duration(seconds: 4),
      action: FeedbackToastAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Show the report in a dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Compilation Report'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  child: SelectableText(
                    buffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _generateAndSubmitPDF(int teamId, String stageLabel) async {
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.post(
        Uri.parse(
          '${ApiConfig.capstoneDeliverablesUrl}/compile-weekly-reports/',
        ),
        body: jsonEncode({'team_id': teamId, 'stage_label': stageLabel}),
      );

      if (response.statusCode == 200) {
        jsonDecode(response.body);

        // Refresh deliverables to show the new PDF submission
        await ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables();

        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to generate PDF');
      }
    } catch (e) {
      rethrow;
    }
  }

  Widget _buildTeamsAndGradesTab(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      final emptyTitle = state.scope == 'pit' ? 'No PIT teams found' : 'No Capstone teams found';
      return Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(34),
          child: Column(
            children: [
              const Icon(Icons.folder_open_outlined, size: 42, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              Text(emptyTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );
    }

    final totalTeams = state.teams.length;
    final publishedTeamsCount = state.teams.where((team) {
      final grade = team['grade'] as Map?;
      return grade != null && grade['status'] == 'published';
    }).length;
    final pendingCount = totalTeams - publishedTeamsCount;
    final completionRate = totalTeams > 0 ? (publishedTeamsCount / totalTeams * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _stat(
              'Total Teams',
              totalTeams,
              Icons.groups_2_outlined,
              AppColors.maroon,
            ),
            _stat(
              'Published Grades',
              publishedTeamsCount,
              Icons.verified_outlined,
              AppColors.success,
            ),
            _stat(
              'Awaiting Publication',
              pendingCount,
              Icons.warning_amber_outlined,
              AppColors.warning,
            ),
            _stat(
              'Completion Rate',
              completionRate,
              Icons.donut_large_outlined,
              Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 24),
        ...state.teams.map((team) => _teamGradeCard(state, team)),
      ],
    );
  }

  Widget _teamGradeCard(CapstoneDeliverablesState state, Map<String, dynamic> team) {
    final grade = team['grade'] != null ? Map<String, dynamic>.from(team['grade'] as Map) : null;
    final status = grade?['status']?.toString() ?? 'pending';

    final panelScore = grade?['panel_score'];
    final peerScore = grade?['peer_score'];
    final adviserScore = grade?['adviser_score'];
    final finalGrade = grade?['final_grade'];
    final result = grade?['result']?.toString() ?? 'pending';

    Color statusBg = const Color(0xFFFEF3C7);
    Color statusText = const Color(0xFFD97706);
    String statusLabel = 'Pending';

    if (status == 'published') {
      statusBg = const Color(0xFFD1FAE5);
      statusText = const Color(0xFF047857);
      statusLabel = 'Published';
    } else if (status == 'awaiting_peers') {
      statusBg = const Color(0xFFDBEAFE);
      statusText = const Color(0xFF2563EB);
      statusLabel = 'Awaiting Peers';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('grade_${team['id']}'),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    team['project_title']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _gradeBadge('Panel', panelScore),
              _gradeBadge('Peer', peerScore),
              if (state.scope == 'capstone') _gradeBadge('Adviser', adviserScore),
              _overallGradeBadge(finalGrade, result),
            ],
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'TEAM ROSTER & INDIVIDUAL PEER GRADES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                _buildRosterAndIndividualGrades(team, grade),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeBadge(String label, dynamic score) {
    final parsedScore = _asDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hasScore ? const Color(0xFFF3F4F6) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasScore ? const Color(0xFFE5E7EB) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: hasScore ? AppColors.textPrimary : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallGradeBadge(dynamic score, String result) {
    final parsedScore = _asDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';

    Color bg = const Color(0xFFF3F4F6);
    Color border = const Color(0xFFE5E7EB);
    Color text = AppColors.textPrimary;

    if (hasScore) {
      if (result == 'passed') {
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        text = const Color(0xFF047857);
      } else {
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFCA5A5);
        text = const Color(0xFFB91C1C);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Overall Grade: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: text,
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: result == 'passed' ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result == 'passed' ? 'PASSED' : 'FAILED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: result == 'passed' ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRosterAndIndividualGrades(Map<String, dynamic> team, Map<String, dynamic>? grade) {
    debugPrint('DefenSYS Debug: _buildRosterAndIndividualGrades team=$team');
    debugPrint('DefenSYS Debug: _buildRosterAndIndividualGrades grade=$grade');
    final List<dynamic> members = team['members'] as List? ?? [];
    final List<dynamic> peerGrades = grade?['peer_per_student'] as List? ?? [];

    if (members.isEmpty) {
      return const Text(
        'No members assigned to this team.',
        style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
        itemBuilder: (context, index) {
          final rawMember = members[index];
          if (rawMember is! Map) return const SizedBox.shrink();
          final member = Map<String, dynamic>.from(rawMember);
          final studentId = member['id'];
          final name = member['name']?.toString() ?? member['username']?.toString() ?? 'Student';
          final role = member['role']?.toString() ?? 'member';
          final isLeader = role == 'leader';

          final peerDetails = peerGrades.firstWhere(
            (g) => g is Map && g['student_id'] == studentId,
            orElse: () => null,
          );

          final double? avgScore = _asDouble(peerDetails?['average_score']);
          final double maxScore = _asDouble(peerDetails?['max_score']) ?? 5.0;
          final double? normScore = _asDouble(peerDetails?['normalized_score']);

          final sanitizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
          final parts = sanitizedName.split(' ');
          final initials = parts.isNotEmpty
              ? (parts.first.isNotEmpty ? parts.first[0] : '') +
                  (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '')
              : '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.maroon.withValues(alpha: 0.1),
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.maroon,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isLeader) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Leader',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member['username']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (avgScore != null) ...[
                            Text(
                              'Peer Score: ${avgScore.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Normalized: ${normScore?.toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else ...[
                            const Text(
                              'Peer Score: Pending',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
