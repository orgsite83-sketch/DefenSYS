import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
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
import '../../widgets/error_banner.dart';
import '../../config/api_config.dart';

class PanelistDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const PanelistDashboard({super.key, this.userData});

  @override
  ConsumerState<PanelistDashboard> createState() => _PanelistDashboardState();
}

class _PanelistDashboardState extends ConsumerState<PanelistDashboard> {
  int _selectedIndex = 0;
  int _selectedTeamIndex = 0;
  bool _loading = true;
  bool _resultsLoading = false;
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
    _loadData();
  }

  Future<void> _loadResults() async {
    if (!mounted) return;
    setState(() => _resultsLoading = true);

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final path =
          _isGuest ? 'guest-panelist-results/' : 'panelist-results/';
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

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _assignmentsError = null;
    });

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final path = _isGuest ? 'guest-assignments/' : 'panelist-assignments/';
      final assignmentsUrl = Uri.parse('${ApiConfig.defenseSchedulesUrl}/$path');
      final response = await httpClient.get(assignmentsUrl);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final teams = data['teams'] as List? ?? [];

        _teams = teams.map((team) {
          final weights = (team['grade_weights'] as Map?)?.cast<String, dynamic>() ?? {};
          final isCapstone = team['is_capstone'] == true ||
              team['scope']?.toString() == 'capstone';
          return TeamData(
            name: (team['name'] ?? 'Team').toString(),
            project: (team['project_title'] ?? 'No project').toString(),
            defenseDate: '${team['defense_stage'] ?? 'No stage'} - ${team['scheduled_date'] ?? ''} ${team['start_time'] ?? ''}',
            isCapstone: isCapstone,
            scope: (team['scope'] ?? (isCapstone ? 'capstone' : 'pit')).toString(),
            teamId: (team['id'] ?? 0).toString(),
            scheduleId: (team['schedule_id'] ?? '').toString(),
            members: (team['members'] as List? ?? [])
                .map((m) => (m['name'] ?? m['username'] ?? 'Member').toString())
                .toList(),
            criteria: [],
            isPosted: false,
            panelWeight: (weights['panel'] as num?)?.toInt() ?? (isCapstone ? 50 : 80),
            peerWeight: (weights['peer'] as num?)?.toInt() ?? (isCapstone ? 20 : 20),
            adviserWeight: (weights['adviser'] as num?)?.toInt() ?? 0,
            panelRubric: team['panel_rubric'] is Map
                ? Map<String, dynamic>.from(team['panel_rubric'] as Map)
                : null,
          );
        }).toList();

        setState(() {
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

  Widget _buildBody() {
    if (_assignmentsError != null) {
      return _buildAssignmentsError();
    }

    return IndexedStack(
      index: _selectedIndex,
      children: [
        AssignmentsTab(
          teams: _teams,
          onOpenGradeSheet: (i) => setState(() {
            _selectedTeamIndex = i;
            _selectedIndex = 1;
          }),
        ),
        GradeSheetTab(
          teams: _teams,
          selectedTeamIndex: _selectedTeamIndex,
          onTeamChanged: (i) => setState(() => _selectedTeamIndex = i),
          onGradesSubmitted: _loadResults,
        ),
        OverallResultsTab(
          results: _results,
          loading: _resultsLoading,
          error: _resultsError,
          onRetry: _loadResults,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Text(
          context.l10n.panelistDashboardTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => _showProfileSheet(context),
          ),
        ],
      ),
      body: OfflineBanner(
        child: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: DefensysTokens.maroon),
                  SizedBox(height: 16),
                  Text('Loading assignments...',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : _buildBody(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
          if (i == 2) {
            _loadResults();
          }
        },
        indicatorColor: DefensysTokens.maroon.withOpacity(0.15),
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
        ],
      ),
    ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
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
                    borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: DefensysTokens.maroon,
                  child: Text(
                      (widget.userData?['name'] ?? 'P')[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(widget.userData?['name'] ?? 'Prof. Panelist',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Panelist · ID ${widget.userData?['id'] ?? '—'}',
                    style: const TextStyle(fontSize: 12)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About DefenSYS'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PrivacyScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: const Text('Terms & Conditions'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TermsScreen()));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  if (await confirmLogout(context)) {
                    await ref.read(authProvider.notifier).logout();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
