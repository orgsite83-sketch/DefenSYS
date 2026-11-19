import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/export/report_export_menu.dart';
import '../../../../widgets/feedback/defensys_skeleton.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/table/defensys_segmented_control.dart';
import '../widgets/defensys_admin_shell.dart';
import 'rubric_full_page_editor.dart';
import 'rubric_library_screen.dart';

int? _id(dynamic value) => int.tryParse('$value');

/// Stage/event navigation and the existing criterion editor share one page.
class RubricEngineScreen extends ConsumerStatefulWidget {
  const RubricEngineScreen({
    super.key,
    this.initialStageId,
    this.initialEvaluationType,
    this.initialLibrary = false,
  });
  final int? initialStageId;
  final String? initialEvaluationType;
  final bool initialLibrary;

  @override
  ConsumerState<RubricEngineScreen> createState() => _RubricEngineScreenState();
}

class _RubricEngineScreenState extends ConsumerState<RubricEngineScreen> {
  static const _labels = {
    'panel': 'Panel',
    'adviser': 'Adviser',
    'peer': 'Peer',
  };
  late final String _scope;
  late bool _library;
  bool _libraryEditor = false;
  bool _loading = true;
  bool _switching = false;
  bool _loadingAssigned = false;
  int? _failedAssignedId;
  int? _destinationId;
  late String _evaluation;
  int _revision = 0;
  String _search = '';
  Map<String, dynamic>? _libraryRubric;
  bool _libraryReadOnly = false;
  String? _editorSessionKey;
  Map<String, dynamic>? _sessionRubric;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _scope =
        user?['is_pit_lead'] == true &&
            user?['role'] != 'admin' &&
            user?['is_superuser'] != true
        ? 'pit'
        : 'capstone';
    _destinationId = widget.initialStageId;
    _evaluation = _labels.containsKey(widget.initialEvaluationType)
        ? widget.initialEvaluationType!
        : 'panel';
    _library = widget.initialLibrary;
    if (_library) {
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(RubricEngineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStageId == widget.initialStageId &&
        oldWidget.initialEvaluationType == widget.initialEvaluationType &&
        oldWidget.initialLibrary == widget.initialLibrary) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await _change(() {
            _destinationId = widget.initialStageId;
            _evaluation = _labels.containsKey(widget.initialEvaluationType)
                ? widget.initialEvaluationType!
                : 'panel';
            _library = widget.initialLibrary;
            _libraryEditor = false;
            _loading = !_library;
          }) &&
          !_library) {
        await _load();
      }
    });
  }

  Future<void> _load() async {
    await ref
        .read(rubricEngineProvider.notifier)
        .fetchRubrics(
          scope: _scope,
          search: '',
          status: '',
          evaluationType: '',
          termContext: _library ? '' : 'active',
        );
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _destinations(RubricEngineState state) =>
      _scope == 'pit'
      ? state.pitEvents
            .where(
              (event) =>
                  _id(event['semester_id']) == _id(state.activeSemester?['id']),
            )
            .toList()
      : state.defenseStages;

  String _destinationLabel(Map<String, dynamic> destination) =>
      (destination[_scope == 'pit' ? 'event_name' : 'label'] ?? 'Untitled')
          .toString();

  Map<String, dynamic> _slot(Map<String, dynamic> destination, String role) {
    final slots = destination['rubric_slots'];
    if (slots is Map && slots[role] is Map) {
      return Map<String, dynamic>.from(slots[role] as Map);
    }
    // Older servers still expose exact event IDs. Do not guess from rubric names.
    final concept = (destination['concept_config'] as Map?)?['enabled'] == true;
    return {
      'required':
          role == 'panel' ||
          (!concept && (role != 'adviser' || _scope != 'pit')),
      'rubric_id': destination['${role}_rubric_id'],
    };
  }

  String _status(Map<String, dynamic> slot) {
    if (slot['required'] != true) return 'Not required';
    if (_id(slot['rubric_id']) == null) return 'Rubric needed';
    return slot['status'] == 'draft' ? 'Draft' : 'Assigned';
  }

  Future<bool> _change(VoidCallback change) async {
    if (_switching || ref.read(rubricEngineProvider).isSaving) return false;
    _switching = true;
    try {
      if (ref.read(unsavedChangesProvider)) {
        final saveDraft = ref.read(unsavedChangesSaveDraftProvider);
        final action = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => DefensysShadcnScope(
            child: ShadDialog(
              constraints: const BoxConstraints(maxWidth: 480),
              title: const Text('Unsaved rubric changes'),
              description: const Text(
                'Save your changes as a draft or discard them before switching.',
              ),
              actions: [
                ShadButton.ghost(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Stay'),
                ),
                ShadButton.outline(
                  onPressed: () => Navigator.pop(dialogContext, 'discard'),
                  child: const Text('Discard'),
                ),
                if (saveDraft != null)
                  ShadButton(
                    backgroundColor: DefensysTokens.maroonOf(context),
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.pop(dialogContext, 'save'),
                    child: const Text('Save draft'),
                  ),
              ],
            ),
          ),
        );
        if (!mounted || action == null) return false;
        if (action == 'save' && (saveDraft == null || !await saveDraft())) {
          return false;
        }
      }
      if (!mounted) return false;
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
      setState(() {
        change();
        _revision++;
        _failedAssignedId = null;
      });
      return true;
    } finally {
      _switching = false;
    }
  }

  Future<void> _showStages() async {
    if (!_library && !_libraryEditor) return;
    if (await _change(() {
      _library = false;
      _libraryEditor = false;
      _loading = true;
    })) {
      await _load();
    }
  }

  Future<void> _showLibrary() async {
    if (_library) return;
    await _change(() {
      _library = true;
      _libraryEditor = false;
    });
  }

  void _openLibraryRubric({
    Map<String, dynamic>? rubric,
    String? initialEvaluationType,
    String? initialScope,
    bool readOnly = false,
  }) {
    _change(() {
      _library = false;
      _libraryEditor = true;
      _libraryRubric = rubric;
      _libraryReadOnly = readOnly || rubric?['is_locked'] == true;
      if (initialEvaluationType != null) _evaluation = initialEvaluationType;
    });
  }

  void _reloadEditor() => setState(() => _revision++);

  Future<void> _fetchAssigned(int rubricId) async {
    final rubric = await ref
        .read(rubricEngineProvider.notifier)
        .fetchSingleRubric(rubricId);
    if (mounted) {
      setState(() {
        _loadingAssigned = false;
        _failedAssignedId = rubric == null ? rubricId : null;
      });
    }
  }

  Widget _header(RubricEngineState state) {
    final semester = state.activeSemester;
    final period =
        semester?['display_name'] ??
        '${semester?['semester'] ?? semester?['label'] ?? 'Semester'}, A.Y. ${semester?['school_year'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefensysPageHeader(
          title: 'Rubrics',
          subtitle:
              '${_scope == 'pit' ? 'PIT' : 'Capstone'} · ${semester == null ? 'No active semester' : period}',
          actions: ReportExportMenu(
            reportId: 'rubrics',
            configureExport: true,
            configureBeforeDownload: true,
            enabled:
                _library ||
                _libraryEditor ||
                (!_loading && _destinationId != null),
            params: _library || _libraryEditor
                ? const {}
                : {
                    'assignment_scope': 'configured',
                    'scope': _scope,
                    'semester_id': semester?['id']?.toString() ?? '',
                    'term_context': '',
                    'search': '',
                    'status': '',
                    'evaluation_type': _evaluation,
                    if (_destinationId != null)
                      _scope == 'pit' ? 'pit_event_config_id' : 'stage_id':
                          '$_destinationId',
                  },
          ),
        ),
        const SizedBox(height: 18),
        _workspaceTabs(state),
        if (_libraryEditor) ...[
          const SizedBox(height: 16),
          Text(
            _libraryRubric?['name']?.toString() ?? 'Create reusable template',
            style: DefensysTokens.sectionTitle.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          ShadButton.outline(
            onPressed: _showLibrary,
            child: const Text('Back to templates & history'),
          ),
        ],
      ],
    );
  }

  Widget _workspaceTabs(RubricEngineState state) {
    final selected = _library || _libraryEditor ? 'library' : 'stages';
    final items = [
      DefensysSegmentItem(
        key: const ValueKey('rubric-workspace-stages'),
        value: 'stages',
        label: _scope == 'pit' ? 'Event rubrics' : 'Stage rubrics',
        icon: Icons.layers_outlined,
      ),
      const DefensysSegmentItem(
        key: ValueKey('rubric-workspace-library'),
        value: 'library',
        label: 'Templates & history',
        icon: Icons.library_books_outlined,
      ),
    ];
    void select(String value) {
      if (value == 'library') {
        _showLibrary();
      } else {
        _showStages();
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (constraints.maxWidth < 420)
            DefensysShadcnScope(
              maroonActions: true,
              neutralActionText: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    Semantics(
                      selected: selected == item.value,
                      child: ShadButton.raw(
                        key: item.key,
                        variant: selected == item.value
                            ? ShadButtonVariant.primary
                            : ShadButtonVariant.outline,
                        enabled: !state.isSaving,
                        onPressed: () => select(item.value),
                        child: Text(item.label),
                      ),
                    ),
                ],
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DefensysSegmentedControl<String>(
                  value: selected,
                  items: items,
                  height: 50,
                  enabled: !state.isSaving,
                  onChanged: select,
                ),
              ],
            ),
          if (widget.initialStageId != null)
            ShadButton.outline(
              enabled: !state.isSaving,
              leading: const Icon(LucideIcons.arrowLeft, size: 16),
              onPressed: () async {
                if (await _change(() {}) && context.mounted) {
                  context.go(
                    AdminRoutes.defenseStageEdit(widget.initialStageId!),
                  );
                }
              },
              child: const Text('Back to stage setup'),
            ),
        ],
      ),
    );
  }

  Widget _destinationNavigation(
    RubricEngineState state,
    Map<String, dynamic> selected,
  ) {
    final destinations = _destinations(state);
    final roles = _scope == 'pit'
        ? ['panel', 'peer']
        : ['panel', 'adviser', 'peer'];
    final disabled = state.isSaving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _scope == 'pit' ? 'PIT event' : 'Defense stage',
          style: DefensysTokens.tableCell.copyWith(
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (destinations.length > 5 || constraints.maxWidth < 560) {
              return ShadSelect<int>.withSearch(
                key: ValueKey('workspace-destination-$_destinationId'),
                initialValue: _destinationId,
                enabled: !disabled,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                searchPlaceholder: const Text('Find stage or event'),
                onSearchChanged: (query) => setState(() => _search = query),
                selectedOptionBuilder: (_, value) => Text(
                  _destinationLabel(selected),
                  overflow: TextOverflow.ellipsis,
                ),
                options: destinations
                    .where(
                      (item) => _destinationLabel(
                        item,
                      ).toLowerCase().contains(_search.toLowerCase()),
                    )
                    .map(
                      (item) => ShadOption(
                        value: _id(item['id'])!,
                        child: Text(_destinationLabel(item)),
                      ),
                    ),
                onChanged: (value) {
                  if (value != null && value != _destinationId) {
                    _selectDestination(value, destinations);
                  }
                },
              );
            }
            final columns = (constraints.maxWidth / 220).floor().clamp(
              1,
              destinations.length,
            );
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in destinations)
                  SizedBox(
                    width: width,
                    child: ShadButton.outline(
                      key: ValueKey('rubric-destination-${item['id']}'),
                      height: 66,
                      enabled: !disabled,
                      decoration: ShadDecoration(
                        border: ShadBorder.all(
                          color: _id(item['id']) == _destinationId
                              ? DefensysTokens.maroonOf(context)
                              : DefensysTokens.borderOf(context),
                        ),
                      ),
                      backgroundColor: _id(item['id']) == _destinationId
                          ? DefensysTokens.surfaceHigherOf(context)
                          : null,
                      onPressed: () {
                        if (_id(item['id']) != _destinationId) {
                          _selectDestination(_id(item['id'])!, destinations);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _destinationLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DefensysTokens.body.copyWith(
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _destinationStatus(item, roles),
                            style: DefensysTokens.caption.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Evaluation type',
          style: DefensysTokens.tableCell.copyWith(
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 560
                ? constraints.maxWidth
                : (constraints.maxWidth - 8 * (roles.length - 1)) /
                      roles.length;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in roles)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      selected: role == _evaluation,
                      child: ShadButton.outline(
                        key: ValueKey('rubric-evaluation-$role'),
                        height: 58,
                        enabled:
                            !disabled &&
                            _slot(selected, role)['required'] == true,
                        decoration: ShadDecoration(
                          border: ShadBorder.all(
                            color: role == _evaluation
                                ? DefensysTokens.maroonOf(context)
                                : DefensysTokens.borderOf(context),
                          ),
                        ),
                        backgroundColor: role == _evaluation
                            ? DefensysTokens.surfaceHigherOf(context)
                            : null,
                        onPressed: () {
                          if (role != _evaluation) {
                            _change(() => _evaluation = role);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _labels[role]!,
                              style: DefensysTokens.body.copyWith(
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            Text(
                              _status(_slot(selected, role)),
                              style: DefensysTokens.caption.copyWith(
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _destinationStatus(
    Map<String, dynamic> destination,
    List<String> roles,
  ) {
    if (destination['is_locked'] == true) return 'Locked';
    final needed = roles.where((role) {
      final slot = _slot(destination, role);
      return slot['required'] == true &&
          (_id(slot['rubric_id']) == null || slot['status'] == 'draft');
    }).length;
    return needed == 0
        ? 'Rubrics assigned'
        : '$needed ${needed == 1 ? 'rubric' : 'rubrics'} needed';
  }

  void _selectDestination(int value, List<Map<String, dynamic>> destinations) {
    _change(() {
      _destinationId = value;
      final selected = destinations.firstWhere(
        (item) => _id(item['id']) == value,
      );
      if (_slot(selected, _evaluation)['required'] != true) {
        _evaluation = 'panel';
      }
    });
  }

  Widget _message(
    RubricEngineState state,
    String title, {
    String? description,
    IconData icon = Icons.quiz_outlined,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
    bool loading = false,
  }) => SingleChildScrollView(
    padding: MediaQuery.sizeOf(context).width < 650
        ? const EdgeInsets.fromLTRB(16, 20, 16, 36)
        : DefensysUi.contentPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(state),
        const SizedBox(height: 24),
        ShadCard(
          padding: EdgeInsets.zero,
          radius: BorderRadius.circular(DefensysTokens.radiusLg),
          backgroundColor: DefensysTokens.surfaceOf(context),
          border: ShadBorder.all(
            color: DefensysTokens.borderOf(context),
            width: 1,
          ),
          child: loading
              ? Semantics(
                  label: title,
                  child: DefensysSkeleton.list(
                    count: 3,
                    rowHeight: 44,
                    padding: const EdgeInsets.all(24),
                  ),
                )
              : DefensysEmptyState(
                  icon: icon,
                  title: title,
                  description: description,
                  actions: onAction != null && actionLabel != null
                      ? ShadButton(
                          backgroundColor: DefensysTokens.maroonOf(context),
                          hoverBackgroundColor: DefensysTokens.isDark(context)
                              ? DefensysTokens.maroonLight
                              : DefensysTokens.maroonDark,
                          foregroundColor: Colors.white,
                          onPressed: onAction,
                          leading: actionIcon == null
                              ? null
                              : Icon(actionIcon, size: 16),
                          child: Text(actionLabel),
                        )
                      : null,
                ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rubricEngineProvider);
    return DefensysShadcnScope(
      child: Builder(
        builder: (context) {
          if (_library) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: DefensysUi.contentPadding.copyWith(bottom: 0),
                  child: _header(state),
                ),
                Expanded(
                  child: RubricLibraryScreen(onOpen: _openLibraryRubric),
                ),
              ],
            );
          }
          if (_loading || (state.isLoading && _destinations(state).isEmpty)) {
            return _message(state, 'Loading rubrics…', loading: true);
          }
          if (_libraryEditor) {
            return RubricFullPageEditor(
              key: ValueKey('library-editor-$_revision'),
              rubric: _libraryRubric,
              initialScope: _scope,
              initialEvaluationType: _evaluation,
              readOnly: _libraryReadOnly,
              workspaceHeader: _header(state),
              onBack: _showLibrary,
              onSaved: _showLibrary,
            );
          }
          if (state.error != null &&
              state.rubrics.isEmpty &&
              _destinations(state).isEmpty) {
            return _message(
              state,
              'Could not load rubric setup',
              description: 'Try again to load your stages and rubrics.',
              icon: Icons.cloud_off_outlined,
              actionLabel: 'Try again',
              actionIcon: LucideIcons.refreshCw,
              onAction: _load,
            );
          }
          if (state.activeSemester == null) {
            return _message(
              state,
              'No active academic period',
              description: _scope == 'pit'
                  ? 'Ask an administrator to activate an academic period, then set up your PIT events.'
                  : 'Activate an academic period in Academic Periods, then configure its defense stages.',
              icon: Icons.calendar_today_outlined,
              actionLabel: _scope == 'pit' ? null : 'Academic Periods',
              actionIcon: LucideIcons.arrowRight,
              onAction: _scope == 'pit'
                  ? null
                  : () => context.go(AdminRoutes.academicPeriods),
            );
          }
          final destinations = _destinations(state);
          if (destinations.isEmpty) {
            return _message(
              state,
              _scope == 'pit'
                  ? 'No PIT events configured'
                  : 'No defense stages available',
              description: _scope == 'pit'
                  ? 'Set up a PIT event for the active academic period, then create or copy its evaluation rubrics here.'
                  : 'Add or publish a defense stage for the active academic period, then create or copy its evaluation rubrics here.',
              icon: _scope == 'pit'
                  ? Icons.event_outlined
                  : Icons.layers_outlined,
              actionLabel: _scope == 'pit'
                  ? 'Set up PIT events'
                  : 'Set up stages',
              actionIcon: LucideIcons.arrowRight,
              onAction: () => context.go(
                _scope == 'pit'
                    ? FacultyRoutes.pitEvents
                    : AdminRoutes.defenseStages,
              ),
            );
          }
          final selected =
              destinations
                  .where((item) => _id(item['id']) == _destinationId)
                  .firstOrNull ??
              destinations.first;
          _destinationId = _id(selected['id']);
          if (_slot(selected, _evaluation)['required'] != true) {
            _evaluation = 'panel';
          }
          final slot = _slot(selected, _evaluation);
          final rubricId = _id(slot['rubric_id']);
          final rubric = state.rubrics
              .where((item) => _id(item['id']) == rubricId)
              .firstOrNull;
          if (rubricId != null && rubric == null) {
            if (!_loadingAssigned && _failedAssignedId != rubricId) {
              _loadingAssigned = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fetchAssigned(rubricId);
              });
            }
            return _message(
              state,
              _failedAssignedId == rubricId
                  ? 'The assigned rubric could not be loaded.'
                  : 'Loading assigned rubric…',
              icon: Icons.cloud_off_outlined,
              loading: _failedAssignedId != rubricId,
              actionLabel: 'Try again',
              actionIcon: LucideIcons.refreshCw,
              onAction: _failedAssignedId == rubricId
                  ? () {
                      setState(() => _failedAssignedId = null);
                    }
                  : null,
            );
          }
          final sessionKey =
              'workspace-$_destinationId-$_evaluation-$_revision';
          if (_editorSessionKey != sessionKey ||
              (!ref.read(unsavedChangesProvider) && !state.isSaving)) {
            _editorSessionKey = sessionKey;
            _sessionRubric = rubric;
          }
          return RubricFullPageEditor(
            key: ValueKey(sessionKey),
            rubric: _sessionRubric,
            initialScope: _scope,
            initialEvaluationType: _evaluation,
            initialDefenseStageId: _scope == 'capstone' ? _destinationId : null,
            initialPitEventId: _scope == 'pit' ? _destinationId : null,
            lockDestination: true,
            readOnly:
                rubric?['is_locked'] == true || selected['is_locked'] == true,
            workspaceHeader: _header(state),
            workspaceStageHeader: _destinationNavigation(state, selected),
            onBack: _reloadEditor,
            onSaved: _reloadEditor,
          );
        },
      ),
    );
  }
}
