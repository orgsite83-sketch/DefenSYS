import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/defensys_loading.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

class EditSectionDialog extends ConsumerStatefulWidget {
  const EditSectionDialog({
    super.key,
    required this.teamId,
    this.scope,
    this.sectionOptions = const [],
    this.onSectionChanged,
  });

  final int teamId;
  final String? scope;
  final List<Map<String, dynamic>> sectionOptions;
  final ValueChanged<int>? onSectionChanged;

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
  int _managerId = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
              ((_details!['project_manager_id'] as num?)?.toInt() ?? 0));

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
    final secondary = DefensysTokens.textSecondaryOf(context);
    return PopScope(
      canPop: !_saving,
      child: DefensysShadcnScope(
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 600,
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
            width: 552,
            child: _loading
                ? DefensysLoading.section(
                    height: 100,
                    label: 'Loading section details…',
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.onSectionChanged != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Section',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        _sectionSelect(),
                        const SizedBox(height: 16),
                      ],
                      if (_details != null) ...[
                        Text(
                          '${_details!['year_level']} · ${_details!['semester_label']}',
                          style: TextStyle(color: secondary, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Changes apply to all ${_details!['team_count']} teams in this section for this term, including teams hidden by filters.',
                          style: TextStyle(color: secondary, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ShadForm(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShadInputFormField(
                                id: 'section',
                                key: const Key('edit-section-name'),
                                controller: _section,
                                enabled: !_saving,
                                maxLength: 80,
                                label: const Text('Section name'),
                                placeholder: const Text('e.g. BSIT-4B'),
                                description: const Text(
                                  'Also updates student records and instructor assignments.',
                                ),
                                validator: (value) => value.trim().isEmpty
                                    ? 'Enter a section name.'
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              ShadInputFormField(
                                id: 'system_name',
                                key: const Key('edit-section-system-name'),
                                controller: _systemName,
                                enabled: !_saving,
                                maxLength: 255,
                                label: const Text(
                                  'Shared system name (optional)',
                                ),
                                description: const Text(
                                  'For sections building one shared system.',
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Project manager',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              _managerSelect(),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_details == null)
                        ShadButton.ghost(
                          onPressed: _load,
                          leading: const Icon(LucideIcons.refreshCw, size: 16),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
