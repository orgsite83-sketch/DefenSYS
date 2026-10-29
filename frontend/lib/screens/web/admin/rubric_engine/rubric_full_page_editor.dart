import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
import 'rubric_details_fields.dart';
import 'rubric_criterion_fields.dart';
import 'rubric_publish_review.dart';

const _kDefaultScales = [
  '5-Point Scale',
  '10-Point Scale',
  '100-Point Scale',
  'Custom Scale',
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
  ConsumerState<RubricFullPageEditor> createState() =>
      _RubricFullPageEditorState();
}

class _RubricFullPageEditorState extends ConsumerState<RubricFullPageEditor> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor =>
      _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _borderColor =>
      _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
  Color get _textPrimaryColor =>
      _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A);
  Color get _textSecondaryColor =>
      _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);

  late final TextEditingController _name;
  late final TextEditingController _customMaxScore;
  late String _scope;
  late String _evaluationType;
  late String _targetType;
  late String _rubricScale;
  late int? _semesterId;
  int? _defenseStageId;
  int? _pitEventId;
  String? _eventName;
  late List<RubricCriterionDraft> _criteria;
  late List<String> _scales;
  bool _isDirty = false;
  bool _isCustomName = false;
  bool _isInitializing = true;
  bool _loadingCopySources = false;
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
      _pitEventId = null;
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
      return 'Create a panel or peer rubric and optionally assign it to a configured PIT event.';
    }
    return 'Create a standard rubric for panel/event criteria and grade weights.';
  }

  void _initFromRubric(Map<String, dynamic>? r) {
    final state = ref.read(rubricEngineProvider);
    _scales = {..._kDefaultScales, ...state.scaleOptions}.toList();
    _name.removeListener(_markDirty);
    _name.text = r?['name']?.toString() ?? '';
    _isCustomName = r != null && _name.text.trim().isNotEmpty;
    _scope = _resolveInitialScope(r);
    _evaluationType =
        r?['evaluation_type']?.toString() ??
        widget.initialEvaluationType ??
        'panel';
    _targetType = r?['target_type']?.toString() ?? 'team';
    if (_evaluationType == 'peer') {
      _targetType = 'individual';
    }
    _semesterId =
        _asInt(r?['semester_id']) ?? _asInt(state.activeSemester?['id']);
    _defenseStageId = _asInt(r?['defense_stage_id']);
    _pitEventId = _asInt(r?['pit_event_id']);
    _eventName = r?['event_name']?.toString();
    try {
      _disposeCriteriaList(_criteria);
    } catch (_) {}
    _criteria = _buildCriterionDrafts(r, _scales);
    _rubricScale =
        r?['scale']?.toString() ??
        (_criteria.isNotEmpty
            ? _criteria.first.scale
            : RubricCriterionDraft.defaultScale(_scales));
    _customMaxScore.text = (_asInt(r?['custom_max_score']) ?? 20).toString();
    if (r != null) {
      final pitYear =
          ref
              .read(dashboardProvider('faculty'))
              .data?['pit_lead_year']
              ?.toString() ??
          ref.read(authProvider).user?['pit_lead_year']?.toString() ??
          '2nd Year';
      _isCustomName =
          _name.text !=
          _computeDefaultRubricName(
            scope: _scope,
            defenseStageId: _defenseStageId,
            evaluationType: _evaluationType,
            defenseStages: state.defenseStages,
            pitYear: pitYear,
          );
    }
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
    _customMaxScore = TextEditingController();
    _initFromRubric(widget.rubric);
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(rubricEngineProvider);
      if (s.rubrics.isEmpty) {
        ref.read(rubricEngineProvider.notifier).fetchRubrics();
      }
      if (mounted) {
        ref
            .read(unsavedChangesSaveDraftProvider.notifier)
            .setCallback(() => _save('draft', showConfirmation: false));
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
    _customMaxScore.dispose();
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
      _customMaxScore.text = (_asInt(sourceRubric['custom_max_score']) ?? 20)
          .toString();
      _defenseStageId = null;
      _pitEventId = null;

      _disposeCriteriaList(_criteria);
      final clonedCriteria = sourceRubric['criteria'];
      if (clonedCriteria is List) {
        _criteria = clonedCriteria
            .whereType<Map>()
            .map((item) => RubricCriterionDraft.fromMap(item, _scales))
            .toList();
      } else {
        _criteria = [
          RubricCriterionDraft(scales: _scales, scale: _rubricScale),
        ];
      }
      _attachCriteriaListeners();
    });
    _markDirty();
    showSuccessToast(context, 'Rubric criteria and details cloned.');
  }

  Future<void> _showCloneRubricDialog(BuildContext context) async {
    setState(() => _loadingCopySources = true);
    try {
      final availableRubrics = await ref
          .read(rubricEngineProvider.notifier)
          .checkExistingRubrics(scope: _scope);
      if (!mounted || !context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return DefensysShadcnScope(
            child: _CloneRubricDialog(
              availableRubrics: availableRubrics,
              onClone: (sourceRubric) {
                _cloneFromRubric(sourceRubric);
                Navigator.pop(dialogContext);
              },
            ),
          );
        },
      );
    } catch (_) {
      if (mounted && context.mounted) {
        showErrorToast(context, 'Unable to load rubrics. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingCopySources = false);
    }
  }

  Widget _buildCloneDropdown(RubricEngineState state) {
    if (_editing || widget.readOnly) return const SizedBox.shrink();

    return ShadButton.outline(
      size: ShadButtonSize.sm,
      enabled: !state.isSaving && !_loadingCopySources,
      onPressed: state.isSaving || _loadingCopySources
          ? null
          : () => _showCloneRubricDialog(context),
      leading: const Icon(LucideIcons.copy, size: 15),
      child: const Text('Copy from rubric'),
    );
  }

  Widget _assignmentSelect({
    required String label,
    required String fieldKey,
    required int? value,
    required Map<int, String> names,
    required bool enabled,
    required ValueChanged<int?> onChanged,
    Set<int> disabled = const {},
    String? note,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: DefensysTokens.tableCell.copyWith(
          fontWeight: FontWeight.w600,
          color: _textPrimaryColor,
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) => ShadSelect<int>(
          key: ValueKey(fieldKey),
          initialValue: value ?? 0,
          enabled: enabled,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          maxHeight: 280,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          selectedOptionBuilder: (_, id) => Text(
            names[id] ?? 'Selected assignment (unavailable)',
            overflow: TextOverflow.ellipsis,
            style: DefensysTokens.tableCell.copyWith(color: _textPrimaryColor),
          ),
          options: names.entries.map((entry) {
            final text = Text(
              entry.value,
              overflow: TextOverflow.ellipsis,
              style: DefensysTokens.tableCell.copyWith(
                color: disabled.contains(entry.key)
                    ? _textSecondaryColor
                    : _textPrimaryColor,
              ),
            );
            if (disabled.contains(entry.key) && entry.key != value) {
              return Semantics(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 10,
                  ),
                  child: text,
                ),
              );
            }
            return ShadOption<int>(value: entry.key, child: text);
          }),
          onChanged: (id) => onChanged(id == 0 ? null : id),
        ),
      ),
      if (note != null) ...[
        const SizedBox(height: 8),
        Text(
          note,
          style: DefensysTokens.caption.copyWith(color: _textSecondaryColor),
        ),
      ],
    ],
  );

  Widget _pitEventControl(RubricEngineState state, {required bool canEdit}) {
    final events = state.pitEvents
        .where((event) => _asInt(event['semester_id']) == _semesterId)
        .toList();
    if (_pitEventId != null &&
        !events.any((event) => _asInt(event['id']) == _pitEventId)) {
      events.add({
        'id': _pitEventId,
        'event_name': _eventName ?? 'Assigned PIT event',
      });
    }
    final selected = events
        .where((event) => _asInt(event['id']) == _pitEventId)
        .firstOrNull;
    final current = _asInt(selected?['${_evaluationType}_rubric_id']);
    final replacing =
        current != null && current != _asInt(widget.rubric?['id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _assignmentSelect(
          label: 'PIT event (optional)',
          fieldKey: 'pit-event-$_semesterId-$_pitEventId',
          value: _pitEventId,
          names: {
            0: 'Unassigned template',
            for (final event in events)
              if (_asInt(event['id']) case final int id)
                id: '${event['event_name']}${event['is_locked'] == true ? ' (Locked)' : ''}',
          },
          disabled: {
            for (final event in events)
              if (event['is_locked'] == true && _asInt(event['id']) != null)
                _asInt(event['id'])!,
          },
          enabled: canEdit,
          onChanged: (value) {
            setState(() => _pitEventId = value);
            _markDirty();
          },
          note: events.isEmpty
              ? 'No configured PIT events for this semester. Create one in PIT Events Setup, or save this rubric as a template.'
              : 'Choose an event or keep this rubric as an unassigned template.',
        ),
        if (replacing) ...[
          const SizedBox(height: 8),
          Text(
            "Saving will replace the selected event's current ${_evaluationType == 'peer' ? 'peer' : 'panel'} rubric.",
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.maroonTextOf(context),
            ),
          ),
        ],
      ],
    );
  }

  String _semesterLabel(RubricEngineState state) {
    final semester =
        state.semesters
            .where((item) => _asInt(item['id']) == _semesterId)
            .firstOrNull ??
        (_asInt(state.activeSemester?['id']) == _semesterId
            ? state.activeSemester
            : null);
    final display =
        semester?['display_name']?.toString() ??
        widget.rubric?['display_semester']?.toString();
    final term =
        semester?['semester']?.toString() ??
        semester?['label']?.toString() ??
        'Semester';
    final year =
        semester?['school_year']?.toString() ??
        widget.rubric?['school_year']?.toString();
    return _semesterId == null
        ? 'No active semester'
        : (display != null && display.isNotEmpty
              ? display
              : '$term${year == null ? '' : ', A.Y. $year'}');
  }

  Widget _detailsFields(RubricEngineState state, String pitYear, bool canEdit) {
    void syncName() => _syncDefaultRubricNameIfAuto(
      defenseStages: state.defenseStages,
      pitYear: pitYear,
    );
    final assignment = _scope == 'pit'
        ? _pitEventControl(state, canEdit: canEdit)
        : _assignmentSelect(
            label: 'Defense stage (optional)',
            fieldKey: 'stage-$_defenseStageId',
            value: _defenseStageId,
            names: {
              0: 'Unassigned template',
              for (final stage in state.defenseStages)
                if (_asInt(stage['id']) case final int id)
                  id: stage['label']?.toString() ?? 'Stage $id',
              if (_defenseStageId != null &&
                  !state.defenseStages.any(
                    (stage) => _asInt(stage['id']) == _defenseStageId,
                  ))
                _defenseStageId!:
                    widget.rubric?['defense_stage_label']?.toString() ??
                    'Assigned stage (unavailable)',
            },
            enabled: canEdit,
            onChanged: (value) {
              setState(() {
                _defenseStageId = value;
                syncName();
              });
              _markDirty();
            },
            note: _defenseStageId == null
                ? 'Choose a stage or keep this rubric as an unassigned template.'
                : 'Saving will automatically assign this rubric to the selected defense stage.',
          );
    return RubricDetailsFields(
      semesterLabel: _semesterLabel(state),
      semesterActive:
          _semesterId != null &&
          _semesterId == _asInt(state.activeSemester?['id']),
      hasSemester: _semesterId != null,
      nameController: _name,
      customName: _isCustomName,
      enabled: canEdit,
      onNameChanged: (_) {
        setState(() => _isCustomName = true);
        _markDirty();
      },
      onResetName: () {
        setState(() {
          _isCustomName = false;
          syncName();
        });
        _markDirty();
      },
      isPit: _scope == 'pit',
      evaluationType: _evaluationType,
      onEvaluationChanged: (value) {
        setState(() {
          _evaluationType = value;
          if (value == 'peer') {
            _targetType = 'individual';
            for (final criterion in _criteria) {
              criterion.targetType = 'individual';
            }
          }
          syncName();
        });
        _markDirty();
      },
      scale: _rubricScale,
      scales: _scales,
      customPoints: _customMaxScore,
      onScaleChanged: _onRubricScaleChanged,
      onCustomPointsChanged: _onCustomMaxScoreChanged,
      target: _targetType,
      onTargetChanged: (value) {
        setState(() {
          _targetType = value;
          if (value != 'both') {
            for (final criterion in _criteria) {
              criterion.targetType = value;
            }
          }
        });
        _markDirty();
      },
      assignment: assignment,
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) => LayoutBuilder(
    builder: (context, constraints) => ShadCard(
      padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
      backgroundColor: _surfaceColor,
      radius: BorderRadius.circular(12),
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: _textSecondaryColor),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: DefensysTokens.sectionTitle.copyWith(
                      color: _textPrimaryColor,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    ),
  );

  Widget _buildScopeHeaderWidget({
    required bool canSwitchScope,
    required RubricEngineState state,
    required String pitYear,
  }) {
    if (!canSwitchScope) {
      return ShadBadge.secondary(
        child: Text(_scope == 'pit' ? 'PIT Program' : 'Capstone Program'),
      );
    }
    return ShadRadioGroup<String>(
      initialValue: _scope,
      axis: Axis.horizontal,
      spacing: 16,
      onChanged: (value) {
        if (value != null && value != _scope) {
          _onScopeChanged(
            value,
            defenseStages: state.defenseStages,
            pitYear: pitYear,
          );
        }
      },
      items: const [
        ShadRadio(value: 'capstone', label: Text('Capstone')),
        ShadRadio(value: 'pit', label: Text('PIT')),
      ],
    );
  }

  void _onRubricScaleChanged(String newScale) {
    setState(() {
      _rubricScale = newScale;
      final max = _rubricMaxScore;
      for (final c in _criteria) {
        c.scale = newScale;
        c.maxScore.text = max.toString();
      }
    });
    _markDirty();
  }

  int get _rubricMaxScore => _rubricScale == 'Custom Scale'
      ? int.tryParse(_customMaxScore.text.trim()) ?? 20
      : _defaultMaxForScale(_rubricScale);

  void _onCustomMaxScoreChanged(String value) {
    final maximum = int.tryParse(value.trim());
    setState(() {
      if (maximum != null && maximum >= 1 && maximum <= 32767) {
        for (final criterion in _criteria) {
          criterion.maxScore.text = maximum.toString();
        }
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

  Widget _buildWeightAssistantBar({required bool enabled}) {
    final total = _totalCriteriaWeight;
    final count = _criteria.length;
    final over = total > 100.000001;
    final under = total < 99.999999;
    String percentage(num value) =>
        value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    final color = over
        ? DefensysTokens.maroonTextOf(context)
        : under
        ? (_isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E))
        : (_isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857));
    final status = over
        ? 'Exceeds 100% by ${percentage(total - 100)}%'
        : under
        ? '${percentage(100 - total)}% Unallocated'
        : '100% Balanced';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${percentage(total)}% of 100%',
                    style: DefensysTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _textPrimaryColor,
                    ),
                  ),
                  ShadBadge.outline(
                    child: Text(
                      status,
                      style: DefensysTokens.caption.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              if (!widget.readOnly && count > 0)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: enabled,
                  onPressed: enabled ? _distributeWeightsEvenly : null,
                  leading: const Icon(LucideIcons.equal, size: 15),
                  child: const Text('Distribute evenly'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ShadProgress(
            value: (total / 100).clamp(0.0, 1.0),
            minHeight: 4,
            color: color,
            backgroundColor: _borderColor,
            semanticsLabel: 'Criterion weight allocation',
            semanticsValue: '${percentage(total)} percent',
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
  }) => RubricCriterionFields(
    key: ObjectKey(draft),
    index: index,
    name: draft.name,
    weight: draft.weight,
    description: draft.description,
    maximum: _rubricMaxScore,
    enabled: enabled,
    showTarget: _targetType == 'both',
    target: draft.targetType,
    onTargetChanged: (value) {
      setState(() => draft.targetType = value);
      _markDirty();
    },
    onChanged: onChanged,
    onMoveUp: index > 0 ? () => _moveCriterionUp(index) : null,
    onMoveDown: index < _criteria.length - 1
        ? () => _moveCriterionDown(index)
        : null,
    onRemove: onRemove,
  );

  String? _validationMessage() {
    if (_name.text.trim().isEmpty) {
      return 'Enter a rubric name.';
    }
    if (_semesterId == null) {
      return 'Configure an active semester in Academic Periods before creating a rubric.';
    }
    if (_rubricScale == 'Custom Scale') {
      final maximum = int.tryParse(_customMaxScore.text.trim());
      if (maximum == null || maximum < 1 || maximum > 32767) {
        return 'Enter a whole number from 1 to 32767 for the custom scale.';
      }
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
      if (weight == null || !weight.isFinite || weight <= 0 || weight > 100) {
        return 'Enter a weight greater than 0% and at most 100% for each criterion.';
      }
      if ((weight * 100 - (weight * 100).round()).abs() > 0.000001) {
        return 'Criterion weights can have at most two decimal places.';
      }
    }

    if (_targetType == 'both') {
      final hasTeam = _criteria.any((c) => c.targetType == 'team');
      final hasIndiv = _criteria.any((c) => c.targetType == 'individual');
      if (!hasTeam || !hasIndiv) {
        return "Rubrics set to 'Both (Team & Individual)' must contain at least one Team criterion and at least one Individual criterion. If all criteria are Team-based, please set the Scoring Target to 'Team'.";
      }
    }

    if ((_totalCriteriaWeight - 100).abs() > 0.000001) {
      return 'Criterion weights must total 100%. Current total: ${_totalCriteriaWeight.toStringAsFixed(2)}%.';
    }
    return null;
  }

  Future<bool> _save(String status, {bool showConfirmation = true}) async {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      showValidationToast(context, validationMessage);
      return false;
    }

    if (showConfirmation && !mounted) return false;

    // Keep the reviewed values identical to the eventual save request.
    final payload = {
      'name': _name.text.trim(),
      'scope': _scope,
      'semester_id': _semesterId,
      'defense_stage_id': _scope == 'capstone' ? _defenseStageId : null,
      if (_scope == 'pit') 'pit_event_id': _pitEventId,
      'event_name': _eventName ?? '',
      'evaluation_type': _evaluationType,
      'target_type': _targetType,
      'scale': _rubricScale,
      'custom_max_score': _rubricScale == 'Custom Scale'
          ? _rubricMaxScore
          : null,
      'status': status,
      'criteria': _criteria.map((d) => d.toPayload()).toList(),
    };
    final state = ref.read(rubricEngineProvider);
    final selectedEvent = state.pitEvents
        .where((event) => _asInt(event['id']) == _pitEventId)
        .firstOrNull;
    final selectedStage = state.defenseStages
        .where((stage) => _asInt(stage['id']) == _defenseStageId)
        .firstOrNull;
    final assignmentLabel = _scope == 'pit'
        ? (_pitEventId == null
              ? 'Unassigned template'
              : selectedEvent?['event_name']?.toString() ??
                    _eventName ??
                    'Assigned PIT event (unavailable)')
        : (_defenseStageId == null
              ? 'Unassigned template'
              : selectedStage?['label']?.toString() ??
                    widget.rubric?['defense_stage_label']?.toString() ??
                    'Assigned stage (unavailable)');
    final assignedRubricId = _asInt(
      selectedEvent?['${_evaluationType}_rubric_id'],
    );
    final assignmentSummary = _scope == 'pit' && _pitEventId != null
        ? 'This will assign the rubric to $assignmentLabel for ${_evaluationType == 'peer' ? 'peer' : 'panel'} evaluation.'
              '${assignedRubricId != null && assignedRubricId != _asInt(widget.rubric?['id']) ? ' The current rubric in that slot will be replaced.' : ''}'
        : _scope == 'capstone' && _defenseStageId != null
        ? 'This will assign the rubric to $assignmentLabel for $_evaluationType evaluation.'
        : '';

    if (showConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DefensysShadcnScope(
          child: status == 'published'
              ? RubricPublishReview(
                  payload: payload,
                  semesterLabel: _semesterLabel(state),
                  assignmentLabel: assignmentLabel,
                  assignmentNotice: assignmentSummary.isNotEmpty
                      ? assignmentSummary
                      : 'This rubric will be published as an unassigned template. '
                            'You can assign it to ${_scope == 'pit' ? 'a PIT event' : 'a defense stage'} later.',
                )
              : ShadDialog(
                  constraints: const BoxConstraints(maxWidth: 560),
                  title: const Text('Save Rubric Draft?'),
                  description: const Text(
                    'Save this rubric as a draft to continue editing later.',
                  ),
                  actions: [
                    ShadButton.outline(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    ShadButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      backgroundColor: DefensysTokens.maroonOf(context),
                      foregroundColor: Colors.white,
                      child: const Text('Save Draft'),
                    ),
                  ],
                  child: assignmentSummary.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            assignmentSummary,
                            style: DefensysTokens.body.copyWith(
                              color: _textPrimaryColor,
                            ),
                          ),
                        ),
                ),
        ),
      );

      if (confirmed != true) return false;
    }

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
    final assignedContext =
        widget.rubric?['assigned_context_name']?.toString() ??
        'a defense stage';
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
    } else if (hasSchedule &&
        assignedContext != null &&
        assignedContext.isNotEmpty) {
      bannerText =
          'This rubric is locked because active defense sessions are currently scheduled for "$assignedContext".';
    } else if (isStageCompleted &&
        assignedContext != null &&
        assignedContext.isNotEmpty) {
      bannerText =
          'This rubric is assigned to Defense Stage "$assignedContext" (Completed). Criteria and deletion are locked.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF2E2214) : DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark ? const Color(0xFF78350F) : DefensysUi.warningBorder,
        ),
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
                color: _isDark
                    ? const Color(0xFFFDE68A)
                    : DefensysUi.warningText,
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
    final canSwitchScope =
        canEdit &&
        !_editing &&
        !isPitLeadOnly &&
        !isCapstoneOnlyManager &&
        state.scopes.length > 1;

    final activeSem = state.activeSemester;
    final activeSemId = _asInt(activeSem?['id']);
    if (_semesterId == null && activeSemId != null && widget.rubric == null) {
      _semesterId = activeSemId;
    }

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (widget.rubric?['id'] != null)
          ReportExportMenu(
            reportId: 'rubric-details',
            params: {
              'rubric_id': widget.rubric!['id'].toString(),
              'scope': widget.rubric!['scope'].toString(),
              'term_context': '',
              'search': '',
              'status': '',
              'evaluation_type': '',
            },
          ),
        ShadButton.outline(
          enabled: !saving,
          onPressed: saving ? null : _handleBack,
          leading: const Icon(LucideIcons.arrowLeft, size: 16),
          child: const Text('Back to rubrics'),
        ),
      ],
    );
    final header = DefensysPageHeader(
      title: widget.readOnly
          ? 'View Rubric'
          : (_editing ? 'Edit Rubric' : 'Create Rubric'),
      subtitle: widget.readOnly
          ? 'This rubric is locked. Criteria and settings cannot be changed.'
          : (_editing
                ? 'Update rubric details, criteria, and evaluation settings.'
                : _createSubtitle()),
    );
    return PopScope(
      canPop: widget.readOnly || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || widget.readOnly) return;
        await _handleBack();
      },
      child: DefensysShadcnScope(
        child: ColoredBox(
          color: DefensysTokens.backgroundOf(context),
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: viewport.maxWidth < 600
                  ? const EdgeInsets.fromLTRB(16, 20, 16, 36)
                  : DefensysUi.contentPadding,
              child: SizedBox(
                key: const ValueKey('rubric-editor-content'),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 720) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actions,
                              const SizedBox(height: 20),
                              header,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: header),
                            const SizedBox(width: 24),
                            actions,
                          ],
                        );
                      },
                    ),
                    if (widget.readOnly ||
                        widget.rubric?['is_locked'] == true) ...[
                      const SizedBox(height: 24),
                      _lockedBanner(),
                    ] else if (widget.rubric?['is_soft_locked'] == true ||
                        widget.rubric?['is_assigned'] == true) ...[
                      const SizedBox(height: 24),
                      _softLockedBanner(),
                    ],
                    const SizedBox(height: 28),
                    _sectionCard(
                      icon: LucideIcons.fileText,
                      title: 'Rubric details',
                      trailing: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildScopeHeaderWidget(
                            canSwitchScope: canSwitchScope,
                            state: state,
                            pitYear: pitYear,
                          ),
                          _buildCloneDropdown(state),
                        ],
                      ),
                      child: _detailsFields(state, pitYear, canEdit),
                    ),
                    const SizedBox(height: 24),
                    _sectionCard(
                      icon: LucideIcons.listChecks,
                      title: 'Evaluation Criteria (${_criteria.length})',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildWeightAssistantBar(enabled: canEdit),
                          ..._criteria.asMap().entries.map((entry) {
                            final i = entry.key;
                            final draft = entry.value;
                            return _criterionCard(
                              draft,
                              i,
                              enabled: canEdit,
                              onRemove: !canEdit || _criteria.length == 1
                                  ? null
                                  : () {
                                      setState(() {
                                        draft.dispose();
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
                          if (canEdit)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ShadButton.outline(
                                onPressed: () {
                                  var defaultTarget =
                                      _targetType == 'individual'
                                      ? 'individual'
                                      : 'team';
                                  if (_targetType == 'both' &&
                                      _criteria.any(
                                        (c) => c.targetType == 'team',
                                      ) &&
                                      !_criteria.any(
                                        (c) => c.targetType == 'individual',
                                      )) {
                                    defaultTarget = 'individual';
                                  }
                                  setState(
                                    () => _criteria.add(
                                      RubricCriterionDraft(
                                        scales: _scales,
                                        name: '',
                                        scale: _rubricScale,
                                        maxScore: _rubricMaxScore,
                                        weight: 10,
                                        displayOrder: _criteria.length,
                                        targetType: defaultTarget,
                                      ),
                                    ),
                                  );
                                  _attachCriteriaListeners();
                                  _markDirty();
                                },
                                leading: const Icon(LucideIcons.plus, size: 16),
                                child: const Text('Add Criterion'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Divider(height: 1, color: _borderColor),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 20,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ShadButton.ghost(
                              enabled: !saving,
                              onPressed: saving ? null : _handleBack,
                              child: Text(widget.readOnly ? 'Back' : 'Cancel'),
                            ),
                            if (widget.onDelete != null)
                              _deleteAction(saving: saving),
                          ],
                        ),
                        if (!widget.readOnly)
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              ShadButton.outline(
                                enabled: !saving,
                                onPressed: saving ? null : () => _save('draft'),
                                child: const Text('Save as Draft'),
                              ),
                              ShadButton(
                                enabled: !saving,
                                backgroundColor: DefensysTokens.maroonOf(
                                  context,
                                ),
                                foregroundColor: Colors.white,
                                onPressed: saving
                                    ? null
                                    : () => _save('published'),
                                leading: const Icon(
                                  LucideIcons.check,
                                  size: 16,
                                ),
                                child: Text(
                                  saving ? 'Saving...' : 'Publish Rubric',
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteAction({required bool saving}) {
    final canDelete = widget.rubric?['can_delete'] != false;
    final lockReason = widget.rubric?['lock_reason']?.toString();
    final assignedContext = widget.rubric?['assigned_context_name']?.toString();
    final tooltip = !canDelete && lockReason != null && lockReason.isNotEmpty
        ? lockReason
        : widget.rubric?['is_assigned'] == true && assignedContext != null
        ? (_scope == 'pit'
              ? 'Rubric is assigned to PIT Event "$assignedContext" and cannot be deleted.'
              : 'Rubric is assigned to Defense Stage "$assignedContext". Deleting will remove assignment.')
        : 'Delete rubric';
    return ShadTooltip(
      builder: (_) => Text(tooltip),
      child: ShadButton.ghost(
        enabled: !saving && canDelete,
        onPressed: saving || !canDelete ? null : widget.onDelete,
        foregroundColor: AppColors.danger,
        child: Text(canDelete ? 'Delete rubric' : 'Delete rubric (Locked)'),
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
      displayOrder: int.tryParse(item['display_order']?.toString() ?? '') ?? 0,
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
  String _evaluationLabel(String? value) => switch (value) {
    'peer' => 'Peer',
    'adviser' => 'Adviser',
    _ => 'Panel',
  };
  String _searchQuery = '';
  String _selectedScope = 'all';
  String _selectedSemester = 'all';
  Map<String, dynamic>? _selectedRubric;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= 800;
    final semesters = widget.availableRubrics
        .map((r) => r['display_semester']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final filtered = widget.availableRubrics.where((r) {
      final query = _searchQuery.trim().toLowerCase();
      final name = r['name']?.toString().toLowerCase() ?? '';
      final semester = r['display_semester']?.toString() ?? '';
      return (query.isEmpty ||
              name.contains(query) ||
              semester.toLowerCase().contains(query)) &&
          (_selectedScope == 'all' || r['scope'] == _selectedScope) &&
          (_selectedSemester == 'all' || semester == _selectedSemester);
    }).toList();
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          placeholder: const Text('Search by name or semester...'),
          leading: const Icon(LucideIcons.search, size: 16),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ShadSelect<String>(
              initialValue: _selectedScope,
              selectedOptionBuilder: (_, value) => Text(
                {
                  'all': 'All programs',
                  'capstone': 'Capstone',
                  'pit': 'PIT',
                }[value]!,
              ),
              options: const [
                ShadOption(value: 'all', child: Text('All programs')),
                ShadOption(value: 'capstone', child: Text('Capstone')),
                ShadOption(value: 'pit', child: Text('PIT')),
              ],
              onChanged: (value) =>
                  setState(() => _selectedScope = value ?? 'all'),
            ),
            ShadSelect<String>(
              key: const ValueKey('copy-rubric-semester'),
              initialValue: _selectedSemester,
              maxWidth: desktop ? 220 : size.width - 96,
              selectedOptionBuilder: (_, value) => Text(
                value == 'all' ? 'All semesters' : value,
                overflow: TextOverflow.ellipsis,
              ),
              options: [
                const ShadOption(value: 'all', child: Text('All semesters')),
                for (final semester in semesters)
                  ShadOption(value: semester, child: Text(semester)),
              ],
              onChanged: (value) =>
                  setState(() => _selectedSemester = value ?? 'all'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching rubrics found'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final rubric = filtered[index];
                    final selected = _selectedRubric?['id'] == rubric['id'];
                    final semester =
                        rubric['display_semester']?.toString() ?? '';
                    return ShadButton.outline(
                      height: 84,
                      expands: true,
                      backgroundColor: selected
                          ? DefensysTokens.surfaceHigherOf(context)
                          : null,
                      onPressed: () => setState(() => _selectedRubric = rubric),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            rubric['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DefensysTokens.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${rubric['scope'] == 'pit' ? 'PIT' : 'Capstone'} / ${_evaluationLabel(rubric['evaluation_type']?.toString())}'
                            '${semester.isEmpty ? '' : ' / $semester'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DefensysTokens.caption.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    return ShadDialog(
      constraints: const BoxConstraints(maxWidth: 960),
      title: const Text('Copy from an existing rubric'),
      description: const Text(
        'Preview the criteria and settings before copying.',
      ),
      actions: [
        ShadButton(
          enabled: _selectedRubric != null,
          onPressed: _selectedRubric == null
              ? null
              : () => widget.onClone(_selectedRubric!),
          child: const Text('Copy rubric'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: SizedBox(
          width: 880,
          height: (size.height - 280).clamp(200.0, 520.0),
          child: desktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 24),
                    Expanded(child: _preview(context)),
                  ],
                )
              : _selectedRubric == null
              ? list
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ShadButton.ghost(
                        onPressed: () => setState(() => _selectedRubric = null),
                        leading: const Icon(LucideIcons.arrowLeft, size: 16),
                        child: const Text('Choose another rubric'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _preview(context)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final rubric = _selectedRubric;
    if (rubric == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Select a rubric to preview its criteria.',
            textAlign: TextAlign.center,
            style: DefensysTokens.body.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      );
    }
    final criteria = (rubric['criteria'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final total = criteria.fold<num>(
      0,
      (total, c) => total + (num.tryParse(c['weight']?.toString() ?? '') ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rubric['name']?.toString() ?? '',
          style: DefensysTokens.sectionTitle.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${criteria.length} criteria / $total% total weight',
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: criteria.length,
            separatorBuilder: (_, index) => const Divider(height: 32),
            itemBuilder: (_, index) {
              final criterion = criteria[index];
              final description = criterion['description']?.toString() ?? '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    criterion['name']?.toString() ?? '',
                    style: DefensysTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${criterion['weight']}% weight / ${criterion['max_score'] ?? 10} points maximum / ${criterion['target_type'] ?? 'team'}',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: DefensysTokens.body.copyWith(
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
