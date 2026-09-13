import 'dart:async';
import 'dart:convert';
import 'dart:ui';

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
import '../../../utils/progress_upload.dart';
import '../../../utils/universal_file_viewer.dart';
import '../../../widgets/export/deliverable_document_reader_screen.dart';

/// Smooth dashed border painter for the upload dropzone container.
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  const _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.radius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double dash = 5.0;
    const double gap = 3.5;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len = (distance + dash < metric.length) ? dash : metric.length - distance;
        dashPath.addPath(metric.extractPath(distance, distance + len), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

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

  String _formatDateString(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final m = months[dt.month - 1];
      final d = dt.day;
      final y = dt.year;
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$m $d, $y · $hour:$min $period';
    } catch (_) {
      return raw.split('T').first;
    }
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
    final isAllDone = total > 0 && done == total;
    final double progressPercent = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final int percentInt = (progressPercent * 100).round();
    final remaining = total - done;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Overline label + Pill counter badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CLEARANCE PROGRESS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: isAllDone
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAllDone
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5.5,
                      height: 5.5,
                      decoration: BoxDecoration(
                        color: isAllDone
                            ? const Color(0xFF15803D)
                            : const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isAllDone
                          ? 'Clear for Defense'
                          : '$done / $total Cleared',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isAllDone
                            ? const Color(0xFF15803D)
                            : const Color(0xFF1D4ED8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Prominent Title
          const Text(
            'Pre-Defense Clearance Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),

          // Row 3: Smooth Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              width: double.infinity,
              child: LinearProgressIndicator(
                value: progressPercent,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isAllDone ? const Color(0xFF16A34A) : DefensysTokens.maroon,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Row 4: Percent Completed & Status text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$percentInt% Completed',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isAllDone ? const Color(0xFF16A34A) : DefensysTokens.maroon,
                ),
              ),
              Text(
                total == 0
                    ? 'No requirements configured'
                    : (isAllDone
                        ? 'All documents ready'
                        : (remaining == 1
                            ? 'Awaiting 1 document'
                            : 'Awaiting $remaining documents')),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
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
    final feedback = replacementUnlockedByAdmin ? '' : rawFeedback;
    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
    final fileName = (submission['file_name'] ?? item['label'] ?? 'Document').toString();
    final uploadedBy = (submission['uploaded_by_name'] ?? 'Team Member').toString();
    final uploadedAt = (submission['uploaded_at'] ?? submission['date'] ?? '').toString();
    final isRequired = item['required'] == true && !isWaived;

    final Color cardBorderColor = (isWaived || isAccepted)
        ? const Color(0xFF86EFAC)
        : (isRejected
            ? const Color(0xFFFECACA)
            : (uploaded
                ? const Color(0xFFFDE68A)
                : (isRequired ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0))));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Title & Status Pill Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    item['label']?.toString() ?? 'Requirement',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: DefensysTokens.textPrimary,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusPill(
                  isWaived: isWaived,
                  isAccepted: isAccepted,
                  isRejected: isRejected,
                  uploaded: uploaded,
                  isRequired: isRequired,
                ),
              ],
            ),
            if (!uploaded ||
                (item['description'] != null &&
                    item['description'].toString().isNotEmpty &&
                    !item['description'].toString().toLowerCase().contains('standard format'))) ...[
              const SizedBox(height: 4),
              Text(
                (item['description'] != null &&
                        item['description'].toString().isNotEmpty &&
                        !item['description'].toString().toLowerCase().contains('standard format'))
                    ? item['description'].toString()
                    : (isRequired ? 'Mandatory for oral defense' : 'Optional document'),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),

            // Main Action Container (Uploaded vs Empty vs WPR)
            if (isWPR) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assessment_outlined, size: 16, color: DefensysTokens.maroon),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Weekly Progress Reports (Team)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _showWPRDialog(team, stageLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('Weekly Reports', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ] else if (uploaded) ...[
              Builder(builder: (context) {
                final actualFormat = DeliverableFormatInfo.fromFileName(fileName);
                return Material(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => _showDeliverableDetailsSheet(
                      team,
                      stageLabel,
                      item,
                      endorsed,
                      stageGrade,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          // Squircle File Extension Badge (Image 2 style)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: actualFormat.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: actualFormat.color.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              actualFormat.badgeCode,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: actualFormat.color,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  actualFormat.label,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Details Action Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Details',
                                  style: TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 3),
                                Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                          if (isDefenseMaterialAttempt2) ...[
                            const SizedBox(width: 6),
                            Material(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                onTap: () => _promptUploadOrReplace(team, stageLabel, item),
                                borderRadius: BorderRadius.circular(6),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  child: Text(
                                    'Attempt #2',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ] else ...[
              // Empty State: Dashed Upload Dropzone Container (Images 1 & 2)
              if (fileLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Text(
                        'Upload locked until oral defense is scheduled',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DefensysTokens.maroon.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _promptUploadOrReplace(team, stageLabel, item),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children:
                            [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.cloud_upload_rounded,
                                  size: 20,
                                  color: DefensysTokens.maroon,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Upload ${(item['label']?.toString().trim().isNotEmpty == true) ? item['label'] : 'Deliverable'}",
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: DefensysTokens.maroon,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Accepted: ${formatInfo.label} • Max 50 MB',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: DefensysTokens.maroon,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: DefensysTokens.maroon.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded, size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Upload',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            // 4. Panel Remarks / Rejection Feedback Banner
            if (uploaded && isRejected && feedback.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Remarks: $feedback',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B), fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 5. Bottom Attribution Row
            const SizedBox(height: 8),
            Row(
              children: [
                if (uploaded) ...[
                  const Icon(Icons.person_outline_rounded, size: 12, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Builder(builder: (ctx) {
                      final cardDate = _formatDateString(uploadedAt).split('·').first.trim();
                      return Text(
                        'Uploaded by $uploadedBy${cardDate.isNotEmpty ? ' • $cardDate' : ''}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }),
                  ),
                ] else ...[
                  const Expanded(
                    child: Text(
                      'Awaiting team upload',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill({
    required bool isWaived,
    required bool isAccepted,
    required bool isRejected,
    required bool uploaded,
    required bool isRequired,
  }) {
    if (isWaived || isAccepted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF15803D)),
            SizedBox(width: 3.5),
            Text(
              'Approved',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
            ),
          ],
        ),
      );
    } else if (uploaded) {
      if (isRejected) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFFDC2626)),
              SizedBox(width: 3.5),
              Text(
                'Needs Revision',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 11, color: Color(0xFFD97706)),
              SizedBox(width: 3.5),
              Text(
                'Under Review',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
              ),
            ],
          ),
        );
      }
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isRequired ? const Color(0xFFFFF1F2) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRequired ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: isRequired ? const Color(0xFFE11D48) : const Color(0xFF94A3B8),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isRequired ? 'Action Required' : 'Optional',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isRequired ? const Color(0xFFBE123C) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showDeliverableDetailsSheet(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    bool endorsed,
    Map<String, dynamic>? stageGrade,
  ) {
    final submission = Map<String, dynamic>.from(item['submission'] as Map? ?? const {});
    final uploaded = item['uploaded'] == true;
    final fileName = (submission['file_name'] ?? item['label'] ?? 'Document').toString();
    final fileUrl = (submission['file_url'] ?? '').toString();
    final uploadedBy = (submission['uploaded_by_name'] ?? 'Team Member').toString();
    final uploadedAt = (submission['uploaded_at'] ?? submission['date'] ?? '').toString();
    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
    final actualFormat = uploaded ? DeliverableFormatInfo.fromFileName(fileName) : formatInfo;
    final sizeStr = (submission['file_size'] ?? submission['size'] ?? '').toString();
    final status = submission['status']?.toString();
    final isAccepted = status == 'accepted';
    final isRejected = status == 'rejected' || status == 'Needs Revision';
    final rawFeedback = (submission['feedback'] ?? item['feedback'])?.toString() ?? '';
    final isWPR = item['id'] == 'WPR';
    final isWaived = item['is_waived'] == true;
    final isRequired = item['required'] == true && !isWaived;
    final stageVerdict = stageGrade?['verdict']?.toString();
    final isForRedefense = stageVerdict == 'for_redefense';
    final replacementUnlockedByAdmin = rawFeedback.contains('Unlocked for file replacement');
    final isDefenseMaterialAttempt2 = isForRedefense && item['type'] == 'pre' && item['is_defense_material'] == true;
    final fileLocked = !isDefenseMaterialAttempt2 && !replacementUnlockedByAdmin && !isRejected && ((item['type'] == 'pre' && endorsed) || item['locked'] == true || isAccepted);

    final formattedDate = _formatDateString(uploadedAt);
    final suggestedName = (item['suggested_file_name'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header with squircle badge & details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: actualFormat.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: actualFormat.color.withValues(alpha: 0.25)),
                  ),
                  alignment: Alignment.center,
                  child: uploaded
                      ? Text(
                          actualFormat.badgeCode,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: actualFormat.color,
                            letterSpacing: 0.4,
                          ),
                        )
                      : Icon(formatInfo.icon, size: 22, color: formatInfo.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['label']?.toString() ?? 'Deliverable',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: actualFormat.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              actualFormat.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: actualFormat.color,
                              ),
                            ),
                          ),
                          if (isRequired) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'MANDATORY',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF991B1B),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                  tooltip: 'Close',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  onPressed: () => Navigator.pop(modalCtx),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Verification Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isWaived || isAccepted
                    ? const Color(0xFFF0FDF4)
                    : (isRejected ? const Color(0xFFFEF2F2) : (uploaded ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC))),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isWaived || isAccepted
                      ? const Color(0xFFBBF7D0)
                      : (isRejected ? const Color(0xFFFECACA) : (uploaded ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0))),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isWaived || isAccepted
                        ? Icons.verified_rounded
                        : (isRejected ? Icons.warning_amber_rounded : (uploaded ? Icons.schedule_rounded : Icons.info_outline_rounded)),
                    size: 16,
                    color: isWaived || isAccepted
                        ? const Color(0xFF15803D)
                        : (isRejected ? const Color(0xFFDC2626) : (uploaded ? const Color(0xFFD97706) : const Color(0xFF64748B))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isWaived
                              ? 'Status: Approved with no revisions'
                              : (isAccepted
                                  ? 'Status: Accepted for Oral Defense'
                                  : (isRejected
                                      ? 'Status: Revisions Requested'
                                      : (uploaded ? 'Status: Awaiting Faculty Review' : 'Status: Awaiting Upload'))),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isWaived || isAccepted
                                ? const Color(0xFF15803D)
                                : (isRejected ? const Color(0xFFDC2626) : (uploaded ? const Color(0xFFB45309) : const Color(0xFF475569))),
                          ),
                        ),
                        Text(
                          isAccepted
                              ? 'Verified and cleared by the defense committee.'
                              : (isRejected
                                  ? 'Please review panel remarks and submit revised file.'
                                  : (uploaded ? 'Submitted and queued for verification.' : 'Please upload document before the stage deadline.')),
                          style: TextStyle(
                            fontSize: 10,
                            color: isWaived || isAccepted
                                ? const Color(0xFF166534)
                                : (isRejected ? const Color(0xFF991B1B) : const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // File Properties & Info (matching reference Image 1)
            if (uploaded && !isWPR) ...[
              const Text(
                'FILE PROPERTIES & INFO',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildDetailsPropertyRow(
                      label: 'Type',
                      value: actualFormat.label,
                      icon: actualFormat.icon,
                      iconColor: actualFormat.color,
                    ),
                    const Divider(height: 14, color: Color(0xFFEEF2F6)),
                    _buildDetailsPropertyRow(
                      label: 'Location / Stage',
                      value: stageLabel.isNotEmpty ? stageLabel : 'Current Defense Stage',
                      icon: Icons.folder_outlined,
                      iconColor: const Color(0xFF64748B),
                    ),
                    if (sizeStr.isNotEmpty) ...[
                      const Divider(height: 14, color: Color(0xFFEEF2F6)),
                      _buildDetailsPropertyRow(
                        label: 'Size',
                        value: sizeStr,
                        icon: Icons.data_usage_outlined,
                        iconColor: const Color(0xFF64748B),
                      ),
                    ],
                    const Divider(height: 14, color: Color(0xFFEEF2F6)),
                    _buildDetailsPropertyRow(
                      label: 'Uploaded By',
                      value: uploadedBy,
                      icon: Icons.person_outline_rounded,
                      iconColor: const Color(0xFF64748B),
                    ),
                    if (formattedDate.isNotEmpty) ...[
                      const Divider(height: 14, color: Color(0xFFEEF2F6)),
                      _buildDetailsPropertyRow(
                        label: 'Created / Submitted',
                        value: formattedDate,
                        icon: Icons.calendar_today_outlined,
                        iconColor: const Color(0xFF64748B),
                      ),
                    ],
                    const Divider(height: 14, color: Color(0xFFEEF2F6)),
                    if (suggestedName.isNotEmpty && (item['type'] == 'post' || item['type'] == 'vault')) ...[
                      _buildDetailsPropertyRow(
                        label: 'File Name',
                        value: suggestedName,
                        icon: Icons.insert_drive_file_outlined,
                        iconColor: DefensysTokens.maroon,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF64748B)),
                          tooltip: 'Copy file name',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(2),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: suggestedName));
                            showSuccessToast(context, 'Filename copied to clipboard');
                          },
                        ),
                      ),
                      if (fileName.isNotEmpty && fileName != suggestedName) ...[
                        const Divider(height: 14, color: Color(0xFFEEF2F6)),
                        _buildDetailsPropertyRow(
                          label: 'Uploaded As',
                          value: fileName,
                          icon: Icons.history_rounded,
                          iconColor: const Color(0xFF64748B),
                        ),
                      ],
                    ] else ...[
                      _buildDetailsPropertyRow(
                        label: 'File Name',
                        value: fileName,
                        icon: Icons.insert_drive_file_outlined,
                        iconColor: const Color(0xFF64748B),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF64748B)),
                          tooltip: 'Copy file name',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(2),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: fileName));
                            showSuccessToast(context, 'Filename copied to clipboard');
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Remarks / Feedback (if available)
            if (rawFeedback.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isRejected ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRejected ? 'Panel Revision Remarks:' : 'Panel Feedback:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isRejected ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rawFeedback,
                      style: TextStyle(
                        fontSize: 12,
                        color: isRejected ? const Color(0xFF7F1D1D) : const Color(0xFF14532D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons Row inside modal
            Row(
              children: [
                if (uploaded && !isWPR) ...[
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        _viewFile(
                          fileUrl,
                          fileName,
                          item: item,
                          team: team,
                          stageLabel: stageLabel,
                          endorsed: endorsed,
                          stageGrade: stageGrade,
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View Document', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (uploaded && !fileLocked && !isWPR) ...[
                  IconButton(
                    onPressed: () {
                      Navigator.pop(modalCtx);
                      _removeFile(team, stageLabel, item);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                    tooltip: 'Remove Submission',
                  ),
                  const SizedBox(width: 4),
                ],
                if (!fileLocked && !isWaived && !isWPR) ...[
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        _promptUploadOrReplace(team, stageLabel, item);
                      },
                      icon: Icon(uploaded ? Icons.swap_horiz_rounded : Icons.upload_file_rounded, size: 16),
                      label: Text(uploaded ? 'Replace File' : 'Upload File', style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.maroon,
                        side: const BorderSide(color: DefensysTokens.maroon),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsPropertyRow({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing,
        ],
      ],
    );
  }

  Future<void> _viewFile(
    String fileUrl,
    String fileName, {
    Map<String, dynamic>? item,
    Map<String, dynamic>? team,
    String? stageLabel,
    bool? endorsed,
    Map<String, dynamic>? stageGrade,
  }) async {
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

      final actualFormat = DeliverableFormatInfo.fromFileName(fileName);
      DeliverablePropertiesInfo? propsInfo;
      if (item != null) {
        final submission = Map<String, dynamic>.from(item['submission'] as Map? ?? const {});
        final uploadedBy = (submission['uploaded_by_name'] ?? 'Team Member').toString();
        final uploadedAt = (submission['uploaded_at'] ?? submission['date'] ?? '').toString();
        final formattedDate = _formatDateString(uploadedAt);
        final status = submission['status']?.toString();
        final isAccepted = status == 'accepted';
        final isRejected = status == 'rejected' || status == 'Needs Revision';
        final rawFeedback = (submission['feedback'] ?? item['feedback'])?.toString() ?? '';
        final isWaived = item['is_waived'] == true;
        final sizeStr = submission['file_size']?.toString().isNotEmpty == true
            ? submission['file_size'].toString()
            : FileViewerMetadata.formatBytes(bytes.length);

        propsInfo = DeliverablePropertiesInfo(
          fileSize: sizeStr,
          fileType: actualFormat.label,
          uploader: uploadedBy,
          timestamp: formattedDate.isNotEmpty ? formattedDate : 'Recently',
          status: status,
          feedback: rawFeedback,
          isApproved: isAccepted || isWaived,
          isRejected: isRejected,
          teamName: team?['name']?.toString() ?? team?['team_name']?.toString() ?? 'Team',
          stageLabel: stageLabel,
        );
      }

      final isPdf = fileName.toLowerCase().endsWith('.pdf') ||
          (bytes.length >= 4 &&
              bytes[0] == 0x25 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x44 &&
              bytes[3] == 0x46); // %PDF

      if (isPdf) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => DeliverableDocumentReaderScreen(
              fileBytes: Uint8List.fromList(bytes),
              fileName: fileName,
              deliverableLabel: item?['label']?.toString(),
              stageLabel: stageLabel,
              teamName: team?['name']?.toString() ?? team?['team_name']?.toString(),
              propertiesInfo: propsInfo,
            ),
          ),
        );
      } else {
        await viewFileInDialog(
          context: context,
          fileBytes: bytes,
          fileName: fileName,
          propertiesInfo: propsInfo,
        );
      }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cloud_upload_rounded, size: 20, color: DefensysTokens.maroon),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Upload ${item['id']}",
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(
                      item['label']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: formatInfo.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: formatInfo.color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(formatInfo.icon, size: 15, color: formatInfo.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Accepted: ${formatInfo.description} • Max 50 MB',
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
                const SizedBox(height: 14),

                // Hero Dropzone (when no file selected)
                if (selectedFileName == null && !isUploading) ...[
                  InkWell(
                    onTap: () async {
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
                          selectedFileSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
                          if (bytes < 1024 * 1024) {
                            selectedFileSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
                          }
                          uploadError = null;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: CustomPaint(
                      painter: _DashedRectPainter(
                        color: const Color(0xFFCBD5E1),
                        strokeWidth: 1.5,
                        radius: 10,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_upload_rounded,
                                size: 28,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Click to browse or drop your document here',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Select any file with ${formatInfo.label} extension',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Rich File Preview Card (when file selected)
                if (selectedFileName != null && !isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.description_rounded, color: Color(0xFF15803D), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFileName!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${selectedFileSize ?? ""} • Ready to submit',
                                style: const TextStyle(
                                  color: Color(0xFF15803D),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Change file',
                          icon: const Icon(Icons.sync_rounded, color: Color(0xFF15803D), size: 20),
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
                                selectedFileSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
                                if (bytes < 1024 * 1024) {
                                  selectedFileSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
                                }
                                uploadError = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                // Recommended File Name Notice (with Copy Button)
                if (!isUploading && suggestedName.isNotEmpty && (item['type'] == 'post' || item['type'] == 'vault')) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Recommended File Name:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: suggestedName));
                                showSuccessToast(context, 'Recommended filename copied');
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.copy_rounded, size: 13, color: DefensysTokens.maroon),
                                    SizedBox(width: 4),
                                    Text(
                                      'Copy',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: DefensysTokens.maroon,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          suggestedName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.maroon,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'You can rename your file to this, or upload directly and DefenSYS will auto-rename it for you.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF64748B),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Upload Progress State
                if (isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: DefensysTokens.maroon),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Uploading ${selectedFileName ?? "document"}...',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${(uploadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: DefensysTokens.maroon, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            color: DefensysTokens.maroon,
                            backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (uploadError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            uploadError!,
                            style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w500),
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
              onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton.icon(
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
              icon: isUploading
                  ? const SizedBox.shrink()
                  : const Icon(Icons.cloud_upload_rounded, size: 16),
              label: Text(isUploading ? 'Uploading...' : 'Submit Deliverable'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
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
