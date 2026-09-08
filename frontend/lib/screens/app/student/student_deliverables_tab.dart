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
import '../../../services/dashboard_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../widgets/status_badge.dart';
import '../../../utils/progress_upload.dart';
import '../../../utils/universal_file_viewer.dart';

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
  } catch (_) {}
  if (responseBody.contains('<!DOCTYPE html>') || responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Try again later.';
  }
  final trimmed = responseBody.trim();
  return trimmed.isEmpty ? 'Upload failed (status $statusCode).' : 'Upload failed: $trimmed';
}

class StudentDeliverablesTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final Map<String, dynamic>? studentData;
  final bool isEmbedded;
  final bool hideHeader;

  const StudentDeliverablesTab({
    super.key,
    required this.isCapstone,
    required this.studentData,
    this.isEmbedded = false,
    this.hideHeader = false,
  });

  @override
  ConsumerState<StudentDeliverablesTab> createState() => _StudentDeliverablesTabState();
}

class _StudentDeliverablesTabState extends ConsumerState<StudentDeliverablesTab> {
  String? get _studentYearLevel {
    final y = widget.studentData?['year_level']?.toString().trim();
    return (y != null && y.isNotEmpty) ? y : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          );
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          ),
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);
    final team = state.teams.firstOrNull;

    if (state.isLoading && team == null) {
      return const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (state.error != null && team == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (team == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No team assigned yet.',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final selectedStage = Map<String, dynamic>.from(
      team['selected_stage'] as Map? ?? const {},
    );
    final isPresentationOnly = selectedStage['is_presentation_only'] == true;
    final configured = selectedStage['deliverables_configured'] == true || isPresentationOnly;
    final endorsed = selectedStage['endorsed'] == true;
    final pre = _deliverables(selectedStage, 'pre');
    final vault = _deliverables(selectedStage, 'post');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.hideHeader) ...[
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DefensysTokens.maroon,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.upload_file, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Deliverables',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final detail = selectedStage['stage_status_detail']?.toString();
                        String label = endorsed ? 'Endorsed' : (isPresentationOnly ? 'Oral / Demo' : 'Awaiting Endorsement');
                        Color bg = endorsed ? Colors.green.shade600 : (isPresentationOnly ? const Color(0xFF2563EB) : Colors.orange.shade600);

                        if (detail == 'passed') {
                          label = 'Completed';
                          bg = Colors.green.shade600;
                        } else if (detail == 'pending_post_defense') {
                          label = 'Pending Post-Defense';
                          bg = Colors.purple.shade600;
                        } else if (detail == 'defense_ongoing') {
                          label = 'Defense Ongoing';
                          bg = Colors.indigo.shade600;
                        } else if (detail == 'defense_scheduled') {
                          label = 'Defense Scheduled';
                          bg = Colors.blue.shade600;
                        } else if (detail == 'endorsed') {
                          label = 'Endorsed';
                          bg = Colors.green.shade600;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Stage/Event: ${state.selectedStage}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

              if (state.message != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.message!,
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (isPresentationOnly)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.campaign_rounded,
                              color: Color(0xFF15803D),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Presentation / Demo Milestone',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF14532D),
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'No document submissions are required for this milestone.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                  Icon(
                                    endorsed ? Icons.verified_rounded : Icons.pending_actions_rounded,
                                    size: 16,
                                    color: endorsed ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  endorsed
                                      ? 'Adviser Endorsed — Ready for Scheduling'
                                      : 'Awaiting Adviser Verbal Endorsement',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: endorsed ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              endorsed
                                  ? 'Your adviser has endorsed your team. Administrators can now schedule your presentation / demo slot.'
                                  : 'Prepare your presentation materials, slides, and live demonstration. Your adviser can endorse your readiness directly without file uploads.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else if (!configured)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No deliverables configured for this stage/event yet.',
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Builder(
                  builder: (context) {
                    final hasPendingPre = StudentTaskBadgeHelper.hasPendingPreDeliverables(selectedStage);
                    final hasPendingPost = StudentTaskBadgeHelper.hasPendingPostDeliverables(selectedStage);
                    final stageGrade = (selectedStage['grade'] as Map<String, dynamic>?) ??
                        (selectedStage['grade'] is Map ? Map<String, dynamic>.from(selectedStage['grade'] as Map) : null);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRequiredProgressBlock(pre),
                        const SizedBox(height: 16),
                        _sectionTitle('Pre-Defense Requirements', showRedDot: hasPendingPre),
                        const SizedBox(height: 8),
                        if (pre.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No pre-defense requirements configured.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...pre.map((item) => _deliverableRow(team, state.selectedStage, item, endorsed, stageGrade)),
                        const SizedBox(height: 20),
                        if (stageGrade != null) ...[
                          _buildDirectivesCard(stageGrade),
                        ],
                        if (vault.isNotEmpty) ...[
                          _sectionTitle('Post-Defense Submissions', showRedDot: hasPendingPost),
                          const SizedBox(height: 8),
                          if (selectedStage['vault_unlocked'] != true && selectedStage['archive_unlocked'] != true)
                            _lockedVaultNotice(state.selectedStage, stageGrade)
                          else
                            ...vault.map((item) => _deliverableRow(team, state.selectedStage, item, endorsed, stageGrade)),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: content,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {bool showRedDot = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.maroon,
            ),
          ),
          if (showRedDot) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequiredProgressBlock(List<Map<String, dynamic>> pre) {
    final requiredItems = pre.where((item) => item['required'] == true).toList();
    final total = requiredItems.length;
    final done = requiredItems.where((item) => item['uploaded'] == true || item['submission'] != null).length;
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : (pre.isEmpty ? 0.0 : 1.0);
    final color = done == total && total > 0 ? DefensysTokens.success : DefensysTokens.gold;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Required Pre-Defense Check',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimary,
                ),
              ),
              Text(
                total > 0 ? '$done / $total Complete' : (pre.isEmpty ? 'Not Configured' : 'Complete'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectivesCard(Map<String, dynamic> grade) {
    final remarks = grade['verdict_remarks']?.toString();
    final deadline = grade['revision_deadline']?.toString();
    final verdict = grade['verdict']?.toString();
    final result = grade['result']?.toString() ?? 'Deliberation Outcome';
    if ((remarks == null || remarks.trim().isEmpty) && (deadline == null || deadline.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    final isRevisions = verdict == 'approved_with_revisions';
    final isForRedefense = verdict == 'for_redefense';
    final Color borderColor = isForRedefense
        ? const Color(0xFFFECACA)
        : (isRevisions ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0));
    final Color bgColor = isForRedefense
        ? const Color(0xFFFEF2F2)
        : (isRevisions ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4));
    final Color accentColor = isForRedefense
        ? const Color(0xFFDC2626)
        : (isRevisions ? const Color(0xFFD97706) : const Color(0xFF16A34A));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isForRedefense ? Icons.replay_rounded : (isRevisions ? Icons.assignment_late_rounded : Icons.verified_rounded),
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Panel Directives ($result)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
              if (deadline != null && deadline.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 11, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Due: $deadline',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accentColor),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (remarks != null && remarks.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote_rounded, size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remarks,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: DefensysTokens.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lockedVaultNotice(String stage, [Map<String, dynamic>? grade]) {
    final verdict = grade?['verdict']?.toString();
    final isForRedefense = verdict == 'for_redefense';
    final attempt = grade?['attempt_count'] ?? 1;

    if (isForRedefense) {
      return Card(
        elevation: 0,
        color: const Color(0xFFFEF2F2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFFECACA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_clock_rounded, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Post-Defense Submissions Locked (For Re-defense)',
                      style: TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The panel has issued a For Re-defense decision for $stage (Attempt #$attempt). Post-defense submissions remain locked until oral defense is re-scheduled and passed.',
                      style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Post-Defense submissions are locked. They will open once your defense for $stage is complete.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _deliverables(Map<String, dynamic> stage, String type) {
    final list = stage['deliverables'] as List?;
    if (list == null) return [];
    return list
        .where((item) {
          if (item is! Map) return false;
          final itemType = item['type']?.toString();
          if (type == 'post') {
            return itemType == 'post' || itemType == 'vault';
          }
          return itemType == type;
        })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Widget _deliverableRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    bool endorsed, [
    Map<String, dynamic>? stageGrade,
  ]) {
    final uploaded = item['uploaded'] == true;
    final isWaived = item['is_waived'] == true;
    final verdictCondition = item['verdict_condition']?.toString();
    final stageVerdict = stageGrade?['verdict']?.toString();
    final isForRedefense = stageVerdict == 'for_redefense';

    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final status = submission['status']?.toString();
    final rawFeedback = (submission['feedback'] ?? item['feedback'])?.toString() ?? '';
    final isAccepted = status == 'accepted';
    final isRejected = status == 'rejected' || status == 'Needs Revision';

    final replacementUnlockedByAdmin = rawFeedback.contains('Unlocked for file replacement');
    final isDefenseMaterialAttempt2 = isForRedefense && item['type'] == 'pre' && item['is_defense_material'] == true;
    final fileLocked = !isDefenseMaterialAttempt2 && !replacementUnlockedByAdmin && !isRejected && ((item['type'] == 'pre' && endorsed) || item['locked'] == true || isAccepted);
    final isWPR = item['id'] == 'WPR';
    final suggestedFile = item['suggested_file_name']?.toString() ?? '';
    final feedback = replacementUnlockedByAdmin ? '' : rawFeedback;
    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Info & Badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: uploaded ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            item['label']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: formatInfo.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: formatInfo.color.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(formatInfo.icon, size: 11, color: formatInfo.color),
                                const SizedBox(width: 3),
                                Text(
                                  formatInfo.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: formatInfo.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (uploaded)
                        Text(
                          isWPR
                              ? 'All weekly reports approved - Compiled by Adviser'
                              : '${submission['file_name'] ?? ''} - ${submission['uploaded_by_name'] ?? ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else if (isWaived)
                        Text(
                          'Not Required: Team received an Approved verdict with no revisions ordered.',
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                        )
                      else if ((item['archive_note'] ?? item['vault_note'])?.toString().isNotEmpty ?? false)
                        Text(
                          (item['archive_note'] ?? item['vault_note']).toString(),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else if (isWPR)
                        const Text(
                          'Adviser will compile weekly reports once approved.',
                          style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badges Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isWaived) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 11, color: Color(0xFF15803D)),
                            SizedBox(width: 3),
                            Text(
                              'Not Required (Approved)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (uploaded) ...[
                      if (isAccepted)
                        const StatusBadge.success(label: 'Accepted')
                      else if (isRejected)
                        const StatusBadge.revision(label: 'Needs Revision')
                      else
                        const StatusBadge.warning(label: 'Awaiting Review'),
                    ] else ...[
                      const StatusBadge.warning(label: 'Awaiting Upload'),
                    ],
                    const SizedBox(height: 4),
                    if (item['required'] == true && !isWaived)
                      StatusBadge.danger(
                        label: verdictCondition == 'revisions_only' ? 'Required (Revisions)' : 'Required',
                        showDot: false,
                      ),
                  ],
                ),
              ],
            ),
            if (uploaded && isRejected && feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Remarks:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
            ],
            if (replacementUnlockedByAdmin) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Admin enabled file replacement for this deliverable.',
                        style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (uploaded && isAccepted && feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Remarks:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ],
            if (suggestedFile.isNotEmpty && !uploaded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DefensysTokens.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: DefensysTokens.gold, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Naming template (${formatInfo.label} must match):',
                            style: const TextStyle(color: DefensysTokens.gold, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            suggestedFile,
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Bottom Actions Section
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (uploaded && !isWPR) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      final fileUrl = (submission['file_url'] ?? '').toString();
                      final fileName = (submission['file_name'] ?? item['label'] ?? 'file').toString();
                      _viewFile(fileUrl, fileName);
                    },
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                    label: const Text('View', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DefensysTokens.maroon,
                      side: BorderSide(color: DefensysTokens.maroon.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (uploaded && !isWPR && !fileLocked) ...[
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => _removeFile(team, stageLabel, item),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isWPR)
                  ElevatedButton.icon(
                    onPressed: () => _showWPRDialog(team, stageLabel),
                    icon: const Icon(Icons.assignment, size: 16),
                    label: const Text('Manage Weekly Reports', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else if (isWaived)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF64748B)),
                        SizedBox(width: 4),
                        Text('Not Required', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      ],
                    ),
                  )
                else if (isDefenseMaterialAttempt2)
                  ElevatedButton.icon(
                    onPressed: () => _promptUploadOrReplace(team, stageLabel, item),
                    icon: const Icon(Icons.replay_rounded, size: 15),
                    label: const Text('Re-upload for Attempt #2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: fileLocked ? null : () => _promptUploadOrReplace(team, stageLabel, item),
                    icon: Icon(uploaded ? Icons.swap_horiz : Icons.upload_file, size: 16),
                    label: Text(uploaded ? 'Replace' : 'Upload', style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uploaded ? Colors.blue.shade600 : DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewFile(String fileUrl, String fileName) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

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
          .fetchAuthenticatedFile(fileUrl);
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
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove file?',
      message: 'Remove submission for "${item['label']}"? This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    await ref.read(capstoneDeliverablesProvider.notifier).removeDeliverable({
      'team_id': team['id'],
      'stage_label': stageLabel,
      'deliverable_id': item['id'],
    });
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
    Uint8List? selectedFileBytes;
    bool isUploading = false;
    double uploadProgress = 0.0;
    String? uploadError;

    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
    final suggestedName = item['suggested_file_name']?.toString() ?? '';

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Upload ${item['id']}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['label']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: formatInfo.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: formatInfo.color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(formatInfo.icon, size: 15, color: formatInfo.color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Accepted: ${formatInfo.description}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: formatInfo.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (suggestedName.isNotEmpty && (item['type'] == 'post' || item['type'] == 'vault')) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.label_important_outline, size: 15, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Expected name: $suggestedName',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (!isUploading)
                  OutlinedButton.icon(
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: formatInfo.extensions,
                        withData: true,
                      );
                      if (result != null && result.files.single.name.isNotEmpty) {
                        setState(() {
                          selectedFileName = result.files.single.name;
                          selectedFileBytes = result.files.single.bytes;
                          final bytes = result.files.single.size;
                          selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
                          uploadError = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: DefensysTokens.maroon),
                      foregroundColor: DefensysTokens.maroon,
                    ),
                  ),
                const SizedBox(height: 16),
                if (selectedFileName != null && !isUploading) ...[
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
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(selectedFileSize ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No file selected.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
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
                            color: Colors.green,
                            backgroundColor: Colors.green.withValues(alpha: 0.15),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Uploading ${selectedFileName ?? "file"}...', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
                if (uploadError != null) ...[
                  const SizedBox(height: 12),
                  Text(uploadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedFileName != null && !isUploading)
                  ? () async {
                      final ext = selectedFileName!.contains('.')
                          ? selectedFileName!.split('.').last.toLowerCase()
                          : '';
                      if (formatInfo.extensions.isNotEmpty &&
                          !formatInfo.extensions.contains(ext)) {
                        setState(() {
                          uploadError =
                              "Invalid file format (.$ext). Please upload a file matching: ${formatInfo.description}";
                        });
                        return;
                      }

                      final suggestedName = item['suggested_file_name']?.toString() ?? '';
                      if ((item['type'] == 'post' || item['type'] == 'vault') && suggestedName.isNotEmpty) {
                        if (selectedFileName!.trim().toLowerCase() != suggestedName.trim().toLowerCase()) {
                          setState(() {
                            uploadError = "File name must match exactly.\nExpected: '$suggestedName'";
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
                        final client = ref.read(authenticatedHttpClientProvider);
                        final uri = Uri.parse('${ApiConfig.capstoneDeliverablesUrl}/upload/');
                        final request = MultipartRequestWithProgress(
                          'POST',
                          uri,
                          onProgress: (sent, total) {
                            if (total > 0) {
                              setState(() {
                                uploadProgress = sent / total;
                              });
                            }
                          },
                        );
                        request.fields['team_id'] = team['id'].toString();
                        request.fields['stage_label'] = stageLabel;
                        request.fields['deliverable_id'] = item['id'].toString();
                        request.fields['file_name'] = selectedFileName!;
                        request.fields['file_size'] = selectedFileSize ?? '';
                        request.files.add(
                          http.MultipartFile.fromBytes(
                            'file',
                            selectedFileBytes!,
                            filename: selectedFileName!,
                          ),
                        );
                        final response = await client.sendAuthenticated(request);
                        if (response.statusCode == 200) {
                          await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                                successMessage: 'Uploaded successfully.',
                              );
                          if (context.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } else {
                          final body = await response.stream.bytesToString();
                          setState(() {
                            isUploading = false;
                            uploadError = _formatUploadFailureMessage(response.statusCode, body);
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
              style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon, foregroundColor: Colors.white),
              child: const Text('Save Upload'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWPRDialog(Map<String, dynamic> team, String stageLabel) {
    final weekNumberCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final now = DateTime.now();
    dateCtrl.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    String? selectedFileName;
    String? selectedFileSize;
    Uint8List? selectedFileBytes;
    bool isSubmitting = false;

    final studentData = widget.studentData;
    final leaderName = team['leader_name'] ?? team['leaderName'] as String?;
    final studentName = studentData?['student']?['name'] as String?;
    final isLeader = leaderName == studentName;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickFile() async {
            try {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
                withData: true,
              );
              if (result != null && result.files.single.name.isNotEmpty) {
                setState(() {
                  selectedFileName = result.files.single.name;
                  selectedFileBytes = result.files.single.bytes;
                  final bytes = result.files.single.size;
                  selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
                });
              }
            } catch (e) {
              if (context.mounted) showErrorToast(context, 'Error picking file: $e');
            }
          }

          Future<void> submitReport() async {
            if (weekNumberCtrl.text.trim().isEmpty) {
              showValidationToast(context, 'Please enter week number');
              return;
            }
            if (selectedFileName == null || selectedFileBytes == null) {
              showValidationToast(context, 'Please select a PDF file');
              return;
            }
            final week = weekNumberCtrl.text.trim();
            final fileName = selectedFileName!;

            final confirmed = await confirmDestructive(
              context,
              title: 'Submit Weekly Report?',
              message: 'Week $week — $fileName. This submission will be sent to your adviser.',
              confirmLabel: 'Submit',
            );
            if (!confirmed || !mounted) return;

            setState(() => isSubmitting = true);
            try {
              final client = ref.read(authenticatedHttpClientProvider);
              final request = http.MultipartRequest(
                'POST',
                Uri.parse('${ApiConfig.weeklyProgressUrl}/'),
              );
              request.fields['team'] = team['id'].toString();
              request.fields['week_number'] = week;
              request.fields['report_date'] = dateCtrl.text.trim();
              request.fields['file_size'] = selectedFileSize ?? '';
              request.fields['accomplishments'] = '[]';
              request.fields['contributions'] = '[]';
              request.fields['issues'] = '[]';
              request.fields['plans'] = '[]';

              request.files.add(http.MultipartFile.fromBytes(
                'report_file',
                selectedFileBytes!,
                filename: fileName,
              ));

              final responseStream = await client.sendAuthenticated(request);
              final response = await http.Response.fromStream(responseStream);

              if (response.statusCode == 201 || response.statusCode == 200) {
                await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                      scope: 'capstone',
                      successMessage: 'Weekly report submitted successfully!',
                    );
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                }
              } else {
                throw Exception('Failed to submit: ${response.body}');
              }
            } catch (e) {
              if (context.mounted) showErrorToast(context, 'Error: $e');
            } finally {
              setState(() => isSubmitting = false);
            }
          }

          return AlertDialog(
            title: const Text('Weekly Progress Reports'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isLeader)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Only the team leader can submit weekly progress reports.',
                          style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    TextField(
                      controller: weekNumberCtrl,
                      keyboardType: TextInputType.number,
                      enabled: isLeader && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Week Number *',
                        hintText: 'e.g. 1, 2, 3...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      enabled: isLeader && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Report Date',
                        prefixIcon: Icon(Icons.event),
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() {
                            dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Upload Report (PDF only) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: (isLeader && !isSubmitting) ? pickFile : null,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Choose PDF File'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        side: BorderSide(color: DefensysTokens.maroon),
                        foregroundColor: DefensysTokens.maroon,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedFileName != null)
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(selectedFileName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(selectedFileSize ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              if (isLeader)
                ElevatedButton.icon(
                  onPressed: (isSubmitting || selectedFileName == null) ? null : submitReport,
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Submit Report'),
                  style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon, foregroundColor: Colors.white),
                ),
            ],
          );
        },
      ),
    );
  }
}
