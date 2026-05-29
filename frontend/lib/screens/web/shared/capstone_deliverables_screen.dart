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
  if (responseBody.contains('<!DOCTYPE html>') || responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Check backend logs or try again.';
  }
  final trimmed = responseBody.trim();
  if (trimmed.isEmpty) {
    return 'Upload failed (status $statusCode).';
  }
  return 'Upload failed: $trimmed';
}

class CapstoneDeliverablesScreen extends ConsumerStatefulWidget {
  const CapstoneDeliverablesScreen({super.key});

  @override
  ConsumerState<CapstoneDeliverablesScreen> createState() =>
      _CapstoneDeliverablesScreenState();
}

class _CapstoneDeliverablesScreenState
    extends ConsumerState<CapstoneDeliverablesScreen> {
  final _searchController = TextEditingController();
  Timer? _pendingRemoveTimer;
  bool _pendingRemoveCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capstone Deliverables'),
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
              constraints: const BoxConstraints(maxWidth: 1220),
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
                  _buildToolbar(state),
                  if (_stageNotConfigured(state)) ...[
                    const SizedBox(height: 12),
                    _notice(
                      Icons.info_outline,
                      'No deliverables configured for ${state.selectedStage}. '
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(CapstoneDeliverablesState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Capstone Deliverables',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.activeSemester?['display_name']?.toString() ??
                    'Upload pre-defense requirements and unlock vault submissions after defense.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStats(CapstoneDeliverablesState state) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _stat(
          'Capstone Teams',
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
      width: 185,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _iconBox(icon, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(CapstoneDeliverablesState state) {
    final List<String> stageOptions = state.stageOptions.isEmpty
        ? const ['Concept Proposal', 'Project Proposal', 'Final Defense']
        : state.stageOptions;
    final List<Map<String, dynamic>> statuses = state.statuses.isEmpty
        ? const <Map<String, dynamic>>[
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
          ]
        : state.statuses;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search team, project, adviser',
                ),
                onSubmitted: (value) => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .fetchDeliverables(search: value),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: state.selectedStage,
                decoration: const InputDecoration(labelText: 'Stage View'),
                items: stageOptions
                    .map(
                      (stage) =>
                          DropdownMenuItem(value: stage, child: Text(stage)),
                    )
                    .toList(),
                onChanged: (value) => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .fetchDeliverables(
                      selectedStage: value ?? state.selectedStage,
                    ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: state.status,
                decoration: const InputDecoration(labelText: 'Status'),
                isExpanded: true,
                items: statuses
                    .map(
                      (item) => DropdownMenuItem(
                        value: item['value']?.toString() ?? '',
                        child: Text(
                          item['label']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
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
              icon: const Icon(Icons.refresh),
              label: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamList(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      return Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(34),
          child: const Column(
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 42,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 10),
              Text(
                'No Capstone teams found',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Assign Capstone teams and advisers first.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team['project_title']?.toString() ?? '',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _requiredProgressBlock(
                    configured: configured,
                    done: requiredUploaded,
                    total: requiredTotal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _vaultProgressBlock(selectedStage),
                ),
                const SizedBox(width: 12),
                if (canEndorse)
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
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Endorse'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: state.isSaving
                      ? null
                      : () => _showTeamDialog(team),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Manage Files'),
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
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
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
                '$label $done/$total',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text('${(pct * 100).round()}%'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: pct,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  void _showTeamDialog(Map<String, dynamic> team) {
    String selectedStage = ref.read(capstoneDeliverablesProvider).selectedStage;
    final stages = _stageList(team);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
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
              title: Text('Deliverables - ${team['name'] ?? ''}'),
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
                          final label = item['stage_label']?.toString() ?? '';
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
                          team,
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
                            team,
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
                              .endorseTeam(_asInt(team['id']), selectedStage);
                          if (context.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        }
                      : null,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(
                    endorsed
                        ? 'Already Endorsed'
                        : (configured ? 'Endorse' : 'Configure Stage First'),
                  ),
                ),
              ],
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
    final isWPR = item['id'] == 'WPR';  // Check if this is Weekly Progress Report

    final suggestedFile = item['suggested_file_name']?.toString() ?? '';

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
                if (uploaded)
                  Text(
                    isWPR 
                        ? 'All weekly reports approved - ${submission['uploaded_by_name'] ?? ''}'
                        : '${submission['file_name'] ?? ''} - ${submission['uploaded_by_name'] ?? ''}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                else if ((item['vault_note']?.toString() ?? '').isNotEmpty)
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
          if (uploaded && !isWPR)
            IconButton(
              tooltip: 'Remove',
              onPressed: () => _removeFile(team, stageLabel, item),
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          // Show "View & Approve" button for WPR, "Upload" for others
          if (isWPR)
            OutlinedButton.icon(
              onPressed: () => _showApproveWPRDialog(team, stageLabel, uploaded, setDialogState),
              icon: Icon(uploaded ? Icons.visibility : Icons.check_circle_outline),
              label: Text(uploaded ? 'View Reports' : 'View & Approve'),
              style: OutlinedButton.styleFrom(
                foregroundColor: uploaded ? Colors.blue : AppColors.success,
                side: BorderSide(color: uploaded ? Colors.blue : AppColors.success),
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
              child: Icon(Icons.info_outline, color: AppColors.gold, size: 20),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
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
                          Clipboard.setData(ClipboardData(text: suggestedFile));
                          showSuccessToast(context, 'Filename copied to clipboard!');
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
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

    final saved = await showDialog<bool>(
      context: context,
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
                OutlinedButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      withData: true, // Load file bytes
                    );

                    if (result != null && result.files.single.name.isNotEmpty) {
                      setState(() {
                        selectedFileName = result.files.single.name;
                        selectedFileBytes = result.files.single.bytes; // Store file bytes
                        // Convert bytes to KB
                        final bytes = result.files.single.size;
                        selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
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
                if (selectedFileName != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
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
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedFileName != null
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Save Upload'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || saved != true || selectedFileName == null || selectedFileBytes == null) {
      return;
    }

    // Send file as multipart/form-data
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final uri = Uri.parse('${ApiConfig.capstoneDeliverablesUrl}/upload/');
      final request = http.MultipartRequest('POST', uri);

      // Add form fields
      request.fields['team_id'] = team['id'].toString();
      request.fields['stage_label'] = stageLabel;
      request.fields['deliverable_id'] = item['id'].toString();
      request.fields['file_name'] = selectedFileName!;
      request.fields['file_size'] = selectedFileSize ?? '';
      
      // Add file
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        selectedFileBytes!,
        filename: selectedFileName!,
      ));
      
      final response = await client.sendAuthenticated(request);

      if (response.statusCode == 200) {
        // Refresh deliverables list
        await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
          successMessage: 'Deliverable file uploaded successfully.',
        );
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } else {
        final responseBody = await response.stream.bytesToString();
        if (mounted) {
          showErrorToast(
            context,
            _formatUploadFailureMessage(response.statusCode, responseBody),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Upload error: $e');
      }
    }
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final label = item['label']?.toString() ?? item['id']?.toString() ?? 'this file';
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
      if (mounted && removed) {
        Navigator.of(context, rootNavigator: true).pop();
      } else if (mounted) {
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
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
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
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
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
                  alreadyApproved ? Icons.visibility : Icons.check_circle_outline,
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
                          alreadyApproved ? Icons.check_circle : Icons.info_outline,
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
                              const Icon(Icons.check_circle,
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
                  label: Text('Generate & Submit PDF (${teamReports.length} reports)'),
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
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
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
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
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
                        const Icon(Icons.info_outline,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
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
                              const Icon(Icons.check_circle,
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
    buffer.writeln('='*60);
    buffer.writeln('WEEKLY PROGRESS REPORTS COMPILATION');
    buffer.writeln('='*60);
    buffer.writeln();
    buffer.writeln('Team: ${team['name']}');
    buffer.writeln('Project: ${team['project_title'] ?? 'N/A'}');
    buffer.writeln('Section: ${team['year_level'] ?? 'N/A'}');
    buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln();
    buffer.writeln('='*60);
    buffer.writeln('WEEKLY REPORTS (${reports.length})');
    buffer.writeln('='*60);
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
      final accomplishments = (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (accomplishments.isNotEmpty) {
        buffer.writeln('   Accomplishments:');
        for (var acc in accomplishments) {
          buffer.writeln('   - Task: ${acc['task'] ?? 'N/A'}');
          buffer.writeln('     Description: ${acc['description'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Contributions
      final contributions = (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (contributions.isNotEmpty) {
        buffer.writeln('   Individual Contributions:');
        for (var contrib in contributions) {
          buffer.writeln('   - ${contrib['member'] ?? 'N/A'}: ${contrib['contribution'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Issues
      final issues = (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (issues.isNotEmpty) {
        buffer.writeln('   Issues & Actions:');
        for (var issue in issues) {
          buffer.writeln('   - Issue: ${issue['issue'] ?? 'N/A'}');
          buffer.writeln('     Action: ${issue['action'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Plans
      final plans = (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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

    buffer.writeln('='*60);
    buffer.writeln('END OF COMPILATION');
    buffer.writeln('='*60);

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
        Uri.parse('${ApiConfig.capstoneDeliverablesUrl}/compile-weekly-reports/'),
        body: jsonEncode({
          'team_id': teamId,
          'stage_label': stageLabel,
        }),
      );

      if (response.statusCode == 200) {
        jsonDecode(response.body);

        // Refresh deliverables to show the new PDF submission
        await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
        
        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to generate PDF');
      }
    } catch (e) {
      rethrow;
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
