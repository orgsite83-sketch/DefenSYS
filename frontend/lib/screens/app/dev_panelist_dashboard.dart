import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../login_screen.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import 'panelist/panelist_models.dart';
import 'panelist/assignments_tab.dart';
import 'panelist/grade_sheet_tab.dart';
import 'panelist/overall_results_tab.dart';
import '../../services/auth_provider.dart';
import '../../config/api_config.dart';

class DevPanelistDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const DevPanelistDashboard({super.key, this.userData});

  @override
  ConsumerState<DevPanelistDashboard> createState() => _DevPanelistDashboardState();
}

class _DevPanelistDashboardState extends ConsumerState<DevPanelistDashboard> {
  int _selectedIndex = 0;
  int _selectedTeamIndex = 0;
  static const _primaryColor = Color(0xFF7F1D1D);
  bool _loading = true;

  List<TeamData> _teams = [];
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      // Get panelist ID
      final panelistId = widget.userData?['id']?.toString() ?? '';
      if (panelistId.isEmpty) {
        print('No panelist ID found');
        setState(() => _loading = false);
        return;
      }
      
      // Load panelist assignments (teams and rubrics assigned to this panelist)
      final assignmentsUrl = '${ApiConfig.defenseSchedulesUrl}/panelist-assignments/?panelist_id=$panelistId';
      print('Fetching panelist assignments from: $assignmentsUrl');
      
      final response = await http
          .get(
            Uri.parse(assignmentsUrl),
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));
      
      print('Assignments API response: ${response.statusCode}');

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        print('Assignments data keys: ${data.keys}');
        
        final teams = data['teams'] as List? ?? [];
        
        print('Found ${teams.length} assigned teams');
        
        // Convert teams to TeamData format
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
        
        setState(() => _loading = false);
      } else {
        print('Assignments API failed: ${response.statusCode}');
        print('Response: ${response.body}');
        setState(() => _loading = false);
      }
    } catch (e) {
      print('Error loading assignments: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Dev Panelist Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => _showProfileSheet(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _primaryColor),
                  SizedBox(height: 16),
                  Text('Loading assignments...',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : IndexedStack(
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
                  panelistId: (widget.userData?['id'] ?? '').toString(),
                  onTeamChanged: (i) => setState(() => _selectedTeamIndex = i),
                ),
                OverallResultsTab(results: _results),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        indicatorColor: _primaryColor.withOpacity(0.15),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.assignment), label: 'Assignments'),
          NavigationDestination(
              icon: Icon(Icons.rate_review), label: 'Grade Sheet'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'Results'),
        ],
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
                  backgroundColor: _primaryColor,
                  child: Text(
                      (widget.userData?['name'] ?? 'D')[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(widget.userData?['name'] ?? 'Prof. Dev Panelist',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('PIT Lead · ID ${widget.userData?['id'] ?? '—'}',
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
                onTap: () {
                  ref.read(authProvider.notifier).logout();
                  Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
