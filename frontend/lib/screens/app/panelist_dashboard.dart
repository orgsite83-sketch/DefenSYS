import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import 'student/profile_edit_screen.dart';
import 'panelist/panelist_models.dart';
import 'panelist/assignments_tab.dart';
import 'panelist/grade_sheet_tab.dart';
import 'panelist/overall_results_tab.dart';
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
import '../../config/api_config.dart';
import '../../navigation/admin_route_paths.dart';
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
  int _selectedTeamIndex = 0;
  bool _loading = true;
  bool _resultsLoading = false;
  bool _navigating = false;
  final _gradeSheetKey = GlobalKey<GradeSheetTabState>();
  String? _assignmentsError;
  String? _resultsError;

  List<TeamData> _teams = [];
  List<Map<String, dynamic>> _results = [];

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
    _loadData();
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
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
        final selectedSchedule = _teams.isNotEmpty
            ? _teams[_selectedTeamIndex].scheduleId
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
            redefenseVerificationRequired: team['redefense_verification_required'] == true,
            workflowGrade: team['grade_record'] is Map ? Map<String, dynamic>.from(team['grade_record']) : null,
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
          final selectedIndex = _teams.indexWhere(
            (t) => t.scheduleId == selectedSchedule,
          );
          _selectedTeamIndex = selectedIndex >= 0 ? selectedIndex : 0;
          _loading = false;
          _assignmentsError = null;
        });
        await _loadResults();
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

  Widget _buildBody() {
    if (_assignmentsError != null) {
      return _buildAssignmentsError();
    }

    return IndexedStack(
      index: _selectedIndex.clamp(0, 2),
      children: [
        AssignmentsTab(
          teams: _teams,
          onOpenGradeSheet: _openGradeSheet,
          onRefresh: _loadData,
        ),
        GradeSheetTab(
          key: _gradeSheetKey,
          teams: _teams,
          selectedTeamIndex: _selectedTeamIndex,
          onTeamChanged: (i) => setState(() => _selectedTeamIndex = i),
          onGradesSubmitted: () => _loadData(showLoading: false),
          onEvaluationChanged: () => setState(() {}),
          onRefresh: _loadData,
        ),
        OverallResultsTab(
          results: _results,
          loading: _resultsLoading,
          error: _resultsError,
          onRetry: _loadResults,
          onRefresh: _loadData,
        ),
      ],
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
                FacultyAppWorkspaceSwitcher(currentRoute: AppRoutes.panelist,
                  beforeSwitch: () async => await (
                    _gradeSheetKey.currentState?.savePendingChanges() ?? Future.value(true))),
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
                icon: const Icon(Icons.assignment),
                label: context.l10n.navAssignments,
              ),
              NavigationDestination(
                icon: const Icon(Icons.rate_review),
                label: context.l10n.navGradeSheet,
              ),
              NavigationDestination(
                icon: const Icon(Icons.bar_chart),
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
        final currentTeam =
            _teams.isNotEmpty && _selectedTeamIndex < _teams.length
            ? _teams[_selectedTeamIndex]
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Defense Grade Sheet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (currentTeam != null)
              Text(
                currentTeam.name,
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
