import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/auth_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../services/dashboard_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/unsaved_changes.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../widgets/defensys_admin_shell.dart';

const _kDefaultScales = [
  '5-Point Scale',
  '10-Point Scale',
  '100-Point Scale',
];

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

int _defaultMaxForScale(String scale) {
  return switch (scale) {
    '5-Point Scale' => 5,
    '100-Point Scale' => 100,
    _ => 10,
  };
}

List<RubricCriterionDraft> _buildCriterionDrafts(
  Map<String, dynamic>? rubric,
  List<String> scales,
) {
  final values = rubric?['criteria'];
  if (values is List && values.isNotEmpty) {
    return values
        .whereType<Map>()
        .map((item) => RubricCriterionDraft.fromMap(item, scales))
        .toList();
  }
  final defaultScale = RubricCriterionDraft.defaultScale(scales);
  final defaultMax = _defaultMaxForScale(defaultScale);
  return [
    RubricCriterionDraft(
      scales: scales,
      name: '',
      scale: defaultScale,
      maxScore: defaultMax,
      weight: 100,
      displayOrder: 0,
    ),
  ];
}

void _disposeCriteriaList(List<RubricCriterionDraft> criteria) {
  for (final draft in criteria) {
    draft.dispose();
  }
}

/// Full-page create/edit rubric form (matches Rubric Engine reference layout — not a modal).
class RubricFullPageEditor extends ConsumerStatefulWidget {
  const RubricFullPageEditor({
    super.key,
    this.rubric,
    this.initialScope,
    this.initialEvaluationType,
    this.readOnly = false,
    required this.onBack,
    this.onDelete,
  });

  final Map<String, dynamic>? rubric;
  final String? initialScope;
  final String? initialEvaluationType;
  final bool readOnly;
  final VoidCallback onBack;
  final Future<void> Function()? onDelete;

  @override
  ConsumerState<RubricFullPageEditor> createState() => _RubricFullPageEditorState();
}

class _RubricFullPageEditorState extends ConsumerState<RubricFullPageEditor> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
  Color get _textPrimaryColor => _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A);
  Color get _textSecondaryColor => _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);
  Color get _subtleFillColor => _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9);

  late final TextEditingController _name;
  late String _scope;
  late String _evaluationType;
  late String _targetType;
  late String _rubricScale;
  late int? _semesterId;
  int? _defenseStageId;
  String? _eventName;
  late List<RubricCriterionDraft> _criteria;
  late List<String> _scales;
  bool _isDirty = false;
  bool _isCustomName = false;
  bool _isInitializing = true;
  final bool _checking = false;
  UnsavedChangesNotifier? _unsavedNotifier;
  UnsavedChangesSaveDraftNotifier? _unsavedDraftNotifier;

  String _computeDefaultRubricName({
    required String scope,
    required int? defenseStageId,
    required String evaluationType,
    required List<Map<String, dynamic>> defenseStages,
    required String pitYear,
  }) {
    final typeLabel = switch (evaluationType) {
      'adviser' => 'Adviser',
      'peer' => 'Peer',
      _ => 'Panel',
    };

    if (scope == 'pit') {
      return '$pitYear PIT — $typeLabel Rubric';
    }

    if (defenseStageId != null) {
      final stage = defenseStages.firstWhere(
        (s) => _asInt(s['id']) == defenseStageId,
        orElse: () => const <String, dynamic>{},
      );
      final stageLabel = stage['label']?.toString();
      if (stageLabel != null && stageLabel.trim().isNotEmpty) {
        return '${stageLabel.trim()} — $typeLabel Rubric';
      }
    }

    return '$typeLabel Evaluation Rubric';
  }

  void _syncDefaultRubricNameIfAuto({
    required List<Map<String, dynamic>> defenseStages,
    required String pitYear,
  }) {
    if (_isCustomName || widget.readOnly) return;
    final defaultTitle = _computeDefaultRubricName(
      scope: _scope,
      defenseStageId: _defenseStageId,
      evaluationType: _evaluationType,
      defenseStages: defenseStages,
      pitYear: pitYear,
    );
    if (_name.text != defaultTitle) {
      _name.text = defaultTitle;
    }
  }

  void _markDirty() {
    if (widget.readOnly || _isDirty || _isInitializing) return;
    setState(() => _isDirty = true);
    ref.read(unsavedChangesProvider.notifier).setDirty(true);
  }

  void _attachCriteriaListeners() {
    for (final draft in _criteria) {
      draft.name.removeListener(_markDirty);
      draft.description.removeListener(_markDirty);
      draft.maxScore.removeListener(_markDirty);
      draft.weight.removeListener(_markDirty);
      draft.displayOrder.removeListener(_markDirty);
      draft.name.addListener(_markDirty);
      draft.description.addListener(_markDirty);
      draft.maxScore.addListener(_markDirty);
      draft.weight.addListener(_markDirty);
      draft.displayOrder.addListener(_markDirty);
    }
  }

  Future<void> _handleBack() async {
    await guardUnsavedExit(
      context,
      isDirty: _isDirty,
      onExit: () {
        ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
        ref.read(unsavedChangesProvider.notifier).setDirty(false);
        widget.onBack();
      },
      onSaveDraft: () => _save('draft', showConfirmation: false),
    );
  }

  bool get _editing => widget.rubric != null;

  bool _isPitLeadOnly(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (user['role']?.toString() == 'admin') return false;
    if (user['is_superuser'] == true) return false;
    return user['is_pit_lead'] == true;
  }

  bool _isCapstoneOnlyManager(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (_isPitLeadOnly(user)) return false;
    return user['role']?.toString() == 'admin' || user['is_superuser'] == true;
  }

  String _resolveInitialScope(Map<String, dynamic>? rubric) {
    final fromRubric = rubric?['scope']?.toString();
    if (fromRubric != null && fromRubric.isNotEmpty) {
      return fromRubric;
    }
    final user = ref.read(authProvider).user;
    if (_isPitLeadOnly(user)) {
      return 'pit';
    }
    if (_isCapstoneOnlyManager(user)) {
      return 'capstone';
    }
    final fromWidget = widget.initialScope?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    return 'capstone';
  }

  void _onScopeChanged(
    String scope, {
    required List<Map<String, dynamic>> defenseStages,
    required String pitYear,
  }) {
    setState(() {
      _scope = scope;
      if (scope == 'pit') {
        _defenseStageId = null;
        if (_evaluationType == 'adviser') {
          _evaluationType = 'panel';
        }
      }
      _syncDefaultRubricNameIfAuto(
        defenseStages: defenseStages,
        pitYear: pitYear,
      );
    });
    _markDirty();
  }


  String _createSubtitle() {
    if (_scope == 'pit') {
      return 'PIT rubrics are semester templates (panel or peer). Set the event name when scheduling defenses.';
    }
    return 'Create a standard rubric for panel/event criteria and grade weights.';
  }

  void _initFromRubric(Map<String, dynamic>? r) {
    final state = ref.read(rubricEngineProvider);
    _scales = state.scaleOptions.isEmpty ? _kDefaultScales : state.scaleOptions;
    _name.removeListener(_markDirty);
    _name.text = r?['name']?.toString() ?? '';
    _isCustomName = r != null && _name.text.trim().isNotEmpty;
    _scope = _resolveInitialScope(r);
    _evaluationType = r?['evaluation_type']?.toString() ??
        widget.initialEvaluationType ??
        'panel';
    _targetType = r?['target_type']?.toString() ?? 'team';
    if (_evaluationType == 'peer') {
      _targetType = 'individual';
    }
    _semesterId = _asInt(r?['semester_id']) ?? _asInt(state.activeSemester?['id']);
    _defenseStageId = _asInt(r?['defense_stage_id']);
    _eventName = r?['event_name']?.toString();
    try {
      _disposeCriteriaList(_criteria);
    } catch (_) {}
    _criteria = _buildCriterionDrafts(r, _scales);
    _rubricScale = r?['scale']?.toString() ??
        (_criteria.isNotEmpty
            ? _criteria.first.scale
            : RubricCriterionDraft.defaultScale(_scales));
    if (_scope == 'pit' && _evaluationType == 'adviser') {
      _evaluationType = 'panel';
    }
    _name.addListener(_markDirty);
    _attachCriteriaListeners();
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _initFromRubric(widget.rubric);
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(rubricEngineProvider);
      if (s.rubrics.isEmpty) {
        ref.read(rubricEngineProvider.notifier).fetchRubrics();
      }
      if (mounted) {
        ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(
            () => _save('draft', showConfirmation: false));
        if (!_isCustomName && _name.text.trim().isEmpty) {
          final dashboard = ref.read(dashboardProvider('faculty')).data;
          final pitYear = dashboard?['pit_lead_year']?.toString() ?? '2nd Year';
          setState(() {
            _syncDefaultRubricNameIfAuto(
              defenseStages: s.defenseStages,
              pitYear: pitYear,
            );
          });
        }
        _isInitializing = false;
      }
    });
  }

  @override
  void didUpdateWidget(RubricFullPageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rubric != oldWidget.rubric && !_isDirty) {
      setState(() {
        _initFromRubric(widget.rubric);
      });
    }
  }

  @override
  void dispose() {
    _name.removeListener(_markDirty);
    _name.dispose();
    for (final draft in _criteria) {
      draft.name.removeListener(_markDirty);
      draft.description.removeListener(_markDirty);
      draft.maxScore.removeListener(_markDirty);
      draft.weight.removeListener(_markDirty);
      draft.displayOrder.removeListener(_markDirty);
    }
    _disposeCriteriaList(_criteria);
    releaseUnsavedChangesAfterFrame(_unsavedNotifier, _unsavedDraftNotifier);
    super.dispose();
  }

  void _cloneFromRubric(Map<String, dynamic> sourceRubric) {
    setState(() {
      _name.text = '${sourceRubric['name']} (Copy)';
      _isCustomName = true;
      _scope = sourceRubric['scope'] ?? _scope;
      _evaluationType = sourceRubric['evaluation_type'] ?? _evaluationType;
      _targetType = sourceRubric['target_type'] ?? _targetType;
      if (_evaluationType == 'peer') {
        _targetType = 'individual';
      }
      _rubricScale = sourceRubric['scale']?.toString() ?? _rubricScale;
      _defenseStageId = null;

      _disposeCriteriaList(_criteria);
      final clonedCriteria = sourceRubric['criteria'];
      if (clonedCriteria is List) {
        _criteria = clonedCriteria
            .whereType<Map>()
            .map((item) => RubricCriterionDraft.fromMap(item, _scales))
            .toList();
      } else {
        _criteria = [RubricCriterionDraft(scales: _scales, scale: _rubricScale)];
      }
      _attachCriteriaListeners();
    });
    _markDirty();
    showSuccessToast(context, 'Rubric criteria and details cloned.');
  }

  void _showCloneRubricDialog(
    BuildContext context,
    List<Map<String, dynamic>> availableRubrics,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _CloneRubricDialog(
          availableRubrics: availableRubrics,
          onClone: (sourceRubric) {
            _cloneFromRubric(sourceRubric);
            Navigator.pop(dialogContext);
          },
        );
      },
    );
  }

  Widget _buildCloneDropdown(RubricEngineState state) {
    if (_editing || widget.readOnly) return const SizedBox.shrink();

    final user = ref.read(authProvider).user;
    final isPitLead = _isPitLeadOnly(user);

    final availableRubrics = state.rubrics.where((r) {
      if (isPitLead) {
        return r['scope'] == 'pit';
      }
      return true;
    }).toList();

    if (availableRubrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeledControl(
          'CLONE FROM EXISTING RUBRIC (OPTIONAL)',
          InkWell(
            onTap: () => _showCloneRubricDialog(context, availableRubrics),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD1D5DB)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.copy_all_rounded,
                    color: AppColors.maroon,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Select a rubric to copy criteria...',
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        color: const Color(0xFF9CA3AF),
                        fontSize: _bodySize,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 16),
      ],
    );
  }

  static const _fieldLabelSize = 10.0;
  static const _bodySize = 13.0;
  static const _sectionTitleSize = 16.0;
  static const _helperSize = 11.0;

  TextStyle get _staticLabelStyle => TextStyle(
        fontFamily: DefensysUi.fontFamily,
        fontSize: _fieldLabelSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.45,
        color: _textSecondaryColor,
      );

  /// Outlined input with **no** Material label on the border — use [_labeledControl] for the caption above.
  InputDecoration _outlineInputDec({String? hint}) {
    final borderSide = BorderSide(color: _borderColor);
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: _subtleFillColor,
      isDense: true,
      hintStyle: TextStyle(
        fontFamily: DefensysUi.fontFamily,
        color: _isDark ? const Color(0xFF71717A) : const Color(0xFF9CA3AF),
        fontSize: _bodySize,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: borderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: borderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _labeledControl(String label, Widget control) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _staticLabelStyle),
        const SizedBox(height: 6),
        control,
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Color? iconColor,
    Widget? trailing,
  }) {
    final effectiveIconColor = iconColor ?? DefensysTokens.maroonOf(context);
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: effectiveIconColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: _sectionTitleSize,
                      fontWeight: FontWeight.w900,
                      color: _isDark ? DefensysTokens.maroonLight : AppColors.maroon,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildScopeHeaderWidget({
    required bool canSwitchScope,
    required RubricEngineState state,
    required String pitYear,
  }) {
    if (canSwitchScope) {
      return Container(
        decoration: BoxDecoration(
          color: _subtleFillColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScopeToggleSegment('capstone', 'Capstone', state, pitYear),
            _buildScopeToggleSegment('pit', 'PIT', state, pitYear),
          ],
        ),
      );
    }
    final isPit = _scope == 'pit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _subtleFillColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPit ? Icons.layers_outlined : Icons.account_balance_outlined,
            size: 13,
            color: _textSecondaryColor,
          ),
          const SizedBox(width: 5),
          Text(
            isPit ? 'PIT Program' : 'Capstone Program',
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: _textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeToggleSegment(
    String val,
    String label,
    RubricEngineState state,
    String pitYear,
  ) {
    final active = _scope == val;
    if (active) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.maroonOf(context),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () {
        _onScopeChanged(
          val,
          defenseStages: state.defenseStages,
          pitYear: pitYear,
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textSecondaryColor,
          ),
        ),
      ),
    );
  }

  TextStyle get _dropdownFieldStyle => TextStyle(
        fontFamily: DefensysUi.fontFamily,
        fontSize: _bodySize,
        color: _textPrimaryColor,
      );

  String _scaleDisplayLabel(String scale) {
    return switch (scale) {
      '5-Point Scale' => '5-Point Scale (1 - 5)',
      '10-Point Scale' => '10-Point Scale (1 - 10)',
      '100-Point Scale' => '100-Point Scale (Percentage)',
      _ => scale,
    };
  }

  void _onRubricScaleChanged(String newScale) {
    setState(() {
      _rubricScale = newScale;
      final max = _defaultMaxForScale(newScale);
      for (final c in _criteria) {
        c.scale = newScale;
        c.maxScore.text = max.toString();
      }
    });
    _markDirty();
  }

  num get _totalCriteriaWeight {
    num total = 0;
    for (final c in _criteria) {
      total += num.tryParse(c.weight.text.trim()) ?? 0;
    }
    return total;
  }

  void _distributeWeightsEvenly() {
    if (_criteria.isEmpty) return;
    final count = _criteria.length;
    final base = (100.0 / count);
    final roundedBase = (base * 10).round() / 10.0;
    num running = 0;
    for (int i = 0; i < count; i++) {
      if (i == count - 1) {
        final remainder = ((100.0 - running) * 10).round() / 10.0;
        _criteria[i].weight.text =
            (remainder % 1 == 0 ? remainder.toInt() : remainder).toString();
      } else {
        _criteria[i].weight.text =
            (roundedBase % 1 == 0 ? roundedBase.toInt() : roundedBase)
                .toString();
        running += roundedBase;
      }
    }
    setState(() {});
    _markDirty();
  }

  void _moveCriterionUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _criteria.removeAt(index);
      _criteria.insert(index - 1, item);
      _reassignDisplayOrders();
    });
    _markDirty();
  }

  void _moveCriterionDown(int index) {
    if (index >= _criteria.length - 1) return;
    setState(() {
      final item = _criteria.removeAt(index);
      _criteria.insert(index + 1, item);
      _reassignDisplayOrders();
    });
    _markDirty();
  }

  void _reassignDisplayOrders() {
    for (int i = 0; i < _criteria.length; i++) {
      _criteria[i].displayOrder.text = i.toString();
    }
  }

  Widget _buildWeightAssistantBar() {
    final total = _totalCriteriaWeight;
    final count = _criteria.length;
    final isOver = total > 100.01;
    final isUnder = total < 99.99;

    final progressRatio = (total / 100.0).clamp(0.0, 1.0);
    Color statusColor = const Color(0xFF16A34A);
    Color statusBg = _isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
    Color statusBorder = _isDark ? const Color(0xFF047857) : const Color(0xFFA7F3D0);
    String statusText = '100% Balanced ✓';

    if (isOver) {
      statusColor = const Color(0xFFDC2626);
      statusBg = _isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
      statusBorder = _isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA);
      final overAmt = (total - 100).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      statusText = 'Exceeds 100% by $overAmt%';
    } else if (isUnder) {
      statusColor = const Color(0xFFD97706);
      statusBg = _isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
      statusBorder = _isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A);
      final remAmt = (100 - total).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      statusText = '$remAmt% Unallocated';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _subtleFillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.balance_rounded, size: 18, color: DefensysTokens.maroonOf(context)),
              const SizedBox(width: 8),
              Text(
                'Weight Allocation: ',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: _textPrimaryColor,
                ),
              ),
              Text(
                '${total.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}% of 100%',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusBorder),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const Spacer(),
              if (!widget.readOnly && count > 0)
                OutlinedButton(
                  onPressed: _distributeWeightsEvenly,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textPrimaryColor,
                    side: BorderSide(color: _borderColor),
                    backgroundColor: _surfaceColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: Text(
                    'Distribute Evenly (${(100.0 / count).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}% each)',
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _textPrimaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 5,
              backgroundColor: _borderColor,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _criterionCard(
    RubricCriterionDraft draft,
    int index, {
    required bool enabled,
    required VoidCallback? onRemove,
    required VoidCallback onChanged,
  }) {
    final isBoth = _targetType == 'both';
    final isTeam = draft.targetType == 'team';
    final maxPts = _defaultMaxForScale(_rubricScale);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: DefensysTokens.maroonOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: draft.name,
                  enabled: enabled,
                  onChanged: enabled ? (_) => onChanged() : null,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _textPrimaryColor,
                  ),
                  decoration: _outlineInputDec(
                    hint: 'Criterion Title (e.g. Technical Implementation)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 105,
                child: TextField(
                  controller: draft.weight,
                  enabled: enabled,
                  onChanged: enabled ? (_) => onChanged() : null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textPrimaryColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'WEIGHT',
                    suffixText: '%',
                    suffixStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: DefensysTokens.maroonOf(context),
                    ),
                    filled: true,
                    fillColor: _subtleFillColor,
                    isDense: true,
                    labelStyle: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _textSecondaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: DefensysTokens.maroonOf(context),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Move up',
                child: IconButton(
                  onPressed: enabled && index > 0 ? () => _moveCriterionUp(index) : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  color: _textSecondaryColor,
                ),
              ),
              Tooltip(
                message: 'Move down',
                child: IconButton(
                  onPressed: enabled && index < _criteria.length - 1
                      ? () => _moveCriterionDown(index)
                      : null,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  color: _textSecondaryColor,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Remove criterion',
                  child: IconButton(
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: AppColors.danger.withValues(alpha: 0.85),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assessment_outlined, size: 13, color: _textSecondaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'Scale: $_rubricScale (Max $maxPts pts)',
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBoth) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Target: ',
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSecondaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: enabled
                          ? () {
                              setState(() => draft.targetType = 'team');
                              _markDirty();
                            }
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTeam
                              ? DefensysTokens.maroonOf(context).withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isTeam
                                ? DefensysTokens.maroonOf(context)
                                : _borderColor,
                            width: isTeam ? 1.2 : 1,
                          ),
                        ),
                        child: Text(
                          '👥 Team',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: 11,
                            fontWeight: isTeam ? FontWeight.w800 : FontWeight.w500,
                            color: isTeam
                                ? DefensysTokens.maroonOf(context)
                                : _textSecondaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: enabled
                          ? () {
                              setState(() => draft.targetType = 'individual');
                              _markDirty();
                            }
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: !isTeam
                              ? const Color(0xFFEFF6FF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: !isTeam
                                ? const Color(0xFF2563EB)
                                : _borderColor,
                            width: !isTeam ? 1.2 : 1,
                          ),
                        ),
                        child: Text(
                          '👤 Individual',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: 11,
                            fontWeight: !isTeam ? FontWeight.w800 : FontWeight.w500,
                            color: !isTeam
                                ? const Color(0xFF1D4ED8)
                                : _textSecondaryColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: draft.description,
            enabled: enabled,
            onChanged: enabled ? (_) => onChanged() : null,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              fontSize: 12.5,
              color: _textPrimaryColor,
              height: 1.4,
            ),
            decoration: _outlineInputDec(
              hint: 'Evaluation Guidelines & Description: Explain the expectations and benchmarks for full vs. partial credit...',
            ),
          ),
        ],
      ),
    );
  }

  String? _validationMessage() {
    if (_name.text.trim().isEmpty) {
      return 'Enter a rubric name.';
    }
    if (_semesterId == null) {
      return 'Select a semester.';
    }
    if (_criteria.isEmpty) {
      return 'Add at least one criterion.';
    }
    final seenNames = <String>{};
    for (final draft in _criteria) {
      final name = draft.name.text.trim();
      if (name.isEmpty) {
        return 'Enter a name for each criterion.';
      }
      final lowerName = name.toLowerCase();
      if (seenNames.contains(lowerName)) {
        return 'Criterion names must be unique.';
      }
      seenNames.add(lowerName);

      final maxScore = num.tryParse(draft.maxScore.text.trim());
      if (maxScore == null || maxScore <= 0) {
        return 'Enter a valid max score for each criterion.';
      }
      final weight = num.tryParse(draft.weight.text.trim());
      if (weight == null || weight <= 0) {
        return 'Enter a valid weight for each criterion.';
      }
    }

    if (_targetType == 'both') {
      final hasTeam = _criteria.any((c) => c.targetType == 'team');
      final hasIndiv = _criteria.any((c) => c.targetType == 'individual');
      if (!hasTeam || !hasIndiv) {
        return "Rubrics set to 'Both (Team & Individual)' must contain at least one Team criterion and at least one Individual criterion. If all criteria are Team-based, please set the Scoring Target to 'Team'.";
      }
    }

    return null;
  }

  Future<bool> _save(String status, {bool showConfirmation = true}) async {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      showValidationToast(context, validationMessage);
      return false;
    }

    String title = '';
    String confirmLabel = '';

    if (status == 'published') {
      title = 'Publish Rubric?';
      confirmLabel = 'Publish';
    } else {
      title = 'Save Rubric Draft?';
      confirmLabel = 'Save Draft';
    }

    if (showConfirmation && !mounted) return false;

    if (showConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            backgroundColor: _surfaceColor,
            title: Text(
              title,
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
                color: _textPrimaryColor,
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    status == 'published'
                        ? 'Are you sure you want to publish this rubric? Published rubrics can be assigned to defense stages and PIT events. You can continue editing criteria until defenses are scheduled or evaluations begin.'
                        : 'Are you sure you want to save this rubric draft?',
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: 13.5,
                      color: _textSecondaryColor,
                      height: 1.4,
                    ),
                  ),
                  if (status == 'published') ...[
                    Builder(
                      builder: (context) {
                        final total = _totalCriteriaWeight;
                        if ((total - 100).abs() <= 0.05) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Criterion weights currently total ${total.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}% (standard target is 100%).',
                                  style: TextStyle(
                                    fontFamily: DefensysUi.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: _textSecondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroonOf(context),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return false;
    }

    final payload = {
      'name': _name.text.trim(),
      'scope': _scope,
      'semester_id': _semesterId,
      'defense_stage_id': _scope == 'capstone' ? _defenseStageId : null,
      'event_name': _eventName ?? '',
      'evaluation_type': _evaluationType,
      'target_type': _targetType,
      'scale': _rubricScale,
      'status': status,
      'criteria': _criteria.map((d) => d.toPayload()).toList(),
    };

    final notifier = ref.read(rubricEngineProvider.notifier);
    final ok = _editing
        ? await notifier.updateRubric(_asInt(widget.rubric!['id'])!, payload)
        : await notifier.addRubric(payload);

    if (!mounted) return ok;
    if (ok) {
      if (mounted) {
        setState(() => _isDirty = false);
      }
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
      await notifier.fetchRubrics();
      if (!mounted) return ok;
      showSuccessToast(
        context,
        status == 'published'
            ? 'Rubric published successfully.'
            : 'Rubric draft saved.',
      );
      if (showConfirmation) {
        widget.onBack();
      }
    } else {
      final error =
          ref.read(rubricEngineProvider).error ?? 'Rubric could not be saved.';
      showErrorToast(context, error);
    }
    return ok;
  }

  Widget _softLockedBanner() {
    final assignedContext = widget.rubric?['assigned_context_name']?.toString() ?? 'a defense stage';
    final scope = widget.rubric?['scope']?.toString() ?? _scope;
    final contextType = scope == 'pit' ? 'PIT Event' : 'Defense Stage';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: Color(0xFF1D4ED8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  color: Color(0xFF1E3A8A),
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(
                    text: 'Assigned Notice: ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text:
                        'This rubric is currently assigned to $contextType "$assignedContext". You can modify criteria and weights freely; any saved changes will automatically reflect in that $contextType.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedBanner() {
    final lockReason = widget.rubric?['lock_reason']?.toString();
    final assignedContext = widget.rubric?['assigned_context_name']?.toString();
    final isStageCompleted = widget.rubric?['is_stage_completed'] == true;
    final hasEvaluations = widget.rubric?['has_evaluations'] == true;
    final hasSchedule = widget.rubric?['has_schedule'] == true;

    String bannerText =
        'This rubric is locked. Criteria and settings cannot be altered.';
    if (lockReason != null && lockReason.isNotEmpty) {
      bannerText = lockReason;
    } else if (hasEvaluations) {
      bannerText =
          'This rubric is locked because evaluations/grades have already been submitted using these criteria.';
    } else if (hasSchedule && assignedContext != null && assignedContext.isNotEmpty) {
      bannerText =
          'This rubric is locked because active defense sessions are currently scheduled for "$assignedContext".';
    } else if (isStageCompleted && assignedContext != null && assignedContext.isNotEmpty) {
      bannerText =
          'This rubric is assigned to Defense Stage "$assignedContext" (Completed). Criteria and deletion are locked.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF2E2214) : DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isDark ? const Color(0xFF78350F) : DefensysUi.warningBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 18,
            color: _isDark ? const Color(0xFFFBBF24) : DefensysUi.warningText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                color: _isDark ? const Color(0xFFFDE68A) : DefensysUi.warningText,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rubricEngineProvider);
    final user = ref.watch(authProvider).user;
    final dashboard = ref.watch(dashboardProvider('faculty')).data;
    final pitYear = dashboard?['pit_lead_year']?.toString() ?? '2nd Year';
    final isPitLeadOnly = _isPitLeadOnly(user);
    final isCapstoneOnlyManager = _isCapstoneOnlyManager(user);
    final saving = state.isSaving || _checking;
    final canEdit = !widget.readOnly && !saving;
    final canSwitchScope = canEdit &&
        !_editing &&
        !isPitLeadOnly &&
        !isCapstoneOnlyManager &&
        state.scopes.length > 1;

    final activeSem = state.activeSemester;
    final activeYear = activeSem?['school_year']?.toString();
    final activeSemId = _asInt(activeSem?['id']);
    if (_semesterId == null && activeSemId != null && widget.rubric == null) {
      _semesterId = activeSemId;
    }

    final filteredSemesters = state.semesters.where((semester) {
      final semId = _asInt(semester['id']);
      final semYear = semester['school_year']?.toString();

      // Always include the currently selected semester to avoid dropdown validation crash.
      if (semId == _semesterId) {
        return true;
      }

      // Limit dropdown to semesters of the active semester's school year.
      if (activeYear != null) {
        return semYear == activeYear;
      }

      return true;
    }).toList();

    final evalItems = [
      DropdownMenuItem(
        value: 'panel',
        child: Text(
          'Panel',
          style: TextStyle(
            fontFamily: DefensysUi.fontFamily,
            fontSize: _bodySize,
            color: DefensysUi.textDark,
          ),
        ),
      ),
      if (_scope != 'pit')
        DropdownMenuItem(
          value: 'adviser',
          child: Text(
            'Adviser',
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              fontSize: _bodySize,
              color: DefensysUi.textDark,
            ),
          ),
        ),
      DropdownMenuItem(
        value: 'peer',
        child: Text(
          'Peer',
          style: TextStyle(
            fontFamily: DefensysUi.fontFamily,
            fontSize: _bodySize,
            color: DefensysUi.textDark,
          ),
        ),
      ),
    ];

    return PopScope(
      canPop: widget.readOnly || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || widget.readOnly) return;
        await _handleBack();
      },
      child: DefensysShadcnScope(
        child: ColoredBox(
          color: DefensysTokens.backgroundOf(context),
          child: SingleChildScrollView(
            padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefensysPageHeader(
              icon: widget.readOnly
                  ? Icons.lock_outline_rounded
                  : Icons.edit_note_rounded,
              title: widget.readOnly
                  ? 'View Rubric'
                  : (_editing ? 'Edit Rubric' : 'Create Rubric'),
              subtitle: widget.readOnly
                  ? 'This rubric is locked. Criteria and settings cannot be changed.'
                  : (_editing
                      ? 'Update rubric details, criteria, and evaluation settings.'
                      : _createSubtitle()),
              actions: OutlinedButton.icon(
                onPressed: saving ? null : _handleBack,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: DefensysTokens.maroonOf(context),
                ),
                label: Text(
                  'Back to Evaluation Rubrics',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: DefensysTokens.maroonOf(context),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DefensysTokens.maroonOf(context),
                  side: BorderSide(color: _borderColor),
                  backgroundColor: _surfaceColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            if (widget.readOnly || widget.rubric?['is_locked'] == true) ...[
              const SizedBox(height: 18),
              _lockedBanner(),
            ] else if (widget.rubric?['is_soft_locked'] == true ||
                widget.rubric?['is_assigned'] == true) ...[
              const SizedBox(height: 18),
              _softLockedBanner(),
            ],
            const SizedBox(height: 26),
                _sectionCard(
                  icon: Icons.description_outlined,
                  iconColor: DefensysUi.primaryMaroon,
                  title: 'Rubric Details',
                  trailing: _buildScopeHeaderWidget(
                    canSwitchScope: canSwitchScope,
                    state: state,
                    pitYear: pitYear,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCloneDropdown(state),
                      if (_scope == 'capstone') ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledControl(
                                'SEMESTER',
                                DropdownButtonFormField<int?>(
                                  key: ValueKey('sem-$_semesterId'),
                                  initialValue: _semesterId,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(
                                    hint: '— Select semester —',
                                  ),
                                  items: [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text(
                                        '— Select semester —',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          color: const Color(0xFF9CA3AF),
                                          fontSize: _bodySize,
                                        ),
                                      ),
                                    ),
                                    ...filteredSemesters.map(
                                      (semester) {
                                        final semId = _asInt(semester['id']);
                                        final isActive = semester['is_active'] == true ||
                                            semId == _asInt(state.activeSemester?['id']);
                                        final displayName =
                                            semester['display_name']?.toString() ?? '';
                                        final labelText = isActive
                                            ? '$displayName (Active)'
                                            : displayName;
                                        return DropdownMenuItem<int?>(
                                          value: semId,
                                          child: Text(
                                            labelText,
                                            style: TextStyle(
                                              fontFamily: DefensysUi.fontFamily,
                                              fontSize: _bodySize,
                                              color: _textPrimaryColor,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  onChanged: canEdit
                                      ? (v) {
                                          setState(() => _semesterId = v);
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _labeledControl(
                                'ASSIGN TO DEFENSE STAGE (OPTIONAL)',
                                DropdownButtonFormField<int?>(
                                  key: ValueKey('stage-$_defenseStageId'),
                                  initialValue: _defenseStageId,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(
                                    hint: '— None / Not assigned to a stage yet —',
                                  ),
                                  items: [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text(
                                        '— None / Not assigned to a stage yet —',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          color: const Color(0xFF9CA3AF),
                                          fontSize: _bodySize,
                                        ),
                                      ),
                                    ),
                                    ...state.defenseStages.map((stage) {
                                      final stageId = _asInt(stage['id']);
                                      final stageLabel =
                                          stage['label']?.toString() ?? 'Stage #$stageId';
                                      return DropdownMenuItem<int?>(
                                        value: stageId,
                                        child: Text(
                                          stageLabel,
                                          style: TextStyle(
                                            fontFamily: DefensysUi.fontFamily,
                                            fontSize: _bodySize,
                                            color: _textPrimaryColor,
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: canEdit
                                      ? (v) {
                                          setState(() {
                                            _defenseStageId = v;
                                            _syncDefaultRubricNameIfAuto(
                                              defenseStages: state.defenseStages,
                                              pitYear: pitYear,
                                            );
                                          });
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_defenseStageId != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 14,
                                color: DefensysTokens.maroonOf(context),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Saving will automatically assign this rubric to the selected Defense Stage.',
                                  style: TextStyle(
                                    fontFamily: DefensysUi.fontFamily,
                                    fontSize: _helperSize,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.maroonOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledControl(
                                'EVALUATION TYPE',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('eval-$_evaluationType'),
                                  initialValue: _evaluationType,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: evalItems,
                                  onChanged: canEdit
                                      ? (v) {
                                          setState(
                                            () {
                                              _evaluationType =
                                                  v ?? _evaluationType;
                                              if (_evaluationType == 'peer') {
                                                _targetType = 'individual';
                                              }
                                              _syncDefaultRubricNameIfAuto(
                                                defenseStages: state.defenseStages,
                                                pitYear: pitYear,
                                              );
                                            },
                                          );
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _labeledControl(
                                'EVALUATION SCALE',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('scale-$_rubricScale'),
                                  initialValue: _rubricScale,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: _scales.map((s) {
                                    return DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        _scaleDisplayLabel(s),
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: canEdit
                                      ? (v) {
                                          if (v != null) _onRubricScaleChanged(v);
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledControl(
                                'SCORING TARGET',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('target-$_targetType'),
                                  initialValue: _targetType,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'team',
                                      child: Text(
                                        'Team (Entire team shares the grade)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'individual',
                                      child: Text(
                                        'Individual (Students graded individually)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'both',
                                      child: Text(
                                        'Both (Team & Individual)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: canEdit && _evaluationType != 'peer'
                                      ? (v) {
                                          setState(() => _targetType = v ?? 'team');
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledControl(
                                'SEMESTER',
                                DropdownButtonFormField<int?>(
                                  key: ValueKey('sem-$_semesterId'),
                                  initialValue: _semesterId,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(
                                    hint: '— Select semester —',
                                  ),
                                  items: [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text(
                                        '— Select semester —',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          color: const Color(0xFF9CA3AF),
                                          fontSize: _bodySize,
                                        ),
                                      ),
                                    ),
                                    ...filteredSemesters.map(
                                      (semester) {
                                        final semId = _asInt(semester['id']);
                                        final isActive = semester['is_active'] == true ||
                                            semId == _asInt(state.activeSemester?['id']);
                                        final displayName =
                                            semester['display_name']?.toString() ?? '';
                                        final labelText = isActive
                                            ? '$displayName (Active)'
                                            : displayName;
                                        return DropdownMenuItem<int?>(
                                          value: semId,
                                          child: Text(
                                            labelText,
                                            style: TextStyle(
                                              fontFamily: DefensysUi.fontFamily,
                                              fontSize: _bodySize,
                                              color: _textPrimaryColor,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  onChanged: canEdit
                                      ? (v) {
                                          setState(() => _semesterId = v);
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _labeledControl(
                                'EVALUATION TYPE',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('eval-$_evaluationType'),
                                  initialValue: _evaluationType,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: evalItems,
                                  onChanged: canEdit
                                      ? (v) {
                                          setState(
                                            () {
                                              _evaluationType =
                                                  v ?? _evaluationType;
                                              if (_evaluationType == 'peer') {
                                                _targetType = 'individual';
                                              }
                                              _syncDefaultRubricNameIfAuto(
                                                defenseStages: state.defenseStages,
                                                pitYear: pitYear,
                                              );
                                            },
                                          );
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _labeledControl(
                                'EVALUATION SCALE',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('scale-$_rubricScale'),
                                  initialValue: _rubricScale,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: _scales.map((s) {
                                    return DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        _scaleDisplayLabel(s),
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: canEdit
                                      ? (v) {
                                          if (v != null) _onRubricScaleChanged(v);
                                        }
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _labeledControl(
                                'SCORING TARGET',
                                DropdownButtonFormField<String>(
                                  key: ValueKey('target-$_targetType'),
                                  initialValue: _targetType,
                                  isExpanded: true,
                                  style: _dropdownFieldStyle,
                                  decoration: _outlineInputDec(),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'team',
                                      child: Text(
                                        'Team (Entire team shares the grade)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'individual',
                                      child: Text(
                                        'Individual (Students graded individually)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'both',
                                      child: Text(
                                        'Both (Team & Individual)',
                                        style: TextStyle(
                                          fontFamily: DefensysUi.fontFamily,
                                          fontSize: _bodySize,
                                          color: _textPrimaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: canEdit && _evaluationType != 'peer'
                                      ? (v) {
                                          setState(() => _targetType = v ?? 'team');
                                          _markDirty();
                                        }
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_targetType == 'both') ...[
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final hasTeam =
                                _criteria.any((c) => c.targetType == 'team');
                            final hasIndiv = _criteria
                                .any((c) => c.targetType == 'individual');
                            final hasBothTargets = hasTeam && hasIndiv;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: hasBothTargets
                                    ? const Color(0xFFEFF6FF)
                                    : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: hasBothTargets
                                      ? const Color(0xFFBFDBFE)
                                      : const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    hasBothTargets
                                        ? Icons.info_outline_rounded
                                        : Icons.warning_amber_rounded,
                                    size: 16,
                                    color: hasBothTargets
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFFB45309),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      hasBothTargets
                                          ? "Rubrics set to 'Both' contain both Team and Individual criteria."
                                          : "Rubrics set to 'Both (Team & Individual)' must contain at least 1 Team criterion and 1 Individual criterion. Update criteria target types or set Scoring Target to 'Team'.",
                                      style: TextStyle(
                                        fontFamily: DefensysUi.fontFamily,
                                        fontSize: _helperSize,
                                        fontWeight: FontWeight.w600,
                                        color: hasBothTargets
                                            ? const Color(0xFF1E40AF)
                                            : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      if (_evaluationType == 'peer') ...[
                        const SizedBox(height: 6),
                        Text(
                          'Peer evaluations are always scored individually per student.',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: _helperSize,
                            fontWeight: FontWeight.w600,
                            color: DefensysUi.primaryMaroon,
                          ),
                        ),
                      ],
                      if (_scope == 'pit') ...[
                        const SizedBox(height: 12),
                        Text(
                          'PIT rubrics: panel or peer evaluation only (criteria here). Grade split and event name are set on Defense Scheduler (Step 1) per PIT event.',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: _helperSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Divider(height: 1, color: _borderColor),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('RUBRIC NAME', style: _staticLabelStyle),
                          if (_isCustomName && canEdit)
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                setState(() {
                                  _isCustomName = false;
                                  _syncDefaultRubricNameIfAuto(
                                    defenseStages: state.defenseStages,
                                    pitYear: pitYear,
                                  );
                                });
                                _markDirty();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.refresh_rounded,
                                      size: 13,
                                      color: DefensysTokens.maroonOf(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reset to default',
                                      style: TextStyle(
                                        fontFamily: DefensysUi.fontFamily,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: DefensysTokens.maroonOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _name,
                        enabled: canEdit,
                        onChanged: (val) {
                          if (!_isCustomName) {
                            setState(() {
                              _isCustomName = true;
                            });
                          }
                          _markDirty();
                        },
                        style: TextStyle(
                          fontFamily: DefensysUi.fontFamily,
                          fontSize: _bodySize,
                          color: _textPrimaryColor,
                        ),
                        decoration: _outlineInputDec(
                          hint: _scope == 'pit'
                              ? 'e.g. $pitYear PIT — Panel Rubric'
                              : 'e.g. Concept Proposal — Panel Rubric',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            _isCustomName ? Icons.edit_note_rounded : Icons.auto_awesome_rounded,
                            size: 14,
                            color: _isCustomName
                                ? _textSecondaryColor
                                : DefensysTokens.maroonOf(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isCustomName
                                  ? 'Custom title applied.'
                                  : 'Default title based on your stage and evaluation type selections.',
                              style: TextStyle(
                                fontFamily: DefensysUi.fontFamily,
                                fontSize: _helperSize,
                                fontWeight: _isCustomName ? FontWeight.w500 : FontWeight.w600,
                                color: _isCustomName
                                    ? _textSecondaryColor
                                    : DefensysTokens.maroonOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _sectionCard(
                  icon: Icons.view_list_rounded,
                  title: 'Evaluation Criteria (${_criteria.length})',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWeightAssistantBar(),
                      ..._criteria.asMap().entries.map((e) {
                        final i = e.key;
                        final d = e.value;
                        return _criterionCard(
                          d,
                          i,
                          enabled: canEdit,
                          onRemove: !canEdit || _criteria.length == 1
                              ? null
                              : () {
                                  setState(() {
                                    d.dispose();
                                    _criteria.removeAt(i);
                                    _reassignDisplayOrders();
                                  });
                                  _attachCriteriaListeners();
                                  _markDirty();
                                },
                          onChanged: () {
                            setState(() {});
                            _markDirty();
                          },
                        );
                      }),
                      if (canEdit) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              String defaultTarget = 'team';
                              if (_targetType == 'both') {
                                final hasTeam = _criteria
                                    .any((c) => c.targetType == 'team');
                                final hasIndiv = _criteria
                                    .any((c) => c.targetType == 'individual');
                                if (hasTeam && !hasIndiv) {
                                  defaultTarget = 'individual';
                                }
                              }
                              setState(() {
                                _criteria.add(
                                  RubricCriterionDraft(
                                    scales: _scales,
                                    name: '',
                                    scale: _rubricScale,
                                    maxScore: _defaultMaxForScale(_rubricScale),
                                    weight: 10,
                                    displayOrder: _criteria.length,
                                    targetType: defaultTarget,
                                  ),
                                );
                              });
                              _attachCriteriaListeners();
                              _markDirty();
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Criterion'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DefensysTokens.maroonOf(context),
                              side: BorderSide(
                                color: DefensysTokens.maroonOf(context),
                                width: 1.5,
                              ),
                              backgroundColor: _surfaceColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: saving ? null : widget.onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: DefensysUi.primaryMaroon,
                        textStyle: TextStyle(
                          fontFamily: DefensysUi.fontFamily,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      child: Text(widget.readOnly ? 'Back' : 'Cancel'),
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final canDelete = widget.rubric?['can_delete'] != false;
                          final lockReason = widget.rubric?['lock_reason']?.toString();
                          final isAssigned = widget.rubric?['is_assigned'] == true;
                          final assignedContext = widget.rubric?['assigned_context_name']?.toString();
                          final isDisabled = saving || !canDelete;

                          final buttonWidget = TextButton(
                            onPressed: isDisabled ? null : widget.onDelete,
                            style: TextButton.styleFrom(
                              foregroundColor: isDisabled
                                  ? const Color(0xFF9CA3AF)
                                  : AppColors.danger,
                              textStyle: TextStyle(
                                fontFamily: DefensysUi.fontFamily,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            child: Text(
                              !canDelete ? 'Delete rubric (Locked)' : 'Delete rubric',
                            ),
                          );

                          final scope = widget.rubric?['scope']?.toString() ?? _scope;
                          if (!canDelete && lockReason != null && lockReason.isNotEmpty) {
                            return Tooltip(
                              message: lockReason,
                              child: buttonWidget,
                            );
                          } else if (isAssigned && assignedContext != null && assignedContext.isNotEmpty) {
                            return Tooltip(
                              message: scope == 'pit'
                                  ? 'Rubric is assigned to PIT Event "$assignedContext" and cannot be deleted.'
                                  : 'Rubric is assigned to Defense Stage "$assignedContext". Deleting will remove assignment.',
                              child: buttonWidget,
                            );
                          }
                          return buttonWidget;
                        },
                      ),
                    ],
                    const Spacer(),
                    if (!widget.readOnly) ...[
                      OutlinedButton(
                        onPressed: saving ? null : () => _save('draft'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DefensysTokens.maroonOf(context),
                          side: BorderSide(
                            color:
                                DefensysTokens.maroonOf(context).withValues(alpha: 0.85),
                            width: 1.5,
                          ),
                          backgroundColor: _surfaceColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Save as Draft',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: saving ? null : () => _save('published'),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          color: DefensysUi.accentGold,
                          size: 17,
                        ),
                        label: const Text(
                          'Publish Rubric',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DefensysTokens.maroonOf(context),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RubricCriterionDraft {
  RubricCriterionDraft({
    required List<String> scales,
    String name = '',
    String description = '',
    String? scale,
    int? maxScore,
    num weight = 100,
    int displayOrder = 0,
    String targetType = 'team',
  }) : this._(
          name: TextEditingController(text: name),
          description: TextEditingController(text: description),
          scale: scale ?? defaultScale(scales),
          maxScore: TextEditingController(
            text: (maxScore ?? _scaleMax(scale ?? defaultScale(scales)))
                .toString(),
          ),
          weight: TextEditingController(text: weight.toString()),
          displayOrder: TextEditingController(text: displayOrder.toString()),
          targetType: targetType,
        );

  RubricCriterionDraft._({
    required this.name,
    required this.description,
    required this.scale,
    required this.maxScore,
    required this.weight,
    required this.displayOrder,
    required this.targetType,
  });

  factory RubricCriterionDraft.fromMap(Map item, List<String> scales) {
    return RubricCriterionDraft(
      scales: scales,
      name: item['name']?.toString() ?? '',
      description: item['description']?.toString() ?? '',
      scale: item['scale']?.toString(),
      maxScore: int.tryParse(item['max_score']?.toString() ?? ''),
      weight: num.tryParse(item['weight']?.toString() ?? '') ?? 1,
      displayOrder:
          int.tryParse(item['display_order']?.toString() ?? '') ?? 0,
      targetType: item['target_type']?.toString() ?? 'team',
    );
  }

  final TextEditingController name;
  final TextEditingController description;
  String scale;
  final TextEditingController maxScore;
  final TextEditingController weight;
  final TextEditingController displayOrder;
  String targetType;

  Map<String, dynamic> toPayload() {
    return {
      'name': name.text.trim(),
      'description': description.text.trim(),
      'scale': scale,
      'max_score': int.tryParse(maxScore.text.trim()) ?? _scaleMax(scale),
      'weight': num.tryParse(weight.text.trim()) ?? 1,
      'display_order': int.tryParse(displayOrder.text.trim()) ?? 0,
      'target_type': targetType,
    };
  }

  void dispose() {
    name.dispose();
    description.dispose();
    maxScore.dispose();
    weight.dispose();
    displayOrder.dispose();
  }

  static int _scaleMax(String scale) {
    return switch (scale) {
      '5-Point Scale' => 5,
      '100-Point Scale' => 100,
      _ => 10,
    };
  }

  static String defaultScale(List<String> scales) {
    if (scales.contains('10-Point Scale')) {
      return '10-Point Scale';
    }
    return scales.isNotEmpty ? scales.first : '10-Point Scale';
  }
}

class _CloneRubricDialog extends StatefulWidget {
  const _CloneRubricDialog({
    required this.availableRubrics,
    required this.onClone,
  });

  final List<Map<String, dynamic>> availableRubrics;
  final ValueChanged<Map<String, dynamic>> onClone;

  @override
  State<_CloneRubricDialog> createState() => _CloneRubricDialogState();
}

class _CloneRubricDialogState extends State<_CloneRubricDialog> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB);
  Color get _textPrimaryColor => _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF111827);
  Color get _textSecondaryColor => _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF6B7280);

  String _searchQuery = '';
  String _selectedScope = 'all';
  String? _selectedSemester;
  Map<String, dynamic>? _selectedRubric;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    final semesters = widget.availableRubrics
        .map((r) => r['display_semester']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final filtered = widget.availableRubrics.where((r) {
      if (_searchQuery.isNotEmpty) {
        final name = r['name']?.toString().toLowerCase() ?? '';
        final sem = r['display_semester']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        if (!name.contains(query) && !sem.contains(query)) {
          return false;
        }
      }
      if (_selectedScope != 'all') {
        if (r['scope'] != _selectedScope) return false;
      }
      if (_selectedSemester != null) {
        if (r['display_semester']?.toString() != _selectedSemester) return false;
      }
      return true;
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: isDesktop ? 950 : screenWidth * 0.9,
        height: 600,
        color: _surfaceColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Divider(height: 1, color: _borderColor),
            Expanded(
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 11,
                          child: _buildLeftPane(filtered, semesters),
                        ),
                        VerticalDivider(width: 1, color: _borderColor),
                        Expanded(
                          flex: 12,
                          child: _buildRightPane(),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildLeftPane(filtered, semesters),
                        ),
                        Divider(height: 1, color: _borderColor),
                        Expanded(
                          flex: 2,
                          child: _buildRightPane(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF9FAFB),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Rubric to Clone',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.maroonOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Browse and preview templates before applying criteria.',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontSize: 12,
                  color: _textSecondaryColor,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPane(List<Map<String, dynamic>> filtered, List<String> semesters) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(fontSize: 13, fontFamily: DefensysUi.fontFamily, color: _textPrimaryColor),
            decoration: InputDecoration(
              hintText: 'Search by name or semester...',
              hintStyle: TextStyle(color: _textSecondaryColor, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 18, color: _textSecondaryColor),
              filled: true,
              fillColor: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _borderColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildScopeTab('all', 'All'),
              const SizedBox(width: 6),
              _buildScopeTab('capstone', 'Capstone'),
              const SizedBox(width: 6),
              _buildScopeTab('pit', 'PIT'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedSemester,
                    dropdownColor: _surfaceColor,
                    hint: Text('All Semesters', style: TextStyle(fontSize: 11, fontFamily: DefensysUi.fontFamily, color: _textSecondaryColor)),
                    isDense: true,
                    style: TextStyle(fontSize: 11, color: _textPrimaryColor, fontFamily: DefensysUi.fontFamily),
                    onChanged: (val) => setState(() {
                      _selectedSemester = val;
                    }),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Semesters', style: TextStyle(color: _textPrimaryColor)),
                      ),
                      ...semesters.map((s) => DropdownMenuItem<String?>(
                        value: s,
                        child: Text(s, style: TextStyle(color: _textPrimaryColor)),
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching rubrics found',
                      style: TextStyle(color: _textSecondaryColor, fontSize: 13, fontFamily: DefensysUi.fontFamily),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final r = filtered[index];
                      final isSelected = _selectedRubric?['id'] == r['id'];
                      final displaySem = r['display_semester']?.toString() ?? '';
                      final isPit = r['scope'] == 'pit';
                      final criteriaCount = (r['criteria'] as List?)?.length ?? 0;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedRubric = r;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? DefensysTokens.maroonOf(context).withValues(alpha: _isDark ? 0.2 : 0.05) : _surfaceColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? DefensysTokens.maroonOf(context) : _borderColor,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['name']?.toString() ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: _textPrimaryColor,
                                    fontFamily: DefensysUi.fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPit ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isPit ? 'PIT' : 'Capstone',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isPit ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                                          fontFamily: DefensysUi.fontFamily,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _evaluationLabel(r['evaluation_type']?.toString()),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF4B5563),
                                          fontFamily: DefensysUi.fontFamily,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (displaySem.isNotEmpty)
                                      Text(
                                        displaySem,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                          fontFamily: DefensysUi.fontFamily,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$criteriaCount Criteria',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                    fontFamily: DefensysUi.fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeTab(String scope, String label) {
    final active = _selectedScope == scope;
    return GestureDetector(
      onTap: () => setState(() => _selectedScope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? DefensysTokens.maroonOf(context) : _borderColor,
            width: active ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? DefensysTokens.maroonOf(context) : _textSecondaryColor,
            fontFamily: DefensysUi.fontFamily,
          ),
        ),
      ),
    );
  }

  Widget _buildRightPane() {
    if (_selectedRubric == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 54, color: _textSecondaryColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Select a rubric template',
              style: TextStyle(
                color: _textSecondaryColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                fontFamily: DefensysUi.fontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select a rubric from the list to preview its evaluation criteria.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondaryColor,
                fontSize: 11.5,
                fontFamily: DefensysUi.fontFamily,
              ),
            ),
          ],
        ),
      );
    }

    final rubric = _selectedRubric!;
    final name = rubric['name']?.toString() ?? '';
    final criteria = rubric['criteria'] as List? ?? [];
    
    num totalWeight = 0;
    for (final c in criteria) {
      if (c is Map) {
        totalWeight += num.tryParse(c['weight']?.toString() ?? '') ?? 0;
      }
    }

    return Container(
      color: DefensysTokens.backgroundOf(context),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _textPrimaryColor,
                        fontFamily: DefensysUi.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total Weight: ${totalWeight.toStringAsFixed(0)}% · ${criteria.length} Criteria',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondaryColor,
                        fontWeight: FontWeight.w500,
                        fontFamily: DefensysUi.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: _borderColor),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: criteria.length,
              itemBuilder: (context, index) {
                final c = criteria[index] as Map? ?? {};
                final critName = c['name']?.toString() ?? 'Criterion ${index + 1}';
                final desc = c['description']?.toString() ?? '';
                final weight = c['weight']?.toString() ?? '0';
                final maxScore = c['max_score']?.toString() ?? '0';
                final targetType = c['target_type'] == 'individual' ? 'Individual' : 'Team';
                final scale = c['scale']?.toString() ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              critName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _textPrimaryColor,
                                fontFamily: DefensysUi.fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isDark ? const Color(0xFF451A03) : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _isDark ? const Color(0xFF9A3412) : const Color(0xFFFFEDD5)),
                            ),
                            child: Text(
                              'Weight: $weight%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isDark ? const Color(0xFFFB923C) : const Color(0xFFC2410C),
                                fontFamily: DefensysUi.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _textSecondaryColor,
                            height: 1.3,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.assessment_outlined, size: 12, color: _textSecondaryColor),
                          const SizedBox(width: 4),
                          Text(
                            'Scale: $scale (Max: $maxScore)',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: _textSecondaryColor,
                              fontFamily: DefensysUi.fontFamily,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              targetType,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: _textSecondaryColor,
                                fontFamily: DefensysUi.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroonOf(context),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () => widget.onClone(rubric),
            child: const Text(
              'Clone Criteria & Configuration',
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _evaluationLabel(String? value) {
    return switch (value) {
      'adviser' => 'Adviser',
      'peer' => 'Peer',
      _ => 'Panel',
    };
  }
}
