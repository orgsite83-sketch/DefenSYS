import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/api_config.dart';
import '../../services/auth_provider.dart';
import '../../services/academic_period_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../services/reports_provider.dart';
import '../../toasts/feedback_toast.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'defensys_export_dialog.dart';
import 'defensys_export_models.dart';
import 'report_catalog.dart';
import 'report_navigation.dart';
import 'report_settings_section.dart';
import 'rubric_export_filters.dart';

Future<bool?> showReportExportConfiguration({
  required BuildContext context,
  required WidgetRef ref,
  required ReportDefinition report,
  Map<String, String> params = const {},
  String initialFormat = 'pdf',
  bool simplified = false,
  ValueChanged<Map<String, String>>? onParamsChanged,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final content = ReportExportWorkspace(
        report: report,
        params: params,
        initialFormat: initialFormat,
        simplified: simplified,
        onParamsChanged: onParamsChanged,
      );
      if (!report.id.endsWith('grade-masterlist')) return content;
      final neutral = DefensysTokens.surfaceHigherOf(dialogContext);
      return Theme(
        data: Theme.of(dialogContext).copyWith(
          hoverColor: neutral,
          focusColor: neutral,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          colorScheme: Theme.of(dialogContext).colorScheme.copyWith(
            primary: DefensysTokens.maroonOf(dialogContext),
            primaryContainer: neutral,
            secondary: DefensysTokens.saveActionBg,
            secondaryContainer: neutral,
          ),
        ),
        child: DefensysShadcnScope(child: content),
      );
    },
  );
}

class ReportExportWorkspace extends ConsumerStatefulWidget {
  const ReportExportWorkspace({
    super.key,
    required this.report,
    this.params = const {},
    this.initialFormat = 'pdf',
    this.embedded = false,
    this.simplified = false,
    this.onParamsChanged,
  });
  final ReportDefinition report;
  final Map<String, String> params;
  final String initialFormat;
  final bool embedded;
  final bool simplified;
  final ValueChanged<Map<String, String>>? onParamsChanged;
  @override
  ConsumerState<ReportExportWorkspace> createState() =>
      _ReportConfigurationState();
}

class _ReportConfigurationState extends ConsumerState<ReportExportWorkspace> {
  Map<String, dynamic> _options = {};
  String? _optionsError;
  bool _loadingOptions = true;
  bool _loadingCandidates = false;
  int _candidateRequest = 0;
  int _previewVersion = 0;
  Map<String, String> _recordParams = {};
  bool get _guided => widget.embedded || widget.simplified;

  bool get _individual =>
      const ['team-grade', 'individual-grade'].contains(widget.report.id);

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse('${ApiConfig.baseUrl}/reports/catalog-options/').replace(
              queryParameters: {...widget.params, 'report': widget.report.id},
            ),
          );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Unable to load report selections.');
      }
      if (!mounted) return;
      _options = Map<String, dynamic>.from(data);
      _optionsError = null;
      if (_recordParams.isEmpty) _recordParams = _scoped(widget.params);
      if (_guided && _individual) await _loadCandidates(_recordParams);
      if (mounted) {
        setState(() {
          _loadingOptions = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _optionsError = error.toString().replaceFirst('Exception: ', '');
          _loadingOptions = false;
        });
      }
    }
  }

  Future<void> _loadCandidates(Map<String, String> params) async {
    final request = ++_candidateRequest;
    final candidates = await ref
        .read(reportsProvider.notifier)
        .fetchAssessmentCandidates(params);
    if (!mounted || request != _candidateRequest) return;
    if (candidates == null) {
      setState(() {
        _loadingCandidates = false;
        _optionsError = 'Unable to load the available students and teams.';
        _options = {..._options, 'teams': [], 'students': []};
      });
      return;
    }
    final teams = (candidates['teams'] as List? ?? [])
        .whereType<Map>()
        .where(
          (team) =>
              ((params['year_level'] ?? '').isEmpty ||
                  team['year_level'] == params['year_level']) &&
              ((params['section'] ?? '').isEmpty ||
                  team['section'] == params['section']),
        )
        .toList();
    final teamIds = teams.map((team) => team['id'].toString()).toSet();
    final contexts = candidates['student_contexts'] as Map? ?? {};
    final students = (candidates['students'] as List? ?? [])
        .whereType<Map>()
        .where((student) {
          final context = contexts[student['id'].toString()] as Map?;
          if (context == null) {
            return (params['year_level'] ?? '').isEmpty &&
                (params['section'] ?? '').isEmpty;
          }
          return (context['contexts'] as List? ?? []).whereType<Map>().any(
            (item) =>
                teamIds.contains((item['team'] as Map?)?['id'].toString()),
          );
        });
    setState(() {
      _loadingCandidates = false;
      _optionsError = null;
      _options = {
        ..._options,
        'teams': [
          for (final team in teams)
            {
              ...team,
              'label': '${team['name']} — ${team['project_title'] ?? ''}',
            },
        ],
        'students': [
          for (final student in students)
            {
              ...student,
              'label':
                  student['name'] ??
                  '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
                      .trim(),
            },
        ],
      };
    });
  }

  void _recordsChanged(Map<String, String> values) {
    final next = _scoped(values);
    final contextChanged = const [
      'scope',
      'semester_id',
      'year_level',
      'section',
    ].any((key) => next[key] != _recordParams[key]);
    final targetChanged = const [
      'team_id',
      'student_id',
    ].any((key) => next[key] != _recordParams[key]);
    _recordParams = next;
    if (_guided && _individual && (contextChanged || targetChanged)) {
      _previewVersion++;
      setState(() {
        _options = {..._options, 'assessments': []};
      });
      if (contextChanged) {
        setState(() => _loadingCandidates = true);
        _loadCandidates(next);
      }
    }
    widget.onParamsChanged?.call(values);
  }

  Map<String, String> _scoped(Map<String, String> values) {
    final params = Map<String, String>.from(values)
      ..removeWhere(
        (key, value) =>
            value.isEmpty ||
            value == 'ALL' ||
            (value == 'all' && key != 'coverage' && key != 'term_context'),
      );
    if (widget.report.scope.isNotEmpty) params['scope'] = widget.report.scope;
    if (widget.report.id.endsWith('grade-masterlist')) {
      params.putIfAbsent('scope', () => 'capstone');
      params.putIfAbsent(
        'coverage',
        () =>
            _guided &&
                !const [
                  'stage_id',
                  'defense_stage_id',
                  'pit_event_config_id',
                  'stage_label',
                ].any((key) => (params[key] ?? '').isNotEmpty)
            ? 'semester'
            : 'assessment',
      );
      params.putIfAbsent('detail_level', () => 'summary');
    }
    if (params['coverage'] != 'specific') params.remove('grade_id');
    final user = ref.read(authProvider).user;
    if (_guided) {
      if (widget.report.filters.contains('semester_id') &&
          !values.containsKey('semester_id')) {
        final active =
            ref.read(academicPeriodProvider).activeSemester?['id'] ??
            _options['default_semester_id'];
        if (active != null) params['semester_id'] = active.toString();
      }
      if ((widget.report.filters.contains('scope') ||
              widget.report.filters.contains('type')) &&
          !values.containsKey('scope') &&
          !values.containsKey('type') &&
          widget.report.scope.isEmpty) {
        final pit =
            user?['is_pit_lead'] == true || user?['is_pit_instructor'] == true;
        params[widget.report.filters.contains('scope') ? 'scope' : 'type'] = pit
            ? 'pit'
            : 'capstone';
      }
      if (_individual) params.putIfAbsent('coverage', () => 'latest');
    }
    if (user?['is_pit_lead'] == true &&
        user?['role'] != 'admin' &&
        user?['is_superuser'] != true) {
      params['scope'] = 'pit';
      params['year_level'] = user?['pit_lead_year']?.toString() ?? '';
      if (widget.report.id == 'project-records') params['type'] = 'pit';
    }
    return params;
  }

  String? _missingSelection(Map<String, String> values) {
    final params = _scoped(values);
    final missing = widget.report.missingSelection(params);
    if (missing != null) return missing;
    if (_guided &&
        widget.report.id.endsWith('grade-masterlist') &&
        params['coverage'] == 'assessment' &&
        !const [
          'stage_id',
          'defense_stage_id',
          'pit_event_config_id',
          'stage_label',
        ].any((key) => (params[key] ?? '').isNotEmpty)) {
      return 'Choose a stage or PIT event to preview this report.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final user = ref.read(authProvider).user;
    final assignedRubrics =
        report.id == 'rubrics' &&
        widget.params['assignment_scope'] == 'configured';
    if (_guided && _loadingOptions) {
      return _statusPanel(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading report selections…'),
            ],
          ),
        ),
      );
    }
    if (_guided && _optionsError != null && !_individual) {
      return _statusPanel(
        DefensysShadcnScope(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_optionsError!),
              const SizedBox(height: 12),
              ShadButton.outline(
                onPressed: _loadOptions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return DefensysShadcnScope(
      child: DefensysExportDialog(
        embedded: widget.embedded,
        simplified: widget.simplified,
        onParamsChanged: _recordsChanged,
        config: DefensysExportConfig(
          title: assignedRubrics
              ? 'Export rubrics'
              : _guided
              ? ReportNavigation.title(report)
              : report.title,
          subtitle: assignedRubrics
              ? 'Saved rubric criteria for the selected stages and evaluation types.'
              : report.description,
          tag: report.category,
          icon: report.icon,
          defaultFilename:
              'DefenSYS_${report.id}_${DateTime.now().toIso8601String().substring(0, 10)}',
          initialFormat: widget.initialFormat,
          initialSignatories: _guided
              ? [
                  DefensysSignatory(
                    label: 'Prepared by:',
                    name:
                        '${user?['first_name'] ?? ''} ${user?['last_name'] ?? ''}'
                            .trim(),
                    role: user?['role'] == 'admin'
                        ? 'Administrator'
                        : 'Faculty',
                  ),
                  const DefensysSignatory(
                    label: 'Noted by:',
                    name: '',
                    role: 'Project Adviser / Panel Chair',
                  ),
                  const DefensysSignatory(
                    label: 'Approved by:',
                    name: '',
                    role: 'IT Program Chairperson',
                  ),
                ]
              : const [],
          formatsForParams: report.id == 'concept-projects'
              ? (params) => params['layout'] == 'roster'
                    ? const ['xlsx']
                    : const ['pdf', 'xlsx']
              : null,
          initialParams: _scoped(widget.params),
          selectionHint: _missingSelection,
          previewError: () => ref.read(reportsProvider).error,
          leftPaneWidth: 380,
          leftPaneBuilder: (_, params, update, refresh) =>
              report.id == 'rubrics' &&
                  params['assignment_scope'] == 'configured'
              ? RubricExportFilters(
                  params: params,
                  options: _options,
                  loading: _loadingOptions,
                  error: _optionsError,
                  onChanged: update,
                  onRetry: _loadOptions,
                )
              : _ReportFilters(
                  report: report,
                  compact: _guided,
                  params: params,
                  options: _options,
                  loading: _loadingOptions || _loadingCandidates,
                  error: _optionsError,
                  onChanged: update,
                  onReset: () => update(_scoped({})),
                  onRetry: _loadOptions,
                  pitLead:
                      ref.read(authProvider).user?['is_pit_lead'] == true &&
                      ref.read(authProvider).user?['role'] != 'admin' &&
                      ref.read(authProvider).user?['is_superuser'] != true,
                ),
          onFetchPreview: (values) async {
            final params = _scoped(values);
            if (_missingSelection(params) != null) return null;
            final version = ++_previewVersion;
            final preview = await ref
                .read(reportsProvider.notifier)
                .fetchReportPreview(
                  endpoint: report.endpointFor(params),
                  queryParams: params,
                );
            if (mounted &&
                version == _previewVersion &&
                _individual &&
                preview != null) {
              setState(() {
                _options = {..._options, 'assessments': preview.assessments};
              });
            }
            return preview;
          },
          onDownload: (values, format, signatories, includeSignatures) async {
            final params = _scoped(values);
            final missing = _missingSelection(params);
            if (missing != null) {
              showValidationToast(context, missing);
              return false;
            }
            if (report.id == 'concept-projects' &&
                params['layout'] == 'roster' &&
                format != 'xlsx') {
              showValidationToast(
                context,
                'Choose Excel for the importable roster template.',
              );
              return false;
            }
            final success = await ref
                .read(reportsProvider.notifier)
                .downloadReport(
                  endpoint: report.endpointFor(params),
                  queryParams: {
                    ...params,
                    'include_signatures': includeSignatures.toString(),
                    'signatories': jsonEncode(
                      signatories.map((signer) => signer.toJson()).toList(),
                    ),
                  },
                  defaultFilename:
                      '${params['custom_filename'] ?? 'DefenSYS_${report.id}'}.${format == 'xlsx' ? 'xlsx' : 'pdf'}',
                  exportFormat: format,
                );
            if (context.mounted && !success) {
              showErrorToast(
                context,
                ref.read(reportsProvider).error ?? 'Unable to export report.',
              );
            }
            return success;
          },
        ),
      ),
    );
  }

  Widget _statusPanel(Widget child) {
    if (widget.embedded) return child;
    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefensysShadcnScope(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ReportNavigation.title(widget.report),
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                child,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton.ghost(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportFilters extends StatefulWidget {
  const _ReportFilters({
    required this.report,
    required this.params,
    required this.options,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onReset,
    required this.onRetry,
    required this.pitLead,
    this.compact = false,
  });
  final ReportDefinition report;
  final Map<String, String> params;
  final Map<String, dynamic> options;
  final bool loading, pitLead;
  final bool compact;
  final String? error;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback onRetry;
  final VoidCallback onReset;
  @override
  State<_ReportFilters> createState() => _ReportFiltersState();
}

class _ReportFiltersState extends State<_ReportFilters> {
  bool _showMore = false;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant _ReportFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in _controllers.entries) {
      final text = widget.params[entry.key] ?? '';
      if (entry.value.text.trim() != text) {
        entry.value.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(String key, String value) {
    final next = {...widget.params, key: value};
    if (key == 'coverage' && value.startsWith('grade:')) {
      next['coverage'] = 'specific';
      next['grade_id'] = value.substring(6);
      widget.onChanged(next);
      return;
    }
    if (const ['team_id', 'student_id'].contains(key)) {
      next.remove('grade_id');
      next['coverage'] = 'latest';
    }
    if (key == 'coverage' &&
        value == 'semester' &&
        widget.report.id.endsWith('grade-masterlist')) {
      for (final selector in [
        'stage_id',
        'defense_stage_id',
        'pit_event_config_id',
      ]) {
        next.remove(selector);
      }
    }
    if (key == 'semester_id' || key == 'scope') {
      for (final selector in [
        'rubric_id',
        'team_id',
        'student_id',
        'grade_id',
        'stage',
        'pit_event',
        'stage_label',
        'stage_id',
        'defense_stage_id',
        'pit_event_config_id',
      ]) {
        next.remove(selector);
      }
      if (next['coverage'] == 'specific') next['coverage'] = 'latest';
    }
    if (key == 'coverage' && value != 'specific') next.remove('grade_id');
    if (key == 'year_level') {
      next.remove('pit_event_config_id');
      next.remove('stage_label');
    }
    if (key == 'pit_event_config_id' && value.isNotEmpty) {
      next.remove('stage_id');
      next.remove('defense_stage_id');
      next.remove('stage_label');
    }
    if (key == 'stage_id' && value.isNotEmpty) {
      next.remove('pit_event_config_id');
      next.remove('stage_label');
    }
    if (key == 'defense_stage_id' && value.isNotEmpty) {
      next.remove('stage_label');
    }
    if (key == 'layout' && value == 'roster') {
      next.remove('concept_status');
      next['include_history'] = '0';
    }
    widget.onChanged(next);
  }

  List<Map<String, String>>? _choices(String key) {
    if (key == 'coverage' &&
        const ['team-grade', 'individual-grade'].contains(widget.report.id)) {
      return [
        {'value': 'latest', 'label': 'Latest recorded assessment'},
        {'value': 'all', 'label': 'All recorded assessments'},
        for (final assessment
            in (widget.options['assessments'] as List? ?? []).whereType<Map>())
          {
            'value': 'grade:${assessment['id']}',
            'label':
                '${assessment['scope'] == 'pit' ? 'PIT' : 'Capstone'} · ${assessment['stage_label']}${assessment['academic_period'] == null ? '' : ' · ${assessment['academic_period']}'}',
          },
      ];
    }
    final masterlist = widget.report.id.endsWith('grade-masterlist');
    final masterlistChoices = masterlist
        ? <String, Map<String, String>>{
            'coverage': {
              'assessment': 'Selected assessment',
              'semester': 'Whole semester',
            },
            'detail_level': {'summary': 'Summary', 'full': 'Full breakdown'},
            'status': {
              'pending': 'Pending publication',
              'published': 'Published',
              'awaiting_peers': 'Awaiting peers',
              'awaiting_evaluations': 'Awaiting evaluations',
              'not_assessed': 'Not assessed',
              'no_team': 'No team',
            },
          }[key]
        : null;
    if (masterlistChoices != null) {
      return masterlistChoices.entries
          .map((entry) => {'value': entry.key, 'label': entry.value})
          .toList();
    }
    if (key == 'stage' || key == 'pit_event') {
      final scope = widget.report.id == 'defense-stage-setup'
          ? 'capstone'
          : widget.report.id == 'pit-event-setup' || key == 'pit_event'
          ? 'pit'
          : widget.params['scope'] ??
                widget.params['type'] ??
                widget.report.scope;
      final semester =
          widget.params['semester_id'] ??
          widget.options['default_semester_id']?.toString() ??
          '';
      final contexts =
          widget.options['stage_choices'] as List? ??
          [
            for (final stage in widget.options['stages'] as List? ?? [])
              {
                'value': stage['label'],
                'label': stage['label'],
                'scope': 'capstone',
              },
          ];
      final seen = <String>{};
      return contexts
          .whereType<Map>()
          .where(
            (row) =>
                (scope.isEmpty || row['scope'] == scope) &&
                (row['semester_id'] == null ||
                    semester.isEmpty ||
                    row['semester_id'].toString() == semester),
          )
          .where((row) => seen.add(row['value'].toString()))
          .map(
            (row) => {
              'value': row['value'].toString(),
              'label': row['label'].toString(),
            },
          )
          .toList();
    }
    final source = const {
      'semester_id': 'semesters',
      'rubric_id': 'rubrics',
      'team_id': 'teams',
      'student_id': 'students',
      'stage_id': 'stages',
      'defense_stage_id': 'stages',
      'pit_event_config_id': 'pit_events',
    }[key];
    // Choices are filtered locally so changing period or scope cannot offer stale records.
    if (source != null) {
      return (widget.options[source] as List? ?? [])
          .whereType<Map>()
          .where(
            (row) =>
                (row['semester_id'] == null ||
                    (widget.params['semester_id'] ?? '').isEmpty ||
                    row['semester_id'].toString() ==
                        widget.params['semester_id']) &&
                (row['year_level'] == null ||
                    (widget.params['year_level'] ?? '').isEmpty ||
                    row['year_level'] == widget.params['year_level']) &&
                (row['scope'] == null ||
                    (widget.params['scope'] ?? '').isEmpty ||
                    row['scope'] == widget.params['scope']),
          )
          .map(
            (row) => {
              'value': row['id'].toString(),
              'label': (row['label'] ?? row['name']).toString(),
            },
          )
          .toList();
    }
    final conceptChoices = <String, Map<String, String>>{
      'layout': {
        'register': 'Concept register (PDF / Excel)',
        'roster': 'Capstone intake roster (Excel)',
      },
      'include_history': {
        '0': 'Current rounds',
        '1': 'Include historical rounds',
      },
      'concept_status': {
        'approved': 'Approved',
        'approved_with_revisions': 'Approved with revisions',
        'awaiting_decision': 'Awaiting decision',
        'rejected': 'Rejected',
        'not_selected': 'Not selected',
        'revise': 'Revision required',
        'for_redefense': 'Re-defense required',
        'replacement_required': 'Replacement required',
        'not_submitted': 'No concept submitted',
        'not_configured': 'Concepts not configured',
      },
    }[key];
    if (conceptChoices != null) {
      return conceptChoices.entries
          .map((e) => {'value': e.key, 'label': e.value})
          .toList();
    }
    final fixed = <String, List<String>>{
      'view': ['directory', 'assignments'],
      'scope': ['capstone', 'pit'],
      'type': ['capstone', 'pit'],
      'term_context': ['active', 'history'],
      'coverage': [
        'latest',
        'all',
        if ((widget.params['grade_id'] ?? '').isNotEmpty) 'specific',
      ],
      'evaluation_type': ['panel', 'adviser', 'peer'],
      'semester': ['1st Semester', '2nd Semester', 'Summer'],
      'year_level': ['1st Year', '2nd Year', '3rd Year', '4th Year'],
    }[key];
    return fixed
        ?.map(
          (value) => {
            'value': value,
            'label': value == 'capstone'
                ? 'Capstone'
                : value == 'pit'
                ? 'PIT'
                : value.replaceFirstMapped(
                    RegExp(r'^.'),
                    (m) => m[0]!.toUpperCase(),
                  ),
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final fields = {
      ...widget.report.filters,
      ...widget.params.keys.where(
        (key) => ![
          'include_signatures',
          'signatories',
          'custom_filename',
          'source_context',
          'view',
          'entity',
          'workspace',
          'ordering',
          'page',
          'page_size',
          'stage_label',
          'source',
        ].contains(key),
      ),
    };
    if (widget.compact) {
      final scope =
          widget.params['scope'] ??
          widget.params['type'] ??
          widget.report.scope;
      final visible = fields.where((key) {
        if (key == 'grade_id') return false;
        if (key == 'scope' && widget.report.scope.isNotEmpty) return false;
        if ((key == 'stage_id' || key == 'defense_stage_id') &&
            scope == 'pit') {
          return false;
        }
        if (key == 'pit_event_config_id' && scope == 'capstone') return false;
        if (widget.report.id.endsWith('grade-masterlist') &&
            widget.params['coverage'] == 'semester' &&
            [
              'stage_id',
              'defense_stage_id',
              'pit_event_config_id',
            ].contains(key)) {
          return false;
        }
        return true;
      }).toList();
      const essentials = {
        'semester_id',
        'scope',
        'type',
        'team_id',
        'student_id',
        'rubric_id',
        'coverage',
        'stage_id',
        'defense_stage_id',
        'pit_event_config_id',
        'stage',
        'pit_event',
        'year_level',
        'section',
        'academic_year',
        'school_year',
        'semester',
        'layout',
        'view',
        'start_date',
        'end_date',
      };
      final more = visible.where((key) => !essentials.contains(key)).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose records',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              ShadButton.ghost(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: DefensysTokens.textSecondaryOf(context),
                hoverForegroundColor: DefensysTokens.textPrimaryOf(context),
                onPressed: widget.onReset,
                leading: const Icon(Icons.restart_alt, size: 15),
                child: const Text(
                  'Reset selections',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (widget.error != null) ...[
            Text(
              widget.error!,
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
              ),
            ),
            ShadButton.outline(
              onPressed: widget.onRetry,
              child: const Text('Retry selections'),
            ),
            const SizedBox(height: 12),
          ],
          for (final key in visible.where(essentials.contains))
            _compactField(key),
          if (widget.report.id == 'concept-projects' &&
              widget.params['layout'] == 'roster') ...[
            const Text(
              'Use a 3rd Year, 1st Semester PIT concept event. The roster prepares a fresh Capstone intake.',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (more.isNotEmpty) ...[
            ReportSettingsSection(
              triggerKey: const ValueKey('report-more-filters'),
              title: 'More filters',
              icon: Icons.tune_outlined,
              expanded: _showMore,
              onToggle: () => setState(() => _showMore = !_showMore),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final key in more) _compactField(key)],
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'EXPORT FILTERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: DefensysTokens.textSecondaryOf(context),
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Exports include every matching record across pages.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.report.id == 'concept-projects') ...[
          const Text(
            'Roster template: select a 3rd Year, 1st Semester PIT period and concept event. Admin keeps or clears titles and assigns advisers in the existing team import review. All Capstone files, reviews and approvals start fresh.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
        ],
        if (widget.loading) const LinearProgressIndicator(),
        if (widget.error != null) ...[
          Text(widget.error!, style: const TextStyle(fontSize: 12)),
          TextButton(
            onPressed: widget.onRetry,
            child: const Text('Retry selections'),
          ),
        ],
        for (final key in fields.where(
          (key) =>
              !widget.report.id.endsWith('grade-masterlist') ||
              !((key == 'stage_id' || key == 'defense_stage_id') &&
                      widget.params['scope'] == 'pit') &&
                  !(key == 'pit_event_config_id' &&
                      widget.params['scope'] == 'capstone') &&
                  !(key == 'stage_id' &&
                      (widget.params['defense_stage_id'] ?? '').isNotEmpty),
        )) ...[
          Text(
            ReportCatalog.filterLabel(key).toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textSecondaryOf(context),
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          _field(key),
          const SizedBox(height: 16),
        ],
        if (widget.report.id.endsWith('grade-masterlist'))
          ShadButton.outline(
            onPressed: widget.onReset,
            child: const Text('Reset filters'),
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Reset All Filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.maroonOf(context),
              side: BorderSide(color: DefensysTokens.borderOf(context)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              ),
            ),
            onPressed: widget.onReset,
          ),
      ],
    );
  }

  Widget _field(String key) {
    if (key == 'grade_id') {
      return const Text(
        'Selected recorded assessment',
        style: TextStyle(fontSize: 12),
      );
    }
    if (widget.pitLead &&
        ['scope', 'type', 'year_level', 'track'].contains(key)) {
      return Text(
        '${key == 'scope' || key == 'type' ? 'PIT' : widget.params[key] ?? 'PIT'} (assigned)',
        style: const TextStyle(fontSize: 12.5),
      );
    }
    final choices = _choices(key);
    if (choices != null) {
      final current = key == 'coverage' && widget.params[key] == 'specific'
          ? 'grade:${widget.params['grade_id']}'
          : widget.params[key] ?? '';
      if (current.isNotEmpty &&
          !choices.any((choice) => choice['value'] == current)) {
        choices.add({
          'value': current,
          'label': sourceIdField(key)
              ? (widget.loading
                    ? 'Loading selected record...'
                    : 'Selected record unavailable for these filters')
              : current,
        });
      }
      if (widget.compact || widget.report.id.endsWith('grade-masterlist')) {
        final required =
            ['coverage', 'detail_level'].contains(key) ||
            (key == 'scope' && widget.report.id.endsWith('grade-masterlist'));
        final emptyLabel = switch (key) {
          'student_id' => 'Choose a student',
          'team_id' => 'Choose a team',
          'rubric_id' => 'Choose a rubric',
          'stage_id' || 'defense_stage_id' => 'Choose a stage',
          'pit_event_config_id' => 'Choose a PIT event',
          'scope' || 'type' => 'All programs',
          'year_level' => 'All year levels',
          'evaluation_type' => 'All evaluator types',
          'semester_id' =>
            const ['team-grade', 'individual-grade'].contains(widget.report.id)
                ? 'All academic periods'
                : 'Active academic period',
          _ => 'All / default',
        };
        return ShadSelect<String>(
          key: ValueKey('$key:$current:${widget.loading}'),
          enabled: !widget.loading,
          initialValue: current,
          options: [
            if (!required) ShadOption(value: '', child: Text(emptyLabel)),
            ...choices.map(
              (choice) => ShadOption(
                value: choice['value']!,
                child: Text(choice['label']!),
              ),
            ),
          ],
          selectedOptionBuilder: (_, value) => Text(
            choices
                    .where((choice) => choice['value'] == value)
                    .firstOrNull?['label'] ??
                emptyLabel,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: (value) => _change(key, value ?? ''),
        );
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('$key:$current:${widget.loading}'),
        initialValue: current,
        isExpanded: true,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 12.5,
          color: DefensysTokens.textPrimaryOf(context),
        ),
        decoration: _decoration(),
        items: [
          const DropdownMenuItem(value: '', child: Text('All / default')),
          ...choices.map(
            (choice) => DropdownMenuItem(
              value: choice['value'],
              child: Text(choice['label']!, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => _change(key, value ?? ''),
      );
    }
    if (widget.compact || widget.report.id.endsWith('grade-masterlist')) {
      return ShadInput(
        key: ValueKey('report-filter-$key'),
        placeholder: Text(
          key.endsWith('_date')
              ? 'YYYY-MM-DD'
              : key == 'section'
              ? 'All sections'
              : 'All',
        ),
        controller: _controllers.putIfAbsent(
          key,
          () => TextEditingController(text: widget.params[key] ?? ''),
        ),
        onChanged: (value) => _change(key, value),
      );
    }
    return TextField(
      key: ValueKey('report-filter-$key'),
      controller: _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: widget.params[key] ?? ''),
      ),
      style: TextStyle(
        fontSize: 12.5,
        color: DefensysTokens.textPrimaryOf(context),
      ),
      decoration: _decoration().copyWith(
        hintText: key.endsWith('_date') ? 'YYYY-MM-DD' : 'All',
      ),
      onChanged: (value) => _change(key, value.trim()),
    );
  }

  Widget _compactField(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key == 'scope' || key == 'type'
              ? 'Program'
              : ReportCatalog.filterLabel(key),
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        _field(key),
      ],
    ),
  );

  InputDecoration _decoration() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DefensysTokens.isDark(context)
          ? DefensysTokens.surfaceHigherOf(context)
          : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: DefensysTokens.maroonOf(context),
          width: 1.5,
        ),
      ),
    );
  }

  bool sourceIdField(String key) => [
    'pit_event_config_id',
    'semester_id',
    'rubric_id',
    'team_id',
    'student_id',
    'stage_id',
  ].contains(key);
}
