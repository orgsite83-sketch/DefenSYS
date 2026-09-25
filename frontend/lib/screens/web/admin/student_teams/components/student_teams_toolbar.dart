import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/theme/defensys_tokens.dart';

Widget buildSecondaryButton({
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  BuildContext? context,
}) {
  final isDark = context != null && Theme.of(context).brightness == Brightness.dark;
  return SizedBox(
    height: 42,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark,
        side: BorderSide(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

Widget buildPrimaryButton({
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
}) {
  return SizedBox(
    height: 42,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: DefensysUi.primaryMaroon,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class StudentTeamsHeaderActions extends StatelessWidget {
  const StudentTeamsHeaderActions({
    super.key,
    required this.isPitInstructor,
    required this.canTapActions,
    this.onDownloadTemplate,
    required this.onBulkImport,
    required this.onCreateTeam,
  });

  final bool isPitInstructor;
  final bool canTapActions;
  final VoidCallback? onDownloadTemplate;
  final VoidCallback? onBulkImport;
  final VoidCallback? onCreateTeam;

  @override
  Widget build(BuildContext context) {
    if (isPitInstructor) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildSecondaryButton(
          icon: Icons.output_rounded,
          label: 'Bulk Import',
          onTap: canTapActions ? onBulkImport : null,
          context: context,
        ),
        const SizedBox(width: 14),
        buildPrimaryButton(
          icon: Icons.add_rounded,
          label: 'Create New Team',
          onTap: canTapActions ? onCreateTeam : null,
        ),
      ],
    );
  }
}

class StudentTeamsSearchField extends StatelessWidget {
  const StudentTeamsSearchField({
    super.key,
    required this.controller,
    required this.isSaving,
    required this.isPitContext,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSaving;
  final bool isPitContext;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 43,
      child: TextField(
        controller: controller,
        enabled: !isSaving,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark,
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: DefensysUi.steelGrey, size: 19),
          hintText: isPitContext
              ? 'Search by project title or leader...'
              : 'Search by project title, leader, or adviser...',
          hintStyle: TextStyle(
            color: isDark ? DefensysTokens.textSecondaryDark : DefensysUi.steelGrey,
            fontSize: 13,
          ),
          filled: true,
          fillColor: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: DefensysUi.primaryMaroon),
          ),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class StudentTeamsLevelFilter extends StatelessWidget {
  const StudentTeamsLevelFilter({
    super.key,
    required this.isPitLeadManager,
    required this.isPitInstructor,
    required this.currentLevel,
    required this.isSaving,
    required this.onLevelChanged,
  });

  final bool isPitLeadManager;
  final bool isPitInstructor;
  final String currentLevel;
  final bool isSaving;
  final ValueChanged<String?> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    if (isPitLeadManager || isPitInstructor) {
      return const SizedBox.shrink();
    }

    final levelItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'Capstone',
        child: Text('Capstone Teams'),
      ),
      const DropdownMenuItem(
        value: 'PIT',
        child: Text('PIT Teams'),
      ),
    ];
    final values = levelItems.map((item) => item.value).toSet();
    final safeValue = values.contains(currentLevel)
        ? currentLevel
        : 'Capstone';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBg = isDark ? DefensysTokens.mistInputFill : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark;

    return Container(
      width: 220,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fillBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          dropdownColor: isDark ? DefensysTokens.mistSurface : Colors.white,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(
            color: textPrimary,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: levelItems,
          onChanged: isSaving ? null : onLevelChanged,
        ),
      ),
    );
  }
}

class PitTeamScopeToggle extends StatelessWidget {
  const PitTeamScopeToggle({
    super.key,
    required this.teamListScope,
    required this.isSaving,
    required this.onScopeChanged,
    required this.onClear,
  });

  final String teamListScope;
  final bool isSaving;
  final ValueChanged<String?> onScopeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBg = isDark ? DefensysTokens.mistInputFill : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark;

    return Row(
      children: [
        Container(
          width: 168,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: fillBg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: teamListScope == 'active' ? 'active' : 'history',
              dropdownColor: isDark ? DefensysTokens.mistSurface : Colors.white,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: TextStyle(
                color: textPrimary,
                fontFamily: DefensysUi.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Current Term')),
                DropdownMenuItem(value: 'history', child: Text('History')),
              ],
              onChanged: isSaving ? null : onScopeChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed: isSaving ? null : onClear,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              foregroundColor: textPrimary,
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class PitYearLevelDropdownFilter extends StatelessWidget {
  const PitYearLevelDropdownFilter({
    super.key,
    required this.currentYearLevel,
    required this.isSaving,
    required this.onYearChanged,
  });

  final String? currentYearLevel;
  final bool isSaving;
  final ValueChanged<String?> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBg = isDark ? DefensysTokens.mistInputFill : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark;

    const items = [
      DropdownMenuItem<String?>(value: null, child: Text('All Year Levels')),
      DropdownMenuItem<String?>(value: '1st Year', child: Text('1st Year')),
      DropdownMenuItem<String?>(value: '2nd Year', child: Text('2nd Year')),
      DropdownMenuItem<String?>(value: '3rd Year', child: Text('3rd Year')),
    ];

    return Container(
      width: 155,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fillBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: currentYearLevel,
          dropdownColor: isDark ? DefensysTokens.mistSurface : Colors.white,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(
            color: textPrimary,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: isSaving ? null : onYearChanged,
        ),
      ),
    );
  }
}

class PitEventDropdownFilter extends StatelessWidget {
  const PitEventDropdownFilter({
    super.key,
    required this.currentEventName,
    required this.pitEvents,
    required this.selectedYearLevel,
    required this.isSaving,
    required this.onEventChanged,
  });

  final String? currentEventName;
  final List<Map<String, dynamic>> pitEvents;
  final String? selectedYearLevel;
  final bool isSaving;
  final ValueChanged<String?> onEventChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillBg = isDark ? DefensysTokens.mistInputFill : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark;

    final filtered = pitEvents.where((e) {
      if (selectedYearLevel == null || selectedYearLevel!.isEmpty) return true;
      final y = e['year_level']?.toString();
      return y == null || y == selectedYearLevel;
    }).toList();

    final menuItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('All PIT Events'),
      ),
      ...filtered.map((e) {
        final name = e['event_name']?.toString() ?? '';
        return DropdownMenuItem<String?>(
          value: name,
          child: Text(name, overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    final values = menuItems.map((m) => m.value).toSet();
    final safeValue = values.contains(currentEventName) ? currentEventName : null;

    return Container(
      width: 220,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fillBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: safeValue,
          dropdownColor: isDark ? DefensysTokens.mistSurface : Colors.white,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(
            color: textPrimary,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: menuItems,
          onChanged: isSaving ? null : onEventChanged,
        ),
      ),
    );
  }
}
