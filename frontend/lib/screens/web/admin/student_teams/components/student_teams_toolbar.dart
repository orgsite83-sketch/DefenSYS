import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';

Widget buildSecondaryButton({
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
}) {
  return SizedBox(
    height: 42,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: DefensysUi.textDark,
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
        foregroundColor: DefensysUi.accentGold,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class StudentTeamsHeaderActions extends StatelessWidget {
  const StudentTeamsHeaderActions({
    super.key,
    required this.isPitInstructor,
    required this.canTapActions,
    required this.onDownloadTemplate,
    required this.onBulkImport,
    required this.onCreateTeam,
  });

  final bool isPitInstructor;
  final bool canTapActions;
  final VoidCallback onDownloadTemplate;
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
          icon: Icons.description_rounded,
          label: 'CSV Template',
          onTap: onDownloadTemplate,
        ),
        const SizedBox(width: 14),
        buildSecondaryButton(
          icon: Icons.output_rounded,
          label: 'Bulk Import',
          onTap: canTapActions ? onBulkImport : null,
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
    return SizedBox(
      height: 43,
      child: TextField(
        controller: controller,
        enabled: !isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: DefensysUi.steelGrey, size: 19),
          hintText: isPitContext
              ? 'Search by project title or leader...'
              : 'Search by project title, leader, or adviser...',
          hintStyle: const TextStyle(color: DefensysUi.steelGrey, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
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

    return Container(
      width: 220,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
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
    return Row(
      children: [
        Container(
          width: 168,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: teamListScope == 'active' ? 'active' : 'history',
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: const TextStyle(
                color: DefensysUi.textDark,
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
              foregroundColor: DefensysUi.textDark,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
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
