import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_provider.dart';
import '../../../services/rubric_engine_provider.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/unsaved_changes.dart';
import '../../../toasts/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';

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
  return [
    RubricCriterionDraft(scales: scales),
    RubricCriterionDraft(scales: scales, name: 'Presentation and Delivery'),
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
  late final TextEditingController _name;
  late String _scope;
  late String _evaluationType;
  late String _targetType;
  late int? _semesterId;
  int? _defenseStageId;
  String? _eventName;
  late List<RubricCriterionDraft> _criteria;
  late List<String> _scales;
  bool _isDirty = false;
  bool _checking = false;

  void _markDirty() {
    if (widget.readOnly || _isDirty) return;
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
      onExit: widget.onBack,
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

  void _onScopeChanged(String scope) {
    setState(() {
      _scope = scope;
      if (scope == 'pit') {
        if (_evaluationType == 'adviser') {
          _evaluationType = 'panel';
        }
      }
    });
    _markDirty();
  }

  List<DropdownMenuItem<String>> _scopeDropdownItems(
    RubricEngineState state,
  ) {
    if (state.scopes.isNotEmpty) {
      return state.scopes
          .map(
            (item) => DropdownMenuItem<String>(
              value: item['value']?.toString(),
              child: Text(
                item['label']?.toString() ?? item['value']?.toString() ?? '',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontSize: _bodySize,
                  color: DefensysUi.textDark,
                ),
              ),
            ),
          )
          .where((item) => item.value != null && item.value!.isNotEmpty)
          .toList();
    }
    return const [
      DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
      DropdownMenuItem(value: 'pit', child: Text('PIT')),
    ];
  }

  String _createSubtitle() {
    if (_scope == 'pit') {
      return 'PIT rubrics are semester templates (panel or peer). Set the event name when scheduling defenses.';
    }
    return 'Create a standard rubric for panel/event criteria and grade weights.';
  }

  @override
  void initState() {
    super.initState();
    final state = ref.read(rubricEngineProvider);
    _scales = state.scaleOptions.isEmpty ? _kDefaultScales : state.scaleOptions;
    final r = widget.rubric;
    _name = TextEditingController(text: r?['name']?.toString() ?? '');
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
    _criteria = _buildCriterionDrafts(r, _scales);
    if (_scope == 'pit' && _evaluationType == 'adviser') {
      _evaluationType = 'panel';
    }
    _name.addListener(_markDirty);
    _attachCriteriaListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(rubricEngineProvider);
      if (s.rubrics.isEmpty) {
        ref.read(rubricEngineProvider.notifier).fetchRubrics();
      }
      if (mounted) {
        ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(
            () => _save('draft', showConfirmation: false));
      }
    });
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
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    });
  }

  String _evaluationLabel(String? value) {
    return switch (value) {
      'adviser' => 'Adviser',
      'peer' => 'Peer',
      _ => 'Panel',
    };
  }

  void _cloneFromRubric(Map<String, dynamic> sourceRubric) {
    setState(() {
      _name.text = '${sourceRubric['name']} (Copy)';
      _scope = sourceRubric['scope'] ?? _scope;
      _evaluationType = sourceRubric['evaluation_type'] ?? _evaluationType;
      _targetType = sourceRubric['target_type'] ?? _targetType;
      if (_evaluationType == 'peer') {
        _targetType = 'individual';
      }

      _disposeCriteriaList(_criteria);
      final clonedCriteria = sourceRubric['criteria'];
      if (clonedCriteria is List) {
        _criteria = clonedCriteria
            .whereType<Map>()
            .map((item) => RubricCriterionDraft.fromMap(item, _scales))
            .toList();
      } else {
        _criteria = [RubricCriterionDraft(scales: _scales)];
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
        color: const Color(0xFF5D6678),
      );

  /// Outlined input with **no** Material label on the border — use [_labeledControl] for the caption above.
  InputDecoration _outlineInputDec({String? hint}) {
    const borderSide = BorderSide(color: Color(0xFFD1D5DB));
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintStyle: TextStyle(
        fontFamily: DefensysUi.fontFamily,
        color: const Color(0xFF9CA3AF),
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
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
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

  InputDecoration _tableCellDec({required String hint}) {
    const borderSide = BorderSide(color: Color(0xFFD1D5DB));
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintStyle: TextStyle(
        fontFamily: DefensysUi.fontFamily,
        color: const Color(0xFF9CA3AF),
        fontSize: _helperSize,
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
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Color iconColor = AppColors.maroon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
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
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: _sectionTitleSize,
                      fontWeight: FontWeight.w900,
                      color: AppColors.maroon,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _criteriaHeaderBar() {
    final hdr = TextStyle(
      fontFamily: DefensysUi.fontFamily,
      fontSize: _fieldLabelSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.45,
      color: AppColors.textSecondary,
    );
    final isBoth = _targetType == 'both';
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(flex: isBoth ? 20 : 22, child: Text('NAME', style: hdr)),
          Expanded(flex: isBoth ? 28 : 34, child: Text('DESCRIPTION', style: hdr)),
          Expanded(flex: isBoth ? 16 : 18, child: Text('SCALE', style: hdr)),
          if (isBoth)
            Expanded(flex: 16, child: Text('TARGET TYPE', style: hdr)),
          SizedBox(width: 64, child: Text('WEIGHT', style: hdr)),
          SizedBox(width: 56, child: Text('ORDER', style: hdr)),
          const SizedBox(width: 130),
        ],
      ),
    );
  }

  TextStyle get _criterionInputStyle => TextStyle(
        fontFamily: DefensysUi.fontFamily,
        fontSize: _bodySize,
        color: DefensysUi.textDark,
      );

  TextStyle get _dropdownFieldStyle => TextStyle(
        fontFamily: DefensysUi.fontFamily,
        fontSize: _bodySize,
        color: DefensysUi.textDark,
      );

  Widget _criterionRow(
    RubricCriterionDraft draft,
    int index, {
    required bool enabled,
    required VoidCallback? onRemove,
    required VoidCallback onChanged,
  }) {
    final isBoth = _targetType == 'both';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: isBoth ? 20 : 22,
            child: TextField(
              controller: draft.name,
              enabled: enabled,
              onChanged: enabled ? (_) => onChanged() : null,
              style: _criterionInputStyle,
              decoration: _tableCellDec(hint: 'e.g. Technical Competency'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: isBoth ? 28 : 34,
            child: TextField(
              controller: draft.description,
              enabled: enabled,
              onChanged: enabled ? (_) => onChanged() : null,
              minLines: 1,
              maxLines: 3,
              style: _criterionInputStyle,
              decoration: _tableCellDec(hint: 'Optional description'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: isBoth ? 16 : 18,
            child: DropdownButtonFormField<String>(
              key: ValueKey('crit-scale-$index-${draft.scale}'),
              initialValue: draft.scale,
              isExpanded: true,
              style: _criterionInputStyle,
              decoration: _tableCellDec(hint: 'Scale'),
              items: _scales
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, style: _criterionInputStyle),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (value) {
                      draft.scale = value ?? draft.scale;
                      draft.maxScore.text =
                          _defaultMaxForScale(draft.scale).toString();
                      onChanged();
                    }
                  : null,
            ),
          ),
          if (isBoth) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 16,
              child: DropdownButtonFormField<String>(
                key: ValueKey('crit-target-$index-${draft.targetType}'),
                initialValue: draft.targetType,
                isExpanded: true,
                style: _criterionInputStyle,
                decoration: _tableCellDec(hint: 'Target'),
                items: const [
                  DropdownMenuItem(
                    value: 'team',
                    child: Text('Team'),
                  ),
                  DropdownMenuItem(
                    value: 'individual',
                    child: Text('Individual'),
                  ),
                ],
                onChanged: enabled
                    ? (value) {
                        draft.targetType = value ?? draft.targetType;
                        onChanged();
                      }
                    : null,
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: draft.weight,
              enabled: enabled,
              onChanged: enabled ? (_) => onChanged() : null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: _criterionInputStyle,
              decoration: _tableCellDec(hint: '1'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: TextField(
              controller: draft.displayOrder,
              enabled: enabled,
              onChanged: enabled ? (_) => onChanged() : null,
              keyboardType: TextInputType.number,
              style: _criterionInputStyle,
              decoration: _tableCellDec(hint: '0'),
            ),
          ),
          SizedBox(
            width: 130,
            child: onRemove == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.topRight,
                    child: Tooltip(
                      message: 'Remove this criterion',
                      child: IconButton(
                        onPressed: onRemove,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger.withValues(alpha: 0.92),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _rubricLevelScale() {
    if (_criteria.isEmpty) return RubricCriterionDraft.defaultScale(_scales);
    return _criteria.first.scale;
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
    for (final draft in _criteria) {
      if (draft.name.text.trim().isEmpty) {
        return 'Enter a name for each criterion.';
      }
      final maxScore = num.tryParse(draft.maxScore.text.trim());
      if (maxScore == null || maxScore <= 0) {
        return 'Enter a valid max score for each criterion.';
      }
      final weight = num.tryParse(draft.weight.text.trim());
      if (weight == null || weight <= 0) {
        return 'Enter a valid weight for each criterion.';
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
      confirmLabel = 'Publish & Lock';
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
            backgroundColor: Colors.white,
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
                color: Color(0xFF111827),
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
                        ? 'Are you sure you want to publish and lock this rubric? Once published, the rubric structure and settings cannot be edited (deletion is only allowed if not tied to any Capstone schedules or PIT events).'
                        : 'Are you sure you want to save this rubric draft?',
                    style: const TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontSize: 13.5,
                      color: Color(0xFF374151),
                      height: 1.4,
                    ),
                  ),
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
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysUi.primaryMaroon,
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
      'defense_stage_id': null,
      'event_name': '',
      'evaluation_type': _evaluationType,
      'target_type': _targetType,
      'scale': _rubricLevelScale(),
      'status': status,
      'criteria': _criteria.map((d) => d.toPayload()).toList(),
    };

    final notifier = ref.read(rubricEngineProvider.notifier);
    final ok = _editing
        ? await notifier.updateRubric(_asInt(widget.rubric!['id'])!, payload)
        : await notifier.addRubric(payload);

    if (!mounted) return ok;
    if (ok) {
      await notifier.fetchRubrics();
      if (!mounted) return ok;
      showSuccessToast(
        context,
        status == 'published'
            ? 'Rubric published and locked.'
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

  Widget _lockedBanner() {
    final lockReason = widget.rubric?['lock_reason']?.toString();
    final canDelete = widget.rubric?['can_delete'] != false;
    final isAssigned = widget.rubric?['is_assigned'] == true;
    final assignedContext = widget.rubric?['assigned_context_name']?.toString();
    final isStageCompleted = widget.rubric?['is_stage_completed'] == true;
    final scope = widget.rubric?['scope']?.toString() ?? _scope;

    String bannerText =
        'This rubric is published and locked. Criteria and settings cannot be changed.';
    if (!canDelete && lockReason != null && lockReason.isNotEmpty) {
      bannerText = lockReason;
    } else if (isStageCompleted &&
        assignedContext != null &&
        assignedContext.isNotEmpty) {
      bannerText =
          'This rubric is assigned to Defense Stage "$assignedContext" (Completed). Criteria and deletion are locked.';
    } else if (isAssigned &&
        assignedContext != null &&
        assignedContext.isNotEmpty) {
      if (scope == 'pit') {
        bannerText =
            'This rubric is currently assigned to PIT Event "$assignedContext". Criteria and settings are locked.';
      } else {
        bannerText =
            'This rubric is currently assigned to Defense Stage "$assignedContext". Criteria and settings are locked.';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysUi.warningBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 18,
            color: DefensysUi.warningText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                color: DefensysUi.warningText,
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

    final activeSem = state.activeSemester;
    final activeYear = activeSem?['school_year']?.toString();

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
      child: ColoredBox(
      color: const Color(0xFFF3F4F6),
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
                  ? 'Published rubrics are read-only. Criteria and settings cannot be changed.'
                  : (_editing
                      ? 'Update rubric details, criteria, and evaluation settings.'
                      : _createSubtitle()),
              actions: OutlinedButton.icon(
                onPressed: saving ? null : _handleBack,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: DefensysUi.primaryMaroon,
                ),
                label: Text(
                  'Back to Rubric Engine',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: DefensysUi.primaryMaroon,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DefensysUi.primaryMaroon,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  backgroundColor: Colors.white,
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
            if (widget.readOnly ||
                widget.rubric?['is_assigned'] == true ||
                widget.rubric?['can_delete'] == false) ...[
              const SizedBox(height: 18),
              _lockedBanner(),
            ],
            const SizedBox(height: 26),
                _sectionCard(
                  icon: Icons.description_outlined,
                  iconColor: DefensysUi.primaryMaroon,
                  title: 'Rubric Details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCloneDropdown(state),
                      _labeledControl(
                        'RUBRIC NAME',
                        TextField(
                          controller: _name,
                          enabled: canEdit,
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: _bodySize,
                            color: DefensysUi.textDark,
                          ),
                          decoration: _outlineInputDec(
                            hint: _scope == 'pit'
                                ? 'e.g. $pitYear PIT — Panel'
                                : 'e.g. Concept Proposal — Panel',
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (isPitLeadOnly || (isCapstoneOnlyManager && _scope == 'pit'))
                        Text(
                          'Scope: PIT',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: _helperSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else if (isCapstoneOnlyManager)
                        Text(
                          'Scope: Capstone',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            fontSize: _helperSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else
                        _labeledControl(
                          'SCOPE',
                          DropdownButtonFormField<String>(
                            key: ValueKey('scope-$_scope'),
                            initialValue: _scope,
                            isExpanded: true,
                            style: _dropdownFieldStyle,
                            decoration: _outlineInputDec(),
                            items: _scopeDropdownItems(state),
                            onChanged: canEdit
                                ? (v) {
                                    if (v != null) _onScopeChanged(v);
                                  }
                                : null,
                          ),
                        ),
                      const SizedBox(height: 14),
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
                                            color: DefensysUi.textDark,
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
                      _labeledControl(
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
                                  color: DefensysUi.textDark,
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
                                  color: DefensysUi.textDark,
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
                                  color: DefensysUi.textDark,
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _sectionCard(
                  icon: Icons.view_list_rounded,
                  title: 'Criteria (at least 1 required)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _criteriaHeaderBar(),
                      const SizedBox(height: 8),
                      ..._criteria.asMap().entries.map((e) {
                        final i = e.key;
                        final d = e.value;
                        return _criterionRow(
                          d,
                          i,
                          enabled: canEdit,
                          onRemove: !canEdit || _criteria.length == 1
                              ? null
                              : () {
                                  setState(() {
                                    d.dispose();
                                    _criteria.removeAt(i);
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
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _criteria.add(
                                  RubricCriterionDraft(scales: _scales),
                                );
                              });
                              _attachCriteriaListeners();
                              _markDirty();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DefensysUi.primaryMaroon,
                              side: const BorderSide(
                                color: DefensysUi.primaryMaroon,
                                width: 1.5,
                              ),
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              '+ Add Criterion',
                              style: TextStyle(
                                fontFamily: DefensysUi.fontFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
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
                          foregroundColor: DefensysUi.primaryMaroon,
                          side: BorderSide(
                            color:
                                DefensysUi.primaryMaroon.withValues(alpha: 0.85),
                            width: 1.5,
                          ),
                          backgroundColor: Colors.white,
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
                        icon: Icon(
                          Icons.lock_outline,
                          color: DefensysUi.accentGold,
                          size: 17,
                        ),
                        label: Text(
                          'Publish and Lock Rubric',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DefensysUi.primaryMaroon,
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
    );
  }
}

class RubricCriterionDraft {
  RubricCriterionDraft({
    required List<String> scales,
    String name = 'Technical Competency',
    String description = '',
    String? scale,
    int? maxScore,
    num weight = 1,
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
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 11,
                          child: _buildLeftPane(filtered, semesters),
                        ),
                        const VerticalDivider(width: 1, color: Color(0xFFE5E7EB)),
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
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
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
      color: const Color(0xFFF9FAFB),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Rubric to Clone',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DefensysUi.primaryMaroon,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Browse and preview templates before applying criteria.',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontSize: 12,
                  color: Color(0xFF4B5563),
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
            style: const TextStyle(fontSize: 13, fontFamily: DefensysUi.fontFamily),
            decoration: InputDecoration(
              hintText: 'Search by name or semester...',
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
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
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedSemester,
                    hint: const Text('All Semesters', style: TextStyle(fontSize: 11, fontFamily: DefensysUi.fontFamily)),
                    isDense: true,
                    style: const TextStyle(fontSize: 11, color: Colors.black, fontFamily: DefensysUi.fontFamily),
                    onChanged: (val) => setState(() {
                      _selectedSemester = val;
                    }),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Semesters'),
                      ),
                      ...semesters.map((s) => DropdownMenuItem<String?>(
                        value: s,
                        child: Text(s),
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
                      style: TextStyle(color: Colors.grey[500], fontSize: 13, fontFamily: DefensysUi.fontFamily),
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
                              color: isSelected ? DefensysUi.primaryMaroon.withValues(alpha: 0.05) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? DefensysUi.primaryMaroon : const Color(0xFFE5E7EB),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: Color(0xFF111827),
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
          color: active ? DefensysUi.primaryMaroon.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? DefensysUi.primaryMaroon : const Color(0xFFD1D5DB),
            width: active ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? DefensysUi.primaryMaroon : const Color(0xFF4B5563),
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
            Icon(Icons.assignment_outlined, size: 54, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Select a rubric template',
              style: TextStyle(
                color: Colors.grey[500],
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
                color: Colors.grey[400],
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
      color: const Color(0xFFFAFAFA),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                        fontFamily: DefensysUi.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total Weight: ${totalWeight.toStringAsFixed(0)}% · ${criteria.length} Criteria',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
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
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                                fontFamily: DefensysUi.fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFFEDD5)),
                            ),
                            child: Text(
                              'Weight: $weight%',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC2410C),
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
                            color: Colors.grey[600],
                            height: 1.3,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.assessment_outlined, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Scale: $scale (Max: $maxScore)',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey[500],
                              fontFamily: DefensysUi.fontFamily,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              targetType,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4B5563),
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
              backgroundColor: DefensysUi.primaryMaroon,
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
