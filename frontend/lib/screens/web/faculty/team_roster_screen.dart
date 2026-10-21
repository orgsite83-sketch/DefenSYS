import 'dart:async';
import 'package:excel/excel.dart' as xl;
import 'package:defensys/widgets/team_import_format_guide.dart';
import 'package:defensys/screens/web/admin/widgets/team_bulk_import_review_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../services/academic/team_roster_service.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/export/team_roster_excel_generator.dart';
import '../../../utils/import/team_bulk_import_file.dart';
import '../../../utils/import/team_bulk_import_csv.dart';
import '../../../widgets/shadcn/defensys_action_menu.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../widgets/shadcn/defensys_workflow_widgets.dart';

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
  String selected = 'current',
      source = 'current',
      projectMode = 'continue',
      method = 'alphabetical';
  int groupSize = 4, requestVersion = 0;
  StreamSubscription? _dropSubscription;
  bool dragging = false;
  bool busy = false, changed = false, carryProjects = true, missingOnly = false;
  List<Map<String, dynamic>> importRows = [];
  final setupTeams = <int>{};
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
  void dispose() {
    requestVersion++;
    _dropSubscription?.cancel();
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
        if (initial && widget.initialEvent != null) {
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

  void begin(String next) {
    setState(() {
      action = next;
      review = null;
      error = null;
      message = null;
      missingOnly = false;
      source = keyFor(
        rosters.firstWhere(
          (r) => keyFor(r) != selected,
          orElse: () => rosters.first,
        ),
      );
      projectMode = roster?['project_setup_policy'] == 'new'
          ? 'new'
          : 'continue';
      setupTeams
        ..clear()
        ..addAll(
          teams
              .where((t) => t['setup_opened'] != true)
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
      final parsed = parseTeamBulkCsv(readTeamImportFiles(files));
      if (parsed.rows.isEmpty) {
        throw const FormatException('No team rows were found in this file.');
      }
      setState(() {
        importRows = parsed.rows
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        fileName = files.map((f) => f.name).join(', ');
        review = null;
      });
    });
  }

  Future<void> preview() => run(() async {
    final result = await ref.read(teamRosterServiceProvider).preview({
      ...target,
      'operation': action,
      'carry_projects': carryProjects,
      if (action == 'copy' && source != 'current')
        'source_event_id': int.parse(source),
      if (action == 'import') 'teams': importRows,
      if (action == 'generate') ...{'group_size': groupSize, 'method': method},
    });
    if (mounted) setState(() => review = result);
  });

  Future<void> apply() => run(() async {
    await ref.read(teamRosterServiceProvider).apply(review!['preview_token']);
    if (!mounted) {
      return;
    }
    changed = true;
    setState(() {
      review = null;
      action = null;
      importRows = [];
      fileName = null;
    });
    await load();
    if (mounted && error == null) {
      setState(
        () => message = selected == 'current'
            ? 'Current roster updated for upcoming events. Saved event rosters are preserved.'
            : 'Roster applied to ${roster?['name']} · $section.',
      );
    }
  });

  Future<void> openSetup() => run(() async {
    final result = await ref.read(teamRosterServiceProvider).requestSetup({
      ...target,
      'project_mode': projectMode,
      'team_ids': setupTeams.toList(),
      'fingerprint': data!['fingerprint'],
    });
    if (!mounted) {
      return;
    }
    changed = true;
    setState(() {
      action = null;
      review = null;
    });
    await load();
    if (mounted && error == null) {
      setState(
        () => message =
            'Event setup opened for ${result['requested_count']} teams. Each leader now has a setup task.',
      );
    }
  });

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
                          '${r['status']}',
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
          badge('${roster?['status']}'),
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
      WorkflowNotice(
        title: locked
            ? 'Roster locked'
            : selected == 'current'
            ? 'Default for upcoming events'
            : 'Event roster',
        message: locked
            ? 'This event keeps its saved teams, leaders and members. You can export this roster or copy it into another roster.'
            : selected == 'current'
            ? 'New and upcoming events using the current roster follow this default. Ongoing, completed and custom event rosters keep their saved teams.'
            : roster?['source'] == 'custom'
            ? 'This roster applies only to this event and $section.'
            : 'This event uses your current teams until you apply a replacement or open team setup.',
      ),
      if (selected == 'current') ...[
        if (rosters.any((r) => r['locked'] == true))
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Saved events stay unchanged: ${rosters.where((r) => r['locked'] == true).map((r) => r['name']).join(', ')}.',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
      ],
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

  Widget browse() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rosterHeading(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
              secondary(
                'Import roster',
                Icons.upload_file_outlined,
                () => begin('import'),
              ),
              if (data?['can_generate'] == true)
                ShadButton(
                  height: 0,
                  enabled: !busy,
                  onPressed: () => begin('generate'),
                  leading: const Icon(Icons.groups_outlined, size: 16),
                  child: const Flexible(
                    child: Text('Generate teams', textAlign: TextAlign.center),
                  ),
                ),
            ],
            if (roster?['can_request_setup'] == true)
              secondary(
                'Project setup',
                Icons.assignment_outlined,
                () => begin('projects'),
              ),
            exportMenu(),
          ],
        ),
        const SizedBox(height: 20),
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
                contextLabel: '$year PIT · $section',
                section: section,
                onDownload: busy
                    ? null
                    : () => run(() async {
                        await downloadBinaryFile(
                          filename: 'PIT-$section-team-roster-template.xlsx',
                          bytes: generateOfficialTeamRosterExcelBytes(
                            isCapstone: false,
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
          if (importRows.isNotEmpty) ...[
            const Text(
              'Review teams',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TeamBulkImportReviewTable(
              rows: importRows,
              previewRows: const [],
              isCapstoneAdmin: false,
              pitLeadYear: year,
              showIssuesOnly: false,
              lockAssignments: true,
              sectionOptions: [if (section != null) section!],
              onRowChanged: (_) => setState(() => review = null),
              onDeleteRow: (index) => setState(() {
                importRows.removeAt(index);
                review = null;
              }),
              onAddRow: () => setState(() {
                importRows.add({
                  'group_key':
                      'manual/${DateTime.now().microsecondsSinceEpoch}',
                  'team_name': '',
                  'project_title': '',
                  'section': section ?? '',
                  'member_ids': <String>[],
                  'leader_id': '',
                });
                review = null;
              }),
            ),
            const SizedBox(height: 18),
          ],
        ],
        if (action == 'generate') ...[
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
                'Generate balanced teams from active enrolled students in this section. Each student appears once and each leader is a member.',
          ),
        ],
        if (action == 'projects') ...[
          WorkflowSelect(
            label: 'Project requirement',
            value: projectMode,
            enabled: !busy,
            options: {
              if (roster?['project_setup_policy'] != 'new')
                'continue': 'Continue existing projects',
              'new': roster?['concept_enabled'] == true
                  ? 'Request new concepts'
                  : 'Request new project titles',
            },
            searchable: false,
            onChanged: (v) => setState(() => projectMode = v),
          ),
          WorkflowNotice(
            title: 'Open event setup',
            message: roster?['concept_enabled'] == true
                ? 'Leaders confirm their team details and use the existing concept workflow. Existing proposal counts and shared-system rules still apply.'
                : 'Leaders confirm their team name and declare a project title. Declaring a title does not imply concept approval.',
          ),
          const Text(
            'Request details from',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final t in teams)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ShadCheckbox(
                value: setupTeams.contains(t['id']),
                enabled: !busy && t['setup_opened'] != true,
                onChanged: (v) => setState(
                  () => v
                      ? setupTeams.add(t['id'] as int)
                      : setupTeams.remove(t['id']),
                ),
                label: Text(
                  '${t['name']}${t['setup_opened'] == true ? ' · Setup already opened' : ''}',
                ),
              ),
            ),
          const WorkflowNotice(
            title: 'Roster confirmation',
            message:
                'Opening setup fixes this event’s members and leaders. Future changes to Current roster will not change these teams.',
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
            secondary(
              'Cancel',
              Icons.close,
              () => setState(() {
                action = null;
                review = null;
              }),
            ),
            ShadButton(
              height: 0,
              enabled:
                  !busy &&
                  (action != 'import' || importRows.isNotEmpty) &&
                  (action != 'projects' || setupTeams.isNotEmpty),
              onPressed: action == 'projects' ? openSetup : preview,
              child: Flexible(
                child: Text(
                  busy
                      ? 'Working…'
                      : action == 'projects'
                      ? 'Confirm roster & request details'
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

  Widget reviewPanel() => panel(
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

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
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
              if (error != null)
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
                if (_maps(data!['scope_options']).length > 1)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final options = _maps(data!['scope_options']);
                      return Wrap(
                        spacing: 12,
                        children: [
                          if (options
                                  .map((v) => v['year_level'])
                                  .toSet()
                                  .length >
                              1)
                            SizedBox(
                              width: constraints.maxWidth < 500
                                  ? constraints.maxWidth
                                  : 200,
                              child: WorkflowSelect(
                                label: 'PIT year',
                                value: year,
                                enabled: !busy,
                                searchable: false,
                                options: {
                                  for (final o in options)
                                    '${o['year_level']}': '${o['year_level']}',
                                },
                                onChanged: (v) {
                                  setState(() {
                                    year = v;
                                    section = null;
                                    action = null;
                                    review = null;
                                  });
                                  load();
                                },
                              ),
                            ),
                          SizedBox(
                            width: constraints.maxWidth < 500
                                ? constraints.maxWidth
                                : 220,
                            child: WorkflowSelect(
                              label: 'Section',
                              value: section,
                              enabled: !busy,
                              searchable: false,
                              options: {
                                for (final o in options.where(
                                  (o) => o['year_level'] == year,
                                ))
                                  '${o['section']}': '${o['section']}',
                              },
                              onChanged: (v) {
                                setState(() {
                                  section = v;
                                  action = null;
                                  review = null;
                                });
                                load();
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: LinearProgressIndicator(),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final content = review != null
                        ? reviewPanel()
                        : action != null
                        ? configure()
                        : browse();
                    if (constraints.maxWidth < 820) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          rosterList(),
                          const SizedBox(height: 16),
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
