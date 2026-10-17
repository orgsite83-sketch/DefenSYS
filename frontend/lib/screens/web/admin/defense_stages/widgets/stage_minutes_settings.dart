import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'stage_deliverable_overview.dart';

class StageMinutesSettings extends StatelessWidget {
  const StageMinutesSettings({
    super.key,
    required this.requiredMinutes,
    required this.enabled,
    required this.onChanged,
  });
  final bool requiredMinutes;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = DefensysTokens.isDark(context);
    final borderColor = DefensysTokens.borderOf(context);
    final textSecondary = DefensysTokens.textSecondaryOf(context);
    final textPrimary = DefensysTokens.textPrimaryOf(context);
    final primaryColor = theme.colorScheme.primary;

    Widget option(
      bool value,
      String title,
      String description, {
      String? badgeText,
    }) {
      final isSelected = requiredMinutes == value;
      return Semantics(
        selected: isSelected,
        child: InkWell(
          onTap: enabled ? () => onChanged(value) : null,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? primaryColor.withValues(alpha: 0.12)
                      : primaryColor.withValues(alpha: 0.05))
                  : DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              border: Border.all(
                color: isSelected ? primaryColor : borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : textSecondary.withValues(alpha: 0.5),
                      width: isSelected ? 5.5 : 1.5,
                    ),
                    color: isSelected ? theme.colorScheme.surface : Colors.transparent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          if (badgeText != null && isSelected) ...[
                            const SizedBox(width: 6),
                            ShadBadge.secondary(
                              child: Text(
                                badgeText,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefensysShadcnScope(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.backgroundOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session documentation',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Signed minutes are included by default for Capstone defenses. Choose the exception only when this stage does not use them.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final yes = option(
                  true,
                  'Signed minutes required',
                  'Assign a documenter to prepare and sign official minutes.',
                  badgeText: 'Deliverable',
                );
                final no = option(
                  false,
                  'Minutes not required',
                  'No documenter assignment or signed-minutes deliverable.',
                );
                return constraints.maxWidth < 600
                    ? Column(children: [yes, const SizedBox(height: 10), no])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: yes),
                          const SizedBox(width: 12),
                          Expanded(child: no),
                        ],
                      );
              },
            ),
            if (requiredMinutes) ...[
              const SizedBox(height: 12),
              ShadAlert(
                icon: const Icon(LucideIcons.info, size: 16),
                description: Text(
                  'Adds a system-generated signed-minutes deliverable in Step 3. Documenter assignment is required when scheduling.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StageMinutesDeliverableCard extends StatelessWidget {
  const StageMinutesDeliverableCard({
    super.key,
    required this.number,
    required this.name,
    required this.stageName,
    required this.enabled,
    required this.onConfigure,
    required this.expanded,
    required this.onToggle,
  });
  final TextEditingController number, name;
  final String stageName;
  final bool enabled;
  final VoidCallback onConfigure;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final borderColor = DefensysTokens.borderOf(context);
    final textPrimary = DefensysTokens.textPrimaryOf(context);
    final textSecondary = DefensysTokens.textSecondaryOf(context);
    final panelBg = DefensysTokens.panelOf(context);
    final inputFill = isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);
    final headerBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.25)
        : const Color(0xFFF8FAFC);
    final headerBorder = isDark ? borderColor : const Color(0xFFE2E8F0);
    final accentColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF0F172A);

    InputDecoration inputDeco({
      required String labelText,
      String? hintText,
    }) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        counterText: '',
        isDense: true,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        hintStyle: TextStyle(
          fontSize: 12.5,
          color: isDark
              ? DefensysTokens.textSecondaryDark.withValues(alpha: 0.6)
              : const Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? borderColor : const Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? borderColor : const Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFFF87171) : DefensysTokens.maroon,
            width: 1.5,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Header Bar (matching Pre/Post deliverable sections)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: headerBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 17, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System records (1)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Generated automatically by the system upon completion.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: !expanded
                ? StageCompactRecordRow(
                    title: 'Signed Minutes',
                    summary: 'PDF · Required · Created by assigned documenter',
                    icon: Icons.description_outlined,
                    onTap: onToggle,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Deliverable Editor Card (matching _deliverableRow styling)
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? DefensysTokens.mistSurface : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? borderColor : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: isDark
                              ? null
                              : const [
                                  BoxShadow(
                                    color: Color(0x06000000),
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Distinct Item Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: inputFill,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(9),
                                  topRight: Radius.circular(9),
                                ),
                                border: Border(bottom: BorderSide(color: borderColor)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Text(
                                      '#SYS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Signed Minutes',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                                          : const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                                            : const Color(0xFFBFDBFE),
                                      ),
                                    ),
                                    child: Text(
                                      'SYSTEM GENERATED',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 2. Card Content Body
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Created automatically by the assigned documenter after the required signatures.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final numberField = TextField(
                                        key: const ValueKey('minutes-deliverable-number'),
                                        controller: number,
                                        readOnly: !enabled,
                                        maxLength: 20,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                        decoration: inputDeco(
                                          labelText: 'Official deliverable number',
                                          hintText: 'e.g. MINUTES',
                                        ),
                                      );
                                      final nameField = TextField(
                                        key: const ValueKey('minutes-deliverable-name'),
                                        controller: name,
                                        readOnly: !enabled,
                                        maxLength: 180,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                        decoration: inputDeco(
                                          labelText: 'Official deliverable name',
                                          hintText: 'Signed Minutes - $stageName',
                                        ),
                                      );
                                      return constraints.maxWidth < 600
                                          ? Column(
                                              children: [
                                                numberField,
                                                const SizedBox(height: 12),
                                                nameField,
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                Expanded(child: numberField),
                                                const SizedBox(width: 12),
                                                Expanded(flex: 3, child: nameField),
                                              ],
                                            );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 14,
                                          color: textSecondary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'PDF · Created by assigned documenter · Applies to conducted defenses regardless of result.',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DefensysShadcnScope(
                                    child: ShadButton.link(
                                      size: ShadButtonSize.sm,
                                      expands: true,
                                      onPressed: onConfigure,
                                      leading: const Icon(Icons.settings_outlined, size: 14),
                                      child: const Text('Change in Stage Details'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: DefensysShadcnScope(
                          child: ShadButton.outline(
                            size: ShadButtonSize.sm,
                            onPressed: onToggle,
                            leading: const Icon(Icons.check_rounded, size: 14),
                            child: const Text('Done editing'),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
