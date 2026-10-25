import 'dart:async';
import 'package:excel/excel.dart' as xl;
import 'package:defensys/widgets/team_import_format_guide.dart';
import 'package:defensys/widgets/team_import_review.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../navigation/admin_route_paths.dart';
import '../../../services/academic/team_roster_service.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/export/team_roster_excel_generator.dart';
import '../../../utils/import/team_bulk_import_file.dart';
import '../../../utils/import/team_bulk_import_csv.dart';
import '../../../widgets/shadcn/defensys_action_menu.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../widgets/shadcn/workflow_step_progress.dart';
import '../admin/student_teams/team_creation_page.dart';
import 'team_roster_students_step.dart';

Future<bool?> openTeamRoster(
  BuildContext context, {
  String? year,
  String? section,
  String? event,
  bool instructor = false,
}) {
  String path = '';
  try {
    path = GoRouterState.of(context).uri.path;
  } catch (_) {}
  final base = path.startsWith('/admin/')
      ? '/admin/student-teams'
      : instructor
      ? '/faculty/deliverables'
      : '/faculty/student-teams';
  final target = Uri(
    path: '$base/roster',
    queryParameters: {
      if (year != null) 'year': year,
      if (section != null) 'section': section,
      if (event != null) 'event': event,
    },
  ).toString();
  try {
    return context.push<bool>(target);
  } catch (_) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: TeamRosterScreen(
            initialYear: year,
            initialSection: section,
            initialEvent: event,
            instructor: instructor,
          ),
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _maps(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((v) => Map<String, dynamic>.from(v))
    .toList();

class TeamRosterScreen extends ConsumerStatefulWidget {
  const TeamRosterScreen({
    super.key,
    this.initialYear,
    this.initialSection,
    this.initialEvent,
    this.instructor = false,
  });
  final String? initialYear, initialSection, initialEvent;
  final bool instructor;
  @override
  ConsumerState<TeamRosterScreen> createState() => _TeamRosterScreenState();
}

class _TeamRosterScreenState extends ConsumerState<TeamRosterScreen> {
  Map<String, dynamic>? data, review;
  String? year, section, action, error, message, fileName;
  String selected = 'current', source = 'current', method = 'alphabetical';
  int groupSize = 4, requestVersion = 0;
  int generationStep = 1;
  List<int> generationStudents = [];
  StreamSubscription? _dropSubscription;
  final _statusTooltip = ShadTooltipController();
  bool _wasVisible = true;
  bool dragging = false;
  bool busy = false, changed = false, carryProjects = true, missingOnly = false;
  List<Map<String, dynamic>> importRows = [];
  final _importFiles = <String, String>{};
  Map<String, dynamic>? importValidation;
  Timer? _validationTimer;
  int _validationVersion = 0;
  bool importChecking = false;
  String importFilter = 'all';
  final _reviewAnchor = GlobalKey();
  final _reviewTable = GlobalKey<TeamBulkImportReviewTableState>();
  final setupTeams = <int>{};
  final projectModes = <int, String>{};
  List<Map<String, dynamic>> get rosters => _maps(data?['rosters']);
  Map<String, dynamic>? get roster =>
      rosters.where((r) => keyFor(r) == selected).firstOrNull;
  List<Map<String, dynamic>> get teams => _maps(roster?['teams']);
  String keyFor(Map<String, dynamic> r) => r['id']?.toString() ?? 'current';
  bool get locked => roster?['locked'] == true;
  Map<String, dynamic> get scope => {
    if (year != null) 'year_level': year,
    if (section != null) 'section': section,
    'workspace': widget.instructor ? 'instructor' : 'operations',
  };
  Map<String, dynamic> get target => {
    ...scope,
    if (selected != 'current') 'event_id': int.parse(selected),
  };

  @override
  void initState() {
    super.initState();
    year = widget.initialYear;
    section = widget.initialSection;
    _dropSubscription = setupDropzoneListener(
      (files) {
        if (mounted && action == 'import' && !busy && review == null) {
          processFiles(files);
        }
      },
      onDragStateChanged: (value) {
        if (mounted) setState(() => dragging = value);
      },
    );
    Future.microtask(() => load(initial: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_wasVisible && !busy) {
      Future.microtask(() {
        if (mounted) load(initial: rosters.isEmpty);
      });
    }
    _wasVisible = visible;
  }

  @override
  void dispose() {
    _validationVersion++;
    _validationTimer?.cancel();
    requestVersion++;
    _dropSubscription?.cancel();
    _statusTooltip.dispose();
    super.dispose();
  }

  Future<void> load({bool initial = false}) async {
    final version = ++requestVersion;
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    }
    try {
      final result = await ref.read(teamRosterServiceProvider).load(scope);
      if (!mounted || version != requestVersion) return;
      setState(() {
        data = result;
        year = result['year_level'];
        section = result['section'];
        if (initial && widget.initialEvent != null && rosters.isNotEmpty) {
          selected = keyFor(
            rosters.firstWhere(
              (r) => r['name'] == widget.initialEvent,
              orElse: () => rosters.first,
            ),
          );
        }
        if (!rosters.any((r) => keyFor(r) == selected)) {
          selected = 'current';
        }
      });
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() => error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && version == requestVersion) setState(() => busy = false);
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String existingProject(Map<String, dynamic> team) =>
      '${team['carry_title'] ?? team['project_title'] ?? ''}'.trim();

  String defaultProjectMode(Map<String, dynamic> team) =>
      team['shared_project'] == true
      ? 'continue'
      : team['project_choice']?.toString() ??
            (existingProject(team).isEmpty ? 'new' : 'continue');

  void begin(String next, {int? teamId}) {
    _validationVersion++;
    _validationTimer?.cancel();
    setState(() {
      importValidation = null;
      importChecking = false;
      importFilter = 'all';
      action = next;
      review = null;
      error = null;
      message = null;
      missingOnly = false;
      if (next == 'generate') {
        generationStep = 1;
        generationStudents = [];
      }
      source = keyFor(
        rosters.firstWhere(
          (r) => keyFor(r) != selected,
          orElse: () => rosters.first,
        ),
      );
      if (next == 'copy') carryProjects = true;
      projectModes
        ..clear()
        ..addEntries(
          teams.map((t) => MapEntry(t['id'] as int, defaultProjectMode(t))),
        );
      final eligible = teams.where((t) => t['project_locked'] != true).toList();
      final unopened = eligible
          .where((t) => t['setup_opened'] != true)
          .toList();
      setupTeams
        ..clear()
        ..addAll(
          (teamId == null
                  ? (unopened.isEmpty ? eligible : unopened)
                  : eligible.where((t) => t['id'] == teamId))
              .map((t) => t['id'] as int),
        );
    });
  }

  Future<void> pick() async {
    final files = await pickMultipleTabularDataFiles();
    if (files.isEmpty || !mounted) {
      return;
    }
    await processFiles(files);
  }

  Future<void> processFiles(List<PickedTabularFile> files) async {
    if (!mounted || busy || files.isEmpty) return;
    await run(() async {
      final parsed = parseTeamBulkCsv(
        readTeamImportFiles(files, includeFileSources: true),
      );
      if (parsed.rows.isEmpty) {
        throw const FormatException('No team rows were found in this file.');
      }
      setState(() {
        importRows = parsed.rows
            .map(
              (r) => {
                ...r,
                'section': '${r['section'] ?? ''}'.trim().isEmpty
                    ? section
                    : r['section'],
              },
            )
            .toList();
        fileName = files.map((f) => f.name).join(', ');
        _importFiles
          ..clear()
          ..addEntries(
            files.indexed.map(
              (entry) => MapEntry('file${entry.$1}', entry.$2.name),
            ),
          );
        review = null;
      });
    });
    if (mounted && error == null && importRows.isNotEmpty) {
      scheduleImportValidation();
    }
  }

  void removeImportFile(String fileKey) {
    if (busy || !_importFiles.containsKey(fileKey)) return;
    _validationTimer?.cancel();
    _validationVersion++;
    setState(() {
      importRows.removeWhere((row) => row['import_file_key'] == fileKey);
      _importFiles.remove(fileKey);
      fileName = _importFiles.isEmpty ? null : _importFiles.values.join(', ');
      review = null;
      importValidation = null;
      importChecking = false;
      importFilter = 'all';
      error = null;
      message = null;
    });
    if (importRows.isNotEmpty) scheduleImportValidation();
  }

  Widget uploadedImportFiles() => Column(
    key: const ValueKey('roster-uploaded-files'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      const Text(
        'Uploaded files',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      for (final file in _importFiles.entries)
        Padding(
          key: ValueKey('roster-uploaded-${file.key}'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.value,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Teams staged: ${importRows.where((row) => row['import_file_key'] == file.key).length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Remove ${file.value}',
                child: ShadButton.ghost(
                  key: ValueKey('remove-roster-file-${file.key}'),
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  leading: const Icon(Icons.close, size: 14),
                  onPressed: () => removeImportFile(file.key),
                  child: const Text('Remove'),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  void scheduleImportValidation() {
    _validationTimer?.cancel();
    final version = ++_validationVersion;
    setState(() {
      review = null;
      importValidation = null;
      error = null;
      importChecking = importRows.isNotEmpty;
    });
    if (importRows.isEmpty) return;
    _validationTimer = Timer(
      const Duration(milliseconds: 400),
      () => validateImport(version),
    );
  }

  Future<void> validateImport(int version) async {
    final contextKey = '$year/$section/$selected';
    try {
      final result = await ref.read(teamRosterServiceProvider).preview({
        ...target,
        'operation': 'import',
        'validation_only': true,
        'teams': importRows,
      });
      if (!mounted ||
          version != _validationVersion ||
          action != 'import' ||
          contextKey != '$year/$section/$selected') {
        return;
      }
      setState(() {
        importValidation = result;
        importChecking = false;
      });
    } catch (e) {
      if (!mounted ||
          version != _validationVersion ||
          action != 'import' ||
          contextKey != '$year/$section/$selected') {
        return;
      }
      setState(() {
        error = '$e'.replaceFirst('Exception: ', '');
        importChecking = false;
      });
    }
  }

  Widget importToolbar() => TeamImportValidationToolbar(
    rows: importRows,
    previewRows: _maps(importValidation?['rows']),
    filter: importFilter,
    checking: importChecking,
    error: error,
    onRetry: busy ? null : scheduleImportValidation,
    onFilter: (value) => setState(() => importFilter = value),
    onFirstIssue: () {
      setState(() => importFilter = 'all');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reviewTable.currentState?.goToFirstIssue(),
      );
    },
    action: ShadButton(
      size: ShadButtonSize.sm,
      enabled:
          !busy &&
          error == null &&
          !importChecking &&
          importValidation?['ready'] == true,
      onPressed: preview,
      child: const Text('Review replacement'),
    ),
  );

  Future<void> preview() => run(() async {
    final version = _validationVersion;
    final contextKey = '$year/$section/$selected';
    final result = await ref.read(teamRosterServiceProvider).preview({
      ...target,
      'operation': action,
      if (action == 'projects') ...{
        'team_ids': setupTeams.toList(),
        'team_modes': {for (final id in setupTeams) '$id': projectModes[id]},
      },
      'carry_projects': carryProjects,
      if (action == 'copy' && source != 'current')
        'source_event_id': int.parse(source),
      if (action == 'import') 'teams': importRows,
      if (action == 'generate') ...{
        'group_size': groupSize,
        'method': method,
        'confirmed_student_ids': generationStudents,
      },
    });
    if (!mounted) return;
    if (action == 'import' &&
        (version != _validationVersion ||
            importChecking ||
            contextKey != '$year/$section/$selected')) {
      return;
    }
    setState(() => review = result);
  });

  Future<void> apply() => run(() async {
    final projects = action == 'projects';
    final result = await ref
        .read(teamRosterServiceProvider)
        .apply(review!['preview_token']);
    if (!mounted) {
      return;
    }
    changed = true;
    setState(() {
      review = null;
      action = null;
      importRows = [];
      fileName = null;
      _importFiles.clear();
    });
    await load();
    if (mounted && error == null) {
      setState(
        () => message = projects
            ? selected == 'current'
                  ? 'Project choices saved for upcoming events. Saved event rosters are preserved.'
                  : 'Project choices saved. ${result['requested_count']} team leaders have details to confirm.'
            : selected == 'current'
            ? 'Current roster updated for upcoming events. Saved event rosters are preserved.'
            : 'Roster applied to ${roster?['name']} · $section.',
      );
    }
  });

  Future<void> importSections() async {
    final imported = await openTeamCreation(
      context,
      importTab: true,
      level: '$year PIT',
      event: roster == null
          ? widget.initialEvent
          : selected != 'current'
          ? roster!['name']
          : null,
    );
    if (!mounted) return;
    changed = changed || imported == true;
    await load(initial: true);
  }

  Future<void> export(String format) => run(() async {
    final result = await ref.read(teamRosterServiceProvider).export(target);
    if (format == 'csv') {
      await downloadTextFile(
        filename: '${result['filename']}.csv',
        content: result['csv'],
      );
    } else {
      final book = xl.Excel.createExcel();
      book.rename(book.getDefaultSheet()!, 'Team roster');
      final sheet = book['Team roster'];
      sheet.appendRow([
        xl.TextCellValue(
          '${result['draft'] == true ? 'DRAFT · ' : ''}${result['event']} · ${result['section']}',
        ),
      ]);
      sheet.appendRow([xl.TextCellValue('${result['semester']}')]);
      for (final row in [result['headers'], ...(result['rows'] as List)]) {
        sheet.appendRow(
          (row as List).map((v) => xl.TextCellValue('$v')).toList(),
        );
      }
      for (var i = 0; i < (result['headers'] as List).length; i++) {
        sheet.setColumnWidth(i, i == 1 || i == 4 ? 46 : 25);
      }
      await downloadBinaryFile(
        filename: '${result['filename']}.xlsx',
        bytes: book.encode()!,
      );
    }
  });

  Future<void> correctTeam(Map<String, dynamic> team) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RosterDetailsDialog(
        team: team,
        target: target,
        conceptEnabled: roster?['concept_enabled'] == true,
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    changed = true;
    await load();
    if (mounted && error == null) {
      setState(
        () => message =
            'Team details corrected. The leader must confirm the updated information.',
      );
    }
  }

  void back() {
    if (context.canPop()) {
      context.pop(changed);
    } else {
      context.go(
        widget.instructor ? '/faculty/deliverables' : '/faculty/student-teams',
      );
    }
  }

  Widget secondary(
    String label,
    IconData icon,
    VoidCallback callback, {
    bool enabled = true,
  }) => ShadButton.outline(
    height: 0,
    enabled: !busy && enabled,
    onPressed: callback,
    leading: Icon(icon, size: 16),
    child: Flexible(child: Text(label, textAlign: TextAlign.center)),
  );

  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  Widget badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: DefensysTokens.panelOf(context),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: DefensysTokens.borderOf(context)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: DefensysTokens.textSecondaryOf(context),
      ),
    ),
  );

  Widget rosterList() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Rosters · $section',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 12),
        for (final r in rosters)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              selected: selected == keyFor(r),
              child: Material(
                color: selected == keyFor(r)
                    ? DefensysTokens.panelOf(context)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: selected == keyFor(r)
                        ? DefensysTokens.borderOf(context)
                        : Colors.transparent,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: busy
                      ? null
                      : () => setState(() {
                          selected = keyFor(r);
                          action = null;
                          review = null;
                          missingOnly = false;
                          error = null;
                          message = null;
                        }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['name']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selected == keyFor(r)
                              ? '${r['team_count']} teams'
                              : '${r['status']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    padding: const EdgeInsets.all(12),
  );

  Widget rosterHeading() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${roster?['name']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ShadTooltip(
            controller: _statusTooltip,
            builder: (context) => SizedBox(
              width: MediaQuery.sizeOf(context).width.clamp(0.0, 360.0) - 64,
              child: Text(
                locked
                    ? 'This event keeps its saved teams, leaders and members. You can export it or copy it into another roster.'
                    : selected == 'current'
                    ? 'New and upcoming events follow this roster. Ongoing, completed and custom event rosters keep their saved teams.'
                    : roster?['source'] == 'custom'
                    ? 'This roster applies only to this event and $section.'
                    : 'This event uses the current teams until you apply a replacement or open team setup.',
              ),
            ),
            child: ShadBadge.outline(
              key: const ValueKey('roster-status'),
              onPressed: _statusTooltip.show,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('${roster?['status']}')),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.info, size: 13),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '$section · ${roster?['team_count']} teams · ${roster?['student_count']} students',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 16),
      if (locked)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.lock, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'This event roster is locked. Export it or copy it to Current roster.',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
    ],
  );

  Widget exportMenu() => DefensysActionMenu(
    wrapLabel: true,
    label: 'Export this roster',
    triggerLabel: 'Export roster',
    triggerIcon: Icons.keyboard_arrow_down,
    enabled: !busy && teams.isNotEmpty,
    items: [
      DefensysMenuItem(
        label: 'Excel (.xlsx)',
        icon: Icons.table_chart_outlined,
        onPressed: () => export('xlsx'),
      ),
      DefensysMenuItem(
        label: 'CSV (.csv)',
        icon: Icons.description_outlined,
        onPressed: () => export('csv'),
      ),
    ],
  );

  Widget importMenu() {
    if (data?['can_import_sections'] != true || widget.instructor) {
      return ShadButton(
        key: const ValueKey('roster-import-section'),
        height: 0,
        enabled: !busy,
        onPressed: () => begin('import'),
        leading: const Icon(LucideIcons.upload, size: 16),
        child: const Flexible(child: Text('Import teams')),
      );
    }
    return DefensysActionMenu(
      key: const ValueKey('roster-import-menu'),
      label: 'Choose team import scope',
      triggerLabel: 'Import teams',
      triggerIcon: LucideIcons.chevronDown,
      primary: true,
      wrapLabel: true,
      enabled: !busy,
      items: [
        DefensysMenuItem(
          label: 'All sections with instructors',
          icon: LucideIcons.users,
          onPressed: importSections,
        ),
        DefensysMenuItem(
          label: 'Selected section · $section',
          icon: LucideIcons.upload,
          onPressed: () => begin('import'),
        ),
      ],
    );
  }

  Widget rosterActions({double? buttonWidth}) => Wrap(
    key: const ValueKey('roster-actions'),
    spacing: 8,
    runSpacing: 8,
    children:
        [
              if (locked && selected != 'current')
                secondary('Copy to Current roster', Icons.copy_outlined, () {
                  final sourceKey = selected;
                  setState(() {
                    selected = 'current';
                    action = 'copy';
                    source = sourceKey;
                    review = null;
                    carryProjects = true;
                    error = null;
                    message = null;
                  });
                }),
              if (!locked) ...[
                secondary(
                  'Copy roster',
                  Icons.copy_outlined,
                  () => begin('copy'),
                  enabled: rosters.length > 1,
                ),
                importMenu(),
                if (data?['can_generate'] == true)
                  secondary(
                    'Generate teams',
                    Icons.groups_outlined,
                    () => begin('generate'),
                  ),
              ],
              if (roster?['can_request_setup'] == true)
                secondary(
                  'Project setup',
                  Icons.assignment_outlined,
                  () => begin('projects'),
                ),
              exportMenu(),
            ]
            .map(
              (button) => buttonWidth == null
                  ? button
                  : SizedBox(width: buttonWidth, height: 44, child: button),
            )
            .toList(),
  );

  Widget browse() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rosterHeading(),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${roster?['ready_count']} of ${roster?['team_count']} teams ready to export',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (teams.any((t) => t['ready'] != true))
              ShadButton.ghost(
                height: 0,
                onPressed: busy
                    ? null
                    : () => setState(() => missingOnly = !missingOnly),
                child: Flexible(
                  child: Text(
                    missingOnly ? 'Show all teams' : 'View missing details',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        if (teams.any((t) => t['ready'] != true))
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              'Incomplete exports are marked as drafts. Export readiness does not grant concept approval.',
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
        const SizedBox(height: 8),
        teamTable(
          teams.where((t) => !missingOnly || t['ready'] != true).toList(),
        ),
      ],
    ),
  );

  Widget rosterToolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final options = _maps(data?['scope_options']);
      final years = {
        for (final option in options)
          '${option['year_level']}': '${option['year_level']}',
      };
      final sections = {
        for (final option in options.where((o) => o['year_level'] == year))
          '${option['section']}': '${option['section']}',
      };
      return Wrap(
        key: const ValueKey('roster-toolbar'),
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 20,
        children: [
          Wrap(
            spacing: 12,
            children: [
              if (years.length > 1)
                SizedBox(
                  width: constraints.maxWidth < 500
                      ? constraints.maxWidth
                      : 200,
                  child: WorkflowSelect(
                    label: 'PIT year',
                    value: year,
                    options: years,
                    enabled: !busy,
                    searchable: false,
                    onChanged: (value) {
                      setState(() {
                        year = value;
                        section = null;
                        action = null;
                        review = null;
                      });
                      load();
                    },
                  ),
                ),
              if (sections.isNotEmpty)
                SizedBox(
                  width: constraints.maxWidth < 500
                      ? constraints.maxWidth
                      : 220,
                  child: WorkflowSelect(
                    label: 'Section',
                    value: section,
                    options: sections,
                    enabled: !busy && sections.length > 1,
                    searchable: false,
                    onChanged: (value) {
                      setState(() {
                        section = value;
                        action = null;
                        review = null;
                      });
                      load();
                    },
                  ),
                ),
            ],
          ),
          if (roster != null && action == null && review == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: rosterActions(
                buttonWidth: constraints.maxWidth < 500
                    ? (constraints.maxWidth - 8) / 2
                    : null,
              ),
            ),
        ],
      );
    },
  );

  Widget teamTable(List<Map<String, dynamic>> rows, {bool preview = false}) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            missingOnly
                ? 'All teams have completed their details.'
                : 'No teams in this roster yet. Copy, import or generate teams to begin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                color: DefensysTokens.panelOf(context),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Team / project',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Leader', style: TextStyle(fontSize: 12)),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text('Members', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            for (final t in rows)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: DefensysTokens.borderOf(context)),
                  ),
                ),
                child: ExpansionTile(
                  key: ValueKey('roster-team-${t['id'] ?? t['name']}'),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: teamInfo(t, preview)),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${t['leader_name']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              width: 78,
                              child: Text(
                                '${_maps(t['members']).length} members',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            teamInfo(t, preview),
                            const SizedBox(height: 6),
                            Text(
                              'Leader: ${t['leader_name']} · ${_maps(t['members']).length} members',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in _maps(t['members']))
                            badge(
                              '${m['name']}${m['id'] == t['leader_id'] ? ' · Leader' : ''}',
                            ),
                        ],
                      ),
                    ),
                    if (!preview &&
                        roster?['can_request_setup'] == true &&
                        t['project_locked'] != true)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: secondary(
                            'Project options',
                            Icons.assignment_outlined,
                            () => begin('projects', teamId: t['id'] as int),
                          ),
                        ),
                      ),
                    if (!preview &&
                        roster?['can_correct_details'] == true &&
                        t['details_revision'] != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: secondary(
                            'Correct team details',
                            Icons.edit_outlined,
                            () => correctTeam(t),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget teamInfo(Map<String, dynamic> t, bool preview) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${t['display_name'] ?? t['name']}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      if (preview && t['project_action'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            '${t['project_action']}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      if (preview &&
          '${t['previous_title'] ?? ''}'.trim().isNotEmpty &&
          t['previous_title'] != t['project_title'])
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            'Previous: ${t['previous_title']}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      if (preview && (t['needs_name'] == true || t['needs_project'] == true))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Leader completes: ${[if (t['needs_name'] == true) 'team name', if (t['needs_project'] == true) 'project setup'].join(' + ')}',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      Text(
        '${t['project_title'] ?? ''}'.trim().isEmpty
            ? 'Project setup pending'
            : '${t['project_title']}',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      if (!preview)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${t['project_status']} · ${t['confirmed'] == true
                ? 'Team details confirmed'
                : t['setup_opened'] == true
                ? 'Awaiting leader confirmation'
                : 'Setup not opened'}',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
    ],
  );

  void applySelectedProjectMode(String mode) {
    setState(() {
      for (final team in teams.where(
        (team) =>
            setupTeams.contains(team['id']) &&
            team['project_locked'] != true &&
            team['shared_project'] != true,
      )) {
        projectModes[team['id'] as int] =
            mode == 'continue' && existingProject(team).isEmpty ? 'new' : mode;
      }
    });
  }

  Widget projectChoicesToolbar() {
    final canApply =
        !busy &&
        teams.any(
          (team) =>
              setupTeams.contains(team['id']) &&
              team['project_locked'] != true &&
              team['shared_project'] != true,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              '${setupTeams.length} selected',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in const {
                'continue': 'Keep existing',
                'new': 'Start new',
              }.entries)
                ShadButton.outline(
                  key: ValueKey('project-bulk-${mode.key}'),
                  enabled: canApply,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => applySelectedProjectMode(mode.key),
                  child: Text(mode.value, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget projectTeamRow(Map<String, dynamic> team) {
    final id = team['id'] as int;
    final title = existingProject(team);
    final details = ShadCheckbox(
      key: ValueKey('project-team-$id'),
      value: setupTeams.contains(id),
      enabled: !busy && team['project_locked'] != true,
      crossAxisAlignment: CrossAxisAlignment.start,
      onChanged: (value) => setState(() {
        value ? setupTeams.add(id) : setupTeams.remove(id);
      }),
      label: Text(
        '${team['name']}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      sublabel: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          title.isEmpty ? 'No existing project' : title,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ),
    );
    final Widget choice;
    if (team['project_locked'] == true || team['shared_project'] == true) {
      choice = Text(
        team['project_locked'] == true
            ? 'Work has started. Use the existing review or revision workflow.'
            : 'Managed through the shared concept workflow.',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      );
    } else if (title.isEmpty) {
      choice = const Text(
        'New project required',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      );
    } else {
      choice = Semantics(
        label: 'Project choice for ${team['name']}',
        child: SegmentedButton<String>(
          key: ValueKey('project-choice-$id'),
          segments: const [
            ButtonSegment(value: 'continue', label: Text('Keep existing')),
            ButtonSegment(value: 'new', label: Text('Start new')),
          ],
          selected: {projectModes[id] ?? defaultProjectMode(team)},
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          style: SegmentedButton.styleFrom(
            foregroundColor: DefensysTokens.textPrimaryOf(context),
            backgroundColor: DefensysTokens.surfaceOf(context),
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: DefensysTokens.maroonOf(context),
            disabledForegroundColor: DefensysTokens.textSecondaryOf(context),
            disabledBackgroundColor: DefensysTokens.surfaceHigherOf(context),
            side: BorderSide(color: DefensysTokens.borderOf(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            minimumSize: const Size(0, 44),
            visualDensity: VisualDensity.compact,
          ),
          onSelectionChanged: !busy && setupTeams.contains(id)
              ? (values) => setState(() => projectModes[id] = values.single)
              : null,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 640
            ? Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 20),
                  SizedBox(width: 240, child: choice),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 10), choice],
              ),
      ),
    );
  }

  Widget projectChoicesSummary() {
    final selected = teams.where((team) => setupTeams.contains(team['id']));
    final keeping = selected
        .where(
          (team) =>
              (projectModes[team['id']] ?? defaultProjectMode(team)) ==
              'continue',
        )
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(
          '$keeping keeping existing · ${selected.length - keeping} starting new',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ),
    );
  }

  Widget prepareGeneration() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Generate new teams',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text('Target: ${roster?['name']} · $section'),
        const SizedBox(height: 20),
        TeamRosterStudentsStep(
          key: ValueKey('generation-students-$year-$section'),
          year: year!,
          section: section!,
          onBusyChanged: (value) => setState(() => busy = value),
          onCancel: () => setState(() => action = null),
          onConfirmed: (ids) => setState(() {
            generationStudents = ids;
            generationStep = 2;
          }),
        ),
      ],
    ),
  );

  Widget configure() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          action == 'copy'
              ? 'Copy an existing roster'
              : action == 'import'
              ? 'Import a roster'
              : action == 'projects'
              ? 'Project setup'
              : 'Generate new teams',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Target: ${roster?['name']} · $section',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 20),
        if (action == 'copy') ...[
          WorkflowSelect(
            label: 'Copy from',
            value: source,
            enabled: !busy,
            options: {
              for (final r in rosters.where((r) => keyFor(r) != selected))
                keyFor(r): '${r['name']} · ${r['team_count']} teams',
            },
            onChanged: (v) => setState(() => source = v),
          ),
          ShadCheckbox(
            value: carryProjects,
            enabled: !busy,
            onChanged: (v) => setState(() => carryProjects = v),
            label: const Text('Carry existing project titles with these teams'),
          ),
          const SizedBox(height: 16),
          const WorkflowNotice(
            title: 'Roster information only',
            message:
                'Copy team names, members and leaders. Files, grades, schedules, endorsements and concept decisions stay with their source event.',
          ),
        ],
        if (action == 'import') ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final guide = TeamImportFormatGuide(
                isCapstone: false,
                instructorWorkspace: widget.instructor,
                contextLabel: '$year PIT · $section',
                section: section,
                onDownload: busy
                    ? null
                    : () => run(() async {
                        await downloadBinaryFile(
                          filename: 'PIT-$section-team-roster-template.xlsx',
                          bytes: generateOfficialTeamRosterExcelBytes(
                            isCapstone: false,
                            instructorWorkspace: widget.instructor,
                            assignedSection: section,
                          ),
                        );
                      }),
              );
              final upload = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Upload spreadsheet',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Upload the complete team roster for this section.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TeamImportDropArea(
                    onPick: busy ? null : pick,
                    dragging: dragging,
                    fileLabel: fileName,
                    teamCount: importRows.length,
                  ),
                  if (_importFiles.isNotEmpty) uploadedImportFiles(),
                ],
              );
              return constraints.maxWidth >= 1000
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: guide),
                        const SizedBox(width: 20),
                        Expanded(child: upload),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [guide, const SizedBox(height: 20), upload],
                    );
            },
          ),
          const SizedBox(height: 18),
          if (error != null && importRows.isEmpty)
            WorkflowNotice(
              title: 'Unable to read spreadsheet',
              message: error!,
              error: true,
            ),
          if (importRows.isNotEmpty) ...[
            SizedBox(key: _reviewAnchor),
            importToolbar(),
            const SizedBox(height: 14),
            const Text(
              'Review teams',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TeamBulkImportReviewTable(
              key: _reviewTable,
              rows: importRows,
              previewRows: _maps(importValidation?['rows']),
              sectionSummaries: _maps(importValidation?['section_summaries']),
              isValidating: importChecking,
              statusFilter: importFilter,
              isCapstoneAdmin: false,
              pitLeadYear: year,
              showIssuesOnly: false,
              lockAssignments: true,
              sectionOptions: [if (section != null) section!],
              onRowChanged: (_) => scheduleImportValidation(),
              onDeleteRow: (index) {
                setState(() => importRows.removeAt(index));
                scheduleImportValidation();
              },
              onAddRow: () {
                setState(() {
                  importRows.add({
                    'group_key':
                        'manual/${DateTime.now().microsecondsSinceEpoch}',
                    'team_name': '',
                    'project_title': '',
                    'section': section ?? '',
                    'member_ids': <String>[],
                    'leader_id': '',
                  });
                });
                scheduleImportValidation();
              },
            ),
            const SizedBox(height: 18),
          ],
        ],
        if (action == 'generate') ...[
          Text(
            '${generationStudents.length} confirmed students · $section',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          WorkflowSelect(
            label: 'Students per team',
            value: '$groupSize',
            enabled: !busy,
            options: const {
              '1': '1 student',
              '2': '2 students',
              '3': '3 students',
              '4': '4 students',
            },
            searchable: false,
            onChanged: (v) => setState(() => groupSize = int.parse(v)),
          ),
          WorkflowSelect(
            label: 'Grouping',
            value: method,
            enabled: !busy,
            searchable: false,
            options: const {'alphabetical': 'Alphabetical', 'random': 'Random'},
            onChanged: (v) => setState(() => method = v),
          ),
          const WorkflowNotice(
            title: 'Section enrollment',
            message:
                'Generate balanced teams from active enrolled students in this section. Each student appears once and each leader is a member. Generated teams start with new projects.',
          ),
        ],
        if (action == 'projects') ...[
          WorkflowNotice(
            title: selected == 'current'
                ? 'Projects for upcoming events'
                : 'Projects for this event',
            message: selected == 'current'
                ? 'Keep existing projects or start fresh. Teams without a project start fresh. Leaders complete project details when event setup opens.'
                : roster?['concept_enabled'] == true
                ? 'Leaders confirm their details and submit concepts using the configured proposal counts and shared-system rules. Teams without a project start fresh.'
                : 'Leaders confirm their team name and project title. Teams without a project start fresh.',
          ),
          if (roster?['legacy_new_project'] == true)
            const WorkflowNotice(
              title: 'Previous project preference',
              message:
                  'This event previously requested new projects. That preference is shown below for teams whose setup has not opened. You can review and change each choice here.',
            ),
          projectChoicesToolbar(),
          for (final team in teams) projectTeamRow(team),
          projectChoicesSummary(),
          WorkflowNotice(
            title: 'Review project choices',
            message: selected == 'current'
                ? 'Review the replacement and affected upcoming events before saving. Earlier event rosters and their records are preserved.'
                : 'Changes take effect after review. Selected leaders confirm again; earlier event records are preserved.',
          ),
        ] else
          const WorkflowNotice(
            title: 'Review before applying',
            message:
                'The existing roster stays active while you prepare a replacement. You will review the teams and affected events before saving.',
          ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          runSpacing: 10,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (action == 'generate')
                  secondary(
                    'Back to students',
                    Icons.arrow_back,
                    () => setState(() {
                      generationStep = 1;
                      generationStudents = [];
                    }),
                  ),
                secondary(
                  'Cancel',
                  Icons.close,
                  () => setState(() {
                    action = null;
                    review = null;
                  }),
                ),
              ],
            ),
            ShadButton(
              height: 0,
              enabled:
                  !busy &&
                  (action != 'import' ||
                      error == null &&
                          !importChecking &&
                          importValidation?['ready'] == true) &&
                  (action != 'projects' || setupTeams.isNotEmpty),
              onPressed: preview,
              child: Flexible(
                child: Text(
                  busy
                      ? 'Working…'
                      : action == 'projects'
                      ? 'Review project choices'
                      : 'Review roster',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget emptySections() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import teams or assign instructors',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text('No sections are available for $year in ${data!['semester']}.'),
        const SizedBox(height: 8),
        Text(
          data!['can_import_sections'] == true
              ? 'Import teams for all sections with their instructors in one upload, or assign instructors so they can import their own section. Existing students are linked and blank section assignments are filled from the roster.'
              : 'Ask your PIT Lead to assign you a section, then import your section\'s team roster here.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (data!['can_import_sections'] == true)
              ShadButton(
                enabled: !busy,
                onPressed: importSections,
                child: const Text('Import teams'),
              ),
            if (data!['can_import_sections'] == true)
              secondary('Assign instructors', Icons.person_add_alt, () {
                context.go(
                  Uri(
                    path: FacultyRoutes.cohort,
                    queryParameters: {'tab': 'instructors'},
                  ).toString(),
                );
              }),
            secondary(
              'Refresh sections',
              Icons.refresh,
              () => load(initial: true),
            ),
          ],
        ),
      ],
    ),
  );

  Widget projectReviewPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Review project choices',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '${review!['target']} · $section',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 16),
        WorkflowNotice(
          title: selected == 'current'
              ? 'Projects for upcoming events'
              : 'Leader confirmation',
          message: selected == 'current'
              ? 'These choices create a replacement Current roster for upcoming events. Earlier event teams keep their projects and records.'
              : 'Selected leaders confirm their details again. New projects follow this event’s requirements. Earlier event records stay intact.',
        ),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            Text('Keep existing: ${review!['kept_project_count']}'),
            Text('Start new: ${review!['new_project_count']}'),
          ],
        ),
        if ((review!['affected_events'] as List? ?? []).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Events using these choices: ${(review!['affected_events'] as List).join(', ')}.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if ((review!['preserved_events'] as List? ?? []).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Event rosters preserved: ${(review!['preserved_events'] as List).join(', ')}.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        teamTable(_maps(review!['teams']), preview: true),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          runSpacing: 10,
          children: [
            secondary(
              'Back',
              Icons.arrow_back,
              () => setState(() => review = null),
            ),
            ShadButton(
              height: 0,
              enabled: !busy,
              onPressed: apply,
              child: Flexible(
                child: Text(
                  busy ? 'Applying…' : '${review!['confirmation']}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget reviewPanel() => action == 'projects'
      ? projectReviewPanel()
      : panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Review roster',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Save as: ${review!['target']} · $section',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              WorkflowNotice(
                title: selected == 'current'
                    ? 'Set the default for upcoming events'
                    : 'Replace this event roster',
                message: selected == 'current'
                    ? 'These teams become the Current roster for $section. New events and upcoming events using the default will use them. Saved and custom event rosters keep their teams.'
                    : 'Only ${review!['target']} · $section will use these teams. Other event rosters stay unchanged.',
              ),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  Text(
                    '${review!['previous_team_count']} → ${review!['team_count']} teams',
                  ),
                  Text('${review!['student_count']} students'),
                  Text(
                    '${review!['omitted_student_count']} enrolled students omitted',
                  ),
                ],
              ),
              if ((review!['section_assignment_count'] as num? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: WorkflowNotice(
                    title: 'Assign unsectioned students',
                    message:
                        '${review!['section_assignment_count']} enrolled students with no class section will be assigned to $section when this roster is applied.',
                  ),
                ),
              if ((review!['omitted_student_count'] as num? ?? 0) > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: WorkflowNotice(
                    title: 'Review omitted students',
                    message:
                        'Some enrolled students are not included in this replacement. Check that this is the complete roster you intend to use.',
                  ),
                ),
              if ((review!['affected_events'] as List? ?? []).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Upcoming events using this roster: ${(review!['affected_events'] as List).join(', ')}.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if ((review!['preserved_events'] as List? ?? []).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Event rosters preserved: ${(review!['preserved_events'] as List).join(', ')}.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              for (final summary in _maps(review!['section_summaries']))
                TeamImportSharedDetails(summary: summary),
              teamTable(_maps(review!['teams']), preview: true),
              const SizedBox(height: 20),
              if (error != null)
                WorkflowNotice(
                  title: 'Unable to apply this roster',
                  message: error!,
                  error: true,
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 10,
                runSpacing: 10,
                children: [
                  secondary(
                    'Back',
                    Icons.arrow_back,
                    () => setState(() => review = null),
                  ),
                  ShadButton(
                    height: 0,
                    enabled: !busy,
                    onPressed: apply,
                    child: Flexible(
                      child: Text(
                        busy ? 'Applying…' : '${review!['confirmation']}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: TeamImportStickyReview(
      anchor: _reviewAnchor,
      toolbar: importToolbar(),
      enabled: action == 'import' && review == null && importRows.isNotEmpty,
      child: PopScope(
        canPop: !busy,
        child: ColoredBox(
          color: DefensysTokens.backgroundOf(context),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 14,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team roster',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${section ?? 'Choose a section'} · ${year ?? 'PIT'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    secondary('Back to PIT Teams', Icons.arrow_back, back),
                  ],
                ),
                const SizedBox(height: 22),
                if (error != null && action != 'import')
                  WorkflowNotice(
                    title: 'Unable to complete this action',
                    message: error!,
                    error: true,
                  ),
                if (error != null && data != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: secondary('Refresh roster', Icons.refresh, () {
                        setState(() {
                          action = null;
                          review = null;
                        });
                        load();
                      }),
                    ),
                  ),
                if (message != null)
                  WorkflowNotice(title: 'Roster updated', message: message!),
                if (data == null) ...[
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!busy) secondary('Try again', Icons.refresh, load),
                ] else ...[
                  rosterToolbar(),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: LinearProgressIndicator(),
                    ),
                  if (section == null || rosters.isEmpty)
                    emptySections()
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final body = review != null
                            ? reviewPanel()
                            : action == 'generate' && generationStep == 1
                            ? prepareGeneration()
                            : action != null
                            ? configure()
                            : browse();
                        final content = action == 'generate'
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  WorkflowStepProgress(
                                    currentStep: review != null
                                        ? 3
                                        : generationStep,
                                    labels: const [
                                      'Import & confirm students',
                                      'Choose grouping',
                                      'Review & apply teams',
                                    ],
                                    compactLabels: const [
                                      'Students',
                                      'Grouping',
                                      'Review',
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  body,
                                ],
                              )
                            : body;
                        if (constraints.maxWidth < 820) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              WorkflowSelect(
                                label: 'Roster',
                                value: selected,
                                options: {
                                  for (final r in rosters)
                                    keyFor(r): '${r['name']}',
                                },
                                searchable: false,
                                enabled: !busy && rosters.length > 1,
                                onChanged: (value) => setState(() {
                                  selected = value;
                                  action = null;
                                  review = null;
                                  missingOnly = false;
                                  error = null;
                                  message = null;
                                }),
                              ),
                              content,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 220, child: rosterList()),
                            const SizedBox(width: 20),
                            Expanded(child: content),
                          ],
                        );
                      },
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

class _RosterDetailsDialog extends ConsumerStatefulWidget {
  const _RosterDetailsDialog({
    required this.team,
    required this.target,
    required this.conceptEnabled,
  });
  final Map<String, dynamic> team, target;
  final bool conceptEnabled;
  @override
  ConsumerState<_RosterDetailsDialog> createState() =>
      _RosterDetailsDialogState();
}

class _RosterDetailsDialogState extends ConsumerState<_RosterDetailsDialog> {
  late final name = TextEditingController(text: '${widget.team['name']}');
  late final project = TextEditingController(
    text: '${widget.team['project_title'] ?? ''}',
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    project.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(teamRosterServiceProvider).correct({
        ...widget.target,
        'team_id': widget.team['id'],
        'revision': widget.team['details_revision'],
        'name': name.text,
        if (!widget.conceptEnabled) 'project_title': project.text,
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      title: const Text('Correct team details'),
      description: Text('${widget.team['name']} · ${widget.target['section']}'),
      constraints: const BoxConstraints(maxWidth: 520),
      actions: [
        ShadButton.outline(
          enabled: !saving,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ShadButton(
          enabled: !saving,
          onPressed: save,
          child: Text(saving ? 'Saving…' : 'Save correction'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              WorkflowNotice(
                title: 'Unable to save',
                message: error!,
                error: true,
              ),
            WorkflowField(
              label: 'Team name for this event',
              child: ShadInput(
                controller: name,
                enabled: !saving,
                maxLength: 120,
              ),
            ),
            if (!widget.conceptEnabled)
              WorkflowField(
                label: 'Project title',
                child: ShadInput(
                  controller: project,
                  enabled: !saving,
                  maxLength: 255,
                ),
              )
            else
              const WorkflowNotice(
                title: 'Concept titles',
                message:
                    'Concept title changes use the existing concept review and revision workflow.',
              ),
            const Text(
              'This corrects this event’s details. Starting a different project uses Project setup.',
            ),
          ],
        ),
      ),
    ),
  );
}
