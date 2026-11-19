import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/feedback/defensys_skeleton.dart';
import '../../../../../widgets/feedback/empty_state.dart';
import '../../../../../widgets/shadcn/defensys_action_menu.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'semester_calendar_fields.dart';
import 'semester_status_badge.dart';

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

  TextStyle _textStyle(BuildContext context, {bool secondary = false}) =>
      TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontSize: 13,
        color: secondary
            ? DefensysTokens.textSecondaryOf(context)
            : DefensysTokens.textPrimaryOf(context),
      );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    maroonActions: true,
    neutralActionText: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final semesters = (year['semesters'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final hasActive = semesters.any(
          (semester) => semester['is_active'] == true,
        );
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final wide = constraints.maxWidth / scale >= 900;
        final compactHeader = constraints.maxWidth / scale < 600;
        final border = DefensysTokens.borderOf(context);
        return Container(
          key: ValueKey('academic-year-${year['id']}'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _yearHeader(context, semesters, hasActive, compactHeader),
              if (isExpanded) ...[
                Divider(height: 1, color: border),
                if (semesters.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: DefensysEmptyState.table(
                      icon: Icons.date_range_outlined,
                      title: 'No semesters yet',
                      description:
                          'Add a semester to configure this school year.',
                      size: DefensysEmptyStateSize.compact,
                      primaryAction: isSaving
                          ? null
                          : DefensysEmptyAction(
                              label: 'Add semester',
                              icon: Icons.add_rounded,
                              onPressed: onAddSemester,
                            ),
                      secondaryAction: isSaving || onDeleteYear == null
                          ? null
                          : DefensysEmptyAction(
                              label: 'Delete School Year',
                              icon: Icons.delete_outline_rounded,
                              isOutlined: true,
                              onPressed: onDeleteYear!,
                            ),
                    ),
                  )
                else ...[
                  if (wide) _tableHeader(context),
                  for (var index = 0; index < semesters.length; index++) ...[
                    if (index > 0) Divider(height: 1, color: border),
                    _semesterRow(context, semesters[index], wide),
                  ],
                ],
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _yearHeader(
    BuildContext context,
    List<Map<String, dynamic>> semesters,
    bool hasActive,
    bool compact,
  ) {
    final count =
        '${semesters.length} ${semesters.length == 1 ? 'semester' : 'semesters'}';
    final title = Semantics(
      expanded: isExpanded,
      child: ShadButton.ghost(
        key: ValueKey('academic-year-toggle-${year['id']}'),
        width: double.infinity,
        expands: true,
        height: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
        onPressed: onToggleExpand,
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? .25 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A.Y. ${year['label'] ?? 'Unknown year'}',
                    textAlign: TextAlign.start,
                    style: _textStyle(context).copyWith(
                      fontSize: 18,
                      fontWeight: hasActive ? FontWeight.w700 : FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasActive ? 'Current school year · $count' : count,
                    textAlign: TextAlign.start,
                    style: _textStyle(
                      context,
                      secondary: true,
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadButton.outline(
          enabled: !isSaving,
          size: ShadButtonSize.sm,
          height: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: const Icon(LucideIcons.plus, size: 14),
          onPressed: onAddSemester,
          child: const Flexible(child: Text('Add semester')),
        ),
        const SizedBox(width: 8),
        _yearMenu(context, semesters),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 12), actions],
            )
          : Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                actions,
              ],
            ),
    );
  }

  Widget _yearMenu(BuildContext context, List<Map<String, dynamic>> semesters) {
    final canEdit = semesters.isEmpty && year['can_edit_label'] != false;
    final reason =
        year['edit_lock_reason']?.toString() ??
        'School year labels are locked after semesters are added.';
    return DefensysActionMenu(
      label: 'School year options',
      enabled: !isSaving,
      items: [
        DefensysMenuItem(
          label: 'Edit School Year',
          icon: canEdit ? LucideIcons.pencil : LucideIcons.lock,
          hint: canEdit ? null : reason,
          onPressed: canEdit && !isSaving ? onEditYear : null,
        ),
        if (!canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 0, 12, 10),
            child: Text(
              'Locked after terms are added',
              style: _textStyle(
                context,
                secondary: true,
              ).copyWith(fontSize: 12),
            ),
          ),
        DefensysMenuItem(
          label: 'Delete School Year',
          icon: LucideIcons.trash2,
          destructive: true,
          onPressed: semesters.isEmpty && !isSaving ? onDeleteYear : null,
        ),
      ],
    );
  }

  // Shared geometry keeps headings aligned with every semester row.
  Widget _columns({
    required Widget semester,
    required Widget programs,
    required Widget evaluations,
    required Widget actions,
  }) => _AcademicCycleColumns(
    semester: semester,
    programs: programs,
    evaluations: evaluations,
    actions: actions,
  );

  Widget _tableHeader(BuildContext context) {
    Widget label(String value) => Text(
      value,
      style: _textStyle(
        context,
        secondary: true,
      ).copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border(
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: _columns(
        semester: label('Semester'),
        programs: label('Programs'),
        evaluations: label('Evaluations'),
        actions: const SizedBox.shrink(),
      ),
    );
  }

  Widget _semesterRow(
    BuildContext context,
    Map<String, dynamic> semester,
    bool wide,
  ) {
    final active = semester['is_active'] == true;
    final term = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              semester['label']?.toString() ?? 'Semester',
              style: _textStyle(context).copyWith(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            SemesterStatusBadge(isActive: active),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          semesterDateRange(semester),
          style: _textStyle(context, secondary: true).copyWith(fontSize: 12),
        ),
      ],
    );
    final (program, phase) = switch (semester['capstone_program_phase']) {
      'capstone_1' => ('Capstone 1', 'Intake'),
      'capstone_2' => ('Capstone 2', 'Continuation'),
      _ => ('Capstone', 'Inactive'),
    };
    final programs = _summary(context, 'Programs', [
      Text.rich(
        TextSpan(
          text: program,
          style: _textStyle(context).copyWith(fontWeight: FontWeight.w500),
          children: [
            TextSpan(
              text: ' · $phase',
              style: _textStyle(context, secondary: true),
            ),
          ],
        ),
      ),
      Text(
        'PIT',
        style: _textStyle(context).copyWith(fontWeight: FontWeight.w500),
      ),
    ], showLabel: !wide);
    final evaluations = _summary(context, 'Evaluations', [
      _evaluation(
        context,
        'Peer',
        semester['capstone_peer_evaluation_enabled'] != false,
      ),
      _evaluation(
        context,
        'Adviser',
        semester['capstone_adviser_grading_enabled'] != false,
      ),
    ], showLabel: !wide);
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (active)
          ShadButton(
            size: ShadButtonSize.sm,
            height: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            onPressed: () => onManageSemester(semester),
            trailing: const Icon(LucideIcons.arrowRight, size: 14),
            child: const Flexible(child: Text('Open semester')),
          )
        else
          ShadButton.outline(
            size: ShadButtonSize.sm,
            height: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            onPressed: () => onManageSemester(semester),
            trailing: const Icon(LucideIcons.arrowRight, size: 14),
            child: const Flexible(child: Text('Open semester')),
          ),
        _semesterMenu(semester),
      ],
    );
    return _SemesterRowSurface(
      key: ValueKey('academic-semester-${semester['id']}'),
      active: active,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: wide
            ? _columns(
                semester: term,
                programs: programs,
                evaluations: evaluations,
                actions: actions,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  term,
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth /
                                MediaQuery.textScalerOf(context).scale(1) >=
                            520
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: programs),
                              const SizedBox(width: 28),
                              Expanded(child: evaluations),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              programs,
                              const SizedBox(height: 16),
                              evaluations,
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  actions,
                ],
              ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    String label,
    List<Widget> values, {
    required bool showLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLabel) ...[
        Text(
          label,
          style: _textStyle(
            context,
            secondary: true,
          ).copyWith(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
      ],
      for (var index = 0; index < values.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        values[index],
      ],
    ],
  );

  Widget _evaluation(BuildContext context, String label, bool enabled) =>
      Semantics(
        label: '$label ${enabled ? 'enabled' : 'disabled'}',
        excludeSemantics: true,
        child: Row(
          children: [
            SizedBox(
              width: 62 * MediaQuery.textScalerOf(context).scale(1),
              child: Text(label, style: _textStyle(context, secondary: true)),
            ),
            Icon(
              enabled ? LucideIcons.check : LucideIcons.minus,
              size: 13,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                enabled ? 'Enabled' : 'Disabled',
                style: _textStyle(context, secondary: !enabled),
              ),
            ),
          ],
        ),
      );

  Widget _semesterMenu(Map<String, dynamic> semester) {
    final active = semester['is_active'] == true;
    return DefensysActionMenu(
      label: 'More options',
      enabled: !isSaving,
      items: [
        if (!active)
          DefensysMenuItem(
            label: 'Set as Active Semester',
            icon: LucideIcons.power,
            onPressed: isSaving
                ? null
                : () => onToggleSemesterActive(semester, true),
          ),
        DefensysMenuItem(
          label: 'Delete Semester',
          icon: LucideIcons.trash2,
          destructive: true,
          onPressed: active || isSaving
              ? null
              : () => onDeleteSemester(semester),
        ),
      ],
    );
  }
}

/// Shared column proportions keep loaded and loading rows aligned.
class _AcademicCycleColumns extends StatelessWidget {
  const _AcademicCycleColumns({
    required this.semester,
    required this.programs,
    required this.evaluations,
    required this.actions,
  });

  final Widget semester;
  final Widget programs;
  final Widget evaluations;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 5, child: semester),
      const SizedBox(width: 24),
      Expanded(flex: 5, child: programs),
      const SizedBox(width: 24),
      Expanded(flex: 4, child: evaluations),
      const SizedBox(width: 24),
      SizedBox(width: 200, child: actions),
    ],
  );
}

class _SemesterRowSurface extends StatefulWidget {
  const _SemesterRowSurface({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_SemesterRowSurface> createState() => _SemesterRowSurfaceState();
}

class _SemesterRowSurfaceState extends State<_SemesterRowSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onFocusChange: (value) => setState(() => _focused = value),
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        color: Color.lerp(
          DefensysTokens.surfaceOf(context),
          DefensysTokens.surfaceHigherOf(context),
          _hovered || _focused ? .8 : (widget.active ? .4 : 0),
        ),
        child: widget.child,
      ),
    ),
  );
}

/// Placeholders follow the year header and semester rows without fake data.
class AcademicCycleSkeleton extends StatelessWidget {
  const AcademicCycleSkeleton({super.key});

  Widget _bone(BuildContext context, {double? width, double height = 13}) =>
      DefensysSkeleton.box(
        width: width,
        height: height,
        borderRadius: 4,
        color: DefensysTokens.borderOf(context),
      );

  Widget _pair(BuildContext context, double width) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _bone(context, width: width),
      const SizedBox(height: 10),
      _bone(context, width: width * .7, height: 11),
    ],
  );

  Widget _header(BuildContext context, bool compact) {
    final title = _pair(context, 180);
    final action = _bone(context, width: 136, height: 36);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 20), action],
            )
          : Row(
              children: [
                Expanded(child: title),
                action,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading academic periods',
    liveRegion: true,
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
          final wide = width >= 900;
          final border = DefensysTokens.borderOf(context);
          BoxDecoration frame() => BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: frame(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, width < 600),
                    Divider(height: 1, color: border),
                    if (wide) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: _AcademicCycleColumns(
                          semester: _bone(context, width: 64, height: 11),
                          programs: _bone(context, width: 64, height: 11),
                          evaluations: _bone(context, width: 76, height: 11),
                          actions: const SizedBox(),
                        ),
                      ),
                      Divider(height: 1, color: border),
                    ],
                    for (var index = 0; index < 2; index++) ...[
                      if (index > 0) Divider(height: 1, color: border),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: wide
                            ? _AcademicCycleColumns(
                                semester: _pair(context, 168),
                                programs: _pair(context, 176),
                                evaluations: _pair(context, 132),
                                actions: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _bone(context, width: 150, height: 36),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _pair(context, 168),
                                  const SizedBox(height: 20),
                                  if (width - 40 >= 520)
                                    Row(
                                      children: [
                                        Expanded(child: _pair(context, 176)),
                                        const SizedBox(width: 28),
                                        Expanded(child: _pair(context, 132)),
                                      ],
                                    )
                                  else ...[
                                    _pair(context, 176),
                                    const SizedBox(height: 20),
                                    _pair(context, 132),
                                  ],
                                  const SizedBox(height: 20),
                                  _bone(context, width: 150, height: 36),
                                ],
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: frame(),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _pair(context, 180),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
