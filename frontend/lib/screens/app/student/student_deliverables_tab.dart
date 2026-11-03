import 'package:defensys/widgets/repository/deliverable_template.dart';
import 'package:defensys/widgets/defense/system_defense_records.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/deliverable_requirement_card.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../widgets/repository/weekly_report_collection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/academic/student_team_selection_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../utils/universal_file_viewer.dart';

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
  bool _pickingFile = false;

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
        if (!widget.hideHeader && state.teams.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final option in state.teams)
                ChoiceChip(
                  label: Text('${option['name']}'),
                  selected: option['id'] == team['id'],
                  onSelected: state.isSaving ? null : (_) => ref
                      .read(studentTeamSelectionProvider.notifier).select(option['id'] as int),
                ),
            ]),
          ),
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
                    final hasPendingScheduling =
                        pre.any(StudentTaskBadgeHelper.isDeliverablePending);
                    final hasPendingPost = StudentTaskBadgeHelper.hasPendingPostDeliverables(selectedStage);
                    final stageGrade = (selectedStage['grade'] as Map<String, dynamic>?) ??
                        (selectedStage['grade'] is Map ? Map<String, dynamic>.from(selectedStage['grade'] as Map) : null);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConceptWorkspace(
                          teamId: team['id'] as int,
                          stageLabel: state.selectedStage,
                          stage: selectedStage,
                          showTitleCard: false,
                          showHistory: false,
                        ),
                        _buildRequiredProgressBlock(pre),
                        const SizedBox(height: 16),
                        _sectionTitle(
                          widget.isCapstone ? 'Pre-defense deliverables' : noEndorsementNeeded ? 'Before scheduling' : 'Before endorsement',
                          showRedDot: hasPendingScheduling,
                        ),
                        const SizedBox(height: 8),
                        if (pre.isEmpty)
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
                            ...pre
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
      backgroundColor: DefensysTokens.backgroundOf(context),
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
  ]) => DeliverableRequirementCard(
    key: ValueKey('student-requirement-${item['id']}'),
    item: item,
    enabled: !ref.watch(capstoneDeliverablesProvider).isSaving,
    onOpen: () => showDeliverableRequirementDialog(
      context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(capstoneDeliverablesProvider);
          final currentTeam = state.teams
              .where((row) => row['id'] == team['id'])
              .firstOrNull;
          final stage = Map<String, dynamic>.from(
            currentTeam?['selected_stage'] as Map? ?? {},
          );
          final post = item['type'] == 'post' || item['type'] == 'vault';
          final postOpen =
              stage['vault_unlocked'] == true ||
              stage['archive_unlocked'] == true ||
              stage['post_unlocked'] == true;
          final current =
              currentTeam == null ||
                  state.selectedStage != stageLabel ||
                  currentTeam['semester_id'] != team['semester_id'] ||
                  currentTeam['project_version'] != team['project_version'] ||
                  (post && !postOpen)
              ? null
              : _deliverables(stage, post ? 'post' : 'pre')
                    .where(
                      (row) =>
                          row['id'] == item['id'] &&
                          row['source'] == item['source'],
                    )
                    .firstOrNull;
          return DeliverableRequirementDialog(
            item: current ?? item,
            child: current == null
                ? const Text(
                    'This requirement is no longer available in the selected stage. Close this window to return to your deliverables.',
                  )
                : _deliverableDetails(
                    currentTeam!,
                    stageLabel,
                    current,
                    stage['endorsed'] == true,
                    stage['grade'] is Map
                        ? Map<String, dynamic>.from(stage['grade'])
                        : null,
                    context,
                  ),
          );
        },
      ),
    ),
  );

  Widget _deliverableDetails(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    bool endorsed, [
    Map<String, dynamic>? stageGrade,
    BuildContext? popupContext,
  ]) {
    final context = popupContext ?? this.context;
    final inPopup = popupContext != null;
    if (item['source'] == 'weekly_reports') {
      return WeeklyReportCollection(
        teamId: team['id'] as int,
        stageLabel: stageLabel,
        item: item,
        semesterId: int.tryParse('${team['semester_id']}'),
        projectVersion: int.tryParse('${team['project_version']}'),
      );
    }
    if (usesGroupedDocumentCard(item)) {
      return DocumentGroup(
        teamId: team['id'] as int,
        stageLabel: stageLabel,
        item: item,
        programScope: widget.isCapstone ? 'capstone' : 'pit',
        framed: !inPopup,
        showHeader: !inPopup,
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

    final replacementUnlockedByAdmin = item['type'] == 'pre' && isAccepted &&
        submission['file_replacement_unlocked'] == true;
    final isDefenseMaterialAttempt2 = isForRedefense && item['type'] == 'pre' && item['is_defense_material'] == true;
    final saving = ref.read(capstoneDeliverablesProvider).isSaving;
    final fileLocked = saving ||
        (item['can_upload'] is bool
            ? item['can_upload'] != true
            : !replacementUnlockedByAdmin &&
                (isAccepted ||
                    (!isDefenseMaterialAttempt2 && !isRejected &&
                        ((item['type'] == 'pre' && endorsed) ||
                            item['locked'] == true))));
    final feedback = rawFeedback;
    final rawFormat = item['file_format'] ?? item['fileFormat'];
    final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
    final fileName = (submission['file_name'] ?? item['label'] ?? 'Document').toString();
    final uploadedBy = (submission['uploaded_by_name'] ?? 'Team Member').toString();
    final uploadedAt = (submission['uploaded_at'] ?? submission['date'] ?? '').toString();
    final isRequired = item['required'] == true && !isWaived;

    final cardBorderColor = (isWaived || isAccepted)
        ? Color.alphaBlend(DefensysTokens.success.withValues(alpha: .3), DefensysTokens.borderOf(context))
        : DefensysTokens.borderOf(context);

    return Container(
      margin: inPopup ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: inPopup ? null : BoxDecoration(
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
        padding: inPopup ? EdgeInsets.zero : const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Title & Status Pill Badge
            if (!inPopup) Row(
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
            const SizedBox(height: 10),

            if (saving) ...[
              DefensysShadcnScope(
                child: ShadProgress(
                  color: DefensysTokens.maroonOf(context),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Uploading...'),
              const SizedBox(height: 8),
            ],
            // Current file or upload action
            DeliverableTemplateDownload(template: item['template']),
            if (uploaded) ...[
              DeliverableUploadedFileTile(
                fileName: fileName,
                onDetails: () => _showDeliverableDetailsSheet(team, stageLabel, item, endorsed, stageGrade, context),
                onRevision: isRejected && !fileLocked && !isWaived && !isDefenseMaterialAttempt2
                    ? () => _promptUploadOrReplace(team, stageLabel, item, context) : null,
                revisionEnabled: !saving,
                trailing: isDefenseMaterialAttempt2 && !fileLocked ? Material(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () => _promptUploadOrReplace(team, stageLabel, item, context),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text('Attempt #2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ) : null,
              ),
            ] else ...[
              if (fileLocked && !saving)
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
                  enabled: !fileLocked,
                  title: "Upload ${item['label'] ?? 'Deliverable'}",
                  format: formatInfo,
                  onUpload: () => _promptUploadOrReplace(team, stageLabel, item, context),
                ),
            ],

            if (replacementUnlockedByAdmin) ...[
              const SizedBox(height: 8),
              _replacementNotice(submission),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: fileLocked ? null : () => _promptUploadOrReplace(team, stageLabel, item, context),
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
  }) {
    if (isWaived || isAccepted) {
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
              isPost && isAccepted ? 'Archived' : 'Approved',
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
                'Under Review',
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
          color: isRequired ? const Color(0xFFFFF1F2) : DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRequired ? const Color(0xFFFECDD3) : DefensysTokens.borderOf(context)),
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
                color: isRequired ? const Color(0xFFBE123C) : DefensysTokens.textSecondaryOf(context),
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
    Map<String, dynamic>? stageGrade, [
    BuildContext? popupContext,
  ]) {
    final context = popupContext ?? this.context;
    final submission = Map<String, dynamic>.from(item['submission'] as Map? ?? {});
    final accepted = submission['status'] == 'accepted';
    final rejected = submission['status'] == 'rejected' || submission['status'] == 'Needs Revision';
    final attemptTwo = stageGrade?['verdict'] == 'for_redefense' && item['type'] == 'pre' && item['is_defense_material'] == true;
    final replacementUnlocked = item['type'] == 'pre' && accepted && submission['file_replacement_unlocked'] == true;
    final locked = item['can_upload'] is bool ? item['can_upload'] != true
        : !replacementUnlocked && (accepted || (!attemptTwo && !rejected && ((item['type'] == 'pre' && endorsed) || item['locked'] == true)));
    showDeliverableFileDetails(
      context: context,
      label: '${item['label'] ?? 'Deliverable'}',
      stageLabel: stageLabel,
      programScope: widget.isCapstone ? 'capstone' : 'pit',
      file: submission,
      status: accepted ? (item['type'] == 'post' ? 'Archived' : 'Accepted') : rejected ? 'Needs correction' : 'Awaiting review',
      uploader: submission['uploaded_by_name']?.toString(),
      onReplace: locked || item['is_waived'] == true ? null : () => _promptUploadOrReplace(team, stageLabel, item, context),
      onRemove: accepted || locked ? null : () => _removeFile(team, stageLabel, item),
    );
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
    Map<String, dynamic> item, [
    BuildContext? popupContext,
  ]) async {
    final context = popupContext ?? this.context;
    if (_pickingFile || ref.read(capstoneDeliverablesProvider).isSaving) return;
    final activity = DeliverablePopupActivity.maybeOf(context);
    _pickingFile = true;
    activity?.value = true;
    try {
      if (hasSubmittedDeliverable(item)) {
        final ok = await confirmDestructive(
          context,
          title: 'Replace file?',
          message: 'The current upload will be replaced. This cannot be undone.',
          confirmLabel: 'Replace',
        );
        if (!ok || !mounted || !context.mounted) return;
      }
      final rawFormat = item['file_format'] ?? item['fileFormat'];
      final format = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
      final unrestricted = rawFormat == null || rawFormat == 'any';
      final picked = await FilePicker.platform.pickFiles(
        type: unrestricted ? FileType.any : FileType.custom,
        allowedExtensions: unrestricted ? null : format.extensions,
        allowMultiple: false,
        withData: true,
      );
      if (picked == null ||
          picked.files.isEmpty ||
          !mounted ||
          !context.mounted) {
        return;
      }
      // A picker can stay open while the selected academic context changes.
      final state = ref.read(capstoneDeliverablesProvider);
      final currentTeam = state.teams
          .where((row) => row['id'] == team['id'])
          .firstOrNull;
      if (state.selectedStage != stageLabel ||
          currentTeam == null ||
          currentTeam['semester_id'] != team['semester_id'] ||
          currentTeam['project_version'] != team['project_version']) {
        return;
      }
      final file = picked.files.single;
      final bytes = file.bytes;
      final limit = (item['max_file_size'] as num?)?.toInt() ?? 50 * 1024 * 1024;
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > limit ||
          file.size > limit) {
        showErrorToast(
          context,
          'Choose a non-empty file of up to ${limit ~/ (1024 * 1024)} MB.',
        );
        return;
      }
      final extension = file.extension?.toLowerCase() ?? '';
      if (format.extensions.isNotEmpty && !format.extensions.contains(extension)) {
        showErrorToast(context, 'Choose a file matching: ${format.description}');
        return;
      }
      final suggested = item['suggested_file_name']?.toString() ?? '';
      final isPost = item['type'] == 'post' || item['type'] == 'vault';
      final filename = isPost && suggested.isNotEmpty
          ? format.recommendedFileName(suggested, selectedFileName: file.name)
          : file.name;
      final saved = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .uploadDocument(
            teamId: team['id'] as int,
            stageLabel: stageLabel,
            deliverableId: '${item['id']}',
            slotKey: '',
            filename: filename,
            bytes: bytes,
          );
      if (!saved && mounted && context.mounted) {
        showErrorToast(
          context,
          ref.read(capstoneDeliverablesProvider).error ??
              'The file could not be uploaded. Try again.',
        );
      }
    } catch (error) {
      if (mounted && context.mounted) {
        showErrorToast(context, 'Could not upload the selected file: $error');
      }
    } finally {
      _pickingFile = false;
      activity?.value = false;
    }
  }
}
