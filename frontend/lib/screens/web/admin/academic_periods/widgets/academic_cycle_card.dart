import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';

class AcademicCycleCard extends StatelessWidget {
  const AcademicCycleCard({
    super.key,
    required this.year,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onAddSemester,
    required this.onEditYear,
    required this.onDeleteYear,
    required this.onManageSemester,
    required this.onToggleSemesterActive,
    required this.onDeleteSemester,
    this.isSaving = false,
  });

  final Map<String, dynamic> year;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onAddSemester;
  final VoidCallback onEditYear;
  final VoidCallback? onDeleteYear;
  final void Function(Map<String, dynamic> semester) onManageSemester;
  final void Function(Map<String, dynamic> semester, bool active)
      onToggleSemesterActive;
  final void Function(Map<String, dynamic> semester) onDeleteSemester;
  final bool isSaving;

  static const _line = DefensysTokens.border;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? DefensysTokens.mistBorder : _line;
    final surfaceColor = isDark ? DefensysTokens.mistSurface : Colors.white;
    final inkColor = isDark ? const Color(0xFFF4F4F5) : _ink;
    final mutedColor = isDark ? const Color(0xFFA1A1AA) : _muted;
    final headerBgColor =
        isDark ? const Color(0xFF18191E) : const Color(0xFFF8FAFC);
    final headerTextColor =
        isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

    final rawSemesters = year['semesters'];
    final semesters = (rawSemesters is List)
        ? rawSemesters.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final hasActive = semesters.any((s) => s['is_active'] == true);
    final yearLabel = year['label']?.toString() ?? 'Unknown Year';

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasActive
              ? (isDark ? const Color(0xFF059669) : const Color(0xFF10B981))
              : borderColor,
          width: hasActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Year Header Card
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: isExpanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: inkColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'A.Y. $yearLabel',
                    style: TextStyle(
                      color: inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (hasActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF059669)
                              : const Color(0xFF10B981),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'CURRENTLY ACTIVE',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF047857),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF27272A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3F3F46)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        semesters.isEmpty ? 'EMPTY' : 'ARCHIVED',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${semesters.length} ${semesters.length == 1 ? "Term" : "Terms"}',
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 14),
                  OutlinedButton.icon(
                    onPressed: isSaving ? null : onAddSemester,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Add Term'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: inkColor,
                      side: BorderSide(color: borderColor),
                      backgroundColor: isDark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Edit school year label',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: isSaving ? null : onEditYear,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: mutedColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: semesters.isEmpty
                        ? 'Delete school year'
                        : 'Delete all semesters first',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: (semesters.isEmpty && !isSaving)
                          ? onDeleteYear
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: semesters.isEmpty
                              ? (isDark
                                  ? const Color(0xFFF87171)
                                  : const Color(0xFFDC2626))
                              : (isDark
                                  ? const Color(0xFF52525B)
                                  : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded Term Table
          if (isExpanded) ...[
            Divider(height: 1, color: borderColor),
            if (semesters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: DefensysEmptyState.table(
                  icon: Icons.date_range_outlined,
                  title: 'No Terms Created',
                  description:
                      'Add a semester to activate terms for A.Y. $yearLabel, or delete this year if created by mistake.',
                  size: DefensysEmptyStateSize.compact,
                  primaryAction: DefensysEmptyAction(
                    label: 'Add Semester',
                    icon: Icons.add_rounded,
                    onPressed: isSaving ? () {} : onAddSemester,
                  ),
                  secondaryAction: DefensysEmptyAction(
                    label: 'Delete School Year',
                    icon: Icons.delete_outline_rounded,
                    isOutlined: true,
                    onPressed: isSaving ? () {} : (onDeleteYear ?? () {}),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Text(
                  'Semesters (A.Y. $yearLabel)',
                  style: TextStyle(
                    color: inkColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Table Header
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: headerBgColor,
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    _headerCell('TERM', 140, headerTextColor),
                    _headerCell('STATUS', 200, headerTextColor),
                    _headerCell('PROGRAM TRACKS', 220, headerTextColor),
                    _headerCell('EVALUATION CONTROLS', 160, headerTextColor),
                    _headerCell('ACTIONS', 160, headerTextColor,
                        alignment: Alignment.centerRight),
                  ],
                ),
              ),

              // Rows
              ...semesters.map((sem) => _buildSemesterRow(
                    context,
                    sem,
                    isDark: isDark,
                    borderColor: borderColor,
                    surfaceColor: surfaceColor,
                    inkColor: inkColor,
                    mutedColor: mutedColor,
                  )),
            ],
          ],
        ],
      ),
    );
  }

  Widget _headerCell(
    String label,
    int flex,
    Color textColor, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: alignment,
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterRow(
    BuildContext context,
    Map<String, dynamic> sem, {
    required bool isDark,
    required Color borderColor,
    required Color surfaceColor,
    required Color inkColor,
    required Color mutedColor,
  }) {
    final isActive = sem['is_active'] == true;
    final termName = sem['label']?.toString() ?? 'Semester';
    final phase = sem['capstone_program_phase']?.toString();
    final peerOn = sem['capstone_peer_evaluation_enabled'] != false;
    final adviserOn = sem['capstone_adviser_grading_enabled'] != false;

    String phaseText;
    if (phase == 'capstone_1') {
      phaseText = 'Capstone 1 Intake';
    } else if (phase == 'capstone_2') {
      phaseText = 'Capstone 2 Continue';
    } else {
      phaseText = 'Capstone Inactive';
    }

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isActive
            ? (isDark ? const Color(0xFF28181A) : const Color(0xFFFFF9F9))
            : surfaceColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Term Name
          Expanded(
            flex: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: isActive ? _maroon : mutedColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      termName,
                      style: TextStyle(
                        color: inkColor,
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Status Badge
          Expanded(
            flex: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: isActive
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF059669).withValues(alpha: 0.5)
                                : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Active (Write-Enabled)',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF047857),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF3F3F46)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF71717A)
                                    : const Color(0xFF94A3B8),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Upcoming',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFFA1A1AA)
                                    : const Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),

          // 3. Program Tracks (Capstone + PIT)
          Expanded(
            flex: 220,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF31151A)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Text(
                        phaseText,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFFCA5A5) : _maroon,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1B4B)
                            : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3730A3)
                              : const Color(0xFFC7D2FE),
                        ),
                      ),
                      child: Text(
                        'PIT Active',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4338CA),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Evaluation Summary
          Expanded(
            flex: 160,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _evalChip(
                      label: 'Peer',
                      on: peerOn,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 6),
                    _evalChip(
                      label: 'Adviser',
                      on: adviserOn,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Actions (Manage Term + Active Toggle + Delete)
          Expanded(
            flex: 160,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => onManageSemester(sem),
                    icon: const Icon(Icons.tune_rounded, size: 13),
                    label: const Text('Manage'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive
                          ? _maroon
                          : (isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFF1F5F9)),
                      foregroundColor: isActive
                          ? Colors.white
                          : (isDark
                              ? const Color(0xFFE4E4E7)
                              : const Color(0xFF334155)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: isActive
                              ? Colors.transparent
                              : (isDark
                                  ? const Color(0xFF3F3F46)
                                  : const Color(0xFFE2E8F0)),
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: isActive
                        ? 'Active semester (activate another semester to switch)'
                        : 'Activate semester',
                    child: DefensysUi.flatSwitch(
                      value: isActive,
                      scale: 0.8,
                      activeTrackColor:
                          isDark ? const Color(0xFFE11D48) : _maroon,
                      onChanged: isSaving
                          ? null
                          : (v) => onToggleSemesterActive(sem, v),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: isActive
                        ? 'Cannot delete active semester'
                        : 'Delete semester',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: (!isActive && !isSaving)
                          ? () => onDeleteSemester(sem)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: !isActive
                              ? (isDark
                                  ? const Color(0xFFF87171)
                                  : const Color(0xFFDC2626))
                              : (isDark
                                  ? const Color(0xFF52525B)
                                  : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _evalChip({
    required String label,
    required bool on,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: on
            ? (isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                : const Color(0xFFECFDF5))
            : (isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: on
              ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
              : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Text(
        '$label: ${on ? "On" : "Off"}',
        style: TextStyle(
          color: on
              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
              : (isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8)),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
