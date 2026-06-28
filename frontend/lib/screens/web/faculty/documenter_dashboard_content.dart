import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/documenter_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../utils/pdf_viewer.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class DocumenterDashboardContent extends ConsumerStatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final ValueChanged<int> onOpenMinutes;

  const DocumenterDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenMinutes,
  });

  @override
  ConsumerState<DocumenterDashboardContent> createState() =>
      _DocumenterDashboardContentState();
}

class _DocumenterDashboardContentState
    extends ConsumerState<DocumenterDashboardContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documenterProvider.notifier).fetchAssignments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documenterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DefensysPageHeader(
          icon: Icons.assignment_outlined,
          title: 'Documenter Workspace',
          subtitle: 'Defense schedules you are assigned to document and record minutes.',
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome, ${widget.facultyName}',
          style: DefensysUi.subtitle.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        if (state.isLoading && state.assignments.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (state.error != null && state.assignments.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Text(
                    state.error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(documenterProvider.notifier)
                        .fetchAssignments(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (state.assignments.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_turned_in_outlined,
                      color: Colors.grey.shade400, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'No assigned defenses found.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: DefensysTokens.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You will see defense schedules here once an administrator assigns you as the documenter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              if (isWide) {
                return _buildTable(state.assignments);
              } else {
                return _buildCards(state.assignments);
              }
            },
          ),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> schedules) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text(
                      'Team & Project',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Stage',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Date & Time',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Action',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: schedules.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, thickness: 1, color: Color(0xFFE9EDF4)),
            itemBuilder: (context, index) {
              final schedule = schedules[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              schedule['team_name']?.toString() ?? 'Unknown Team',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              schedule['project_title']?.toString() ?? '',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(schedule['defense_stage_label']?.toString() ?? ''),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(schedule['scheduled_date']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(schedule['start_time']),
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _buildMinutesStatusBadge(schedule['minutes_status']?.toString()),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          ElevatedButton(
                            onPressed: () => widget.onOpenMinutes(schedule['id'] as int),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DefensysTokens.maroon,
                              foregroundColor: DefensysTokens.gold,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            child: Text(
                              schedule['minutes_status'] == null || schedule['minutes_status'] == 'draft'
                                  ? 'Record'
                                  : 'View',
                            ),
                          ),
                          if (schedule['minutes_status'] == 'completed') ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.download, color: DefensysTokens.maroon, size: 20),
                              tooltip: 'Download PDF',
                              onPressed: () => _downloadMinutesPdf(schedule['id'] as int, schedule['team_name']?.toString()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCards(List<Map<String, dynamic>> schedules) {
    return Column(
      children: schedules.map((schedule) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        schedule['team_name']?.toString() ?? 'Team',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    _buildMinutesStatusBadge(schedule['minutes_status']?.toString()),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  schedule['project_title']?.toString() ?? '',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.layers_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(schedule['defense_stage_label']?.toString() ?? ''),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('${schedule['scheduled_date']} @ ${_formatTime(schedule['start_time'])}'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (schedule['minutes_status'] == 'completed') ...[
                      IconButton(
                        icon: const Icon(Icons.download, color: DefensysTokens.maroon),
                        tooltip: 'Download PDF',
                        onPressed: () => _downloadMinutesPdf(schedule['id'] as int, schedule['team_name']?.toString()),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: () => widget.onOpenMinutes(schedule['id'] as int),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: DefensysTokens.gold,
                      ),
                      child: Text(
                        schedule['minutes_status'] == null || schedule['minutes_status'] == 'draft'
                            ? 'Record Minutes'
                            : 'View Minutes',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMinutesStatusBadge(String? status) {
    if (status == null) {
      return const StatusBadge(
        label: 'No Minutes',
        background: DefensysTokens.neutralBg,
        textColor: DefensysTokens.neutralText,
        borderColor: DefensysTokens.neutralBorder,
      );
    }
    switch (status) {
      case 'draft':
        return const StatusBadge(
          label: 'Draft',
          background: DefensysTokens.warningBg,
          textColor: DefensysTokens.warningText,
          borderColor: DefensysTokens.warningBorder,
        );
      case 'submitted':
        return const StatusBadge(
          label: 'Submitted',
          background: DefensysTokens.infoBg,
          textColor: DefensysTokens.infoText,
          borderColor: DefensysTokens.infoBorder,
        );
      case 'adviser_signed':
        return const StatusBadge(
          label: 'Adviser Signed',
          background: DefensysTokens.infoBg,
          textColor: DefensysTokens.infoText,
          borderColor: DefensysTokens.infoBorder,
        );
      case 'completed':
        return const StatusBadge.success(
          label: 'Completed',
        );
      default:
        return StatusBadge(
          label: status,
          background: DefensysTokens.neutralBg,
          textColor: DefensysTokens.neutralText,
          borderColor: DefensysTokens.neutralBorder,
        );
    }
  }

  String _formatTime(dynamic timeVal) {
    if (timeVal == null) return '';
    final timeStr = timeVal.toString();
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final dt = DateTime(2026, 1, 1, hour, minute);
        return DateFormat('h:mm a').format(dt);
      }
    } catch (_) {}
    return timeStr;
  }

  Future<void> _downloadMinutesPdf(int scheduleId, String? teamName) async {
    final bytes = await ref.read(documenterProvider.notifier).downloadPdf(scheduleId);
    if (bytes != null && mounted) {
      final safeTeam = (teamName ?? 'team').replaceAll(' ', '_');
      await downloadBytesFile(
        bytes: bytes,
        fileName: 'minutes_$safeTeam.pdf',
        mimeType: 'application/pdf',
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download PDF.')),
        );
      }
    }
  }
}
