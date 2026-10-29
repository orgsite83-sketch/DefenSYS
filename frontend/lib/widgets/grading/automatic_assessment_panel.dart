import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/api_config.dart';
import '../../services/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../../screens/app/panelist/widgets/evaluation_score_picker.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../repository/section_concept_workspace.dart';

/// The automatic result and the two distinct chair actions: selection and notes.
class AutomaticAssessmentPanel extends ConsumerStatefulWidget {
  const AutomaticAssessmentPanel({
    super.key,
    required this.grade,
    required this.isChair,
    this.onUpdated,
    this.embedded = false,
    this.showSharedLink = true,
    this.sharedContext,
    this.teamName,
    this.assessmentConcepts = const [],
  });

  final Map<String, dynamic> grade;
  final bool isChair;
  final VoidCallback? onUpdated;
  final bool embedded, showSharedLink;
  final Map<String, dynamic>? sharedContext;
  final String? teamName;
  final List<Map<String, dynamic>> assessmentConcepts;

  @override
  ConsumerState<AutomaticAssessmentPanel> createState() =>
      _AutomaticAssessmentPanelState();
}

class _AutomaticAssessmentPanelState
    extends ConsumerState<AutomaticAssessmentPanel> {
  late Map<String, dynamic> _grade;
  late final TextEditingController _notes;
  String? _selection;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _grade = widget.grade;
    _notes = TextEditingController(text: '${_grade['verdict_remarks'] ?? ''}');
  }

  @override
  void didUpdateWidget(covariant AutomaticAssessmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.grade, oldWidget.grade)) {
      final changed =
          widget.grade['id'] != _grade['id'] ||
          widget.grade['schedule_id'] != _grade['schedule_id'];
      _grade = widget.grade;
      if (changed) {
        _selection = null;
        _notes.text = '${_grade['verdict_remarks'] ?? ''}';
      }
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rule = (_grade['workflow'] as Map?)?['outcome_rule'] as Map?;
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse(
              '${ApiConfig.gradeCenterUrl}/${_grade['id']}/assessment/',
            ),
            body: jsonEncode({
              'action': action,
              'review_token': rule?['review_token'],
              if (action == 'select_concept') ...{
                'concept_key': _selection,
              } else
                'recommendations': _notes.text.trim(),
            }),
          );
      if (!mounted) return;
      final result = jsonDecode(response.body);
      if (response.statusCode != 200) {
        showErrorToast(
          context,
          '${result['detail'] ?? 'Unable to save. Refresh and try again.'}',
        );
        return;
      }
      setState(
        () => _grade = Map<String, dynamic>.from(result['grade'] as Map),
      );
      showSuccessToast(
        context,
        action == 'select_concept'
            ? 'Concept selected.'
            : 'Recommendations saved.',
      );
      widget.onUpdated?.call();
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Unable to save. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sharedAssessments(
    List<Map> rows,
    List<Map> assessments,
    String selectedKey,
    bool complete,
  ) {
    final muted = DefensysTokens.textSecondaryOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final systems = (widget.sharedContext?['systems'] as List? ?? [])
        .whereType<Map>();
    Widget module(Map assessment) {
      final candidate = rows
          .where((row) => row['key'] == assessment['key'])
          .firstOrNull;
      final selected =
          selectedKey.isNotEmpty && assessment['key'] == selectedKey;
      final parent =
          candidate?['system_title'] ??
          systems
              .where((row) => row['key'] == assessment['key'])
              .firstOrNull?['title'];
      final score = assessment['score'];
      final state = !complete
          ? 'Provisional'
          : selected
          ? assessment['qualifies'] == true
                ? 'Module qualifies'
                : 'Below qualifying score'
          : selectedKey.isEmpty
          ? 'Assessment complete'
          : 'Alternative system';
      return Container(
        key: ValueKey('module-assessment-${assessment['key']}'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? DefensysTokens.maroonTextOf(context).withValues(alpha: .5)
                : DefensysTokens.borderOf(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (parent != null && parent.toString().isNotEmpty) ...[
              Text(
                selected ? 'Selected shared system' : 'Shared system',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 4),
              Text(
                parent.toString(),
                style: TextStyle(fontSize: 13, height: 1.5, color: ink),
              ),
              const SizedBox(height: 14),
            ],
            Text('Team module', style: TextStyle(fontSize: 11, color: muted)),
            const SizedBox(height: 4),
            Text(
              '${candidate?['title'] ?? assessment['title'] ?? ''}',
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(state, style: TextStyle(fontSize: 12, color: muted)),
                Text(
                  score is num
                      ? 'Module panel score: ${formatEvaluationScore(score.toDouble())}%'
                      : 'Not assessed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final selected = assessments
        .where((row) => row['key'] == selectedKey)
        .toList();
    final alternatives = assessments
        .where((row) => row['key'] != selectedKey)
        .toList();
    // Pair identity remains readable even before the selected module has a score.
    final selectedCandidate = rows
        .where((row) => row['key'] == selectedKey)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedKey.isNotEmpty) ...[
          for (final assessment in selected) module(assessment),
          if (selected.isEmpty && selectedCandidate != null)
            module({'key': selectedKey, 'title': selectedCandidate['title']}),
          if (alternatives.isNotEmpty)
            ShadAccordion<String>(
              children: [
                ShadAccordionItem(
                  value: 'alternative-assessments',
                  title: const Text(
                    'Alternative module assessments',
                    style: TextStyle(fontSize: 12),
                  ),
                  child: Column(
                    children: [
                      for (final assessment in alternatives) module(assessment),
                    ],
                  ),
                ),
              ],
            ),
        ] else ...[
          Text(
            'Team module assessments',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          for (final assessment in assessments) module(assessment),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final workflow = (_grade['workflow'] as Map?) ?? const {};
    final rule = (workflow['outcome_rule'] as Map?) ?? const {};
    final concepts = (workflow['concept_workflow'] as Map?) ?? const {};
    final capturedRows =
        (concepts['hearing_concepts'] as List? ??
                concepts['concepts'] as List? ??
                const [])
            .whereType<Map>()
            .toList();
    final keys = <dynamic>{
      ...capturedRows.map((row) => row['key']),
      ...widget.assessmentConcepts.map((row) => row['key']),
    };
    final rows = [
      for (final key in keys)
        {
          ...?capturedRows.where((row) => row['key'] == key).firstOrNull,
          ...?widget.assessmentConcepts
              .where((row) => row['key'] == key)
              .firstOrNull,
        },
    ];
    final assessments = (rule['assessments'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final complete = rule['panel_complete'] == true;
    final recorded = '${_grade['verdict'] ?? ''}'.isNotEmpty;
    final closedFailed =
        ((_grade['outcome_metadata'] as Map?)?['closure'] as Map?)?['failed'] ==
        true;
    final shared =
        widget.sharedContext != null ||
        concepts['selection_mode'] == 'shared_module' ||
        concepts['section_project_id'] != null ||
        rows.any((row) => row.containsKey('system_title'));
    final selectedKey =
        (widget.sharedContext?['selected_key'] ??
                concepts['section_selected_key'] ??
                (concepts['shared_selection'] as Map?)?['selected_key'] ??
                rows
                    .where((row) => row['section_selected'] == true)
                    .firstOrNull?['key'] ??
                '')
            .toString();
    final sharedRepeat =
        (widget.sharedContext?['verdict'] ??
            (concepts['shared_selection'] as Map?)?['decision']) ==
        'for_redefense';
    final qualified = assessments
        .where(
          (row) =>
              row['qualifies'] == true &&
              (!shared ||
                  rows.any(
                    (c) => c['key'] == row['key'] && c['key'] == selectedKey,
                  )),
        )
        .toList();
    final selecting =
        !shared &&
        !recorded &&
        complete &&
        rule['outcome'] == 'approved' &&
        rule['per_concept'] == true &&
        qualified.length > 1;
    final title = closedFailed
        ? 'Failed at stage closure'
        : sharedRepeat
        ? 'Another shared hearing required'
        : !complete
        ? 'Awaiting panel evaluations'
        : rule['outcome'] == 'pending'
        ? 'Awaiting section system selection'
        : selecting
        ? 'Choose the official concept'
        : _grade['verdict'] == 'for_redefense'
        ? 'Re-defense required'
        : recorded
        ? 'Qualified'
        : 'Assessment pending';
    final canEdit =
        widget.isChair &&
        _grade['status'] != 'published' &&
        !_busy &&
        workflow['can_save_recommendations'] != false;
    final primary = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final progress = workflow['assessment_progress'] as Map? ?? {};
    final required = progress['panel_evaluators_required'];
    final submitted = progress['panel_evaluators_submitted'];
    String percentage(dynamic value) => value is num
        ? '${formatEvaluationScore(value.toDouble())}%'
        : '$value%';

    return DefensysShadcnScope(
      child: Container(
        key: const ValueKey('automatic-assessment-panel'),
        padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(16),
        decoration: widget.embedded
            ? null
            : BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.teamName != null
                        ? '${widget.teamName} outcome'
                        : widget.embedded
                        ? 'Panel qualifying score'
                        : 'Team outcome',
                    style: DefensysTokens.sectionTitle.copyWith(color: primary),
                  ),
                ),
                if (widget.teamName == null)
                  Text(
                    rule['qualifying_score'] == null
                        ? 'Not configured'
                        : percentage(rule['qualifying_score']),
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (widget.teamName != null) ...[
              const SizedBox(height: 8),
              Text(
                '${shared ? 'Module' : 'Panel'} qualifying score: ${rule['qualifying_score'] is num ? percentage(rule['qualifying_score']) : 'Not configured'}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ] else if (!widget.embedded)
              Text(
                'Panel qualifying score',
                textAlign: TextAlign.end,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!complete || rule['reason']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                !complete
                    ? (required is num && required > 0 && submitted is num
                          ? '$submitted of $required panelists submitted'
                          : 'All required panel evaluations must be submitted.')
                    : '${rule['reason']}',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
            if (shared &&
                selectedKey.isEmpty &&
                !sharedRepeat &&
                !closedFailed &&
                !complete) ...[
              const SizedBox(height: 8),
              Text(
                'Waiting for shared-system selection',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
            if (widget.showSharedLink && concepts['section_project_id'] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  height: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SectionConceptWorkspace(
                          projectId: concepts['section_project_id'] as int,
                        ),
                      ),
                    );
                    widget.onUpdated?.call();
                  },
                  child: const Flexible(
                    child: Text(
                      'Open section systems',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            if (shared) ...[
              const SizedBox(height: 24),
              _sharedAssessments(rows, assessments, selectedKey, complete),
            ] else if (rule['per_concept'] == true) ...[
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _selection,
                onChanged: (value) => setState(() => _selection = value),
                child: Column(
                  children: [
                    for (final assessment in assessments)
                      Builder(
                        builder: (context) {
                          final concept = rows
                              .where((row) => row['key'] == assessment['key'])
                              .firstOrNull;
                          final official = [
                            'approved',
                            'approved_with_revisions',
                          ].contains(concept?['decision']);
                          final available = qualified.any(
                            (row) => row['key'] == assessment['key'],
                          );
                          final state = !complete
                              ? 'Provisional'
                              : official
                              ? 'Official concept'
                              : available
                              ? 'Qualifies'
                              : 'Below qualifying score';
                          final selected =
                              official ||
                              (selecting && _selection == assessment['key']);
                          return Container(
                            key: ValueKey(
                              'concept-assessment-${assessment['key']}',
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: DefensysTokens.surfaceOf(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? DefensysTokens.maroonTextOf(
                                        context,
                                      ).withValues(alpha: .5)
                                    : border,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (selecting)
                                  Radio<String>(
                                    value: '${assessment['key']}',
                                    enabled: canEdit && available,
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${assessment['title'] ?? concept?['title'] ?? ''}',
                                        style: TextStyle(
                                          color: primary,
                                          fontSize: 14,
                                          height: 1.45,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        spacing: 16,
                                        runSpacing: 6,
                                        children: [
                                          Text(
                                            state,
                                            style: TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            assessment['score'] == null
                                                ? 'Not assessed'
                                                : percentage(
                                                    assessment['score'],
                                                  ),
                                            style: TextStyle(
                                              color: primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ] else if (rule['per_concept'] != true &&
                assessments.isNotEmpty &&
                assessments.first['score'] != null) ...[
              const SizedBox(height: 10),
              Text(
                'Panel assessment: ${percentage(assessments.first['score'])}',
                style: TextStyle(color: primary),
              ),
            ],
            if (selecting && widget.isChair) ...[
              const SizedBox(height: 12),
              ShadButton(
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                onPressed: canEdit && _selection != null
                    ? () => _save('select_concept')
                    : null,
                child: const Flexible(
                  child: Text(
                    'Confirm concept selection',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            if (widget.isChair && !closedFailed) ...[
              Divider(height: 28, color: border),
              Text(
                'Panel recommendations',
                style: TextStyle(color: primary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ShadInput(
                controller: _notes,
                enabled: canEdit,
                maxLength: 5000,
                maxLines: 3,
                placeholder: const Text('Recommendations for the team'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.outline(
                  height: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  onPressed: canEdit ? () => _save('recommendations') : null,
                  child: Flexible(
                    child: Text(
                      _busy ? 'Saving...' : 'Save recommendations',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ] else if ('${_grade['verdict_remarks'] ?? ''}'
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${_grade['verdict_remarks']}',
                style: TextStyle(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
