import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/defensys_loading.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:defensys/widgets/repository/section_concept_setup_dialog.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';

import 'current_roster_dialog.dart';

class EditSectionDialog extends ConsumerStatefulWidget {
  const EditSectionDialog({
    super.key,
    required this.teamId,
    this.scope,
    this.sectionOptions = const [],
    this.onSectionChanged,
    this.onImportSectionRoster,
    this.onRosterUpdated,
  });

  final int teamId;
  final String? scope;
  final List<Map<String, dynamic>> sectionOptions;
  final ValueChanged<int>? onSectionChanged;
  final ValueChanged<String>? onImportSectionRoster;
  final VoidCallback? onRosterUpdated;

  @override
  ConsumerState<EditSectionDialog> createState() => _EditSectionDialogState();
}

class _EditSectionDialogState extends ConsumerState<EditSectionDialog> {
  final _formKey = GlobalKey<ShadFormState>();
  final _section = TextEditingController();
  final _systemName = TextEditingController();
  late final ShadSelectController<int> _sectionPicker;
  String _sectionSearch = '';
  String _managerSearch = '';
  Map<String, dynamic>? _details;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _conceptContexts = [];
  int _managerId = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool get _canManageConcepts => _details?['can_manage_concepts'] != false;

  @override
  void initState() {
    super.initState();
    _sectionPicker = ShadSelectController(initialValue: {widget.teamId});
    _load();
  }

  @override
  void dispose() {
    _section.dispose();
    _systemName.dispose();
    _sectionPicker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await ref
          .read(studentTeamsProvider.notifier)
          .fetchSectionDetails(widget.teamId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _section.text = details['section']?.toString() ?? '';
        _systemName.text = details['system_name']?.toString() ?? '';
        _managerId = (details['project_manager_id'] as num?)?.toInt() ?? 0;
        _conceptContexts =
            (jsonDecode(jsonEncode(details['concept_contexts'] ?? [])) as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
        _students = (details['students'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final changes = _conceptChanges;
    var confirmed = false;
    if (changes.isNotEmpty) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => DefensysShadcnScope(
              child: ShadDialog.alert(
                constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.sizeOf(dialogContext).height - 48),
                title: const Text('Review concept requirements'),
                description: Text(
                  'Apply the reviewed policies to this section?\n\n${_conceptContexts.where((c) => changes.any((change) => change['context_key'] == c['key'])).map((c) => '${c['label']}: ${(c['teams'] as List).map((t) => t['name']).join(', ')}').join('\n')}\n\nScheduled hearings stay locked. For teams whose requirements change, current concept papers are preserved in history and fresh papers and adviser clearance are required.',
                ),
                actions: [Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Keep editing'),
                  ),
                  ShadButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Apply reviewed changes'),
                  ),
                ])],
              ),
            ),
          ) ??
          false;
      if (!mounted || !confirmed) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final success = await ref
        .read(studentTeamsProvider.notifier)
        .updateSectionDetails(widget.teamId, {
          'expected_section': _details!['section'],
          'section': _section.text.trim(),
          'system_name': _systemName.text.trim(),
          'project_manager_id': _managerId == 0 ? null : _managerId,
          if (changes.isNotEmpty) 'concept_policy_changes': changes,
          if (changes.isNotEmpty) 'confirm_concept_changes': confirmed,
        }, scope: widget.scope);
    if (!mounted) return;
    if (success) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error =
          ref.read(studentTeamsProvider).error ??
          'Unable to save section details.';
    });
  }

  bool get _hasUnsavedChanges =>
      _details != null &&
      (_section.text.trim() != '${_details!['section']}' ||
          _systemName.text.trim() !=
              (_details!['system_name']?.toString() ?? '') ||
          _managerId !=
              ((_details!['project_manager_id'] as num?)?.toInt() ?? 0) ||
          _conceptChanges.isNotEmpty);

  List<Map<String, dynamic>> get _conceptChanges {
    final original = (_details?['concept_contexts'] as List? ?? []);
    return [
      for (final c in _conceptContexts)
        if (jsonEncode(c) !=
            jsonEncode(original.where((o) => o['key'] == c['key']).firstOrNull))
          {
            'context_key': c['key'],
            'section_policy': c['policy'],
            'team_policies': [
              for (final t in c['teams'] as List)
                {'team_id': t['id'], 'policy': t['override']},
            ],
          },
    ];
  }

  Widget _conceptPolicyFields() {
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.fileCheck, size: 16, color: DefensysTokens.maroon),
              const SizedBox(width: 8),
              const Text(
                'Concept requirements',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Automatic uses the saved import: assigned projects/modules need one concept; unassigned teams use the stage default.',
            style: TextStyle(color: secondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final c in _conceptContexts)
            ExpansionTile(
              key: ValueKey('concept-policy-${c['key']}'),
              tilePadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text('${c['label']}'),
              children: [
                WorkflowChoice(
                  value: '${c['policy']['mode'] ?? 'auto'}',
                  enabled: !_saving && _canManageConcepts,
                  options: const {
                    'auto': 'Automatic from import',
                    'proposals': 'Require multiple proposals',
                    'assigned': 'Use one assigned concept',
                  },
                  onChanged: (mode) => setState(
                    () => c['policy'] = {
                      'mode': mode,
                      if (mode == 'proposals') 'required_count': 3,
                    },
                  ),
                ),
                if (c['policy']['mode'] == 'proposals') ...[
                  const SizedBox(height: 8),
                  WorkflowChoice(
                    value: '${c['policy']['required_count'] ?? 3}',
                    enabled: !_saving && _canManageConcepts,
                    options: {
                      for (var i = 1; i <= 10; i++)
                        '$i': '$i concept${i == 1 ? '' : 's'}',
                    },
                    onChanged: (value) => setState(
                      () => c['policy']['required_count'] = int.parse(value),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final raw in c['teams'] as List)
                  _teamConceptFields(c, raw as Map),
              ],
            ),
        ],
      ),
    );
  }

  Widget _teamConceptFields(Map<String, dynamic> contextPolicy, Map team) {
    final override = team['override'] as Map;
    final mode = override['mode'] ?? 'auto';
    final assigned =
        mode == 'assigned' ||
        (mode == 'auto' && contextPolicy['policy']['mode'] == 'assigned');
    final locked = team['locked'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${team['name']}${locked ? ' · Hearing locked' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            'Current: ${team['effective_policy']['required_count']} concept(s)${team['effective_policy']['mode'] == 'assigned' ? ' · ${team['effective_policy']['assigned_title']}' : ''}',
            style: TextStyle(
              color: DefensysTokens.textSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          WorkflowChoice(
            value: '$mode',
            enabled: !_saving && !locked && _canManageConcepts,
            options: const {
              'auto': 'Follow section / import',
                'proposals': 'Multiple proposals',
                'assigned': 'One assigned concept',
            },
            onChanged: (value) => setState(
              () => team['override'] = {
                'mode': value,
                if (value == 'proposals') 'required_count': 3,
                if (value == 'assigned')
                  'assigned_title':
                      team['effective_policy']['assigned_title'] ?? '',
              },
            ),
          ),
          if (mode == 'proposals') ...[
            const SizedBox(height: 6),
            WorkflowChoice(
              value: '${override['required_count'] ?? 3}',
              enabled: !_saving && !locked && _canManageConcepts,
              options: {
                for (var i = 1; i <= 10; i++)
                  '$i': '$i concept${i == 1 ? '' : 's'}',
              },
              onChanged: (value) =>
                  setState(() => override['required_count'] = int.parse(value)),
            ),
          ],
          if (assigned) ...[
            const SizedBox(height: 6),
            ShadInput(
              key: ValueKey('assignment-${contextPolicy['key']}-${team['id']}'),
              initialValue:
                  '${override['assigned_title'] ?? team['effective_policy']['assigned_title'] ?? ''}',
              enabled: !_saving && !locked && _canManageConcepts,
              placeholder: const Text('Assigned project / module title'),
              onChanged: (value) => setState(
                () => team['override'] = {
                  'mode': 'assigned',
                  'assigned_title': value,
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectSection(int? id) async {
    if (id == null || id == widget.teamId || _saving) return;
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DefensysShadcnScope(
          child: ShadDialog.alert(
            title: const Text('Discard unsaved changes?'),
            description: const Text(
              'The changes to this section have not been saved.',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (discard != true) {
        _sectionPicker.value = {widget.teamId};
        return;
      }
    }
    if (mounted) widget.onSectionChanged?.call(id);
  }

  Widget _sectionSelect() => LayoutBuilder(
    builder: (_, constraints) => ShadSelect<int>.withSearch(
      key: const Key('section-picker'),
      controller: _sectionPicker,
      enabled: !_saving,
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
      maxHeight: 250,
      clearSearchOnClose: true,
      searchPlaceholder: const Text('Search sections…'),
      onSearchChanged: (query) =>
          setState(() => _sectionSearch = query.toLowerCase().trim()),
      options: widget.sectionOptions
          .where(
            (option) =>
                '${option['label']}'.toLowerCase().contains(_sectionSearch),
          )
          .map(
            (option) => ShadOption<int>(
              value: option['team_id'] as int,
              child: Text(
                '${option['label']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      selectedOptionBuilder: (_, id) => Text(
        '${widget.sectionOptions.firstWhere((option) => option['team_id'] == id)['label']}',
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: _selectSection,
    ),
  );

  Widget _managerSelect() {
    return LayoutBuilder(
      builder: (_, constraints) => ShadSelect<int>.withSearch(
        key: ValueKey('edit-section-manager-${widget.teamId}-$_managerId'),
        initialValue: _managerId,
        enabled: !_saving,
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
        maxHeight: 220,
        clearSearchOnClose: true,
        searchPlaceholder: const Text('Search students by name or ID…'),
        onSearchChanged: (query) =>
            setState(() => _managerSearch = query.toLowerCase().trim()),
        options: [
          const ShadOption(value: 0, child: Text('Unassigned')),
          for (final student in _students)
            if ('${student['name']} ${student['username']}'
                .toLowerCase()
                .contains(_managerSearch))
              ShadOption<int>(
                value: (student['id'] as num).toInt(),
                child: Text(
                  '${student['name']} (${student['username']})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
        selectedOptionBuilder: (_, id) {
          final student = _students
              .where((student) => student['id'] == id)
              .firstOrNull;
          return Text(
            id == 0
                ? 'Unassigned'
                : student == null
                ? '${_details!['project_manager_name'] ?? 'Current manager'} (unavailable)'
                : '${student['name']} (${student['username']})',
            overflow: TextOverflow.ellipsis,
          );
        },
        onChanged: (id) => setState(() => _managerId = id ?? 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = DefensysTokens.textSecondaryOf(context);
    final cardBg = isDark ? DefensysTokens.mistSurface : Colors.white;
    final cardBorder = isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
    final bannerBg = isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);

    return PopScope(
      canPop: !_saving,
      child: DefensysShadcnScope(
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight:
                MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                48,
          ),
          closeIcon: const SizedBox.shrink(),
          titlePinned: true,
          actionsPinned: true,
          title: Text(
            widget.onSectionChanged == null
                ? 'Edit section'
                : 'Manage sections',
          ),
          description: const Text(
            'Update section details for the current term.',
          ),
          actions: [
            ShadButton.outline(
              enabled: !_saving,
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ShadButton(
              key: const Key('save-section-details'),
              onPressed: _loading || _saving || _details == null ? null : _save,
              enabled: !_loading && !_saving && _details != null,
              child: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ],
          child: SizedBox(
            width: 572,
            child: _loading
                ? DefensysLoading.section(
                    height: 120,
                    label: 'Loading section details…',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onSectionChanged != null || _details != null) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: bannerBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorder),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.onSectionChanged != null) ...[
                                  Row(
                                    children: [
                                      Icon(LucideIcons.layers, size: 14, color: secondary),
                                      const SizedBox(width: 6),
                                      Text(
                                        'ACTIVE SECTION',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                          color: secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _sectionSelect(),
                                  const SizedBox(height: 12),
                                ],
                                if (_details != null) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      ShadBadge.secondary(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(LucideIcons.graduationCap, size: 13),
                                            const SizedBox(width: 5),
                                            Text('${_details!['year_level']}'),
                                          ],
                                        ),
                                      ),
                                      ShadBadge.secondary(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(LucideIcons.calendar, size: 13),
                                            const SizedBox(width: 5),
                                            Text('${_details!['semester_label']}'),
                                          ],
                                        ),
                                      ),
                                      ShadBadge.outline(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(LucideIcons.users, size: 13),
                                            const SizedBox(width: 5),
                                            Text('${_details!['team_count']} teams enrolled'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(LucideIcons.info, size: 14, color: secondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Changes apply to all ${_details!['team_count']} teams in this section for this term, including teams hidden by filters.',
                                          style: TextStyle(
                                            color: secondary,
                                            fontSize: 12,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_details != null) ...[
                          ShadForm(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(LucideIcons.fileText, size: 16, color: DefensysTokens.maroon),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Section Information',
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Configure the official section identifier and umbrella system naming.',
                                        style: TextStyle(color: secondary, fontSize: 12),
                                      ),
                                      const SizedBox(height: 16),
                                      ShadInputFormField(
                                        id: 'section',
                                        key: const Key('edit-section-name'),
                                        controller: _section,
                                        enabled: !_saving,
                                        maxLength: 80,
                                        leading: const Icon(LucideIcons.hash, size: 16),
                                        label: const Text('Section name'),
                                        placeholder: const Text('e.g. BSIT-4B'),
                                        description: const Text(
                                          'Also updates student records and instructor assignments.',
                                        ),
                                        validator: (value) => value.trim().isEmpty
                                            ? 'Enter a section name.'
                                            : null,
                                      ),
                                      const SizedBox(height: 16),
                                      ShadInputFormField(
                                        id: 'system_name',
                                        key: const Key('edit-section-system-name'),
                                        controller: _systemName,
                                        enabled: !_saving,
                                        maxLength: 255,
                                        leading: const Icon(LucideIcons.layoutGrid, size: 16),
                                        label: const Text(
                                          'Shared system name (optional)',
                                        ),
                                        description: const Text(
                                          'For sections building one shared system.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(LucideIcons.userCheck, size: 16, color: DefensysTokens.maroon),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Project Management',
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Designate a lead student to oversee section deliverables and coordination.',
                                        style: TextStyle(color: secondary, fontSize: 12),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Project manager',
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      const SizedBox(height: 8),
                                      _managerSelect(),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Grants student coordinator privileges to manage section repositories.',
                                        style: TextStyle(fontSize: 12, color: secondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_details?['is_pit'] == true ||
                                    widget.scope == 'pit' ||
                                    _conceptContexts.any((c) => c['key'].toString().startsWith('pit:'))) ...[
                                  const SizedBox(height: 16),
                                  Builder(
                                    builder: (context) {
                                      final roster = _details!['roster_info'] as Map<String, dynamic>? ?? {};
                                      final needsSelection = roster['needs_selection'] == true;
                                      final teamCount = _details!['team_count'] ?? 0;
                                      final canManage = _details!['can_manage_roster'] != false;

                                      return Container(
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: cardBorder),
                                        ),
                                        padding: const EdgeInsets.all(18),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(LucideIcons.users, size: 16, color: DefensysTokens.maroon),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  'Team Roster',
                                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Manage the active team membership for this section. Unstarted events inherit these teams automatically.',
                                              style: TextStyle(color: secondary, fontSize: 12),
                                            ),
                                            const SizedBox(height: 14),
                                            if (needsSelection) ...[
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 12),
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFEF3C7),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF92400E)),
                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'Teams require review before events can be scheduled.',
                                                        style: TextStyle(color: Color(0xFF92400E), fontSize: 12, fontWeight: FontWeight.w600),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '$teamCount ${teamCount == 1 ? 'team' : 'teams'} currently assigned to this section',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                      color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF4B5563),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (canManage) ...[
                                              const SizedBox(height: 12),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  OutlinedButton.icon(
                                                    key: const Key('manage-roster-btn'),
                                                    icon: Icon(
                                                      Icons.checklist_rounded,
                                                      size: 15,
                                                      color: DefensysTokens.maroonTextOf(context),
                                                    ),
                                                    label: Text(
                                                      needsSelection ? 'Review Roster (Action Required)' : 'Review / Manage Roster',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: DefensysTokens.maroonTextOf(context),
                                                      ),
                                                    ),
                                                    style: OutlinedButton.styleFrom(
                                                      side: BorderSide(color: DefensysTokens.maroonTextOf(context).withValues(alpha: 0.4)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: _saving
                                                        ? null
                                                        : () async {
                                                            final year = '${_details!['year_level']}';
                                                            final sec = _section.text.trim();
                                                            try {
                                                              final saved = await reviewCurrentRoster(
                                                                context,
                                                                ref.read(teamFormationServiceProvider),
                                                                year,
                                                                sec,
                                                              );
                                                              if (saved == true && mounted) {
                                                                await _load();
                                                                widget.onRosterUpdated?.call();
                                                              }
                                                            } catch (e) {
                                                              if (mounted) {
                                                                setState(() {
                                                                  _error = e.toString().replaceFirst('Exception: ', '');
                                                                });
                                                              }
                                                            }
                                                          },
                                                  ),
                                                  if (widget.onImportSectionRoster != null)
                                                    OutlinedButton.icon(
                                                      key: const Key('import-roster-btn'),
                                                      icon: Icon(
                                                        Icons.upload_file_rounded,
                                                        size: 15,
                                                        color: isDark ? DefensysTokens.textPrimaryDark : DefensysTokens.textPrimary,
                                                      ),
                                                      label: Text(
                                                        'Import Section Roster',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? DefensysTokens.textPrimaryDark : DefensysTokens.textPrimary,
                                                        ),
                                                      ),
                                                      style: OutlinedButton.styleFrom(
                                                        side: BorderSide(color: cardBorder),
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                      ),
                                                      onPressed: _saving
                                                          ? null
                                                          : () {
                                                              final sec = _section.text.trim();
                                                              Navigator.of(context).pop();
                                                              widget.onImportSectionRoster!(sec);
                                                            },
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                if (_conceptContexts.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  for (final c in _conceptContexts.where((c) => c['section_project_id'] != null))
                                    TextButton.icon(icon: const Icon(Icons.account_tree_outlined),
                                      label: Text('${c['label']} system proposals'),
                                      onPressed: () async {
                                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                                          SectionConceptWorkspace(projectId: c['section_project_id'] as int)));
                                        if (mounted) await _load();
                                      }),
                                  if (_details?['can_setup_shared_system'] == true)
                                    OutlinedButton.icon(icon: const Icon(Icons.account_tree_outlined),
                                      onPressed: _saving ? null : () async {
                                        await openSectionConceptSetup(context, _details!, widget.scope ??
                                          (_conceptContexts.first['key'].toString().startsWith('pit:') ? 'pit' : 'capstone'));
                                        if (mounted) await _load();
                                      }, label: const Text('Configure shared system proposals')),
                                  const SizedBox(height: 16),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: cardBorder),
                                    ),
                                    padding: const EdgeInsets.all(18),
                                    child: _conceptPolicyFields(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          ShadAlert.destructive(
                            icon: const Icon(LucideIcons.alertCircle, size: 16),
                            description: Text(_error!),
                          ),
                        ],
                        if (_details == null && !_loading) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: ShadButton.ghost(
                              onPressed: _load,
                              leading: const Icon(LucideIcons.refreshCw, size: 16),
                              child: const Text('Retry'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
