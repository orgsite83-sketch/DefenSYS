import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../services/network/authenticated_client.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../utils/universal_file_viewer.dart';
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
  late String _view;
  String? _selectedSource;
  final _sourcesKey = GlobalKey();
  final _sourceKeys = <String, GlobalKey>{};
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _expandedDetails = <String>{};
  bool _loading = true;
  String? _openingDocument, _documentError, _failedDocument;
  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _view = widget.allAssessments ? 'overview' : 'assessments';
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeView(String value) {
    setState(() => _view = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
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
      scrollable: false,
      title: Text(
        '${widget.project['project_title']}',
        key: const ValueKey('project-dialog-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
      description: Text(
        '${widget.project['team_name']} · Version ${widget.project['project_version']}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: SizedBox(
        key: const ValueKey('project-dialog-body'),
        height: (MediaQuery.sizeOf(context).height * .66).clamp(0.0, 560.0),
        width: 720,
        child: _loading
            ? DefensysLoading.section(
                height: 250,
                label: 'Loading recorded evidence…',
              )
            : Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_data != null) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 460;
                        return ShadTabs<String>(
                          value: _view,
                          gap: 0,
                          scrollable: false,
                          onChanged: _changeView,
                          tabs: [
                            for (final entry in {
                              'overview': 'Overview',
                              'sources': 'Sources',
                              'assessments': 'Assessments',
                            }.entries)
                              ShadTab<String>(
                                key: ValueKey('project-view-${entry.key}'),
                                value: entry.key,
                                flex: narrow
                                    ? (entry.key == 'assessments' ? 4 : 3)
                                    : 1,
                                padding: narrow
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 8,
                                      )
                                    : null,
                                child: Flexible(
                                  child: Text(
                                    entry.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: narrow ? 12 : 13,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: Scrollbar(
                        key: const ValueKey('project-evidence-scrollbar'),
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 4,
                        radius: const Radius.circular(4),
                        child: SingleChildScrollView(
                          key: ValueKey('project-scroll-$_view'),
                          controller: _scrollController,
                          padding: const EdgeInsets.only(right: 16, bottom: 8),
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
                              if (_data != null)
                                ...switch (_view) {
                                  'overview' => _overviewContent(),
                                  'sources' => _sourcesContent(),
                                  _ => _assessmentsContent(),
                                },
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );

  void _showSource(String? documentId) {
    setState(() {
      _selectedSource = documentId;
      _view = 'sources';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sourceContext =
          _sourceKeys[documentId]?.currentContext ?? _sourcesKey.currentContext;
      if (sourceContext != null) Scrollable.ensureVisible(sourceContext);
    });
  }

  Widget _sourceLink(Map<String, dynamic> evidence, String key) => Align(
    alignment: Alignment.centerLeft,
    child: ShadButton.link(
      key: ValueKey('profile-source-$key'),
      size: ShadButtonSize.sm,
      padding: EdgeInsets.zero,
      onPressed: () => _showSource(evidence['document_id']?.toString()),
      child: Flexible(
        child: Text(
          '${evidence['source_label'] ?? 'View source evidence'} · ${evidence['section'] ?? 'Source'}',
          maxLines: 2,
          textAlign: TextAlign.left,
          overflow: TextOverflow.ellipsis,
          style: _muted.copyWith(color: DefensysTokens.maroonTextOf(context)),
        ),
      ),
    ),
  );

  Widget _overviewFact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _muted),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    ],
  );

  List<Widget> _overviewContent() {
    final classification = Map<String, dynamic>.from(
      _data!['classification'] as Map? ?? {},
    );
    final profile = Map<String, dynamic>.from(_data!['profile'] as Map? ?? {});
    final description = Map<String, dynamic>.from(
      profile['description'] as Map? ?? {},
    );
    final platforms = explorerRows(profile['platforms']);
    final technologies = explorerRows(classification['technologies']);
    final unresolved =
        classification['status'] == 'unresolved' ||
        classification['label'] == 'Unclassified';
    return [
      Container(
        key: const ValueKey('project-overview'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (_, constraints) {
                final focus = _overviewFact(
                  'Computing focus',
                  '${classification['label'] ?? 'Unclassified'}',
                );
                final domain = _overviewFact(
                  'Application domain',
                  '${classification['domain'] ?? 'Unresolved domain'}',
                );
                return constraints.maxWidth < 460
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [focus, const SizedBox(height: 16), domain],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: focus),
                          const SizedBox(width: 24),
                          Expanded(child: domain),
                        ],
                      );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Document-based estimate · not faculty-reviewed',
              style: _muted,
            ),
          ],
        ),
      ),
      if (unresolved) ...[
        const SizedBox(height: 12),
        WorkflowNotice(
          title: 'Computing focus needs more evidence',
          message:
              '${classification['reason'] ?? 'A supported estimate is not available from the current sources.'}',
        ),
      ],
      _heading(
        description.isEmpty
            ? 'Project context'
            : '${description['section'] ?? 'Document excerpt'}',
      ),
      if (description.isNotEmpty) ...[
        Text('Source excerpt', style: _muted),
        const SizedBox(height: 8),
        SelectableText(
          '${description['text']}',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        if (description['truncated'] == true)
          Text(
            'Excerpt shortened. Open the source document to read the full section.',
            style: _muted,
          ),
      ] else
        Text(
          'No readable background, introduction or abstract section was found in the current sources.',
          style: _muted,
        ),
      const SizedBox(height: 12),
      ..._overviewSourceRows(description['document_id']?.toString()),
      const Divider(height: 28),
      if (platforms.isEmpty && technologies.isEmpty)
        Text(
          'Platform and technologies have not been identified in the available text.',
          style: _muted,
        )
      else ...[
        Text(
          'Technical details',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          platforms.isEmpty
              ? 'Platform has not been identified in the available text.'
              : 'Platform: ${platforms.map((p) => '${p['name']} · ${p['status'] == 'proposed' ? 'proposed' : 'documented'}').join(', ')}',
          style: _muted,
        ),
        const SizedBox(height: 4),
        Text(
          technologies.isEmpty
              ? 'Technology names have not been identified in the available text.'
              : 'Documented technologies: ${technologies.map((t) => t['name']).join(', ')}',
          style: _muted,
        ),
      ],
    ];
  }

  List<Map<String, dynamic>> _overviewDocuments() {
    final documents = explorerRows(
      _data!['documents'],
    ).where((d) => _documentUses(d).isNotEmpty).toList();
    final primary = (_data!['classification'] as Map?)?['document_id'];
    documents.sort(
      (a, b) =>
          (b['id'] == primary ? 1 : 0).compareTo(a['id'] == primary ? 1 : 0),
    );
    return documents;
  }

  String _usageText(List<String> uses) => uses.length < 2
      ? uses.join()
      : '${uses.take(uses.length - 1).join(', ')} and ${uses.last}';

  List<Widget> _overviewSourceRows(String? backgroundId) {
    final documents = _overviewDocuments();
    if (documents.isEmpty) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.link(
            key: const ValueKey('profile-view-evidence'),
            padding: EdgeInsets.zero,
            size: ShadButtonSize.sm,
            onPressed: () => _showSource(null),
            child: const Text('Browse sources'),
          ),
        ),
      ];
    }
    return [
      for (final document in documents)
        Padding(
          key: ValueKey('overview-source-${document['id']}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final caption = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _documentTitle(document),
                    style: _muted.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Used for: ${_usageText(_documentUses(document))}.',
                    style: _muted,
                  ),
                ],
              );
              final action = ShadButton.link(
                key: ValueKey(
                  document['id'] == backgroundId
                      ? 'profile-source-description'
                      : 'profile-source-${document['id']}',
                ),
                padding: EdgeInsets.zero,
                size: ShadButtonSize.sm,
                onPressed: () => _showSource('${document['id']}'),
                child: const Text(
                  'View evidence',
                  style: TextStyle(fontSize: 12),
                ),
              );
              return constraints.maxWidth < 440
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [caption, action],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: caption),
                        const SizedBox(width: 16),
                        action,
                      ],
                    );
            },
          ),
        ),
    ];
  }

  List<Widget> _assessmentsContent() {
    final data = _data!, assessments = explorerRows(data['assessments']);
    final assessment = assessments
        .where((a) => '${a['id']}' == _assessment)
        .firstOrNull;
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
      const SizedBox(height: 14),
      Text(
        'These are recorded evaluator scores and remarks. Project estimates do not change assessment results.',
        style: _muted,
      ),
    ];
  }

  List<Widget> _sourcesContent() {
    final data = _data!;
    final classification = Map<String, dynamic>.from(
      data['classification'] as Map? ?? {},
    );
    final documents = explorerRows(data['documents']);
    final used = _overviewDocuments();
    final additional = documents
        .where((d) => _documentUses(d).isEmpty)
        .toList();
    return [
      Text(
        'Project documents',
        key: _sourcesKey,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text('Current uploads for the selected period.', style: _muted),
      if (documents.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'No suitable project documents are available. Administrative attachments are excluded.',
            style: _muted,
          ),
        ),
      if (used.isNotEmpty) ...[
        _heading('Used in this overview'),
        for (final document in used) _documentRow(document),
      ],
      if (additional.isNotEmpty) ...[
        _heading('Additional documents'),
        for (final document in additional) _documentRow(document),
      ],
      _classificationEvidence(classification),
    ];
  }

  List<String> _documentUses(Map<String, dynamic> document) {
    final id = document['id'];
    final classification = Map<String, dynamic>.from(
      _data!['classification'] as Map? ?? {},
    );
    final profile = Map<String, dynamic>.from(_data!['profile'] as Map? ?? {});
    final description = Map<String, dynamic>.from(
      profile['description'] as Map? ?? {},
    );
    return [
      if (id == classification['document_id']) 'computing focus',
      if (id == description['document_id'])
        '${description['section'] ?? ''}'.toLowerCase().contains('background')
            ? 'background'
            : 'project context',
      if (explorerRows(
        classification['domain_evidence'],
      ).any((e) => e['document_id'] == id))
        'domain',
      if (explorerRows(profile['platforms']).any((p) => p['document_id'] == id))
        'platform',
      if (explorerRows(
        classification['technologies'],
      ).any((t) => t['document_id'] == id))
        'technologies',
    ];
  }

  Widget _documentRow(Map<String, dynamic> document) {
    final id = '${document['id']}';
    final uses = _documentUses(document);
    final selected = id == _selectedSource;
    final expanded = _expandedDetails.contains(id);
    final hasDetails =
        '${document['uploaded_by'] ?? ''}'.trim().isNotEmpty ||
        document['uploaded_at'] != null;
    final metadata = [
      if ('${document['stage'] ?? ''}'.trim().isNotEmpty)
        '${document['stage']}',
      if (document['deliverable_type'] == 'pre') 'Pre-defense',
      if (document['deliverable_type'] == 'post') 'Post-defense',
      if ('${document['status'] ?? ''}'.trim().isNotEmpty)
        '${document['status']}',
    ].join(' · ');
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.fileText,
              size: 18,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _documentTitle(document),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(metadata, style: _muted),
        ],
        if (uses.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Used for: ${_usageText(uses)}.',
            key: ValueKey('source-uses-$id'),
            style: _muted,
          ),
        ],
      ],
    );
    final preview = '${document['url'] ?? ''}'.trim().isEmpty
        ? Text('Source file is unavailable.', style: _muted)
        : ShadButton.outline(
            key: ValueKey('open-source-$id'),
            size: ShadButtonSize.sm,
            leading: _openingDocument == id
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.eye, size: 14),
            onPressed: _openingDocument != null
                ? null
                : () => _openDocument(document),
            child: Text(_openingDocument == id ? 'Opening…' : 'Open'),
          );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasDetails)
          ShadButton.link(
            key: ValueKey('source-details-$id'),
            padding: EdgeInsets.zero,
            size: ShadButtonSize.sm,
            onPressed: () => setState(() {
              if (expanded) {
                _expandedDetails.remove(id);
              } else {
                _expandedDetails.add(id);
              }
            }),
            child: Text(
              expanded ? 'Hide details' : 'Details',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if ('${document['url'] ?? ''}'.trim().isNotEmpty)
          Tooltip(message: 'Open ${_documentTitle(document)}', child: preview)
        else
          preview,
      ],
    );
    return Container(
      key: _sourceKeys.putIfAbsent(id, GlobalKey.new),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Selected source',
                style: _muted.copyWith(
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (_, constraints) => constraints.maxWidth < 440
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [details, const SizedBox(height: 8), actions],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 185,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: actions,
                        ),
                      ),
                    ],
                  ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            if ('${document['uploaded_by'] ?? ''}'.trim().isNotEmpty)
              Text('By ${document['uploaded_by']}', style: _muted),
            if (document['uploaded_at'] != null)
              Text(
                'Uploaded ${_classificationTime(document['uploaded_at'])}',
                style: _muted,
              ),
          ],
          if (_failedDocument == id && _documentError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: WorkflowNotice(
                title: 'Source document could not open',
                message: _documentError!,
                error: true,
              ),
            ),
        ],
      ),
    );
  }

  String _documentTitle(Map<String, dynamic> document) {
    final displayName = '${document['display_name'] ?? ''}'.trim();
    if (displayName.isNotEmpty) return displayName;
    final label = '${document['label'] ?? ''}'.trim();
    final deliverableId = '${document['deliverable_id'] ?? ''}'.trim();
    if (label.isNotEmpty) {
      return deliverableId.isEmpty ? label : '$deliverableId · $label';
    }
    return '${document['file_name'] ?? 'Project document'}';
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    final id = '${document['id']}';
    setState(() {
      _openingDocument = id;
      _failedDocument = null;
      _documentError = null;
    });
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${document['url']}');
      if (!mounted) return;
      setState(() => _openingDocument = null);
      // Keep the real extension so the shared Repository viewer can select
      // the correct preview format, while the source list uses metadata.
      final fileName = '${document['file_name'] ?? ''}'
          .split(RegExp(r'[/\\]'))
          .last;
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName.isEmpty ? _documentTitle(document) : fileName,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _failedDocument = id;
          _documentError =
              '${error.toString().replaceFirst('Exception: ', '')}. Try opening the document again.';
        });
      }
    } finally {
      if (mounted) setState(() => _openingDocument = null);
    }
  }

  Widget _classificationEvidence(Map<String, dynamic> classification) => Column(
    key: const ValueKey('project-classification-explanation'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('About the estimates'),
      Text(
        'Computing focus: ${classification['label'] ?? 'Unclassified'}',
        style: _muted.copyWith(fontWeight: FontWeight.w600),
      ),
      Text(
        'Application domain: ${classification['domain'] ?? 'Unresolved domain'}',
        style: _muted,
      ),
      const SizedBox(height: 8),
      Text('${classification['reason'] ?? ''}', style: _muted),
      ShadAccordion<String>(
        children: [
          if (_classificationPassages(classification).isNotEmpty)
            ShadAccordionItem<String>(
              value: 'classification-evidence',
              title: Text(
                'Supporting passages for the estimates',
                style: _muted,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final passage in _classificationPassages(classification))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${passage['dimension']} · ${passage['section']}',
                            style: _muted.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            '${passage['excerpt']}',
                            style: _muted,
                          ),
                          Text(
                            'Matched terms: ${(passage['terms'] as Set<String>).join(', ')}',
                            style: _muted,
                          ),
                          _sourceLink(
                            passage,
                            'passage-${passage['dimension']}-${passage['section']}-${passage['document_id']}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
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

  List<Map<String, dynamic>> _classificationPassages(
    Map<String, dynamic> classification,
  ) {
    final passages = <String, Map<String, dynamic>>{};
    final evidence = [
      for (final hit in explorerRows(classification['evidence']))
        {
          ...hit,
          'dimension': 'Computing focus',
          'document_id': hit['document_id'] ?? classification['document_id'],
          'source_label': hit['source_label'] ?? classification['source_label'],
        },
      for (final hit in explorerRows(classification['domain_evidence']))
        {...hit, 'dimension': 'Application domain'},
      for (final technology in explorerRows(classification['technologies']))
        for (final hit in explorerRows(technology['evidence']))
          {
            ...hit,
            'dimension': '${technology['name']}',
            'document_id': technology['document_id'],
            'source_label': technology['source_label'],
          },
    ];
    for (final hit in evidence) {
      if ('${hit['excerpt'] ?? ''}'.trim().isEmpty) {
        continue;
      }
      final key =
          '${hit['dimension']}-${hit['document_id']}-${hit['section']}-${hit['excerpt']}';
      final group = passages.putIfAbsent(
        key,
        () => {...hit, 'terms': <String>{}},
      );
      if ('${hit['term'] ?? ''}'.trim().isNotEmpty) {
        (group['terms'] as Set<String>).add('${hit['term']}');
      }
    }
    return passages.values.toList();
  }

  String _classificationTime(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null
        ? 'Unavailable'
        : DateFormat('MMM d, y · h:mm a').format(parsed.toLocal());
  }
}
