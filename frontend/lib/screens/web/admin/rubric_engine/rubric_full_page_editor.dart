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
import '../../../../utils/rubric_weight_allocation.dart';
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
  'Points-Based (Sections)',
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
    'Points-Based (Sections)' => 10,
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
  final List<SectionEditorDraft> _sections = [];
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
      if (_pitEventId != null) {
        final event = ref
            .read(rubricEngineProvider)
            .pitEvents
            .where((event) => _asInt(event['id']) == _pitEventId)
            .firstOrNull;
        final eventLabel = (event?['event_name']?.toString() ?? _eventName)
            ?.trim();
        if (eventLabel != null && eventLabel.isNotEmpty) {
          return '$eventLabel — $typeLabel Rubric';
        }
      }
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
      draft.section.removeListener(_markDirty);
      draft.name.removeListener(_markDirty);
      draft.description.removeListener(_markDirty);
      draft.maxScore.removeListener(_markDirty);
      draft.weight.removeListener(_markDirty);
      draft.displayOrder.removeListener(_markDirty);
      draft.section.addListener(_markDirty);
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
      for (final s in _sections) {
        s.dispose();
      }
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
    if (_rubricScale == 'Points-Based (Sections)') {
      _syncSectionsFromCriteria();
    }
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
      draft.section.removeListener(_markDirty);
      draft.name.removeListener(_markDirty);
      draft.description.removeListener(_markDirty);
      draft.maxScore.removeListener(_markDirty);
      draft.weight.removeListener(_markDirty);
      draft.displayOrder.removeListener(_markDirty);
    }
    for (final s in _sections) {
      s.dispose();
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

      for (final s in _sections) {
        s.dispose();
      }
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
      if (_rubricScale == 'Points-Based (Sections)') {
        _syncSectionsFromCriteria();
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

  Widget _pitEventControl(
    RubricEngineState state, {
    required bool canEdit,
    required VoidCallback syncName,
  }) {
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
            setState(() {
              _pitEventId = value;
              _eventName = events
                  .where((event) => _asInt(event['id']) == value)
                  .firstOrNull?['event_name']
                  ?.toString();
              syncName();
            });
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
        ? _pitEventControl(state, canEdit: canEdit, syncName: syncName)
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
            for (final section in _sections) {
              section.targetType = 'individual';
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
            for (final section in _sections) {
              section.targetType = value;
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
      if (newScale == 'Points-Based (Sections)') {
        _syncSectionsFromCriteria();
      } else {
        if (_sections.isNotEmpty) {
          _recomputeCriteriaWeightsFromSections();
          for (final section in _sections) {
            section.dispose();
          }
          _sections.clear();
        }
        final max = _rubricMaxScore;
        for (final c in _criteria) {
          c.scale = newScale;
          c.maxScore.text = max.toString();
        }
      }
    });
    _markDirty();
  }

  int get _rubricMaxScore => _rubricScale == 'Custom Scale'
      ? int.tryParse(_customMaxScore.text.trim()) ?? 20
      : _defaultMaxForScale(_rubricScale);

  void _onCustomMaxScoreChanged(String value) {
    if (_rubricScale == 'Points-Based (Sections)') return;
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

  num get _totalSectionWeight {
    num total = 0;
    for (final s in _sections) {
      total += num.tryParse(s.weight.text.trim()) ?? 0;
    }
    return total;
  }

  bool get _hasSections =>
      _criteria.any((c) => c.section.text.trim().isNotEmpty);

  Future<void> _distributeWeightsBySections() async {
    if (_criteria.isEmpty) return;
    final sectionNames = <String>[];
    for (final c in _criteria) {
      final s = c.section.text.trim();
      final key = s.isEmpty ? 'General' : s;
      if (!sectionNames.contains(key)) sectionNames.add(key);
    }
    if (sectionNames.isEmpty) return;

    final sectionPoints = <String, int>{};
    for (final s in sectionNames) {
      int pts = 0;
      for (final c in _criteria) {
        final key = c.section.text.trim().isEmpty
            ? 'General'
            : c.section.text.trim();
        if (key == s) {
          pts += int.tryParse(c.maxScore.text.trim()) ?? 10;
        }
      }
      sectionPoints[s] = pts > 0 ? pts : 10;
    }

    final sectionWeightControllers = <String, TextEditingController>{};
    final shares = allocateRubricWeight(
      10000,
      List<int>.filled(sectionNames.length, 1),
    );
    for (int i = 0; i < sectionNames.length; i++) {
      final s = sectionNames[i];
      sectionWeightControllers[s] = TextEditingController(
        text: formatRubricWeight(shares[i]),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => DefensysShadcnScope(
        child: StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            num totalWeight = 0;
            for (final ctrl in sectionWeightControllers.values) {
              totalWeight += num.tryParse(ctrl.text.trim()) ?? 0;
            }
            final isValid =
                (totalWeight - 100).abs() < 0.000001 &&
                sectionWeightControllers.values.every((controller) {
                  final value = num.tryParse(controller.text.trim());
                  return value != null &&
                      value.isFinite &&
                      value > 0 &&
                      value <= 100 &&
                      (value * 100 - (value * 100).round()).abs() < 0.000001;
                });

            return ShadDialog(
              title: const Text('Calculate Section Weights'),
              description: const Text(
                'Enter the target weight percentage for each section. DefenSYS will proportionally allocate criterion weights so they total 100%.',
              ),
              actions: [
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ShadButton(
                  size: ShadButtonSize.sm,
                  enabled: isValid,
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _applySectionWeights(sectionWeightControllers);
                  },
                  child: const Text('Apply Weights'),
                ),
              ],
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in sectionNames) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s,
                                    style: DefensysTokens.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${sectionPoints[s]} total points',
                                    style: DefensysTokens.caption,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 90,
                              child: ShadInput(
                                controller: sectionWeightControllers[s],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                trailing: const Text('%'),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Weight:',
                          style: DefensysTokens.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ShadBadge.outline(
                          child: Text(
                            '$totalWeight% / 100%',
                            style: TextStyle(
                              color: isValid
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    for (final ctrl in sectionWeightControllers.values) {
      ctrl.dispose();
    }
  }

  void _applySectionWeights(Map<String, TextEditingController> weightCtrls) {
    setState(() {
      for (final entry in weightCtrls.entries) {
        final criteria = _criteria.where((criterion) {
          final section = criterion.section.text.trim();
          return (section.isEmpty ? 'General' : section) == entry.key;
        }).toList();
        final total = ((num.tryParse(entry.value.text.trim()) ?? 0) * 100)
            .round();
        final shares = allocateRubricWeight(total, [
          for (final criterion in criteria) _allocationPoints(criterion),
        ]);
        for (var i = 0; i < criteria.length; i++) {
          criteria[i].weight.text = formatRubricWeight(shares[i]);
        }
      }
    });
    _markDirty();
    showSuccessToast(
      context,
      'Weights calculated for ${weightCtrls.length} sections.',
    );
  }

  void _distributeWeightsEvenly() {
    if (_criteria.isEmpty) return;
    final shares = allocateRubricWeight(
      10000,
      List<int>.filled(_criteria.length, 1),
    );
    setState(() {
      for (var i = 0; i < _criteria.length; i++) {
        _criteria[i].weight.text = formatRubricWeight(shares[i]);
      }
    });
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

  void _syncSectionsFromCriteria() {
    for (final s in _sections) {
      s.dispose();
    }
    _sections.clear();

    final sectionMap = <String, List<RubricCriterionDraft>>{};
    final sectionOrder = <String>[];
    const unsectionedKey = '__UNSECTIONED__';
    var needsInitialWeightSync = false;

    for (final draft in _criteria) {
      final sName = draft.section.text.trim();
      final key = sName.isEmpty ? unsectionedKey : sName;
      if (sName.isEmpty) {
        needsInitialWeightSync = true;
      }
      if (!sectionMap.containsKey(key)) {
        sectionMap[key] = [];
        sectionOrder.add(key);
      }
      sectionMap[key]!.add(draft);
    }

    if (sectionOrder.isEmpty) {
      final defaultTarget = _targetType == 'individual' ? 'individual' : 'team';
      final first = RubricCriterionDraft(
        scales: _scales,
        name: '',
        scale: 'Points-Based (Sections)',
        maxScore: 10,
        weight: 100,
        displayOrder: 0,
        targetType: defaultTarget,
      );
      final sec = SectionEditorDraft(
        title: 'Section 1',
        weight: '100',
        targetType: defaultTarget,
        criteria: [first],
      );
      _sections.add(sec);
      needsInitialWeightSync = true;
    } else {
      for (int i = 0; i < sectionOrder.length; i++) {
        final key = sectionOrder[i];
        final list = sectionMap[key]!;
        num secWeight = list.fold<num>(0, (sum, c) {
          final w = num.tryParse(c.weight.text.trim()) ?? 0;
          if (w <= 0) needsInitialWeightSync = true;
          return sum + w;
        });
        if (secWeight <= 0 && sectionOrder.length == 1) {
          secWeight = 100;
          needsInitialWeightSync = true;
        }
        final target = list.every((c) => c.targetType == 'individual')
            ? 'individual'
            : 'team';
        final formattedWeight = secWeight > 0
            ? (secWeight % 1 == 0
                  ? secWeight.toInt().toString()
                  : secWeight
                        .toStringAsFixed(2)
                        .replaceFirst(RegExp(r'\.?0+$'), ''))
            : '';
        final resolvedTitle = key == unsectionedKey ? 'Section ${i + 1}' : key;
        for (final c in list) {
          if (c.section.text.trim() != resolvedTitle) {
            c.section.text = resolvedTitle;
          }
        }
        _sections.add(
          SectionEditorDraft(
            title: resolvedTitle,
            weight: formattedWeight,
            targetType: target,
            criteria: list,
          ),
        );
      }
    }

    _attachSectionListeners();
    if (needsInitialWeightSync) {
      _recomputeCriteriaWeightsFromSections();
    }
  }

  void _attachSectionListeners() {
    for (final s in _sections) {
      s.title.removeListener(_markDirty);
      s.weight.removeListener(_markDirty);
      s.title.addListener(_markDirty);
      s.weight.addListener(_markDirty);
      for (final c in s.criteria) {
        c.name.removeListener(_markDirty);
        c.description.removeListener(_markDirty);
        c.maxScore.removeListener(_markDirty);
        c.name.addListener(_markDirty);
        c.description.addListener(_markDirty);
        c.maxScore.addListener(_markDirty);
      }
    }
  }

  void _recomputeCriteriaWeightsFromSections() {
    final allCriteria = <RubricCriterionDraft>[];
    int runningDisplayOrder = 0;

    for (final section in _sections) {
      final secTitle = section.title.text.trim();
      final secWeight = num.tryParse(section.weight.text.trim()) ?? 0;
      final critCount = section.criteria.length;
      final totalBasisPoints = secWeight.isFinite && secWeight > 0
          ? (secWeight * 100).round()
          : 0;

      if (totalBasisPoints > 0 && critCount > 0) {
        final shares = allocateRubricWeight(totalBasisPoints, [
          for (final criterion in section.criteria)
            _allocationPoints(criterion),
        ]);
        for (var i = 0; i < critCount; i++) {
          final c = section.criteria[i];
          c.section.text = secTitle;
          c.targetType = _targetType == 'both'
              ? section.targetType
              : _targetType;
          c.scale = 'Points-Based (Sections)';
          c.displayOrder.text = (runningDisplayOrder++).toString();
          c.weight.text = formatRubricWeight(shares[i]);
          allCriteria.add(c);
        }
      } else {
        for (final c in section.criteria) {
          c.section.text = secTitle;
          c.targetType = _targetType == 'both'
              ? section.targetType
              : _targetType;
          c.scale = 'Points-Based (Sections)';
          c.displayOrder.text = (runningDisplayOrder++).toString();
          c.weight.text = '0';
          allCriteria.add(c);
        }
      }
    }

    _criteria = allCriteria;
  }

  void _distributeSectionWeightsEvenly() {
    if (_sections.isEmpty) return;
    final shares = allocateRubricWeight(
      10000,
      List<int>.filled(_sections.length, 1),
    );
    setState(() {
      for (var i = 0; i < _sections.length; i++) {
        _sections[i].weight.text = formatRubricWeight(shares[i]);
      }
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  int _allocationPoints(RubricCriterionDraft criterion) {
    final points = int.tryParse(criterion.maxScore.text.trim()) ?? 0;
    // Incomplete point edits remain editable and are rejected on save.
    return points > 0 ? points : 0;
  }

  void _moveSectionUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index - 1, item);
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _moveSectionDown(int index) {
    if (index >= _sections.length - 1) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(index + 1, item);
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _addNewSection() {
    setState(() {
      final defaultTarget = _targetType == 'individual' ? 'individual' : 'team';
      final newSection = SectionEditorDraft(
        title: 'Section ${_sections.length + 1}',
        weight: '',
        targetType: defaultTarget,
        criteria: [],
      );
      final defaultCrit = RubricCriterionDraft(
        scales: _scales,
        name: '',
        scale: 'Points-Based (Sections)',
        maxScore: 10,
        weight: 0,
        displayOrder: _criteria.length,
        targetType: defaultTarget,
      );
      newSection.criteria.add(defaultCrit);
      _sections.add(newSection);
      _attachSectionListeners();
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _removeSection(int index) {
    if (_sections.length <= 1) return;
    setState(() {
      final removed = _sections.removeAt(index);
      for (final c in removed.criteria) {
        c.dispose();
      }
      removed.dispose();
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _addCriterionToSection(SectionEditorDraft section) {
    setState(() {
      final newCrit = RubricCriterionDraft(
        scales: _scales,
        name: '',
        scale: 'Points-Based (Sections)',
        maxScore: 10,
        weight: 0,
        displayOrder: _criteria.length,
        targetType: section.targetType,
      );
      section.criteria.add(newCrit);
      _attachSectionListeners();
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _removeCriterionFromSection(
    SectionEditorDraft section,
    int criterionIndex,
  ) {
    if (section.criteria.length <= 1) return;
    setState(() {
      final removed = section.criteria.removeAt(criterionIndex);
      removed.dispose();
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _moveCriterionUpInSection(
    SectionEditorDraft section,
    int criterionIndex,
  ) {
    if (criterionIndex <= 0) return;
    setState(() {
      final item = section.criteria.removeAt(criterionIndex);
      section.criteria.insert(criterionIndex - 1, item);
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  void _moveCriterionDownInSection(
    SectionEditorDraft section,
    int criterionIndex,
  ) {
    if (criterionIndex >= section.criteria.length - 1) return;
    setState(() {
      final item = section.criteria.removeAt(criterionIndex);
      section.criteria.insert(criterionIndex + 1, item);
      _recomputeCriteriaWeightsFromSections();
    });
    _markDirty();
  }

  Widget _buildSectionedCriteriaEditor(bool canEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWeightAssistantBar(enabled: canEdit),
        for (int sIdx = 0; sIdx < _sections.length; sIdx++) ...[
          _buildSingleSectionCard(
            section: _sections[sIdx],
            sectionIndex: sIdx,
            canEdit: canEdit,
          ),
          const SizedBox(height: 16),
        ],
        if (canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              onPressed: _addNewSection,
              leading: const Icon(LucideIcons.plus, size: 16),
              child: const Text('Add Section'),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleSectionCard({
    required SectionEditorDraft section,
    required int sectionIndex,
    required bool canEdit,
  }) {
    final secWeight = num.tryParse(section.weight.text.trim()) ?? 0;
    final totalPts = section.totalPoints;
    final titleText = section.title.text.trim();
    final displayTitle = titleText.isNotEmpty
        ? titleText
        : 'Section ${sectionIndex + 1}';

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                  : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final titleField = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroonOf(
                                  context,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  DefensysTokens.radiusSm,
                                ),
                                border: Border.all(
                                  color: DefensysTokens.maroonOf(
                                    context,
                                  ).withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                (sectionIndex + 1).toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: DefensysTokens.maroonOf(context),
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'SECTION ${sectionIndex + 1}',
                              style: DefensysTokens.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.maroonOf(context),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ShadInput(
                          controller: section.title,
                          enabled: canEdit,
                          placeholder: const Text(
                            'e.g. ORAL EXAMINATION, PROJECT MANUSCRIPT',
                          ),
                          style: DefensysTokens.tableCell.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _textPrimaryColor,
                          ),
                          onChanged: (_) {
                            _recomputeCriteriaWeightsFromSections();
                            _markDirty();
                          },
                        ),
                      ],
                    );

                    final weightField = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Section Weight',
                          style: DefensysTokens.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 110,
                          child: ShadInput(
                            controller: section.weight,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            trailing: Text('%', style: DefensysTokens.caption),
                            onChanged: (_) {
                              setState(() {
                                _recomputeCriteriaWeightsFromSections();
                              });
                              _markDirty();
                            },
                          ),
                        ),
                      ],
                    );

                    final actions = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShadTooltip(
                          builder: (_) => const Text('Move section up'),
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            width: 36,
                            height: 36,
                            padding: EdgeInsets.zero,
                            enabled: canEdit && sectionIndex > 0,
                            onPressed: canEdit && sectionIndex > 0
                                ? () => _moveSectionUp(sectionIndex)
                                : null,
                            child: const Icon(LucideIcons.arrowUp, size: 16),
                          ),
                        ),
                        ShadTooltip(
                          builder: (_) => const Text('Move section down'),
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            width: 36,
                            height: 36,
                            padding: EdgeInsets.zero,
                            enabled:
                                canEdit && sectionIndex < _sections.length - 1,
                            onPressed:
                                canEdit && sectionIndex < _sections.length - 1
                                ? () => _moveSectionDown(sectionIndex)
                                : null,
                            child: const Icon(LucideIcons.arrowDown, size: 16),
                          ),
                        ),
                        if (canEdit && _sections.length > 1)
                          ShadTooltip(
                            builder: (_) => const Text('Remove section'),
                            child: ShadButton.ghost(
                              size: ShadButtonSize.sm,
                              width: 36,
                              height: 36,
                              padding: EdgeInsets.zero,
                              onPressed: () => _removeSection(sectionIndex),
                              child: const Icon(
                                LucideIcons.trash2,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                      ],
                    );

                    if (constraints.maxWidth < 640) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          titleField,
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [weightField, actions],
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: titleField),
                        const SizedBox(width: 16),
                        weightField,
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: actions,
                        ),
                      ],
                    );
                  },
                ),
                if (_targetType == 'both') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Scoring Target:',
                        style: DefensysTokens.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _textSecondaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ShadRadioGroup<String>(
                        initialValue: section.targetType,
                        enabled: canEdit,
                        axis: Axis.horizontal,
                        spacing: 16,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              section.targetType = val;
                              for (final c in section.criteria) {
                                c.targetType = val;
                              }
                            });
                            _markDirty();
                          }
                        },
                        items: [
                          ShadRadio(
                            value: 'team',
                            label: Text(
                              'Team (Entire Group)',
                              style: DefensysTokens.caption,
                            ),
                          ),
                          ShadRadio(
                            value: 'individual',
                            label: Text(
                              'Individual (Per Student)',
                              style: DefensysTokens.caption,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int cIdx = 0; cIdx < section.criteria.length; cIdx++) ...[
                  Builder(
                    builder: (context) {
                      final criterion = section.criteria[cIdx];
                      final pts =
                          int.tryParse(criterion.maxScore.text.trim()) ?? 0;
                      final calcWeight = (totalPts > 0 && secWeight > 0)
                          ? ((pts / totalPts) * secWeight)
                                .toStringAsFixed(2)
                                .replaceFirst(RegExp(r'\.?0+$'), '')
                          : '0';

                      return RubricCriterionFields(
                        key: ObjectKey(criterion),
                        index: cIdx,
                        section: null,
                        name: criterion.name,
                        maxScore: criterion.maxScore,
                        weight: criterion.weight,
                        description: criterion.description,
                        maximum: pts > 0 ? pts : 10,
                        enabled: canEdit,
                        showTarget: false,
                        target: criterion.targetType,
                        isPointsScale: true,
                        hideWeight: true,
                        badge: ShadBadge.outline(
                          child: Text(
                            '$pts pts • $calcWeight% of rubric',
                            style: DefensysTokens.caption.copyWith(
                              fontWeight: FontWeight.w500,
                              color: pts > 0
                                  ? DefensysTokens.maroonOf(context)
                                  : _textSecondaryColor,
                            ),
                          ),
                        ),
                        onTargetChanged: (_) {},
                        onChanged: () {
                          setState(() {
                            _recomputeCriteriaWeightsFromSections();
                          });
                          _markDirty();
                        },
                        onMoveUp: cIdx > 0
                            ? () => _moveCriterionUpInSection(section, cIdx)
                            : null,
                        onMoveDown: cIdx < section.criteria.length - 1
                            ? () => _moveCriterionDownInSection(section, cIdx)
                            : null,
                        onRemove: section.criteria.length > 1
                            ? () => _removeCriterionFromSection(section, cIdx)
                            : null,
                      );
                    },
                  ),
                  if (cIdx < section.criteria.length - 1)
                    const SizedBox(height: 16),
                ],
                const SizedBox(height: 16),
                if (canEdit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: () => _addCriterionToSection(section),
                      leading: const Icon(LucideIcons.plus, size: 14),
                      child: Text('Add Criterion to $displayTitle'),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.4)
                  : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(9),
              ),
              border: Border(top: BorderSide(color: _borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${section.criteria.length} criteria • Total: $totalPts pts',
                  style: DefensysTokens.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _textPrimaryColor,
                  ),
                ),
                ShadBadge.secondary(
                  child: Text(
                    'Section Weight: ${section.weight.text.trim().isEmpty ? '0' : section.weight.text.trim()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: secWeight > 0
                          ? DefensysTokens.maroonOf(context)
                          : _textSecondaryColor,
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

  Widget _buildWeightAssistantBar({required bool enabled}) {
    final isSectioned = _rubricScale == 'Points-Based (Sections)';
    final total = isSectioned ? _totalSectionWeight : _totalCriteriaWeight;
    final count = isSectioned ? _sections.length : _criteria.length;
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
    final label = isSectioned
        ? 'Section weight allocation'
        : 'Criterion weight allocation';

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
                  if (isSectioned)
                    Text(
                      '($count ${_sections.length == 1 ? 'section' : 'sections'}, ${_criteria.length} criteria)',
                      style: DefensysTokens.caption.copyWith(
                        color: _textSecondaryColor,
                      ),
                    ),
                ],
              ),
              if (!widget.readOnly && count > 0)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isSectioned)
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: enabled,
                        onPressed: enabled
                            ? _distributeSectionWeightsEvenly
                            : null,
                        leading: const Icon(LucideIcons.equal, size: 15),
                        child: const Text('Distribute section weights evenly'),
                      )
                    else ...[
                      if (_hasSections)
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          enabled: enabled,
                          onPressed: enabled
                              ? _distributeWeightsBySections
                              : null,
                          leading: const Icon(LucideIcons.calculator, size: 15),
                          child: const Text('Calculate from sections'),
                        ),
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: enabled,
                        onPressed: enabled ? _distributeWeightsEvenly : null,
                        leading: const Icon(LucideIcons.equal, size: 15),
                        child: const Text('Distribute evenly'),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          ShadProgress(
            value: (total / 100).clamp(0.0, 1.0),
            minHeight: 4,
            color: color,
            backgroundColor: _borderColor,
            semanticsLabel: label,
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
    section: null,
    name: draft.name,
    maxScore: draft.maxScore,
    weight: draft.weight,
    description: draft.description,
    maximum: int.tryParse(draft.maxScore.text.trim()) ?? _rubricMaxScore,
    enabled: enabled,
    showTarget: _targetType == 'both',
    target: draft.targetType,
    isPointsScale: _rubricScale == 'Custom Scale',
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
    if (_rubricScale == 'Points-Based (Sections)') {
      _recomputeCriteriaWeightsFromSections();
      if (_sections.isEmpty) {
        return 'Add at least one section.';
      }
      final seenSectionTitles = <String>{};
      for (int sIdx = 0; sIdx < _sections.length; sIdx++) {
        final s = _sections[sIdx];
        final title = s.title.text.trim();
        if (title.isEmpty) {
          return 'Enter a title for Section ${sIdx + 1}.';
        }
        final lowerTitle = title.toLowerCase();
        if (seenSectionTitles.contains(lowerTitle)) {
          return 'Section titles must be unique ("$title" is duplicated).';
        }
        seenSectionTitles.add(lowerTitle);

        final secWeight = num.tryParse(s.weight.text.trim());
        if (secWeight == null ||
            !secWeight.isFinite ||
            secWeight <= 0 ||
            secWeight > 100) {
          return 'Enter a valid weight (> 0% and <= 100%) for section "$title".';
        }
        if ((secWeight * 100 - (secWeight * 100).round()).abs() > 0.000001) {
          return 'Section weights can have at most two decimal places.';
        }

        if (s.criteria.isEmpty) {
          return 'Section "$title" must contain at least one criterion.';
        }

        final seenInSec = <String>{};
        for (int cIdx = 0; cIdx < s.criteria.length; cIdx++) {
          final c = s.criteria[cIdx];
          final cName = c.name.text.trim();
          if (cName.isEmpty) {
            return 'Enter a name for Criterion ${cIdx + 1} in section "$title".';
          }
          final lowerName = cName.toLowerCase();
          if (seenInSec.contains(lowerName)) {
            return 'Criterion "$cName" is duplicated in section "$title".';
          }
          seenInSec.add(lowerName);

          final pts = int.tryParse(c.maxScore.text.trim());
          if (pts == null || pts <= 0 || pts > 32767) {
            return 'Enter valid points (1–32767) for "$cName" in section "$title".';
          }

          final computedWeight = num.tryParse(c.weight.text.trim()) ?? 0;
          if (computedWeight < 0.01) {
            return 'Criterion "$cName" in section "$title" has an effective weight below 0.01%. Increase the section weight or adjust criterion points.';
          }
        }
      }

      if ((_totalSectionWeight - 100).abs() > 0.0001 ||
          (_totalCriteriaWeight - 100).abs() > 0.0001) {
        return 'Section weights must total 100% (up to 2 decimal places). Current total: ${_totalSectionWeight.toStringAsFixed(2)}%.';
      }

      if (_targetType == 'both') {
        final hasTeam = _sections.any((s) => s.targetType == 'team');
        final hasIndiv = _sections.any((s) => s.targetType == 'individual');
        if (!hasTeam || !hasIndiv) {
          return "Rubrics set to 'Both (Team & Individual)' must contain at least one Team section and at least one Individual section.";
        }
      }

      return null;
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

    if (_rubricScale == 'Points-Based (Sections)') {
      _recomputeCriteriaWeightsFromSections();
    }

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
                      title: _rubricScale == 'Points-Based (Sections)'
                          ? 'Evaluation Sections & Criteria (${_sections.length} sections, ${_criteria.length} criteria)'
                          : 'Evaluation Criteria (${_criteria.length})',
                      child: _rubricScale == 'Points-Based (Sections)'
                          ? _buildSectionedCriteriaEditor(canEdit)
                          : Column(
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
                                              (c) =>
                                                  c.targetType == 'individual',
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
                                      leading: const Icon(
                                        LucideIcons.plus,
                                        size: 16,
                                      ),
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

class SectionEditorDraft {
  SectionEditorDraft({
    required String title,
    String weight = '',
    this.targetType = 'team',
    List<RubricCriterionDraft>? criteria,
  }) : title = TextEditingController(text: title),
       weight = TextEditingController(text: weight),
       criteria = criteria ?? [];

  final TextEditingController title;
  final TextEditingController weight;
  String targetType;
  final List<RubricCriterionDraft> criteria;

  int get totalPoints => criteria.fold<int>(
    0,
    (sum, c) => sum + (int.tryParse(c.maxScore.text.trim()) ?? 0),
  );

  void dispose() {
    title.dispose();
    weight.dispose();
  }
}

class RubricCriterionDraft {
  RubricCriterionDraft({
    required List<String> scales,
    String section = '',
    String name = '',
    String description = '',
    String? scale,
    int? maxScore,
    num weight = 100,
    int displayOrder = 0,
    String targetType = 'team',
  }) : this._(
         section: TextEditingController(text: section),
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
    required this.section,
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
      section: item['section']?.toString() ?? '',
      name: item['name']?.toString() ?? '',
      description: item['description']?.toString() ?? '',
      scale: item['scale']?.toString(),
      maxScore: int.tryParse(item['max_score']?.toString() ?? ''),
      weight: num.tryParse(item['weight']?.toString() ?? '') ?? 1,
      displayOrder: int.tryParse(item['display_order']?.toString() ?? '') ?? 0,
      targetType: item['target_type']?.toString() ?? 'team',
    );
  }

  final TextEditingController section;
  final TextEditingController name;
  final TextEditingController description;
  String scale;
  final TextEditingController maxScore;
  final TextEditingController weight;
  final TextEditingController displayOrder;
  String targetType;

  Map<String, dynamic> toPayload() {
    return {
      'section': section.text.trim(),
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
    section.dispose();
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
      'Points-Based (Sections)' => 10,
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
