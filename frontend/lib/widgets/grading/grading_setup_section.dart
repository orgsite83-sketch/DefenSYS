import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Existing role settings and filtered rubric choices, owned by the editor.
class GradingRoleSetup {
  const GradingRoleSetup({
    required this.role,
    required this.label,
    required this.weightController,
    required this.rubrics,
    required this.onWeightChanged,
    required this.onRubricChanged,
    this.rubricId,
    this.rubricName,
  });
  final String role, label;
  final TextEditingController weightController;
  final List<Map<String, dynamic>> rubrics;
  final int? rubricId;
  final String? rubricName;
  final ValueChanged<String> onWeightChanged;
  final ValueChanged<int?> onRubricChanged;
}

/// Shared neutral grading rows for PIT and Capstone setup.
class GradingSetupSection extends StatelessWidget {
  const GradingSetupSection({
    super.key,
    required this.roles,
    required this.resetLabel,
    required this.onReset,
    required this.onManageRubrics,
    this.enabled = true,
    this.canManageRubrics = true,
  });
  final List<GradingRoleSetup> roles;
  final String resetLabel;
  final VoidCallback onReset, onManageRubrics;
  final bool enabled, canManageRubrics;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: AnimatedBuilder(
      animation: Listenable.merge(roles.map((role) => role.weightController)),
      builder: (context, _) {
        final muted = DefensysTokens.textSecondaryOf(context);
        final noRubrics = roles.every(
          (role) => role.rubrics.isEmpty && role.rubricId == null,
        );
        final values = roles
            .map((role) => int.tryParse(role.weightController.text.trim()))
            .toList();
        final total = values.fold(0, (sum, value) => sum + (value ?? 0));
        final valid =
            total == 100 &&
            values.every(
              (value) => value != null && value >= 0 && value <= 100,
            );
        final missingRubric = roles.any(
          (role) =>
              (int.tryParse(role.weightController.text.trim()) ?? 0) > 0 &&
              role.rubricId == null,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Grading setup',
                        style: DefensysTokens.sectionTitle.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      enabled: canManageRubrics,
                      onPressed: canManageRubrics ? onManageRubrics : null,
                      child: Text(
                        noRubrics ? 'Create rubric' : 'Manage rubrics',
                        style: DefensysTokens.tableCell.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!compact) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Evaluator',
                          style: DefensysTokens.caption.copyWith(color: muted),
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: Text(
                          'Grade weight',
                          style: DefensysTokens.caption.copyWith(color: muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Evaluation rubric',
                          style: DefensysTokens.caption.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                for (final role in roles) ...[
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _GradingRoleRow(
                      role: role,
                      compact: compact,
                      enabled: enabled,
                    ),
                  ),
                ],
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        valid
                            ? 'Total 100%'
                            : 'Total $total% · Must equal 100%',
                        key: const ValueKey('grading-weight-total'),
                        style: DefensysTokens.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: valid
                              ? DefensysTokens.textPrimaryOf(context)
                              : (DefensysTokens.isDark(context)
                                    ? DefensysTokens.danger
                                    : DefensysTokens.dangerText),
                        ),
                      ),
                    ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      enabled: enabled,
                      onPressed: enabled ? onReset : null,
                      child: Text(
                        resetLabel,
                        style: DefensysTokens.tableCell.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                if (noRubrics || missingRubric) ...[
                  const SizedBox(height: 4),
                  Text(
                    noRubrics
                        ? 'No published rubrics available.'
                        : 'Attach rubrics before scheduling.',
                    style: DefensysTokens.caption.copyWith(color: muted),
                  ),
                ],
              ],
            );
          },
        );
      },
    ),
  );
}

class _GradingRoleRow extends StatelessWidget {
  const _GradingRoleRow({
    required this.role,
    required this.compact,
    required this.enabled,
  });
  final GradingRoleSetup role;
  final bool compact, enabled;

  @override
  Widget build(BuildContext context) {
    final weight = Semantics(
      label: '${role.label} grade weight',
      child: ShadInput(
        key: ValueKey('${role.role}-weight'),
        controller: role.weightController,
        style: DefensysTokens.tableCell.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        ),
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        trailing: Text(
          '%',
          style: DefensysTokens.tableCell.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        onChanged: role.onWeightChanged,
      ),
    );
    final rubric = _RubricSelect(role: role, enabled: enabled);
    final label = Text(
      role.label,
      style: DefensysTokens.tableCell.copyWith(
        fontWeight: FontWeight.w600,
        color: DefensysTokens.textPrimaryOf(context),
      ),
    );
    if (!compact) {
      return Row(
        children: [
          SizedBox(width: 100, child: label),
          SizedBox(width: 96, child: weight),
          const SizedBox(width: 16),
          Expanded(child: rubric),
        ],
      );
    }
    Widget field(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label,
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 88, child: field('Grade weight', weight)),
            const SizedBox(width: 12),
            Expanded(child: field('Evaluation rubric', rubric)),
          ],
        ),
      ],
    );
  }
}

class _RubricSelect extends StatelessWidget {
  const _RubricSelect({required this.role, required this.enabled});
  final GradingRoleSetup role;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // An explicit clear choice also avoids the select package's null reset case.
      final names = <int, String>{
        0: 'Select later',
        for (final rubric in role.rubrics)
          if (int.tryParse('${rubric['id']}') case final int id)
            id: rubric['name']?.toString() ?? 'Evaluation rubric',
      };
      final unavailable =
          role.rubricId != null && !names.containsKey(role.rubricId);
      if (unavailable) {
        names[role.rubricId!] =
            role.rubricName ?? 'Selected rubric (unavailable)';
      }
      return Semantics(
        label: '${role.label} rubric',
        child: ShadSelect<int>(
          key: ValueKey('${role.role}-rubric-${role.rubricId ?? 0}'),
          initialValue: role.rubricId ?? 0,
          enabled: enabled,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          maxHeight: 260,
          selectedOptionBuilder: (_, value) => Text(
            names[value]!,
            overflow: TextOverflow.ellipsis,
            style: DefensysTokens.tableCell.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          options: names.entries
              .where((entry) => !unavailable || entry.key != role.rubricId)
              .map(
                (entry) => ShadOption<int>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    overflow: TextOverflow.ellipsis,
                    style: DefensysTokens.tableCell.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
          onChanged: (value) {
            if (value == null) return;
            final selected = value == 0 ? null : value;
            if (selected != role.rubricId) role.onRubricChanged(selected);
          },
        ),
      );
    },
  );
}
