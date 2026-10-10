import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import 'student/profile_edit_screen.dart';
import 'panelist/panelist_models.dart';
import 'panelist/panelist_stage.dart';
import 'panelist/panelist_session.dart';
import 'panelist/assignments_tab.dart';
import 'panelist/grade_sheet_tab.dart';
import 'panelist/overall_results_tab.dart';
import 'panelist/widgets/panelist_segmented_tabs.dart';
import '../../services/auth_provider.dart';
import '../../services/authenticated_client.dart';
import '../../services/authz_errors.dart';
import '../../services/session_expired.dart';
import '../../theme/defensys_tokens.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/defensys_skeleton.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../config/api_config.dart';
import '../../navigation/admin_route_paths.dart';
import '../../notifications/notifications_bell.dart';
import '../../widgets/minutes/faculty_app_workspace_switcher.dart';

class PanelistDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const PanelistDashboard({super.key, this.userData});

  @override
  ConsumerState<PanelistDashboard> createState() => _PanelistDashboardState();
}

class _PanelistDashboardState extends ConsumerState<PanelistDashboard>
    with WidgetsBindingObserver {
  Timer? _availabilityTimer;
  DateTime _lastDay = TeamData.manilaToday;
  bool _refreshingAssignments = false;
  int _selectedIndex = 0;
  String? _selectedScheduleId;
  String? _selectedStageKey;
  String? _selectedSessionKey;
  bool _showHistory = false;
  final _workspaceTabs = ShadTabsController<bool>(value: false);
  bool _loading = true;
  bool _resultsLoading = false;
  bool _navigating = false;
  String? _workspaceChangeError;
  final _gradeSheetKey = GlobalKey<GradeSheetTabState>();
  String? _assignmentsError;
  String? _resultsError;

  List<TeamData> _teams = [];
  List<Map<String, dynamic>> _results = [];

  List<PanelistStage> get _stages {
    final stages = <String, PanelistStage>{};
    for (final team in _sessionTeams) {
      final stage = PanelistStage.forTeam(team);
      stages[stage.key] = stage;
    }
    return stages.values.toList();
  }

  List<PanelistSession> get _sessions {
    final grouped = <String, List<TeamData>>{};
    for (final team in _teams) {
      grouped.putIfAbsent(PanelistSession.teamKey(team), () => []).add(team);
    }
    return [
      for (final entry in grouped.entries)
        PanelistSession(entry.key, entry.value),
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  List<PanelistSession> get _modeSessions {
    final sessions = _sessions;
    return sessions
        .where((session) => session.isHistory(sessions) == _showHistory)
        .toList();
  }

  List<TeamData> get _sessionTeams =>
      _modeSessions
          .where((session) => session.key == _selectedSessionKey)
          .firstOrNull
          ?.teams ??
      [];

  List<TeamData> get _visibleTeams => _sessionTeams
      .where((team) => PanelistStage.forTeam(team).key == _selectedStageKey)
      .toList();

  List<Map<String, dynamic>> get _visibleResults => _results
      .where(
        (result) =>
            _visibleTeams.any(
              (team) => team.scheduleId == result['schedule_id']?.toString(),
            ) &&
            PanelistStage.forResult(result).key == _selectedStageKey,
      )
      .toList();

  int get _selectedTeamIndex {
    final index = _visibleTeams.indexWhere(
      (team) => team.scheduleId == _selectedScheduleId,
    );
    return index >= 0 ? index : 0;
  }

  void _ensureStageSelection() {
    final sessions = _modeSessions;
    if (!sessions.any((session) => session.key == _selectedSessionKey)) {
      final today = TeamData.manilaToday;
      final preferred =
          sessions
              .where(
                (session) =>
                    session.startsAt.year == today.year &&
                    session.startsAt.month == today.month &&
                    session.startsAt.day == today.day,
              )
              .firstOrNull ??
          sessions
              .where((session) => !session.startsAt.isBefore(today))
              .firstOrNull ??
          sessions.lastOrNull;
      _selectedSessionKey = preferred?.key;
      _selectedStageKey = null;
      _selectedScheduleId = null;
    }
    if (_stages.any((stage) => stage.key == _selectedStageKey)) return;
    final active = _sessionTeams;
    final preferred =
        active.where((team) => team.gradingAvailable).firstOrNull ??
        active.where((team) => !team.isPosted).firstOrNull ??
        active.firstOrNull ??
        active.lastOrNull;
    _selectedStageKey = preferred != null
        ? PanelistStage.forTeam(preferred).key
        : _stages.firstOrNull?.key;
    _selectedScheduleId = null;
  }

  String? get _stagePreferenceKey {
    final user = widget.userData ?? ref.read(authProvider).user;
    final id = user?['id'] ?? user?['guest_code_id'];
    return id == null ? null : 'panel_stage_${user?['role']}_$id';
  }

  Future<void> _initializeWorkspace() async {
    try {
      final key = _stagePreferenceKey;
      if (key != null) {
        final preferences = await SharedPreferences.getInstance();
        _selectedStageKey = preferences.getString(key);
        _selectedSessionKey = preferences.getString('${key}_session');
      }
    } catch (_) {
      // The workspace remains usable when local preference storage is unavailable.
    }
    if (mounted) await _loadData();
  }

  Future<void> _rememberStage() async {
    try {
      final key = _stagePreferenceKey;
      if (key != null && _selectedStageKey != null) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(key, _selectedStageKey!);
        if (_selectedSessionKey != null) {
          await preferences.setString('${key}_session', _selectedSessionKey!);
        }
      }
    } catch (_) {
      // Remembering a view must never block grading or history access.
    }
  }

  Future<void> _changeWorkspace({
    String? stageKey,
    String? sessionKey,
    bool? history,
  }) async {
    if (_navigating || _loading) return;
    _navigating = true;
    _workspaceChangeError = null;
    try {
      if (!await (_gradeSheetKey.currentState?.savePendingChanges() ??
          Future.value(true))) {
        _workspaceChangeError =
            'Your draft could not be saved. Check your connection and try again.';
        return;
      }
      if (!mounted) return;
      if (stageKey != null && !_stages.any((stage) => stage.key == stageKey)) {
        return;
      }
      setState(() {
        if (stageKey != null) _selectedStageKey = stageKey;
        if (sessionKey != null) {
          _selectedSessionKey = sessionKey;
          _selectedStageKey = null;
        }
        if (history != null) _showHistory = history;
        _selectedScheduleId = null;
        _ensureStageSelection();
      });
      await _rememberStage();
    } finally {
      _navigating = false;
      if (mounted) {
        _workspaceTabs.select(_showHistory);
        setState(() {});
      }
    }
  }

  bool get _isGuest =>
      widget.userData?['role'] == 'guest_panelist' ||
      ref.read(authProvider).user?['role'] == 'guest_panelist';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _availabilityTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_lastDay != TeamData.manilaToday) {
        _lastDay = TeamData.manilaToday;
        _loadData(showLoading: false);
      }
    });
    _initializeWorkspace();
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _workspaceTabs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData(showLoading: false);
    final gradeSheet = _gradeSheetKey.currentState;
    if (state == AppLifecycleState.paused && gradeSheet != null) {
      unawaited(gradeSheet.savePendingChanges());
    }
  }

  Future<void> _loadResults() async {
    if (!mounted) return;
    setState(() => _resultsLoading = true);

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final path = _isGuest ? 'guest-panelist-results/' : 'panelist-results/';
      final url = Uri.parse('${ApiConfig.defenseSchedulesUrl}/$path');
      final response = await httpClient.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final raw = data['results'] as List? ?? [];
        _results = raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        setState(() {
          _ensureStageSelection();
          _resultsLoading = false;
          _resultsError = null;
        });
      } else {
        setState(() {
          _resultsLoading = false;
          _resultsError = friendlyHttpErrorMessage(
            response.statusCode,
            response.body,
          );
        });
      }
    } on SessionExpiredException {
      if (mounted) setState(() => _resultsLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultsLoading = false;
          _resultsError = 'Error loading results: $e';
        });
      }
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (_refreshingAssignments || !mounted) return;
    _refreshingAssignments = true;
    setState(() {
      if (showLoading) _loading = true;
      _assignmentsError = null;
    });

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final path = _isGuest ? 'guest-assignments/' : 'panelist-assignments/';
      final assignmentsUrl = Uri.parse(
        '${ApiConfig.defenseSchedulesUrl}/$path',
      );
      final response = await httpClient.get(assignmentsUrl);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final teams = data['teams'] as List? ?? [];

        final previousTeams = {for (final t in _teams) t.scheduleId: t};
        final previousSession = _selectedSessionKey;
        final selectedSchedule = _visibleTeams.isNotEmpty
            ? _visibleTeams[_selectedTeamIndex].scheduleId
            : null;
        _teams = teams.map((team) {
          final weights =
              (team['grade_weights'] as Map?)?.cast<String, dynamic>() ?? {};
          final rawScope = team['scope']?.toString().trim() ?? '';
          final scope = rawScope == 'capstone' || rawScope == 'pit'
              ? rawScope
              : 'unknown';
          final isCapstone = scope == 'capstone';
          final rawDate = team['scheduled_date']?.toString() ?? '';
          final scheduledDate = DateTime.tryParse(rawDate);
          final isPosted =
              team['is_posted'] == true || team['is_submitted'] == true;
          final rawSubmissions =
              team['submissions'] as List? ??
              team['submitted_scores'] as List? ??
              [];
          final submissions = rawSubmissions
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList();

          final rawDefenseMaterials = team['defense_materials'] as List? ?? [];
          final defenseMaterials = rawDefenseMaterials.whereType<Map>().map((
            d,
          ) {
            final map = Map<String, dynamic>.from(d);
            final sub = map['submission'] is Map
                ? map['submission'] as Map
                : null;
            final fileUrl = (map['file_url']?.toString().isNotEmpty == true)
                ? map['file_url']?.toString()
                : sub?['file_url']?.toString();
            final fileName =
                (map['file_name']?.toString().isNotEmpty == true &&
                    map['file_name'] != 'File')
                ? map['file_name']?.toString()
                : (sub?['file_name']?.toString() ??
                      map['suggested_file_name']?.toString() ??
                      'File');
            final name =
                (map['name']?.toString().isNotEmpty == true &&
                    map['name'] != 'Defense Material')
                ? map['name']?.toString()
                : (map['label']?.toString() ?? 'Defense Material');

            map['file_url'] = fileUrl;
            map['file_name'] = fileName;
            map['name'] = name;
            map['label'] = name;
            return map;
          }).toList();

          final assignment = TeamData(
            name: (team['name'] ?? 'Team').toString(),
            project: (team['project_title'] ?? 'No project').toString(),
            defenseDate:
                '${team['defense_stage'] ?? 'No stage'} - ${team['scheduled_date'] ?? ''} ${team['start_time'] ?? ''}',
            stageName: (team['defense_stage'] ?? '').toString(),
            eventName: (team['event_name'] ?? '').toString(),
            startTime: (team['start_time'] ?? '').toString(),
            room: (team['room'] ?? '').toString(),
            leaderName: (team['leader_name'] ?? '').toString(),
            adviserName: (team['adviser_name'] ?? '').toString(),
            instructorName: (team['instructor_name'] ?? '').toString(),
            section: (team['section'] ?? '').toString(),
            level: (team['year_level'] ?? team['level'] ?? '').toString(),
            isCapstone: isCapstone,
            scope: scope,
            teamId: (team['id'] ?? 0).toString(),
            scheduleId: (team['schedule_id'] ?? '').toString(),
            sessionId: team['session_id']?.toString() ?? '',
            semesterId: team['semester_id']?.toString() ?? '',
            semesterLabel: team['display_semester']?.toString() ?? '',
            defenseStageId: team['defense_stage_id']?.toString() ?? '',
            displayStatus: team['display_status']?.toString() ?? '',
            isCompleted: team['is_completed'] == true,
            members: (team['members'] as List? ?? [])
                .map((m) => (m['name'] ?? m['username'] ?? 'Member').toString())
                .toList(),
            memberDetails: (team['members'] as List? ?? [])
                .map(
                  (m) => TeamMember(
                    id: (m['id'] ?? '').toString(),
                    name: (m['name'] ?? m['username'] ?? 'Member').toString(),
                    isLeader:
                        m['is_leader'] == true ||
                        (team['leader_id'] != null &&
                            (m['id'] ?? '').toString() ==
                                team['leader_id'].toString()),
                  ),
                )
                .toList(),
            criteria: [],
            isPosted: isPosted,
            submittedSubmissions: submissions,
            defenseMaterials: defenseMaterials,
            panelWeight: (weights['panel'] as num?)?.toInt() ?? 0,
            peerWeight: (weights['peer'] as num?)?.toInt() ?? 0,
            adviserWeight: (weights['adviser'] as num?)?.toInt() ?? 0,
            panelRubric: team['panel_rubric'] is Map
                ? Map<String, dynamic>.from(team['panel_rubric'] as Map)
                : null,
            scheduledDate: scheduledDate,
            serverGradingAvailable: team['grading_available'] as bool?,
            gradingUnavailableReason:
                team['grading_unavailable_reason']?.toString() ?? '',
            evaluationContext: team['evaluation_context']?.toString() ?? '',
            serverCanIssueVerdict: team['can_issue_verdict'] as bool?,
            verdictUnavailableReason:
                team['verdict_unavailable_reason']?.toString() ?? '',
            scheduleStatus: team['schedule_status']?.toString() ?? 'scheduled',
            draftSubmissions: (team['draft']?['submissions'] as List? ?? [])
                .whereType<Map>()
                .map((s) => Map<String, dynamic>.from(s))
                .toList(),
            draftSavedAt: team['draft']?['saved_at']?.toString(),
            isChair: team['is_chair'] == true,
            verdict: team['verdict']?.toString(),
            verdictRemarks: team['verdict_remarks']?.toString(),
            verdictByName: team['verdict_by_name']?.toString(),
            revisionDeadline: team['revision_deadline']?.toString(),
            redefenseVerificationRequired:
                team['redefense_verification_required'] == true,
            workflowGrade: team['grade_record'] is Map
                ? Map<String, dynamic>.from(team['grade_record'])
                : null,
            attemptCount: (team['attempt_count'] as num?)?.toInt() ?? 1,
            gradeId: (team['grade_id'] as num?)?.toInt(),
          );
          final previous = previousTeams[assignment.scheduleId];
          if (!assignment.isPosted &&
              previous != null &&
              previous.hasUnsavedChanges &&
              previous.evaluationContext == assignment.evaluationContext) {
            assignment.draftSubmissions = previous.draftSubmissions;
            assignment.hasUnsavedChanges = true;
          }
          return assignment;
        }).toList();

        setState(() {
          _ensureStageSelection();
          _selectedScheduleId =
              _visibleTeams.any((team) => team.scheduleId == selectedSchedule)
              ? selectedSchedule
              : null;
          _loading = false;
          _assignmentsError = null;
        });
        await _loadResults();
        if (mounted &&
            !_showHistory &&
            previousTeams.isNotEmpty &&
            previousSession != _selectedSessionKey &&
            _sessions.any(
              (session) =>
                  session.key == previousSession &&
                  session.isHistory(_sessions),
            )) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Grading day finished. Earlier evaluations are in History.',
              ),
              action: SnackBarAction(
                label: 'History',
                onPressed: () => _changeWorkspace(history: true),
              ),
            ),
          );
        }
      } else {
        setState(() {
          _loading = false;
          _assignmentsError = friendlyHttpErrorMessage(
            response.statusCode,
            response.body,
          );
        });
      }
    } on SessionExpiredException {
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _assignmentsError = 'Error loading assignments: $e';
        });
      }
    } finally {
      _refreshingAssignments = false;
    }
  }

  Widget _buildAssignmentsError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBanner(
          title: 'Failed to load assignments',
          message: _assignmentsError!,
          onRetry: _loadData,
        ),
      ),
    );
  }

  Future<void> _openGradeSheet(int teamIndex) async {
    if (_navigating || _loading) return;
    _navigating = true;
    try {
      final opened = await _gradeSheetKey.currentState?.openTeam(teamIndex);
      if (mounted && opened == true) setState(() => _selectedIndex = 1);
    } finally {
      _navigating = false;
    }
  }

  Future<void> _selectDestination(int index) async {
    if (_navigating || index == _selectedIndex) return;
    _navigating = true;
    try {
      if (_selectedIndex == 1 &&
          !await (_gradeSheetKey.currentState?.savePendingChanges() ??
              Future.value(true))) {
        return;
      }
      if (!mounted) return;
      setState(() => _selectedIndex = index);
      if (index == 2) await _loadResults();
    } finally {
      _navigating = false;
    }
  }

  Future<String?> _pickSession(
    BuildContext context,
    List<PanelistSession> sessions,
  ) async {
    var query = '';
    final ordered = [...sessions]
      ..sort(
        (a, b) => _showHistory
            ? b.startsAt.compareTo(a.startsAt)
            : a.startsAt.compareTo(b.startsAt),
      );
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) {
          final q = query.toLowerCase();
          final filtered = ordered.where((item) {
            final haystack = [
              item.label,
              for (final team in item.teams) ...[
                team.name,
                team.project,
                team.displayStage,
                team.displayEvent,
              ],
            ].join(' ').toLowerCase();
            return haystack.contains(q);
          }).toList();
          final screenHeight = MediaQuery.sizeOf(context).height;
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final available = screenHeight - keyboard - 80;
          final sheetHeight = available < 580 ? available : 580.0;
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: sheetHeight < 240 ? 240 : sheetHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        _showHistory
                            ? 'Choose a past session'
                            : 'Choose a session',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        key: const ValueKey('panel-session-search'),
                        autofocus: sessions.length > 5,
                        onChanged: (value) =>
                            refresh(() => query = value.trim()),
                        decoration: const InputDecoration(
                          hintText: 'Search date, room, team, or project',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching sessions'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final selected =
                                    item.key == _selectedSessionKey;
                                final newDay =
                                    index == 0 ||
                                    filtered[index - 1].day != item.day;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (newDay)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          3,
                                          14,
                                          3,
                                          8,
                                        ),
                                        child: Text(
                                          DateFormat(
                                            'EEEE, MMM d, yyyy',
                                          ).format(item.day),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                DefensysTokens.textSecondaryOf(
                                                  context,
                                                ),
                                          ),
                                        ),
                                      ),
                                    Material(
                                      color: selected
                                          ? DefensysTokens.maroonOf(
                                              context,
                                            ).withValues(alpha: .05)
                                          : DefensysTokens.surfaceOf(context),
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        key: ValueKey(
                                          'panel-session-option-${item.key}',
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => Navigator.pop(
                                          sheetContext,
                                          item.key,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: selected
                                                  ? DefensysTokens.maroonOf(
                                                      context,
                                                    )
                                                  : DefensysTokens.borderOf(
                                                      context,
                                                    ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.event_outlined,
                                                size: 18,
                                                color: selected
                                                    ? DefensysTokens.maroonTextOf(
                                                        context,
                                                      )
                                                    : DefensysTokens.textSecondaryOf(
                                                        context,
                                                      ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${DateFormat('h:mm a').format(item.startsAt)} · ${item.teams.first.room}',
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      '${item.teams.length} ${item.teams.length == 1 ? 'team' : 'teams'} · ${item.teams.map((team) => team.displayStage).toSet().join(', ')}',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            DefensysTokens.textSecondaryOf(
                                                              context,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                selected
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                          .chevron_right_rounded,
                                                size: 18,
                                                color: selected
                                                    ? DefensysTokens.maroonTextOf(
                                                        context,
                                                      )
                                                    : DefensysTokens.textSecondaryOf(
                                                        context,
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkspaceControls({VoidCallback? onSelectionChanged}) {
    final stages = _stages;
    final selected = stages
        .where((stage) => stage.key == _selectedStageKey)
        .firstOrNull;
    final sessions = _sessions;
    final activeCount = sessions
        .where((session) => !session.isHistory(sessions))
        .length;
    final historyCount = sessions.length - activeCount;
    final availableSessions = _modeSessions;
    final session = availableSessions
        .where((session) => session.key == _selectedSessionKey)
        .firstOrNull;
    final showSessionSelect =
        availableSessions.isNotEmpty &&
        (_showHistory || availableSessions.length > 1);
    final showStageSelect =
        stages.isNotEmpty && (_showHistory || stages.length > 1);
    final multipleTerms = stages.map((stage) => stage.term).toSet().length > 1;
    Future<void> select({
      String? stageKey,
      String? sessionKey,
      bool? history,
    }) async {
      await _changeWorkspace(
        stageKey: stageKey,
        sessionKey: sessionKey,
        history: history,
      );
      onSelectionChanged?.call();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelistSegmentedTabs<bool>(
            key: const ValueKey('panel-workspace-tabs'),
            controller: _workspaceTabs,
            onChanged: (history) => select(history: history),
            segments: [
              PanelistSegment(
                value: false,
                key: const ValueKey('panel-active-view'),
                label: MediaQuery.sizeOf(context).width < 480
                    ? 'Active'
                    : 'Active sessions',
                icon: Icons.event_available_outlined,
                count: '$activeCount',
              ),
              PanelistSegment(
                value: true,
                key: const ValueKey('panel-history-view'),
                label: 'History',
                icon: Icons.history_rounded,
                count: '$historyCount',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_workspaceChangeError != null) ...[
            ShadAlert.destructive(description: Text(_workspaceChangeError!)),
            const SizedBox(height: 12),
          ],
          if (showSessionSelect) ...[
            Text(
              'Assigned session',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Material(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const ValueKey('panel-session-selector'),
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final choice = await _pickSession(context, availableSessions);
                  if (choice != null && choice != _selectedSessionKey) {
                    await select(sessionKey: choice);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 18,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          session == null
                              ? 'Choose a session'
                              : '${session.label} · ${session.teams.length} ${session.teams.length == 1 ? 'team' : 'teams'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showStageSelect) ...[
            Text(
              'Defense stage / event',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              key: const ValueKey('panel-stage-selector'),
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final stage in stages)
                  Semantics(
                    selected: stage.key == _selectedStageKey,
                    button: true,
                    child: Material(
                      color: stage.key == _selectedStageKey
                          ? DefensysTokens.maroonOf(
                              context,
                            ).withValues(alpha: .07)
                          : DefensysTokens.surfaceOf(context),
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        key: ValueKey('panel-stage-option-${stage.key}'),
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => select(stageKey: stage.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: stage.key == _selectedStageKey
                                  ? DefensysTokens.maroonOf(context)
                                  : DefensysTokens.borderOf(context),
                            ),
                          ),
                          child: Text(
                            multipleTerms
                                ? '${stage.label} · ${stage.term}'
                                : stage.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: stage.key == _selectedStageKey
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: stage.key == _selectedStageKey
                                  ? DefensysTokens.maroonTextOf(context)
                                  : DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!_showHistory &&
              session != null &&
              selected != null &&
              (!showSessionSelect || !showStageSelect))
            Text(
              showStageSelect
                  ? session.label
                  : showSessionSelect
                  ? selected.label
                  : '${selected.label}\n${session.label}',
              key: const ValueKey('panel-active-context'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: DefensysTokens.textSecondary,
              ),
            )
          else if (selected != null && selected.term.isNotEmpty)
            Text(
              selected.term,
              style: const TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondary,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showWorkspaceSheet(BuildContext context) => showShadSheet<void>(
    context: context,
    builder: (sheetContext) => DefensysShadcnScope(
      child: StatefulBuilder(
        builder: (context, refreshControls) => ShadSheet(
          key: const ValueKey('panel-workspace-sheet'),
          title: const Text('Sessions & history'),
          isScrollControlled: true,
          scrollable: true,
          expandCrossSide: true,
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
            maxWidth: 560,
          ),
          actions: [
            ShadButton.outline(
              key: const ValueKey('close-panel-workspace'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Done'),
            ),
          ],
          child: _buildWorkspaceControls(
            onSelectionChanged: () {
              if (context.mounted) refreshControls(() {});
            },
          ),
        ),
      ),
    ),
  );

  Widget _buildEmptyWorkspace() => RefreshIndicator(
    onRefresh: _loadData,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(
          _showHistory ? Icons.history : Icons.assignment_outlined,
          size: 40,
          color: DefensysTokens.textSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          _showHistory
              ? 'No earlier grading sessions'
              : 'No active assignments for this session',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _showHistory
              ? 'A finished day moves to History when another session is assigned.'
              : 'Choose another session or view earlier evaluations in History.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: DefensysTokens.textSecondary,
          ),
        ),
        if (!_showHistory &&
            _sessions.any((session) => session.isHistory(_sessions))) ...[
          const SizedBox(height: 16),
          Center(
            child: ShadButton.outline(
              onPressed: () => _changeWorkspace(history: true),
              leading: const Icon(LucideIcons.history, size: 16),
              child: const Text('View history'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildBody() {
    if (_assignmentsError != null) {
      return _buildAssignmentsError();
    }

    final teams = _visibleTeams;
    return DefensysShadcnScope(
      child: Column(
        children: [
          if (_selectedIndex != 1) _buildWorkspaceControls(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex.clamp(0, 2),
              children: [
                teams.isEmpty
                    ? _buildEmptyWorkspace()
                    : AssignmentsTab(
                        key: ValueKey(
                          'assignments-$_selectedSessionKey-$_selectedStageKey-$_showHistory',
                        ),
                        teams: teams,
                        compactHeader: true,
                        history: _showHistory,
                        onOpenGradeSheet: _openGradeSheet,
                        onRefresh: _loadData,
                      ),
                GradeSheetTab(
                  key: _gradeSheetKey,
                  teams: teams,
                  selectedTeamIndex: _selectedTeamIndex,
                  onTeamChanged: (i) => setState(
                    () => _selectedScheduleId = _visibleTeams[i].scheduleId,
                  ),
                  onGradesSubmitted: () => _loadData(showLoading: false),
                  onEvaluationChanged: () => setState(() {}),
                  onRefresh: _loadData,
                  emptyMessage: _showHistory
                      ? 'No evaluations in this earlier session'
                      : 'No active assignments for this session',
                  stageScoped: true,
                ),
                OverallResultsTab(
                  key: ValueKey(
                    'results-$_selectedSessionKey-$_selectedStageKey-$_showHistory',
                  ),
                  results: _visibleResults,
                  showStageFilters: false,
                  initiallyExpanded: false,
                  emptyMessage: _showHistory
                      ? 'No submitted results for this earlier session.'
                      : 'No submitted results for this session and stage.',
                  loading: _resultsLoading,
                  error: _resultsError,
                  onRetry: _loadResults,
                  onRefresh: _loadData,
                  onOpenGradeSheet: teams.isEmpty
                      ? null
                      : () => _selectDestination(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
            title: _buildAppBarTitle(),
            actions: [
              if (!_isGuest)
                const NotificationsBell(
                  workspace: 'panelist',
                  workspaceLabel: 'Panelist',
                  color: Colors.white,
                ),
              if (_selectedIndex == 1 && !_loading)
                DefensysShadcnScope(
                  child: Builder(
                    builder: (context) => IconButton(
                      key: const ValueKey('open-panel-workspace'),
                      tooltip: 'Sessions & history',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => _showWorkspaceSheet(context),
                    ),
                  ),
                ),
              if (!_isGuest)
                FacultyAppWorkspaceSwitcher(
                  currentRoute: AppRoutes.panelist,
                  beforeSwitch: () async =>
                      await (_gradeSheetKey.currentState
                              ?.savePendingChanges() ??
                          Future.value(true)),
                ),
              if (_isGuest)
                IconButton(
                  icon: const Icon(Icons.account_circle_outlined),
                  tooltip: 'Guest access & sign out',
                  onPressed: () => _showGuestAccessSheet(context),
                ),
            ],
          ),
          body: OfflineBanner(
            child: IndexedStack(
              index: _selectedIndex == 3 ? 1 : 0,
              children: [
                _loading
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Text(
                              context.l10n.loadingAssignments,
                              style: const TextStyle(
                                color: DefensysTokens.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: DefensysSkeleton.list(
                                count: 6,
                                rowHeight: 64,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildBody(),
                if (!_isGuest)
                  const ProfileScreen(
                    showAppBar: false,
                    includeAppSettings: true,
                    compactInstallation: true,
                    compactPanelistHeader: true,
                  ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectDestination,
            indicatorColor: DefensysTokens.maroon.withValues(alpha: 0.15),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.assignment_outlined),
                selectedIcon: const Icon(Icons.assignment_rounded),
                label: context.l10n.navAssignments,
              ),
              NavigationDestination(
                icon: const Icon(Icons.rate_review_outlined),
                selectedIcon: const Icon(Icons.rate_review_rounded),
                label: context.l10n.navGradeSheet,
              ),
              NavigationDestination(
                icon: const Icon(Icons.bar_chart_outlined),
                selectedIcon: const Icon(Icons.bar_chart_rounded),
                label: context.l10n.navResults,
              ),
              if (!_isGuest)
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return const Text(
          'Assigned Defenses',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        );
      case 1:
        final currentTeam = _visibleTeams.isNotEmpty
            ? _visibleTeams[_selectedTeamIndex]
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Defense Grade Sheet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (currentTeam != null)
              Text(
                currentTeam.name,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );
      case 2:
        return const Text(
          'Defense Results',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        );
      case 3:
        return const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        );
      default:
        return const Text(
          'Panelist Workspace',
          style: TextStyle(fontWeight: FontWeight.bold),
        );
    }
  }

  String _guestAccessLabel(Map<String, dynamic>? user) {
    final expiry = DateTime.tryParse(user?['expires_at']?.toString() ?? '');
    return expiry == null
        ? 'External evaluator'
        : 'External evaluator · Access expires ${DateFormat('MMM d · h:mm a').format(expiry.toLocal())}';
  }

  void _showGuestAccessSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      backgroundColor: DefensysTokens.panelOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer(
        builder: (sheetCtx, ref, _) {
          final user = ref.watch(authProvider).user;
          final displayName = user != null && user['name'] != null
              ? user['name'] as String
              : (widget.userData?['name'] ?? 'Prof. Panelist');
          final avatarUrl = user?['avatar'] != null
              ? ApiConfig.publicMediaUrl(user!['avatar'] as String)
              : null;

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: DefensysTokens.maroon.withValues(
                          alpha: 0.15,
                        ),
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'P',
                                style: const TextStyle(
                                  color: DefensysTokens.maroon,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _guestAccessLabel(user),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About DefenSYS'),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Policy'),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PrivacyScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_rounded),
                      title: const Text('Terms & Conditions'),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TermsScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        final authNotifier = ref.read(authProvider.notifier);
                        Navigator.pop(sheetCtx);
                        if (await confirmLogout(context)) {
                          await authNotifier.logout();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
