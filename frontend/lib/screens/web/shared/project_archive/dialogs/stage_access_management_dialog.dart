import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback_toast.dart';

class StageAccessManagementDialog {
  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    int? teamId,
    String? teamName,
    required String scope, // 'team' or 'global'
    String programScope = 'capstone', // 'capstone' or 'pit'
    String? yearLevel,
    ProjectArchiveState? state,
    List<String> availableStages = const [],
  }) async {
    List<String> stages = availableStages.isNotEmpty ? List.from(availableStages) : [];

    if (stages.isEmpty && state != null) {
      final scopeKey = state.scope['scope']?.toString() ?? 'admin';
      final isPitLead = scopeKey == 'pit_lead';

      // For PIT Leads, derive stages ONLY from entries (already scoped to
      // their assigned year level by the backend). state.options['stage_options']
      // includes Capstone defense stages and must NOT be used here.
      if (isPitLead || programScope == 'pit') {
        // 1. Extract unique stage names from the entries visible to this user
        if (state.entries.isNotEmpty) {
          stages = state.entries
              .map((e) => e['stage']?.toString() ?? e['event_name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
        }

        // 2. Fallback: groupedByStage (also already scoped)
        if (stages.isEmpty && state.groupedByStage.isNotEmpty) {
          stages = state.groupedByStage
              .map((g) => g['stage']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
        }
      } else {
        // Admin / Capstone scope — stage_options are safe to use directly
        final stageOpts = state.options['stage_options'];
        if (stageOpts is List && stageOpts.isNotEmpty) {
          stages = stageOpts.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final isTeam = scope == 'team';
          final title = isTeam
              ? 'Manage Stage File Access for ${teamName ?? 'Team'}'
              : 'Program Stage Access (${programScope.toUpperCase()}${yearLevel != null && yearLevel.isNotEmpty ? ' - $yearLevel' : ''})';

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 580,
              decoration: DefensysTokens.dialogDecoration(),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.maroon,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Helper Banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Helper: Manually grant or revoke student file upload permissions by stage and file type. '
                              'Defense stage grades and team approval status will remain intact.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E3A8A),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // List of Stages
                    ...stages.map((stage) => _StageItemCard(
                          stageLabel: stage,
                          teamId: teamId,
                          scope: scope,
                          programScope: programScope,
                          yearLevel: yearLevel,
                          ref: ref,
                        )),

                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StageItemCard extends StatefulWidget {
  final String stageLabel;
  final int? teamId;
  final String scope;
  final String programScope;
  final String? yearLevel;
  final WidgetRef ref;

  const _StageItemCard({
    required this.stageLabel,
    this.teamId,
    required this.scope,
    required this.programScope,
    this.yearLevel,
    required this.ref,
  });

  @override
  State<_StageItemCard> createState() => _StageItemCardState();
}

class _StageItemCardState extends State<_StageItemCard> {
  bool _preUnlocked = false;
  bool _postUnlocked = false;
  bool _isLoading = false;

  Future<void> _toggle(String unlockType, bool targetState) async {
    setState(() => _isLoading = true);
    final notifier = widget.ref.read(capstoneDeliverablesProvider.notifier);
    final success = await notifier.unlockDeliverables(
      teamId: widget.teamId,
      stageLabel: widget.stageLabel,
      unlockType: unlockType,
      scope: widget.scope,
      programScope: widget.programScope,
      yearLevel: widget.yearLevel,
      targetState: targetState,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (success) {
          if (unlockType == 'pre') _preUnlocked = targetState;
          if (unlockType == 'post') _postUnlocked = targetState;
          if (unlockType == 'all') {
            _preUnlocked = targetState;
            _postUnlocked = targetState;
          }
        }
      });
      if (success) {
        showSuccessToast(
          context,
          'Updated ${widget.stageLabel} file permissions.',
        );
        widget.ref.read(projectArchiveProvider.notifier).fetchEntries();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.stageLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(height: 18, color: Color(0xFFE2E8F0)),
            
            // Pre-Defense Files Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: Color(0xFF475569)),
                    SizedBox(width: 8),
                    Text(
                      'Pre-Defense Files',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _preUnlocked,
                  activeColor: AppColors.maroon,
                  onChanged: _isLoading ? null : (val) => _toggle('pre', val),
                ),
              ],
            ),
            
            // Post-Defense Files Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 16, color: Color(0xFF475569)),
                    SizedBox(width: 8),
                    Text(
                      'Post-Defense Files',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _postUnlocked,
                  activeColor: AppColors.maroon,
                  onChanged: _isLoading ? null : (val) => _toggle('post', val),
                ),
              ],
            ),
            const SizedBox(height: 6),
            
            // Preset Buttons
            Row(
              children: [
                InkWell(
                  onTap: _isLoading ? null : () => _toggle('all', true),
                  child: const Text(
                    'Unlock All Files',
                    style: TextStyle(fontSize: 11.5, color: AppColors.maroon, fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('  •  ', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                InkWell(
                  onTap: _isLoading ? null : () => _toggle('all', false),
                  child: const Text(
                    'Lock All Files',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
