part of 'curriculum_analytics_screen.dart';

extension _AssessmentDetails on _CurriculumAnalyticsScreenState {
  List<Map<String, dynamic>> _orderedCriteria(
    List<Map<String, dynamic>> rows,
  ) => [...rows]
    ..sort((a, b) {
      final left = explorerNumber(a['score']),
          right = explorerNumber(b['score']);
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return _strongestFirst ? right.compareTo(left) : left.compareTo(right);
    });

  List<String> _availableRoles(
    Map<String, dynamic> data,
    CurriculumExplorerQuery q,
  ) {
    final performance = data['performance'] as Map? ?? {};
    final selected = explorerRows(
      performance['contexts'],
    ).where((r) => r['id'] == q.context).firstOrNull;
    final components = explorerRows(selected?['components']);
    return ['panel', 'peer', if (q.scope == 'capstone') 'adviser']
        .where(
          (role) =>
              components.isEmpty ||
              components.any((r) => r['id'] == role && r['available'] == true),
        )
        .toList();
  }

  Widget _criteriaView(
    List<Map<String, dynamic>> criteria,
    List<Map<String, dynamic>> contexts,
    Map<String, dynamic> data,
    CurriculumExplorerQuery q,
  ) => _card(
    'Performance by criterion',
    'Recorded ${q.role} rubric evidence · ${_strongestFirst ? 'strongest' : 'weakest'} averages first',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (contexts.isNotEmpty)
          LayoutBuilder(
            builder: (_, constraints) => _field(
              q.scope == 'capstone' ? 'Stage' : 'Event',
              {
                for (final c in contexts)
                  '${c['id']}':
                      '${c['label']}${c['semester_label'] != null && q.semester.isEmpty ? ' (${c['semester_label']})' : ''}',
              },
              q.context,
              (value) => _fetch(q.copyWith(context: value, role: 'panel')),
              width: constraints.maxWidth,
            ),
          ),
        const SizedBox(height: 14),
        ShadTabs<String>(
          key: const ValueKey('performance-evaluator-tabs'),
          value: q.role,
          gap: 0,
          scrollable: false,
          onChanged: (role) => _fetch(q.copyWith(role: role)),
          tabs: [
            for (final role in _availableRoles(data, q))
              ShadTab(
                value: role,
                child: Flexible(
                  child: Text(
                    role[0].toUpperCase() + role.substring(1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShadButton.ghost(
            key: const ValueKey('criterion-sort'),
            size: ShadButtonSize.sm,
            leading: const Icon(LucideIcons.arrowDownUp, size: 14),
            onPressed: () => _change(() => _strongestFirst = !_strongestFirst),
            child: Text(_strongestFirst ? 'Strongest first' : 'Weakest first'),
          ),
        ),
        if (criteria.isEmpty)
          _empty(
            'No rubric results for this selection',
            'Choose another period or assessment. Missing scores are kept out of averages.',
          )
        else ...[
          ..._orderedCriteria(criteria).map(
            (c) => CurriculumRankedBar(
              key: ValueKey('criterion-${c['id']}'),
              label: '${c['name']}',
              value: explorerNumber(c['score']),
              reference: q.reference,
              color: CurriculumChartPalette.evaluator(context, q.role),
              caption:
                  '${c['assessed']} / ${c['eligible']} ${c['target_type'] == 'individual' ? 'students' : 'teams'} assessed  |  ${c['semester_label'] ?? ''} / ${c['rubric_name']}',
              onPressed: () => _selectCriterion('${c['id']}'),
            ),
          ),
          const CurriculumPercentAxis(),
          const SizedBox(height: 14),
          Text(
            'Select a criterion to see the teams behind its score.',
            style: _muted,
          ),
        ],
        ShadAccordion<String>(
          children: [
            ShadAccordionItem(
              value: 'reference',
              title: Text(
                'Analysis reference: ${q.reference.toStringAsFixed(0)}%',
                style: _muted,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'An optional analysis target. Changing it does not change recorded grades or passing rules.',
                    style: _muted,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 100,
                        child: ShadInput(
                          controller: _reference,
                          keyboardType: TextInputType.number,
                          placeholder: const Text('0–100'),
                        ),
                      ),
                      ShadButton.outline(
                        onPressed: () {
                          final v = double.tryParse(_reference.text.trim());
                          if (v == null || !v.isFinite || v < 0 || v > 100) {
                            _change(
                              () => _referenceError =
                                  'Enter a number from 0 to 100.',
                            );
                            return;
                          }
                          _change(() => _referenceError = null);
                          _fetch(q.copyWith(reference: v));
                        },
                        child: const Text('Apply reference'),
                      ),
                    ],
                  ),
                  if (_referenceError != null)
                    Text(
                      _referenceError!,
                      style: TextStyle(color: DefensysTokens.dangerText),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _teamView(Map<String, dynamic> c, CurriculumExplorerQuery q) {
    final rows = explorerRows(c['teams']).where((t) {
      if (_teamCategory != null && t['category'] != _teamCategory) return false;
      final score = explorerNumber(t['score']);
      return switch (_filter) {
        'below' => score != null && score < q.reference,
        'meeting' => score != null && score >= q.reference,
        'pending' => score == null,
        _ => true,
      };
    }).toList();
    final score = explorerNumber(c['score']),
        individual = c['target_type'] == 'individual';
    final page = _page.clamp(0, rows.isEmpty ? 0 : (rows.length - 1) ~/ 6);
    return _card(
      '${c['name']} / teams',
      '${score == null ? 'Awaiting assessment' : '${score.toStringAsFixed(1)}% average'} / ${c['below']} of ${c['assessed']} assessed ${individual ? 'students' : 'teams'} below reference',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_teamCategory != null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Project focus: $_teamCategory', style: _muted),
                ShadButton.link(
                  size: ShadButtonSize.sm,
                  onPressed: () => _change(() {
                    _teamCategory = null;
                    _page = 0;
                  }),
                  child: const Text('Show all teams'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                {
                      'all': 'All',
                      'below': 'Below reference',
                      'meeting': 'Meeting reference',
                      'pending': 'Awaiting',
                    }.entries
                    .map(
                      (e) => ShadButton.raw(
                        key: ValueKey('filter-${e.key}'),
                        variant: _filter == e.key
                            ? ShadButtonVariant.secondary
                            : ShadButtonVariant.outline,
                        size: ShadButtonSize.sm,
                        onPressed: () => _change(() {
                          _filter = e.key;
                          _page = 0;
                        }),
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (individual)
            Text(
              'Team bars show the average of assessed members. Open a team for individual student results.',
              style: _muted,
            ),
          if (rows.isEmpty)
            _empty(
              'No teams match this selection',
              'Select another result filter.',
            )
          else
            ...rows
                .skip(page * 6)
                .take(6)
                .map(
                  (t) => CurriculumRankedBar(
                    key: ValueKey('team-${t['id']}'),
                    label: '${t['team_name']}',
                    value: explorerNumber(t['score']),
                    reference: q.reference,
                    caption: individual
                        ? '${t['assessed']} / ${t['eligible']} members assessed'
                        : '${t['project_title']}',
                    onPressed: () => _evidence(t, c),
                  ),
                ),
          const CurriculumPercentAxis(),
          const SizedBox(height: 18),
          _pager(rows.length, page),
          const SizedBox(height: 14),
          Text(
            'Select a team to inspect recorded scores, feedback and project evidence.',
            style: _muted,
          ),
        ],
      ),
    );
  }

  Widget _pager(int count, int page) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 10,
    children: [
      Text(
        '${count == 0 ? 0 : page * 6 + 1}–${((page + 1) * 6).clamp(0, count)} of $count',
        style: _muted,
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: page > 0,
            onPressed: () => _change(() => _page = page - 1),
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: (page + 1) * 6 < count,
            onPressed: () => _change(() => _page = page + 1),
            child: const Text('Next'),
          ),
        ],
      ),
    ],
  );

  Widget _projectRow(Map<String, dynamic> p) => Column(
    children: [
      ShadButton.ghost(
        key: ValueKey('project-${p['id']}'),
        width: double.infinity,
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        mainAxisAlignment: MainAxisAlignment.start,
        onPressed: () => _evidence(p, null),
        child: Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${p['project_title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p['team_name']} · ${p['category'] ?? 'Unclassified'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 17,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
      Divider(height: 1, color: DefensysTokens.borderOf(context)),
    ],
  );

  void _evidence(
    Map<String, dynamic> project,
    Map<String, dynamic>? criterion,
  ) => showShadDialog(
    context: _shadContext ?? context,
    barrierLabel: 'Close project evidence',
    builder: (_) => CurriculumEvidenceDialog(
      project: project,
      criterion: criterion,
      allAssessments: _tab == 'projects',
      initialRole: ref.read(curriculumExplorerProvider).query.role,
    ),
  );
}
