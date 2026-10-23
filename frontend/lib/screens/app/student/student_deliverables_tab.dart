import 'package:defensys/widgets/defense/system_defense_records.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/academic/student_team_selection_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../utils/progress_upload.dart';
import '../../../utils/universal_file_viewer.dart';
import '../../../widgets/repository/defense_material_readiness.dart';

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
    final selectedTeamId = ref.watch(studentTeamSelectionProvider);
    final team = state.teams.where((t) => t['id'] == selectedTeamId).firstOrNull ?? state.teams.firstOrNull;

    if (state.isLoading && team == null) {
      return Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroonOf(context)),
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
                style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroonOf(context)),
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
    final noEndorsementNeeded = !widget.isCapstone &&
        configured &&
        selectedStage['endorsement_required'] == false;
    final pre = _deliverables(selectedStage, 'pre');
    final vault = _deliverables(selectedStage, 'post');
    final postUnlocked = selectedStage['vault_unlocked'] == true ||
        selectedStage['archive_unlocked'] == true ||
        selectedStage['post_unlocked'] == true;
    final systemRecords = _deliverables(selectedStage, 'system');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.teams.length > 1) Padding(padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<int>(
            key: ValueKey('deliverables-team-${team['id']}'), initialValue: team['id'] as int,
            isExpanded: true, decoration: const InputDecoration(labelText: 'Team'),
            items: state.teams.map((t) => DropdownMenuItem<int>(value: t['id'] as int,
              child: Text('${t['name']} · ${t['current_defense_stage'] ?? t['level'] ?? ''}',
                  overflow: TextOverflow.ellipsis))).toList(),
            onChanged: state.isSaving ? null : (id) {
              ref.read(studentTeamSelectionProvider.notifier).select(id);
              final next = state.teams.where((t) => t['id'] == id).firstOrNull;
              final stage = next?['current_defense_stage']?.toString();
              if (stage != null && state.stageOptions.contains(stage)) {
                ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(selectedStage: stage);
              }
            },
          )),
        if (!widget.hideHeader) ...[
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DefensysTokens.maroonOf(context),
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
                        return TeamWorkflowBadge(status: TeamWorkflowStatus.fromStage(
                          selectedStage, scope: widget.isCapstone ? 'capstone' : 'pit'));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "${widget.isCapstone ? 'Stage' : 'Event'}: ${state.selectedStage}",
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
                                  'No student file submissions are required for this milestone.',
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
                          color: DefensysTokens.surfaceOf(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                  Icon(
                                    endorsed || noEndorsementNeeded
                                        ? Icons.verified_rounded
                                        : Icons.pending_actions_rounded,
                                    size: 16,
                                    color: endorsed || noEndorsementNeeded
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFD97706),
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  endorsed
                                      ? 'Adviser Endorsed — Ready for Scheduling'
                                      : noEndorsementNeeded
                                          ? 'Ready to Schedule'
                                          : 'Awaiting Adviser Verbal Endorsement',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: endorsed || noEndorsementNeeded
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              endorsed
                                  ? 'Your adviser has endorsed your team. Administrators can now schedule your presentation / demo slot.'
                                  : noEndorsementNeeded
                                      ? 'No endorsement or file uploads are needed for scheduling. Prepare your presentation materials, slides, and live demonstration.'
                                      : 'Prepare your presentation materials, slides, and live demonstration. Your adviser can endorse your readiness directly without file uploads.',
                              style: TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.textSecondaryOf(context),
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
                    final hasPendingScheduling = pre
                        .where((item) => item['requirement_timing'] != 'defense')
                        .any(StudentTaskBadgeHelper.isDeliverablePending);
                    final hasPendingPost = StudentTaskBadgeHelper.hasPendingPostDeliverables(selectedStage);
                    final stageGrade = (selectedStage['grade'] as Map<String, dynamic>?) ??
                        (selectedStage['grade'] is Map ? Map<String, dynamic>.from(selectedStage['grade'] as Map) : null);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConceptWorkspace(teamId: team['id'] as int, stageLabel: state.selectedStage, stage: selectedStage),
                        _buildRequiredProgressBlock(pre.where((item) => item['requirement_timing'] != 'defense').toList()),
                        const SizedBox(height: 16),
                        _sectionTitle(
                          widget.isCapstone ? 'Pre-defense deliverables' : noEndorsementNeeded ? 'Before scheduling' : 'Before endorsement',
                          showRedDot: hasPendingScheduling,
                        ),
                        const SizedBox(height: 8),
                        if (!pre.any((item) => item['requirement_timing'] != 'defense'))
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No files are required before endorsement or scheduling.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                noEndorsementNeeded
                                    ? 'Required files here must be cleared before your team can be scheduled.'
                                    : 'Required files here must be cleared before your team can be endorsed.',
                                style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                              ),
                            ),
                            ...pre.where((item) => item['requirement_timing'] != 'defense')
                                .map((item) => _deliverableRow(team, state.selectedStage, item, endorsed, stageGrade)),
                          ],
                        if (pre.any((item) => item['requirement_timing'] == 'defense')) ...[
                          const SizedBox(height: 10),
                          _sectionTitle('Before Your Defense'),
                          const SizedBox(height: 8),
                          DefenseMaterialReadiness(readiness: Map<String, dynamic>.from(
                              selectedStage['materials_readiness'] as Map? ?? const {})),
                          ...pre.where((item) => item['requirement_timing'] == 'defense')
                              .map((item) => _deliverableRow(team, state.selectedStage, item, endorsed, stageGrade)),
                        ],
                        const SizedBox(height: 20),
                        if (stageGrade != null) ...[
                          _buildDirectivesCard(stageGrade),
                        ],
                        if (vault.isNotEmpty) ...[
                          _sectionTitle('Post-Defense Submissions', showRedDot: hasPendingPost),
                          const SizedBox(height: 8),
                          if (!postUnlocked)
                            _lockedVaultNotice(state.selectedStage, stageGrade)
                          else
                            ...vault.map((item) => _deliverableRow(team, state.selectedStage, item, endorsed, stageGrade)),
                        ],
                      ],
                    );
                  },
                ),
                if (systemRecords.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SystemDefenseRecords(items: systemRecords),
                ],
              ],
            ],
          );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroonOf(context),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.maroonTextOf(context),
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
    final done = requiredItems.where((item) {
      final submission = item['submission'] as Map?;
      return submission != null && (widget.isCapstone
          ? submission['status'] == 'accepted'
          : submission['status'] != 'rejected');
    }).length;
    final isAllDone = total == 0 || done == total;
    final double progressPercent = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final int percentInt = (progressPercent * 100).round();
    final remaining = total - done;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DefensysTokens.borderOf(context), width: 1.2),
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
              Expanded(child: Text(
                'CLEARANCE PROGRESS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.textSecondaryOf(context),
                  letterSpacing: 0.8,
                ),
              )),
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
                          ? 'Clear for Scheduling'
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
          Text(
            'Scheduling Clearance Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.textPrimaryOf(context),
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
                  isAllDone ? const Color(0xFF16A34A) : DefensysTokens.maroonOf(context),
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
                  color: isAllDone ? const Color(0xFF16A34A) : DefensysTokens.maroonTextOf(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  total == 0
                      ? 'No scheduling requirements'
                      : (isAllDone
                          ? 'All documents ready'
                          : (remaining == 1
                              ? 'Awaiting 1 document'
                              : 'Awaiting $remaining documents')),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
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
                    color: DefensysTokens.surfaceOf(context),
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
                color: DefensysTokens.surfaceOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remarks,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: DefensysTokens.textPrimaryOf(context),
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
    if (usesGroupedDocumentCard(item)) {
      return DocumentGroup(
        teamId: team['id'] as int,
        stageLabel: stageLabel,
        item: item,
        programScope: widget.isCapstone ? 'capstone' : 'pit',
      );
    }
    final uploaded = hasSubmittedDeliverable(item);
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
    final isDefenseUploaded = item['requirement_timing'] == 'defense' && uploaded && !isRejected;

    final replacementUnlockedByAdmin = item['type'] == 'pre' && isAccepted &&
        submission['file_replacement_unlocked'] == true;
    final isDefenseMaterialAttempt2 = isForRedefense && item['type'] == 'pre' && item['is_defense_material'] == true;
    final fileLocked = item['can_upload'] is bool ? item['can_upload'] != true :
        !replacementUnlockedByAdmin && (isAccepted || (!isDefenseMaterialAttempt2 && !isRejected &&
        ((item['type'] == 'pre' && endorsed) || item['locked'] == true)));
    final isWPR = item['id'] == 'WPR';
    final feedback = rawFeedback;
    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
    final fileName = (submission['file_name'] ?? item['label'] ?? 'Document').toString();
    final uploadedBy = (submission['uploaded_by_name'] ?? 'Team Member').toString();
    final uploadedAt = (submission['uploaded_at'] ?? submission['date'] ?? '').toString();
    final isRequired = item['required'] == true && !isWaived;
    final dueAfterScheduling = item['requirement_timing'] == 'defense' &&
        item['materials_status'] == 'awaiting_schedule';

    final cardBorderColor = (isWaived || isAccepted || isDefenseUploaded)
        ? Color.alphaBlend(DefensysTokens.success.withValues(alpha: .3), DefensysTokens.borderOf(context))
        : DefensysTokens.borderOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: DefensysTokens.textPrimaryOf(context),
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
                  isPost: item['type'] == 'post',
                  isRejected: isRejected,
                  uploaded: uploaded,
                  isRequired: isRequired,
                  isDefenseTimed: item['requirement_timing'] == 'defense',
                  dueAfterScheduling: dueAfterScheduling,
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
                style: TextStyle(
                  fontSize: 11.5,
                  color: DefensysTokens.textSecondaryOf(context),
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (item['requirement_timing'] == 'defense') ...[
              const SizedBox(height: 6),
              Text(item['due_at'] == null
                  ? 'Deadline set when your defense is scheduled'
                  : 'Due: ${materialDeadlineLabel(item['due_at'])}',
                  style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context))),
              if (item['upload_lock_reason']?.toString().isNotEmpty == true)
                Text(item['upload_lock_reason'].toString(), style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),

            // Main Action Container (Uploaded vs Empty vs WPR)
            if (isWPR) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.assessment_outlined, size: 16, color: DefensysTokens.maroonTextOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Weekly Progress Reports (Team)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _showWPRDialog(team, stageLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroonOf(context),
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
              DeliverableUploadedFileTile(
                fileName: fileName,
                onDetails: () => _showDeliverableDetailsSheet(team, stageLabel, item, endorsed, stageGrade),
                onRevision: isRejected && !fileLocked && !isWaived && !isDefenseMaterialAttempt2
                    ? () => _promptUploadOrReplace(team, stageLabel, item) : null,
                trailing: isDefenseMaterialAttempt2 ? Material(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () => _promptUploadOrReplace(team, stageLabel, item),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text('Attempt #2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ) : null,
              ),
            ] else ...[
              // Empty State: Dashed Upload Dropzone Container (Images 1 & 2)
              if (fileLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Uploads are currently locked for this deliverable',
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DeliverableUploadTile(
                  title: "Upload ${item['label'] ?? 'Deliverable'}",
                  format: formatInfo,
                  onUpload: () => _promptUploadOrReplace(team, stageLabel, item),
                ),
            ],

            if (replacementUnlockedByAdmin) ...[
              const SizedBox(height: 8),
              _replacementNotice(submission),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: fileLocked ? null : () => _promptUploadOrReplace(team, stageLabel, item),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Replace File'),
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
                  Icon(Icons.person_outline_rounded, size: 12, color: DefensysTokens.textSecondaryOf(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Builder(builder: (ctx) {
                      final cardDate = _formatDateString(uploadedAt).split('·').first.trim();
                      return Text(
                        'Uploaded by $uploadedBy${cardDate.isNotEmpty ? ' • $cardDate' : ''}',
                        style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context), fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }),
                  ),
                ] else ...[
                  Expanded(
                    child: Text(
                      'Awaiting team upload',
                      style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context), fontStyle: FontStyle.italic),
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

  Widget _replacementNotice(Map<String, dynamic> submission) {
    final reason = submission['file_replacement_reason']?.toString().trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Text(
        'File replacement requested — upload the correct file. Approval is retained.'
        '${reason.isEmpty ? '' : '\nReason: $reason'}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF115E59)),
      ),
    );
  }

  Widget _buildStatusPill({
    required bool isWaived,
    required bool isAccepted,
    required bool isPost,
    required bool isRejected,
    required bool uploaded,
    required bool isRequired,
    bool isDefenseTimed = false,
    bool dueAfterScheduling = false,
  }) {
    if (isWaived || isAccepted || (isDefenseTimed && uploaded && !isRejected)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF15803D)),
            const SizedBox(width: 3.5),
            Text(
              isDefenseTimed && uploaded ? 'Uploaded' : isPost && isAccepted ? 'Archived' : 'Approved',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
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
          child: Row(
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, size: 11, color: Color(0xFFD97706)),
              const SizedBox(width: 3.5),
              Text(
                isDefenseTimed ? 'Submitted' : 'Under Review',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
              ),
            ],
          ),
        );
      }
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isRequired && !dueAfterScheduling ? const Color(0xFFFFF1F2) : DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRequired && !dueAfterScheduling ? const Color(0xFFFECDD3) : DefensysTokens.borderOf(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: isRequired && !dueAfterScheduling ? const Color(0xFFE11D48) : const Color(0xFF94A3B8),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              dueAfterScheduling ? 'Due later' : isRequired ? 'Action Required' : 'Optional',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isRequired && !dueAfterScheduling ? const Color(0xFFBE123C) : DefensysTokens.textSecondaryOf(context),
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
    final uploaded = hasSubmittedDeliverable(item);
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
    final isPost = item['type'] == 'post';
    final isRejected = status == 'rejected' || status == 'Needs Revision';
    final isDefenseUploaded = item['requirement_timing'] == 'defense' && uploaded && !isRejected;
    final rawFeedback = (submission['feedback'] ?? item['feedback'])?.toString() ?? '';
    final isWPR = item['id'] == 'WPR';
    final isWaived = item['is_waived'] == true;
    final isRequired = item['required'] == true && !isWaived;
    final stageVerdict = stageGrade?['verdict']?.toString();
    final isForRedefense = stageVerdict == 'for_redefense';
    final isDefenseMaterialAttempt2 = isForRedefense && item['type'] == 'pre' && item['is_defense_material'] == true;
    final replacementUnlocked = item['type'] == 'pre' && isAccepted &&
        submission['file_replacement_unlocked'] == true;
    final fileLocked = item['can_upload'] is bool ? item['can_upload'] != true :
        !replacementUnlocked && (isAccepted || (!isDefenseMaterialAttempt2 && !isRejected &&
        ((item['type'] == 'pre' && endorsed) || item['locked'] == true)));

    final formattedDate = _formatDateString(uploadedAt);
    final suggestedName = formatInfo.recommendedFileName(
      (item['suggested_file_name'] ?? '').toString(),
      selectedFileName: uploaded ? fileName : null,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(child: Column(
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimaryOf(context),
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
                  icon: Icon(Icons.close_rounded, size: 20, color: DefensysTokens.textSecondaryOf(context)),
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
                color: isWaived || isAccepted || isDefenseUploaded
                    ? const Color(0xFFF0FDF4)
                    : (isRejected ? const Color(0xFFFEF2F2) : (uploaded ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC))),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isWaived || isAccepted || isDefenseUploaded
                      ? const Color(0xFFBBF7D0)
                      : (isRejected ? const Color(0xFFFECACA) : (uploaded ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0))),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isWaived || isAccepted || isDefenseUploaded
                        ? Icons.verified_rounded
                        : (isRejected ? Icons.warning_amber_rounded : (uploaded ? Icons.schedule_rounded : Icons.info_outline_rounded)),
                    size: 16,
                    color: isWaived || isAccepted || isDefenseUploaded
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
                              ? 'Status: Recorded historical exemption'
                              : isDefenseUploaded ? 'Status: Uploaded'
                              : (isAccepted
                                  ? (isPost ? 'Status: Archived' : 'Status: Accepted for Oral Defense')
                                  : (isRejected
                                      ? 'Status: Revisions Requested'
                                      : (uploaded ? 'Status: Awaiting Faculty Review' : 'Status: Awaiting Upload'))),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isWaived || isAccepted || isDefenseUploaded
                                ? const Color(0xFF15803D)
                                : (isRejected ? const Color(0xFFDC2626) : (uploaded ? const Color(0xFFB45309) : const Color(0xFF475569))),
                          ),
                        ),
                        Text(
                          isAccepted
                              ? (isPost
                                  ? 'Final file approved and available in the archive.'
                                  : 'Verified and cleared by the defense committee.')
                              : (isRejected
                                  ? 'Please review panel remarks and submit revised file.'
                                  : (uploaded ? 'Submitted and queued for verification.' : 'Please upload document before the stage deadline.')),
                          style: TextStyle(
                            fontSize: 10,
                            color: isWaived || isAccepted || isDefenseUploaded
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
              Text(
                'FILE PROPERTIES & INFO',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.textSecondaryOf(context),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
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
                      label: widget.isCapstone ? 'Stage' : 'Event',
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
                        iconColor: DefensysTokens.maroonOf(context),
                        trailing: IconButton(
                          icon: Icon(Icons.copy_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
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
                          icon: Icon(Icons.copy_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
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

            if (replacementUnlocked) ...[
              _replacementNotice(submission),
              const SizedBox(height: 16),
            ],

            if (uploaded && !isWPR)
              DeliverableDetailsActions(
                onView: () {
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
                replacementLabel: isRejected ? 'Upload revision' : 'Replace File',
                onReplace: fileLocked || isWaived ? null : () {
                  Navigator.pop(modalCtx);
                  _promptUploadOrReplace(team, stageLabel, item);
                },
                onRemove: isAccepted || fileLocked ? null : () {
                  Navigator.pop(modalCtx);
                  _removeFile(team, stageLabel, item);
                },
              )
            else if (!fileLocked && !isWaived && !isWPR)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(modalCtx);
                    _promptUploadOrReplace(team, stageLabel, item);
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Upload File'),
                ),
              ),
          ],
        )),
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
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
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
      builder: (context) => Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroonOf(context)),
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

      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
        propertiesInfo: propsInfo,
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
    String recommendedName() => formatInfo.recommendedFileName(
      suggestedName,
      selectedFileName: selectedFileName,
    );

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
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.cloud_upload_rounded, size: 20, color: DefensysTokens.maroonTextOf(context)),
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
                      style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: DefensysTokens.textSecondaryOf(context)),
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
                          color: DefensysTokens.surfaceHigherOf(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.cloud_upload_rounded,
                                size: 28,
                                color: DefensysTokens.maroonTextOf(context),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Click to browse or drop your document here',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Select any file with ${formatInfo.label} extension',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: DefensysTokens.textSecondaryOf(context),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: DefensysTokens.textPrimaryOf(context),
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
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DefensysTokens.borderOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Recommended File Name:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: recommendedName()));
                                showSuccessToast(context, 'Recommended filename copied');
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy_rounded, size: 13, color: DefensysTokens.maroonTextOf(context)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Copy',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: DefensysTokens.maroonTextOf(context),
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
                          recommendedName(),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.maroonTextOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'DefenSYS will automatically standardize this file for the repository archive upon upload.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: DefensysTokens.textSecondaryOf(context),
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
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DefensysTokens.borderOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: DefensysTokens.maroonOf(context)),
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
                              style: TextStyle(fontWeight: FontWeight.bold, color: DefensysTokens.maroonTextOf(context), fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            color: DefensysTokens.maroonOf(context),
                            backgroundColor: DefensysTokens.maroonOf(context).withValues(alpha: 0.15),
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
              child: Text('Cancel', style: TextStyle(color: DefensysTokens.textSecondaryOf(context))),
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

                      // Determine the effective filename for the repository
                      final isPostDefense = item['type'] == 'post' || item['type'] == 'vault';
                      String effectiveFileName = selectedFileName!;

                      if (isPostDefense && suggestedName.isNotEmpty) {
                        // Compare basenames (ignoring extension) to detect mismatch
                        String stripExt(String name) {
                          final dotIdx = name.lastIndexOf('.');
                          return dotIdx > 0 ? name.substring(0, dotIdx) : name;
                        }

                        final targetRepoName = recommendedName();

                        final selectedBase = stripExt(selectedFileName!).trim().toLowerCase();
                        final suggestedBase = stripExt(suggestedName).trim().toLowerCase();

                        if (selectedBase != suggestedBase) {
                          // Show blocking rename confirmation dialog
                          final confirmed = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (confirmCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.drive_file_rename_outline_rounded, size: 20, color: Color(0xFFD97706)),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Filename Will Be Adjusted',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your file:',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DefensysTokens.textSecondaryOf(context)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.surfaceHigherOf(context),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: DefensysTokens.borderOf(context)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.description_outlined, size: 15, color: DefensysTokens.textSecondaryOf(context)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selectedFileName!,
                                            style: TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: DefensysTokens.textPrimaryOf(context)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Repository name:',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DefensysTokens.textSecondaryOf(context)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.maroonOf(context).withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: DefensysTokens.maroonOf(context).withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.inventory_2_outlined, size: 15, color: DefensysTokens.maroonTextOf(context)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            targetRepoName,
                                            style: TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: DefensysTokens.maroonTextOf(context)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEFCE8),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFD97706)),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'The repository requires a standardized filename. Your file will be saved under the repository name shown above.',
                                            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E), height: 1.35),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(confirmCtx, false),
                                  child: Text('Cancel', style: TextStyle(color: DefensysTokens.textSecondaryOf(context))),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(confirmCtx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: DefensysTokens.maroonOf(context),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('OK, Proceed', style: TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;
                          effectiveFileName = targetRepoName;
                        } else {
                          effectiveFileName = targetRepoName;
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
                        request.fields['file_name'] = effectiveFileName;
                        request.fields['file_size'] = selectedFileSize ?? '';
                        request.files.add(
                          http.MultipartFile.fromBytes(
                            'file',
                            selectedFileBytes!,
                            filename: effectiveFileName,
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
                backgroundColor: DefensysTokens.maroonOf(context),
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
                        side: BorderSide(color: DefensysTokens.maroonOf(context)),
                        foregroundColor: DefensysTokens.maroonOf(context),
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
                  style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroonOf(context), foregroundColor: Colors.white),
                ),
            ],
          );
        },
      ),
    );
  }
}
