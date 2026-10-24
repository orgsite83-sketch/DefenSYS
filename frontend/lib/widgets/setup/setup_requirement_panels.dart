import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';

/// Display-only rubric tile shared by PIT event and Capstone stage setup.
class SetupRubricCard extends StatelessWidget {
  const SetupRubricCard({
    super.key,
    required this.role,
    required this.name,
    required this.isRequired,
    required this.isReady,
  });

  final String role;
  final String? name;
  final bool isRequired;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final surface = DefensysTokens.surfaceOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final dark = DefensysTokens.isDark(context);
    final small = TextStyle(fontSize: 13, height: 1.5, color: muted);
    final success = dark ? DefensysTokens.success : DefensysTokens.successText;
    final warning = DefensysTokens.goldOf(context);
    final rubricName = name;
    final hasRubric = rubricName != null && rubricName.trim().isNotEmpty;
    final roleLabel = '${role[0].toUpperCase()}${role.substring(1)} evaluation';
    final fallbackText = isRequired
        ? 'Rubric required'
        : (isReady
              ? 'Not required for current grading settings'
              : 'Not attached');

    IconData roleIcon;
    Color roleColor;
    switch (role) {
      case 'panel':
        roleIcon = LucideIcons.graduationCap;
        roleColor = DefensysTokens.maroonOf(context);
        break;
      case 'adviser':
        roleIcon = LucideIcons.userCheck;
        roleColor = const Color(0xFF0284C7);
        break;
      default:
        roleIcon = LucideIcons.users;
        roleColor = const Color(0xFF7C3AED);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(roleIcon, size: 16, color: roleColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: small.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRubric ? rubricName : fallbackText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hasRubric ? ink : muted,
                  ),
                ),
              ],
            ),
          ),
          if (hasRubric)
            Icon(LucideIcons.check, size: 15, color: success)
          else if (isRequired)
            ShadBadge.outline(
              backgroundColor: dark
                  ? DefensysTokens.goldOf(context).withValues(alpha: 0.1)
                  : const Color(0xFFFEF3C7),
              foregroundColor: warning,
              child: const Text('Required'),
            ),
        ],
      ),
    );
  }
}

/// Display-only requirement cards; callers supply their own scoped rows.
class SetupRequirementGroup extends StatelessWidget {
  const SetupRequirementGroup({
    super.key,
    required this.title,
    required this.rows,
    this.system = false,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final bool system;

  @override
  Widget build(BuildContext context) {
    final surface = DefensysTokens.surfaceOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final fill = DefensysTokens.surfaceHigherOf(context);
    final dark = DefensysTokens.isDark(context);
    final small = TextStyle(fontSize: 13, height: 1.5, color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              system
                  ? LucideIcons.stamp
                  : (title.contains('Pre')
                        ? LucideIcons.fileUp
                        : LucideIcons.fileCheck),
              size: 15,
              color: ink,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(width: 6),
              ShadBadge.secondary(child: Text('${rows.length}')),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Text('No requirements configured', style: small),
          )
        else
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        system ? LucideIcons.fileCheck : LucideIcons.fileText,
                        size: 16,
                        color: system
                            ? DefensysTokens.maroonOf(context)
                            : muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row['label']?.toString() ?? 'Deliverable',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ShadBadge.outline(
                        backgroundColor: row['required'] == true
                            ? (dark
                                  ? DefensysTokens.maroonOf(
                                      context,
                                    ).withValues(alpha: 0.15)
                                  : const Color(0xFFFEE2E2))
                            : null,
                        foregroundColor: row['required'] == true
                            ? DefensysTokens.maroonOf(context)
                            : muted,
                        child: Text(
                          row['required'] == true ? 'Required' : 'Optional',
                        ),
                      ),
                    ],
                  ),
                  if (system) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Assigned documenter · All required signatures completed',
                      style: small.copyWith(fontSize: 12),
                    ),
                  ] else if (_requirementMetadata(row).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _requirementMetadata(row),
                      style: small.copyWith(fontSize: 12),
                    ),
                  ],
                  if ((row['archive_file_template'] ?? '')
                      .toString()
                      .isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        'Archive filename: ${row['archive_file_template']}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }

  String _requirementMetadata(Map<String, dynamic> row) => [
    if (row['file_format'] != null && row['file_format'] != 'any')
      row['file_format'].toString().toUpperCase(),
    if (row['is_defense_material'] == true) 'Visible to panelists',
    if (row['is_restricted'] == true) 'Private archive',
  ].join(' · ');
}
