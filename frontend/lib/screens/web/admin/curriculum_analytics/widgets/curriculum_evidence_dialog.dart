import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../config/api_config.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../../../widgets/feedback/defensys_loading.dart';

class CurriculumEvidenceDialog extends ConsumerStatefulWidget {
  const CurriculumEvidenceDialog({
    super.key,
    required this.project,
    this.criterion,
    required this.allAssessments,
    required this.initialRole,
  });
  final Map<String, dynamic> project;
  final Map<String, dynamic>? criterion;
  final bool allAssessments;
  final String initialRole;
  @override
  ConsumerState<CurriculumEvidenceDialog> createState() =>
      _CurriculumEvidenceDialogState();
}

class _CurriculumEvidenceDialogState
    extends ConsumerState<CurriculumEvidenceDialog> {
  Map<String, dynamic>? _data;
  String? _error, _assessment;
  late String _role;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(curriculumExplorerProvider.notifier)
          .detail(
            '${widget.project['id']}',
            allAssessments: widget.allAssessments,
          );
      if (!mounted) return;
      final assessments = explorerRows(data['assessments']);
      setState(() {
        _data = data;
        final matched = assessments
            .where((a) => a['semester_id'] == widget.criterion?['semester_id'])
            .firstOrNull;
        _assessment = assessments.isEmpty
            ? null
            : '${(matched ?? assessments.last)['id']}';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  TextStyle get _muted => TextStyle(
    fontSize: 12,
    height: 1.5,
    color: DefensysTokens.textSecondaryOf(context),
  );
  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      key: const ValueKey('curriculum-evidence-dialog'),
      constraints: const BoxConstraints(maxWidth: 800),
      title: Text('${widget.project['team_name']}'),
      description: Text(
        '${widget.project['project_title']} / Project v${widget.project['project_version']}',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .66,
        ),
        child: SizedBox(
          width: 720,
          child: _loading
              ? DefensysLoading.section(
                  height: 250,
                  label: 'Loading recorded evidence…',
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        WorkflowNotice(
                          title: 'Evidence could not load',
                          message: _error!,
                          error: true,
                        ),
                        ShadButton.outline(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                      if (_data != null) ..._content(),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );

  List<Widget> _content() {
    final data = _data!, assessments = explorerRows(data['assessments']);
    final assessment = assessments
        .where((a) => '${a['id']}' == _assessment)
        .firstOrNull;
    final classification = Map<String, dynamic>.from(
      data['classification'] as Map? ?? {},
    );
    final roles = data['scope'] == 'pit'
        ? ['panel', 'peer']
        : ['panel', 'adviser', 'peer'];
    final criteria = explorerRows(
      assessment?['criteria'],
    ).where((c) => c['evaluation_type'] == _role).toList();
    final selectedIndex = criteria.indexWhere(
      (c) =>
          c['name'] == widget.criterion?['name'] &&
          c['rubric_id'] == widget.criterion?['rubric_id'],
    );
    return [
      if (widget.allAssessments) _classificationEvidence(classification),
      if (assessments.length > 1)
        WorkflowSelect(
          label: data['scope'] == 'pit' ? 'Recorded event' : 'Recorded stage',
          options: {
            for (final a in assessments)
              '${a['id']}':
                  '${a['label']} / ${a['academic_year']} / ${a['semester']}',
          },
          value: _assessment,
          searchable: false,
          onChanged: (v) => setState(() => _assessment = v),
        ),
      if (assessment != null)
        Text(
          '${assessment['label']} / ${assessment['academic_year']} / ${assessment['semester']}',
          style: _muted,
        ),
      _heading('Recorded rubric results'),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: data['scope'] == 'pit' ? 200 : 280,
          child: ShadTabs<String>(
            value: _role,
            gap: 0,
            scrollable: false,
            onChanged: (v) => setState(() => _role = v),
            tabs: roles
                .map(
                  (r) => ShadTab<String>(
                    value: r,
                    child: Flexible(
                      child: Text(
                        '${r[0].toUpperCase()}${r.substring(1)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (criteria.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No recorded $_role criterion scores for this assessment. Missing results are not treated as zero.',
            style: _muted,
          ),
        )
      else
        ShadAccordion<String>(
          key: ValueKey('$_role-$_assessment'),
          initialValue: selectedIndex >= 0 ? '$selectedIndex' : null,
          children: criteria.asMap().entries.map((entry) {
            final c = entry.value;
            return ShadAccordionItem<String>(
              value: '${entry.key}',
              title: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c['name']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (c['student_name'] != null)
                          Text('${c['student_name']}', style: _muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${explorerNumber(c['percentage'])!.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${explorerNumber(c['score'])!.toStringAsFixed(2)} / ${c['max_score']} points (consolidated)',
                    style: _muted,
                  ),
                  const SizedBox(height: 9),
                  ...explorerRows(c['records']).map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['evaluator']}: ${r['score']} / ${r['max_score']} points',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r['remarks']}'.trim().isEmpty
                                ? 'No remarks recorded.'
                                : '${r['remarks']}',
                            style: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      if (assessment != null &&
          '${assessment['remarks'] ?? ''}'.trim().isNotEmpty) ...[
        _heading('Recorded verdict remarks'),
        Text('${assessment['remarks']}', style: _muted),
      ],
      if (!widget.allAssessments) _classificationEvidence(classification),
      _heading('Source project documents'),
      if (explorerRows(data['documents']).isEmpty)
        Text(
          'No suitable project documents are available. Administrative attachments are excluded.',
          style: _muted,
        )
      else
        ShadAccordion<String>(
          children: explorerRows(data['documents'])
              .map(
                (d) => ShadAccordionItem<String>(
                  value: '${d['id']}',
                  title: Text(
                    '${d['file_name']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d['label']}', style: _muted),
                      if ('${d['category'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            'Stored ML label: ${d['category']}${d['model_score'] == null ? '' : ' / model score ${explorerNumber(d['model_score'])!.toStringAsFixed(1)} out of 100'}',
                            style: _muted,
                          ),
                        ),
                      if ((d['topics'] as List? ?? []).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Extracted terms: ${(d['topics'] as List).join(', ')}',
                          style: _muted,
                        ),
                      ],
                      const SizedBox(height: 8),
                      SelectableText(
                        '${d['excerpt']}'.isEmpty
                            ? 'No readable text extracted.'
                            : '${d['excerpt']}',
                        style: _muted,
                      ),
                      if (d['url'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ShadButton.outline(
                            size: ShadButtonSize.sm,
                            leading: const Icon(
                              LucideIcons.externalLink,
                              size: 14,
                            ),
                            onPressed: () async {
                              final uri = Uri.parse(
                                ApiConfig.baseUrl,
                              ).resolve('${d['url']}');
                              if (uri.scheme != 'http' &&
                                  uri.scheme != 'https') {
                                return;
                              }
                              final opened = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!opened && mounted) {
                                setState(
                                  () => _error =
                                      'The source document could not open. Try again.',
                                );
                              }
                            },
                            child: const Text('Open source document'),
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      const SizedBox(height: 14),
      Text(
        'Project documents provide context. Recorded evaluator scores and remarks explain the assessment.',
        style: _muted,
      ),
    ];
  }

  Widget _classificationEvidence(Map<String, dynamic> classification) => Column(
    key: const ValueKey('project-classification-explanation'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('Why this project has this label'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ShadBadge.outline(
            child: Text('${classification['label'] ?? 'Unclassified'}'),
          ),
          const ShadBadge.outline(
            child: Text('Estimate · not faculty-reviewed'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text('${classification['reason'] ?? ''}', style: _muted),
      if (classification['file_name'] != null)
        Text('Primary source: ${classification['file_name']}', style: _muted),
      if (classification['domain'] != null) ...[
        const SizedBox(height: 10),
        Text(
          'Application domain: ${classification['domain']}',
          style: _muted.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
      if (explorerRows(classification['technologies']).isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          'Technologies documented: ${explorerRows(classification['technologies']).map((t) => t['name']).join(', ')}',
          style: _muted,
        ),
      ],
      if (explorerRows(classification['evidence']).isNotEmpty ||
          explorerRows(classification['domain_evidence']).isNotEmpty ||
          explorerRows(classification['technologies']).isNotEmpty) ...[
        const SizedBox(height: 12),
        ShadAccordion<String>(
          children: [
            for (final (i, e) in [
              ...explorerRows(classification['evidence']),
              ...explorerRows(classification['domain_evidence']),
              for (final technology in explorerRows(
                classification['technologies'],
              ))
                ...explorerRows(
                  technology['evidence'],
                ).map((e) => {...e, 'file_name': technology['file_name']}),
            ].indexed)
              ShadAccordionItem(
                value: 'classification-evidence-$i',
                title: Text(
                  '${e['term']} · ${e['section']}',
                  style: const TextStyle(fontSize: 12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('${e['excerpt']}', style: _muted),
                    if (e['file_name'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Source: ${e['file_name']}', style: _muted),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
      ShadAccordion<String>(
        children: [
          ShadAccordionItem(
            value: 'classification-model',
            title: Text('Model details and candidate scores', style: _muted),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (classification['model_version'] != null)
                  Text(
                    'Model version: ${classification['model_version']}',
                    style: _muted,
                  ),
                if (classification['classified_at'] != null)
                  Text(
                    'Classified: ${_classificationTime(classification['classified_at'])}',
                    style: _muted,
                  ),
                for (final candidate in explorerRows(
                  classification['candidates'],
                ))
                  Text(
                    '${candidate['category']}: ${(explorerNumber(candidate['probability']) ?? 0).toStringAsFixed(1)} / 100',
                    style: _muted,
                  ),
                const SizedBox(height: 8),
                Text(
                  'These are model scores, not measured accuracy. The current model uses authored development examples; a faculty-reviewed evaluation dataset is still needed.',
                  style: _muted,
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  String _classificationTime(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null
        ? 'Unavailable'
        : DateFormat('MMM d, y · h:mm a').format(parsed.toLocal());
  }
}
