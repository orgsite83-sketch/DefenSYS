import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/rubric_engine_provider.dart';
import '../../../theme/app_theme.dart';
import 'widgets/defensys_admin_shell.dart';

class RubricEngineScreen extends ConsumerStatefulWidget {
  const RubricEngineScreen({super.key});

  @override
  ConsumerState<RubricEngineScreen> createState() => _RubricEngineScreenState();
}

class _RubricEngineScreenState extends ConsumerState<RubricEngineScreen> {
  final _searchController = TextEditingController();

  static const _defaultScales = [
    '5-Point Scale',
    '10-Point Scale',
    '100-Point Scale',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rubricEngineProvider.notifier).fetchRubrics();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rubricEngineProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.checklist_rounded,
            title: 'Rubric Engine',
            subtitle:
                'Manage the standard rubric path for panel/event criteria and overall grade weights.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _primaryButton(
                  icon: Icons.rate_review_rounded,
                  label: 'Create Adviser Rubric',
                  onTap: state.isSaving
                      ? null
                      : () => _showRubricDialog(initialEvaluationType: 'adviser'),
                  outlined: true,
                ),
                const SizedBox(width: 10),
                _primaryButton(
                  icon: Icons.add_rounded,
                  label: 'Create Standard Rubric',
                  onTap: state.isSaving ? null : () => _showRubricDialog(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.error_outline_rounded,
              text: state.error!,
              color: AppColors.danger,
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.check_circle_outline_rounded,
              text: state.message!,
              color: AppColors.success,
            ),
          ],
          const SizedBox(height: 22),
          _rubricTableCard(state),
        ],
      ),
    );
  }

  Widget _buildStats(RubricEngineState state) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'Standard Rubrics',
            value: _count(state, 'all').toString(),
            subtitle: '${_count(state, 'published')} Published',
            icon: Icons.checklist_rounded,
            selected: true,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: _weightConfigCard(state)),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    bool selected = false,
  }) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? DefensysUi.primaryMaroon : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFF3E8FF)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: selected ? const Color(0xFF7C3AED) : DefensysUi.techBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightConfigCard(RubricEngineState state) {
    final capstone = state.rubrics
        .where((item) => item['scope']?.toString() == 'capstone')
        .toList();

    final source = capstone.isNotEmpty
        ? capstone.first
        : state.rubrics.isNotEmpty
        ? state.rubrics.first
        : null;

    final panel = source?['panel_weight']?.toString() ?? '50';
    final adviser = source?['adviser_weight']?.toString() ?? '30';
    final peer = source?['peer_weight']?.toString() ?? '20';

    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.balance_rounded,
              color: Color(0xFF2563EB),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weight Config',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'P: $panel% A: $adviser% Pr: $peer%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Panel / Adviser / Peer split',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rubricTableCard(RubricEngineState state) {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _scopeFilter(state),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: 150,
              child: Center(
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (state.rubrics.isEmpty)
            _emptyRubricTable()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: 1515, child: _rubricTable(state)),
            ),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
        ],
      ),
    );
  }

  Widget _searchField(RubricEngineState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: DefensysUi.steelGrey,
            size: 19,
          ),
          hintText: 'Search by rubric name or academic year...',
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
        onSubmitted: (value) {
          ref.read(rubricEngineProvider.notifier).fetchRubrics(search: value);
        },
      ),
    );
  }

  Widget _scopeFilter(RubricEngineState state) {
    return Container(
      width: 190,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.scope,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('Capstone Rubrics')),
            DropdownMenuItem(
              value: 'capstone',
              child: Text('Capstone Rubrics'),
            ),
            DropdownMenuItem(value: 'pit', child: Text('PIT Rubrics')),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(rubricEngineProvider.notifier)
                      .fetchRubrics(scope: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _rubricTable(RubricEngineState state) {
    return Column(
      children: [
        _rubricHeader(),
        ...state.rubrics.map((rubric) => _rubricRow(state, rubric)),
      ],
    );
  }

  Widget _rubricHeader() {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: const [
          _RubricHeaderCell('Rubric Name', flex: 1.35),
          _RubricHeaderCell('Scope', flex: 0.85),
          _RubricHeaderCell('Weight Distribution', flex: 1.9),
          _RubricHeaderCell('Created By', flex: 1.2),
          _RubricHeaderCell('Status', flex: 0.9),
          _RubricHeaderCell('Action', flex: 0.8),
        ],
      ),
    );
  }

  Widget _emptyRubricTable() {
    return Column(
      children: [
        _rubricHeader(),
        Container(
          height: 84,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: const Text(
            'No rubrics found. Click "Create Standard Rubric" to get started.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _rubricRow(RubricEngineState state, Map<String, dynamic> rubric) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _RubricTableCell(_rubricNameCell(rubric), flex: 1.35),
          _RubricTableCell(_scopeCell(rubric), flex: 0.85),
          _RubricTableCell(_weightChips(rubric), flex: 1.9),
          _RubricTableCell(
            _bodyText(rubric['created_by']?.toString() ?? '-'),
            flex: 1.2,
          ),
          _RubricTableCell(_statusChip(rubric), flex: 0.9),
          _RubricTableCell(_buildActions(state, rubric), flex: 0.8),
        ],
      ),
    );
  }

  Widget _rubricNameCell(Map<String, dynamic> rubric) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rubric['name']?.toString() ?? '-',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          rubric['display_semester']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _scopeCell(Map<String, dynamic> rubric) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _scopeChip(rubric['scope']?.toString() ?? ''),
        const SizedBox(height: 4),
        Text(
          _evaluationLabel(rubric['evaluation_type']?.toString()),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: DefensysUi.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildActions(RubricEngineState state, Map<String, dynamic> rubric) {
    final rubricId = _asInt(rubric['id']);
    final published = rubric['status'] == 'published';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving ? null : () => _showRubricDialog(rubric: rubric),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.edit_square,
              color: DefensysUi.techBlue,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || rubricId == null
              ? null
              : () => _showWeightsDialog(rubric),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.balance_rounded,
              color: DefensysUi.steelGrey,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || published || rubricId == null
              ? null
              : () => ref
                    .read(rubricEngineProvider.notifier)
                    .publishRubric(rubricId),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.lock_outline,
              color: published || rubricId == null
                  ? const Color(0xFFC9CED8)
                  : DefensysUi.primaryMaroon,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || rubricId == null
              ? null
              : () => _confirmDelete(
                  rubricId,
                  rubric['name']?.toString() ?? 'rubric',
                ),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.delete_rounded,
              color: AppColors.danger,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool outlined = false,
  }) {
    if (outlined) {
      return SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: DefensysUi.primaryMaroon,
            side: const BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }
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

  Future<void> _showRubricDialog({Map<String, dynamic>? rubric, String? initialEvaluationType}) async {
    final editing = rubric != null;
    final state = ref.read(rubricEngineProvider);
    final scales = state.scaleOptions.isEmpty
        ? _defaultScales
        : state.scaleOptions;
    final name = TextEditingController(text: rubric?['name']?.toString() ?? '');
    final eventName = TextEditingController(
      text: rubric?['event_name']?.toString() ?? '',
    );
    String scope = rubric?['scope']?.toString() ?? 'capstone';
    String evaluationType = rubric?['evaluation_type']?.toString()
        ?? initialEvaluationType
        ?? 'panel';
    String scale =
        rubric?['scale']?.toString() ?? _CriterionDraft.defaultScale(scales);
    int? semesterId =
        _asInt(rubric?['semester_id']) ?? _asInt(state.activeSemester?['id']);
    int? defenseStageId = _asInt(rubric?['defense_stage_id']);
    final criteria = _criterionDrafts(rubric, scales);

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final evalItems = [
              const DropdownMenuItem(value: 'panel', child: Text('Panel')),
              if (scope != 'pit')
                const DropdownMenuItem(
                  value: 'adviser',
                  child: Text('Adviser'),
                ),
              const DropdownMenuItem(value: 'peer', child: Text('Peer')),
            ];
            if (scope == 'pit' && evaluationType == 'adviser') {
              evaluationType = 'panel';
            }

            return AlertDialog(
              title: Text(editing ? 'Edit Rubric' : 'Create Rubric'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Rubric Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: scope,
                              decoration: const InputDecoration(
                                labelText: 'Scope',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'capstone',
                                  child: Text('Capstone'),
                                ),
                                DropdownMenuItem(
                                  value: 'pit',
                                  child: Text('PIT'),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() {
                                  scope = value ?? scope;
                                  if (scope == 'pit') {
                                    defenseStageId = null;
                                    evaluationType = evaluationType == 'adviser'
                                        ? 'panel'
                                        : evaluationType;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: semesterId,
                              decoration: const InputDecoration(
                                labelText: 'Semester',
                              ),
                              items: state.semesters
                                  .map(
                                    (semester) => DropdownMenuItem<int?>(
                                      value: _asInt(semester['id']),
                                      child: Text(
                                        semester['display_name']?.toString() ??
                                            '',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  semesterId = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: evaluationType,
                              decoration: const InputDecoration(
                                labelText: 'Evaluation Type',
                              ),
                              items: evalItems,
                              onChanged: (value) {
                                setDialogState(() {
                                  evaluationType = value ?? evaluationType;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: scale,
                              decoration: const InputDecoration(
                                labelText: 'Default Scale',
                              ),
                              items: scales
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  scale = value ?? scale;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (scope == 'capstone')
                        DropdownButtonFormField<int?>(
                          initialValue: defenseStageId,
                          decoration: const InputDecoration(
                            labelText: 'Defense Stage',
                          ),
                          items: state.defenseStages
                              .map(
                                (stage) => DropdownMenuItem<int?>(
                                  value: _asInt(stage['id']),
                                  child: Text(stage['label']?.toString() ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              defenseStageId = value;
                            });
                          },
                        )
                      else
                        TextField(
                          controller: eventName,
                          decoration: const InputDecoration(
                            labelText: 'PIT Event Name',
                            hintText: 'e.g. 2nd Year PIT Expo',
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Criteria',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                criteria.add(_CriterionDraft(scales: scales));
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Row'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...criteria.asMap().entries.map((entry) {
                        final index = entry.key;
                        final draft = entry.value;
                        return _criterionEditor(
                          draft,
                          index,
                          scales,
                          onRemove: criteria.length == 1
                              ? null
                              : () {
                                  setDialogState(() {
                                    draft.dispose();
                                    criteria.removeAt(index);
                                  });
                                },
                          onChanged: () => setDialogState(() {}),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'draft'),
                  child: const Text('Save Draft'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'published'),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Publish and Lock'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || action == null) {
      _disposeCriteria(criteria);
      return;
    }

    final payload = {
      'name': name.text.trim(),
      'scope': scope,
      'semester_id': semesterId,
      'defense_stage_id': scope == 'capstone' ? defenseStageId : null,
      'event_name': scope == 'pit' ? eventName.text.trim() : '',
      'evaluation_type': evaluationType,
      'scale': scale,
      'status': action,
      'criteria': criteria.map((draft) => draft.toPayload()).toList(),
    };
    _disposeCriteria(criteria);

    if (editing) {
      await ref
          .read(rubricEngineProvider.notifier)
          .updateRubric(_asInt(rubric['id'])!, payload);
    } else {
      await ref.read(rubricEngineProvider.notifier).addRubric(payload);
    }
  }

  Widget _criterionEditor(
    _CriterionDraft draft,
    int index,
    List<String> scales, {
    required VoidCallback? onRemove,
    required VoidCallback onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.name,
                  decoration: InputDecoration(
                    labelText: 'Criterion ${index + 1}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: draft.scale,
                  decoration: const InputDecoration(labelText: 'Scale'),
                  items: scales
                      .map(
                        (scale) =>
                            DropdownMenuItem(value: scale, child: Text(scale)),
                      )
                      .toList(),
                  onChanged: (value) {
                    draft.scale = value ?? draft.scale;
                    draft.maxScore.text = _defaultMaxForScale(
                      draft.scale,
                    ).toString();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 86,
                child: TextField(
                  controller: draft.maxScore,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max'),
                ),
              ),
              IconButton(
                tooltip: 'Remove criterion',
                onPressed: onRemove,
                color: AppColors.danger,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.description,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional scoring guidance',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeightsDialog(Map<String, dynamic> rubric) async {
    final rubricId = _asInt(rubric['id']);
    if (rubricId == null) {
      return;
    }

    final isPit = rubric['scope'] == 'pit';
    final panel = TextEditingController(
      text: rubric['panel_weight']?.toString() ?? (isPit ? '80' : '50'),
    );
    final adviser = TextEditingController(
      text: rubric['adviser_weight']?.toString() ?? (isPit ? '0' : '30'),
    );
    final peer = TextEditingController(
      text: rubric['peer_weight']?.toString() ?? '20',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Weight Configuration'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rubric['name']?.toString() ?? '',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: panel,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Panel %'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!isPit)
                    Expanded(
                      child: TextField(
                        controller: adviser,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Adviser %',
                        ),
                      ),
                    ),
                  if (!isPit) const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: peer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Peer %'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isPit
                    ? 'PIT uses Panel + Peer only. Adviser weight is locked to 0%.'
                    : 'Weights must total 100%.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save Weights'),
          ),
        ],
      ),
    );

    if (!mounted || saved != true) {
      return;
    }

    await ref.read(rubricEngineProvider.notifier).updateWeights(rubricId, {
      'panel_weight': int.tryParse(panel.text.trim()) ?? 0,
      'adviser_weight': isPit ? 0 : int.tryParse(adviser.text.trim()) ?? 0,
      'peer_weight': int.tryParse(peer.text.trim()) ?? 0,
    });
  }

  Future<void> _confirmDelete(int rubricId, String rubricName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Rubric'),
        content: Text('Delete $rubricName? This removes its criteria too.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }
    await ref.read(rubricEngineProvider.notifier).deleteRubric(rubricId);
  }

  List<_CriterionDraft> _criterionDrafts(
    Map<String, dynamic>? rubric,
    List<String> scales,
  ) {
    final values = rubric?['criteria'];
    if (values is List && values.isNotEmpty) {
      return values
          .whereType<Map>()
          .map((item) => _CriterionDraft.fromMap(item, scales))
          .toList();
    }
    return [
      _CriterionDraft(scales: scales),
      _CriterionDraft(scales: scales, name: 'Presentation and Delivery'),
    ];
  }

  void _disposeCriteria(List<_CriterionDraft> criteria) {
    for (final draft in criteria) {
      draft.dispose();
    }
  }

  Widget _weightChips(Map<String, dynamic> rubric) {
    final isPit = rubric['scope'] == 'pit';
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        _buildChip('P ${rubric['panel_weight'] ?? 0}%', AppColors.maroon),
        if (!isPit)
          _buildChip('A ${rubric['adviser_weight'] ?? 0}%', AppColors.success),
        _buildChip('Pr ${rubric['peer_weight'] ?? 0}%', Colors.blue),
      ],
    );
  }

  Widget _statusChip(Map<String, dynamic> rubric) {
    final published = rubric['status'] == 'published';
    return _buildChip(
      published ? 'Published' : 'Draft',
      published ? AppColors.success : AppColors.warning,
      icon: published ? Icons.lock_outline : Icons.edit_note,
    );
  }

  Widget _scopeChip(String scope) {
    return _buildChip(
      scope == 'pit' ? 'PIT' : 'Capstone',
      scope == 'pit' ? Colors.blue : AppColors.maroon,
    );
  }

  Widget _buildChip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
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

  int _defaultMaxForScale(String scale) {
    return switch (scale) {
      '5-Point Scale' => 5,
      '100-Point Scale' => 100,
      _ => 10,
    };
  }

  int _count(RubricEngineState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _CriterionDraft {
  _CriterionDraft({
    required List<String> scales,
    String name = 'Technical Competency',
    String description = '',
    String? scale,
    int? maxScore,
    num weight = 1,
    int displayOrder = 0,
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
       );

  _CriterionDraft._({
    required this.name,
    required this.description,
    required this.scale,
    required this.maxScore,
    required this.weight,
    required this.displayOrder,
  });

  factory _CriterionDraft.fromMap(Map item, List<String> scales) {
    return _CriterionDraft(
      scales: scales,
      name: item['name']?.toString() ?? '',
      description: item['description']?.toString() ?? '',
      scale: item['scale']?.toString(),
      maxScore: int.tryParse(item['max_score']?.toString() ?? ''),
      weight: num.tryParse(item['weight']?.toString() ?? '') ?? 1,
      displayOrder: int.tryParse(item['display_order']?.toString() ?? '') ?? 0,
    );
  }

  final TextEditingController name;
  final TextEditingController description;
  String scale;
  final TextEditingController maxScore;
  final TextEditingController weight;
  final TextEditingController displayOrder;

  Map<String, dynamic> toPayload() {
    return {
      'name': name.text.trim(),
      'description': description.text.trim(),
      'scale': scale,
      'max_score': int.tryParse(maxScore.text.trim()) ?? _scaleMax(scale),
      'weight': num.tryParse(weight.text.trim()) ?? 1,
      'display_order': int.tryParse(displayOrder.text.trim()) ?? 0,
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

class _RubricHeaderCell extends StatelessWidget {
  const _RubricHeaderCell(this.text, {required this.flex});

  final String text;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RubricTableCell extends StatelessWidget {
  const _RubricTableCell(this.child, {required this.flex});

  final Widget child;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}
