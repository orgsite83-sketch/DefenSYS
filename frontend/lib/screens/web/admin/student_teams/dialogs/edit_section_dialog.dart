import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/pit_instructor_provider.dart';
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
    this.onDetailsLoaded,
  });

  final int teamId;
  final String? scope;
  final List<Map<String, dynamic>> sectionOptions;
  final ValueChanged<int>? onSectionChanged;
  final ValueChanged<String>? onImportSectionRoster;
  final VoidCallback? onRosterUpdated;
  final ValueChanged<Map<String, dynamic>>? onDetailsLoaded;

  @override
  ConsumerState<EditSectionDialog> createState() => _EditSectionDialogState();
}

class _EditSectionDialogState extends ConsumerState<EditSectionDialog> {
  final _formKey = GlobalKey<ShadFormState>();
  final _section = TextEditingController();
  final _systemName = TextEditingController();
  String _sectionSearch = '';
  String _managerSearch = '';
  Map<String, dynamic>? _details;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _conceptContexts = [];
  int _managerId = 0;
  bool _loading = true;
  bool _saving = false;
  bool _instructorSaving = false;
  bool _showMobileSections = false;
  bool _choosingInstructor = false;
  int? _instructorAssignmentId;
  int? _facultyId;
  String _facultySearch = '';
  int _activeTab = 0;
  int _loadRevision = 0;
  String? _error;
  bool get _canManageConcepts => _details?['can_manage_concepts'] != false;
  bool get _busy => _saving || _instructorSaving;
  bool get _isPit =>
      _details?['is_pit'] == true ||
      widget.scope == 'pit' ||
      _conceptContexts.any((c) => '${c['key']}'.startsWith('pit:'));

  @override
  void initState() {
    super.initState();
    _showMobileSections = widget.onSectionChanged != null;
    _section.addListener(_fieldChanged);
    _systemName.addListener(_fieldChanged);
    _load();
  }

  void _fieldChanged() {
    if (mounted && !_loading) setState(() {});
  }

  @override
  void didUpdateWidget(covariant EditSectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _activeTab = 0;
      _choosingInstructor = false;
      _load();
    }
  }

  @override
  void dispose() {
    _section.dispose();
    _systemName.dispose();
    _loadRevision++;
    super.dispose();
  }

  Future<void> _load({bool preserveEdits = false}) async {
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _error = null;
      if (!preserveEdits) _details = null;
    });
    try {
      final details = await ref
          .read(studentTeamsProvider.notifier)
          .fetchSectionDetails(widget.teamId);
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _details = details;
        if (!preserveEdits) {
          _section.text = details['section']?.toString() ?? '';
          _systemName.text = details['system_name']?.toString() ?? '';
          _managerId = (details['project_manager_id'] as num?)?.toInt() ?? 0;
          _conceptContexts =
              (jsonDecode(jsonEncode(details['concept_contexts'] ?? []))
                      as List)
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
        }
        _students = (details['students'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
      widget.onDetailsLoaded?.call(details);
    } catch (e) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    if (_busy || !_hasUnsavedChanges) return;
    if (_formKey.currentState?.validate() != true) {
      setState(() => _activeTab = 0);
      return;
    }
    final changes = _conceptChanges;
    var confirmed = false;
    if (changes.isNotEmpty) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => DefensysShadcnScope(
              child: ShadDialog.alert(
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.sizeOf(dialogContext).height - 48,
                ),
                title: const Text('Review concept requirements'),
                description: Text(
                  'Apply the reviewed policies to this section?\n\n${_conceptContexts.where((c) => changes.any((change) => change['context_key'] == c['key'])).map((c) => '${c['label']}: ${(c['teams'] as List).map((t) => t['name']).join(', ')}').join('\n')}\n\nScheduled hearings stay locked. For teams whose requirements change, current concept papers are preserved in history and fresh papers and adviser clearance are required.',
                ),
                actions: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      ShadButton.outline(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Keep editing'),
                      ),
                      ShadButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Apply reviewed changes'),
                      ),
                    ],
                  ),
                ],
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
              const Icon(
                LucideIcons.fileCheck,
                size: 16,
                color: DefensysTokens.maroon,
              ),
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
                  enabled: !_busy && _canManageConcepts,
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
                    enabled: !_busy && _canManageConcepts,
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
            enabled: !_busy && !locked && _canManageConcepts,
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
              enabled: !_busy && !locked && _canManageConcepts,
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
              enabled: !_busy && !locked && _canManageConcepts,
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

  Widget _managerSelect() {
    return LayoutBuilder(
      builder: (_, constraints) => ShadSelect<int>.withSearch(
        key: ValueKey('edit-section-manager-${widget.teamId}-$_managerId'),
        initialValue: _managerId,
        enabled: !_busy,
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

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => DefensysShadcnScope(
            child: ShadDialog.alert(
              title: const Text('Discard unsaved changes?'),
              description: const Text(
                'The changes to this section have not been saved.',
              ),
              actions: [
                ShadButton.outline(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep editing'),
                ),
                ShadButton.destructive(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard changes'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _close() async {
    if (_busy || !await _confirmDiscard() || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _chooseSection(int id) async {
    if (_busy) return;
    if (id != widget.teamId && !await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() => _showMobileSections = false);
    if (id != widget.teamId) widget.onSectionChanged?.call(id);
  }

  void _chooseInstructor([Map? assignment]) {
    setState(() {
      _choosingInstructor = true;
      _facultySearch = '';
      _instructorAssignmentId = (assignment?['id'] as num?)?.toInt();
      _facultyId = (assignment?['faculty_id'] as num?)?.toInt();
    });
  }

  Future<void> _applyInstructor() async {
    if (_busy || _facultyId == null || _details == null) return;
    setState(() {
      _instructorSaving = true;
      _error = null;
    });
    final notifier = ref.read(pitInstructorProvider.notifier);
    final success = _instructorAssignmentId == null
        ? await notifier.assignInstructor(
            facultyId: _facultyId!,
            section: '${_details!['section']}',
            yearLevel: '${_details!['year_level']}',
          )
        : await notifier.replaceInstructor(
            _instructorAssignmentId!,
            _facultyId!,
          );
    if (!mounted) return;
    if (success) {
      await _load(preserveEdits: true);
      if (!mounted) return;
      await ref.read(studentTeamsProvider.notifier).fetchTeams();
      if (!mounted) return;
      widget.onRosterUpdated?.call();
    }
    setState(() {
      _instructorSaving = false;
      if (success) {
        _choosingInstructor = false;
      } else {
        _error =
            ref.read(pitInstructorProvider).error ??
            'Unable to update the instructor.';
      }
    });
  }

  Widget _sectionNavigation() {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final matches = widget.sectionOptions
        .where(
          (s) => '${s['section']} ${s['instructor_name'] ?? ''}'
              .toLowerCase()
              .contains(_sectionSearch),
        )
        .toList();
    return Column(
      key: const Key('section-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sections · ${widget.sectionOptions.length}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ShadInput(
          key: const Key('section-search'),
          leading: const Icon(Icons.search_rounded, size: 17),
          placeholder: const Text('Search sections…'),
          onChanged: (value) =>
              setState(() => _sectionSearch = value.toLowerCase().trim()),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: matches.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No matching sections.',
                    style: TextStyle(color: secondary),
                  ),
                )
              : ListView.separated(
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, index) {
                    final option = matches[index];
                    final selected = option['team_id'] == widget.teamId;
                    final name = '${option['instructor_name'] ?? ''}'.trim();
                    final pit = option['is_pit'] == true;
                    return Material(
                      color: selected
                          ? DefensysTokens.maroonTextOf(
                              context,
                            ).withValues(alpha: 0.09)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: ValueKey('section-option-${option['team_id']}'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: _busy
                            ? null
                            : () => _chooseSection(option['team_id'] as int),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${option['section']}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? DefensysTokens.maroonTextOf(
                                                context,
                                              )
                                            : DefensysTokens.textPrimaryOf(
                                                context,
                                              ),
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: DefensysTokens.maroonTextOf(
                                        context,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${option['year_level']} · ${option['team_count']} ${option['team_count'] == 1 ? 'team' : 'teams'}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: secondary,
                                ),
                              ),
                              if (pit) ...[
                                const SizedBox(height: 7),
                                Text(
                                  name.isEmpty ? 'Needs instructor' : name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: name.isEmpty
                                        ? Theme.of(context).colorScheme.error
                                        : secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _heading(String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      Text(
        description,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _instructorFields() {
    final instructors = (_details?['instructors'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final options = (_details?['instructor_options'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final canManage = _details?['can_manage_instructors'] == true;
    final renamed = _section.text.trim() != '${_details?['section']}';
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Section instructor',
          'The section assignment applies to every PIT team in this class.',
        ),
        if (instructors.isEmpty)
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No instructor assigned',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (canManage)
                TextButton(
                  onPressed: _busy || renamed
                      ? null
                      : () => _chooseInstructor(),
                  child: const Text('Assign'),
                ),
            ],
          ),
        for (final instructor in instructors)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 23,
                  color: DefensysTokens.maroonTextOf(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${instructor['faculty_name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ('${instructor['faculty_email'] ?? ''}'
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        SelectableText(
                          '${instructor['faculty_email']}',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canManage)
                  TextButton(
                    onPressed: _busy || renamed
                        ? null
                        : () => _chooseInstructor(instructor),
                    child: const Text('Change'),
                  ),
              ],
            ),
          ),
        if (canManage && renamed)
          Text(
            'Save the section name before changing its instructor.',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        if (_choosingInstructor) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, box) => ShadSelect<int>.withSearch(
              key: ValueKey(
                'section-instructor-select-$_instructorAssignmentId',
              ),
              initialValue: _facultyId,
              enabled: !_busy,
              minWidth: box.maxWidth,
              maxWidth: box.maxWidth,
              maxHeight: 220,
              placeholder: const Text('Select an instructor'),
              searchPlaceholder: const Text('Search faculty…'),
              onSearchChanged: (query) =>
                  setState(() => _facultySearch = query.toLowerCase().trim()),
              options: [
                for (final faculty in options)
                  if ('${faculty['name']} ${faculty['email']}'
                      .toLowerCase()
                      .contains(_facultySearch))
                    ShadOption<int>(
                      value: (faculty['id'] as num).toInt(),
                      child: Text(
                        '${faculty['name']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              selectedOptionBuilder: (_, id) => Text(
                '${options.where((f) => f['id'] == id).firstOrNull?['name'] ?? 'Select an instructor'}',
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (id) => setState(() => _facultyId = id),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton(
                key: const Key('apply-section-instructor'),
                enabled:
                    !_busy &&
                    _facultyId != null &&
                    !renamed &&
                    !instructors.any(
                      (i) =>
                          i['id'] == _instructorAssignmentId &&
                          i['faculty_id'] == _facultyId,
                    ),
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                onPressed:
                    _busy ||
                        _facultyId == null ||
                        renamed ||
                        instructors.any(
                          (i) =>
                              i['id'] == _instructorAssignmentId &&
                              i['faculty_id'] == _facultyId,
                        )
                    ? null
                    : _applyInstructor,
                child: Text(
                  _instructorSaving
                      ? 'Updating…'
                      : _instructorAssignmentId == null
                      ? 'Assign instructor'
                      : 'Update instructor',
                ),
              ),
              ShadButton.ghost(
                enabled: !_busy,
                onPressed: _busy
                    ? null
                    : () => setState(() => _choosingInstructor = false),
                child: const Text('Keep current'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Changes apply to all ${_details!['team_count']} teams in this section for the current term.',
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 20),
      if (_isPit) ...[
        _instructorFields(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Divider(color: DefensysTokens.borderOf(context)),
        ),
      ],
      ShadInputFormField(
        id: 'section',
        key: const Key('edit-section-name'),
        controller: _section,
        enabled: !_busy,
        maxLength: 80,
        label: const Text('Section name'),
        placeholder: const Text('e.g. BSIT-1B'),
        description: const Text(
          'Also updates student records and instructor assignments.',
        ),
        validator: (value) =>
            value.trim().isEmpty ? 'Enter a section name.' : null,
      ),
    ],
  );

  Future<void> _reviewRoster() async {
    if (_busy || !await _confirmDiscard() || !mounted) return;
    try {
      final saved = await reviewCurrentRoster(
        context,
        ref.read(teamFormationServiceProvider),
        '${_details!['year_level']}',
        '${_details!['section']}',
      );
      if (saved == true && mounted) {
        await _load();
        widget.onRosterUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _importRoster() async {
    if (_busy || !await _confirmDiscard() || !mounted) return;
    final section = '${_details!['section']}';
    Navigator.of(context).pop();
    widget.onImportSectionRoster?.call(section);
  }

  Widget _rosterPanel() {
    final roster = _details!['roster_info'] as Map? ?? {};
    final needsReview = roster['needs_selection'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Section roster',
          _isPit
              ? 'Upcoming events inherit the current roster. Review or import teams for this section.'
              : 'Students linked to the teams and enrollment records in this section.',
        ),
        Text(
          '${_details!['team_count']} teams · ${_details!['student_count'] ?? _students.length} students',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (needsReview) ...[
          ShadAlert(
            icon: const Icon(Icons.info_outline_rounded, size: 18),
            description: const Text(
              'Teams require review before events can be scheduled.',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_isPit && _details!['can_manage_roster'] != false) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton.outline(
                key: const Key('manage-roster-btn'),
                onPressed: _busy ? null : _reviewRoster,
                leading: const Icon(Icons.checklist_rounded, size: 16),
                child: Text(needsReview ? 'Review roster' : 'Manage roster'),
              ),
              if (widget.onImportSectionRoster != null)
                ShadButton.outline(
                  key: const Key('import-roster-btn'),
                  onPressed: _busy ? null : _importRoster,
                  leading: const Icon(Icons.upload_file_rounded, size: 16),
                  child: const Text('Import roster'),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        Divider(color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 12),
        const Text(
          'Students in this section',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_students.isEmpty)
          const Text('No students are linked to this section yet.'),
        for (final student in _students)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${student['name']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${student['username']}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _projectPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Project setup',
        'Set the shared system and student coordinator when this section works on a connected project.',
      ),
      ShadInputFormField(
        id: 'system_name',
        key: const Key('edit-section-system-name'),
        controller: _systemName,
        enabled: !_busy,
        maxLength: 255,
        label: const Text('Shared system name (optional)'),
        placeholder: const Text('Enter the shared system name'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Project manager',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      _managerSelect(),
      const SizedBox(height: 7),
      Text(
        'Choose an active student from this section.',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      if (_conceptContexts.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Divider(color: DefensysTokens.borderOf(context)),
        ),
        for (final c in _conceptContexts.where(
          (c) => c['section_project_id'] != null,
        ))
          TextButton.icon(
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text('${c['label']} system proposals'),
            onPressed: _busy
                ? null
                : () async {
                    if (!await _confirmDiscard() || !mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SectionConceptWorkspace(
                          projectId: c['section_project_id'] as int,
                        ),
                      ),
                    );
                    if (mounted) await _load();
                  },
          ),
        if (_details?['can_setup_shared_system'] == true) ...[
          ShadButton.outline(
            onPressed: _busy
                ? null
                : () async {
                    if (!await _confirmDiscard() || !mounted) return;
                    await openSectionConceptSetup(
                      context,
                      _details!,
                      _isPit ? 'pit' : 'capstone',
                    );
                    if (mounted) await _load();
                  },
            child: const Text('Configure shared system proposals'),
          ),
          const SizedBox(height: 20),
        ],
        _conceptPolicyFields(),
      ],
    ],
  );

  Widget _editorContent(bool narrow) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow && widget.onSectionChanged != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('back-to-sections'),
              onPressed: _busy
                  ? null
                  : () => setState(() => _showMobileSections = true),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Sections'),
            ),
          ),
        if (_details != null) ...[
          Text(
            '${_details!['section']}',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_details!['year_level']} · ${_details!['semester_label']}',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (index, label) in [
                  (0, 'Details'),
                  (1, 'Roster'),
                  (2, 'Project setup'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: TextButton(
                      key: ValueKey('section-tab-$index'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _activeTab = index),
                      style: TextButton.styleFrom(
                        foregroundColor: _activeTab == index
                            ? DefensysTokens.maroonTextOf(context)
                            : secondary,
                        backgroundColor: _activeTab == index
                            ? DefensysTokens.maroonTextOf(
                                context,
                              ).withValues(alpha: 0.08)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _activeTab == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ShadAlert.destructive(description: Text(_error!)),
          ),
        if (!_loading && _details == null)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              onPressed: () => _load(),
              child: const Text('Retry'),
            ),
          ),
        Expanded(
          child: _loading
              ? DefensysLoading.section(
                  height: 160,
                  label: 'Loading section details…',
                )
              : _details == null
              ? const SizedBox.shrink()
              : ShadForm(
                  key: _formKey,
                  child: IndexedStack(
                    index: _activeTab,
                    children: [
                      for (final panel in [
                        _detailsPanel(),
                        _rosterPanel(),
                        _projectPanel(),
                      ])
                        SingleChildScrollView(
                          padding: const EdgeInsets.only(
                            top: 20,
                            bottom: 24,
                            right: 4,
                          ),
                          child: panel,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 800;
    final hasSections = widget.onSectionChanged != null;
    final showList = narrow && hasSections && _showMobileSections;
    final available = size.height - MediaQuery.viewInsetsOf(context).bottom;
    final bodyHeight = (available - (narrow ? 210 : 190)).clamp(160.0, 610.0);
    return PopScope(
      canPop: !_busy && !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: DefensysShadcnScope(
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: hasSections ? 1040 : 760,
            maxHeight: available - 24,
          ),
          padding: EdgeInsets.all(narrow ? 16 : 24),
          closeIcon: const SizedBox.shrink(),
          titlePinned: true,
          actionsPinned: true,
          title: Align(
            alignment: Alignment.centerLeft,
            child: Text(hasSections ? 'Manage sections' : 'Edit section'),
          ),
          description: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'People, rosters and project settings for the current term.',
              textAlign: TextAlign.left,
            ),
          ),
          actions: [
            SizedBox(
              width: (size.width - (narrow ? 32 : 96)).clamp(
                180.0,
                hasSections ? 992.0 : 712.0,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_hasUnsavedChanges)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        'Unsaved changes',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ShadButton.outline(
                    width: narrow && !showList ? 92 : null,
                    enabled: !_busy,
                    onPressed: _busy ? null : _close,
                    child: const Text('Close'),
                  ),
                  if (!showList)
                    ShadButton(
                      key: const Key('save-section-details'),
                      width: narrow ? 136 : null,
                      enabled: !_busy && !_loading && _hasUnsavedChanges,
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      onPressed: _busy || _loading || !_hasUnsavedChanges
                          ? null
                          : _save,
                      child: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                ],
              ),
            ),
          ],
          child: SizedBox(
            width: hasSections ? 992 : 712,
            height: bodyHeight,
            child: !hasSections
                ? _editorContent(narrow)
                : narrow
                ? (showList ? _sectionNavigation() : _editorContent(true))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 238, child: _sectionNavigation()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: VerticalDivider(
                          width: 1,
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                      Expanded(child: _editorContent(false)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
