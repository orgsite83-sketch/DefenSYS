import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/import/faculty_role_parser.dart';
import 'package:defensys/widgets/branding/status_badge.dart';
import 'package:defensys/widgets/table/table.dart';

/// Review identities and assignments without exposing the redundant base role.
class FacultyImportReviewTable extends StatelessWidget {
  const FacultyImportReviewTable({
    super.key,
    required this.rows,
    required this.isExistingUser,
  });

  final List<Map<String, dynamic>> rows;
  final bool Function(String id, String email) isExistingUser;

  @override
  Widget build(BuildContext context) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(12) / 12,
    );
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);

    return DefensysDataTable<Map<String, dynamic>>(
      items: rows,
      rowMinHeight: 56,
      columns: [
        DefensysTableColumn(
          title: 'Name',
          flex: 2.2,
          minWidth: 220 * scale,
          cellBuilder: (context, row, _) {
            final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'
                .trim();
            return Text(
              name.isEmpty ? 'Unnamed Faculty' : name,
              style: DefensysTokens.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            );
          },
        ),
        DefensysTableColumn(
          title: 'Faculty ID',
          flex: 1.2,
          minWidth: 120 * scale,
          cellBuilder: (context, row, _) => Text(
            row['id_number']?.toString() ?? '',
            style: DefensysTokens.caption.copyWith(color: muted),
          ),
        ),
        DefensysTableColumn(
          title: 'Email',
          flex: 2.5,
          minWidth: 250 * scale,
          cellBuilder: (context, row, _) {
            final email = row['email']?.toString() ?? '';
            return Text(
              email.isEmpty ? 'No email provided' : email,
              style: DefensysTokens.caption.copyWith(
                fontSize: 12.5,
                color: email.isEmpty ? muted : ink,
              ),
            );
          },
        ),
        DefensysTableColumn(
          title: 'Role assignments',
          flex: 2.8,
          minWidth: 280 * scale,
          cellBuilder: (context, row, _) {
            final rawRole = (row['raw_role'] ?? row['role'] ?? 'faculty')
                .toString();
            final badges = parseFacultyRoles(rawRole).badges;
            final isDark = DefensysTokens.isDark(context);
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in badges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? badge.fg.withValues(alpha: 0.2)
                          : badge.bg,
                      borderRadius: BorderRadius.circular(
                        DefensysTokens.radiusSm,
                      ),
                    ),
                    child: Text(
                      badge.label,
                      style: DefensysTokens.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? badge.bg : badge.fg,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        DefensysTableColumn(
          title: 'Import status',
          flex: 1.7,
          minWidth: 170 * scale,
          cellBuilder: (context, row, _) {
            final exists = isExistingUser(
              row['id_number']?.toString() ?? '',
              row['email']?.toString() ?? '',
            );
            return exists
                ? const DefensysStatusBadge.warning(
                    label: 'Existing Account',
                    showDot: false,
                  )
                : const DefensysStatusBadge.success(
                    label: 'Ready to Import',
                    showDot: false,
                  );
          },
        ),
      ],
    );
  }
}
