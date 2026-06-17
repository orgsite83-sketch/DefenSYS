import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/pit_instructor_provider.dart';
import '../../../services/pit_lead_cohort_provider.dart';
import '../../../services/student_teams_provider.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitLeadCohortSectionDetailScreen extends ConsumerStatefulWidget {
  final String sectionName;
  final VoidCallback onBack;

  const PitLeadCohortSectionDetailScreen({
    super.key,
    required this.sectionName,
    required this.onBack,
  });

  @override
  ConsumerState<PitLeadCohortSectionDetailScreen> createState() =>
      _PitLeadCohortSectionDetailScreenState();
}

class _PitLeadCohortSectionDetailScreenState
    extends ConsumerState<PitLeadCohortSectionDetailScreen> {
  int? _selectedFacultyId;
  bool _isReplacing = false;

  static const _maroon = DefensysUi.primaryMaroon;
  static const _ink = DefensysUi.textDark;
  static const _muted = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);

  String _sectionKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pitLeadCohortProvider.notifier).fetchCohort();
      ref.read(pitInstructorProvider.notifier).fetchAssignments();
      ref.read(studentTeamsProvider.notifier).fetchTeams(scope: 'active');
    });
  }

  @override
  Widget build(BuildContext context) {
    final cohortState = ref.watch(pitLeadCohortProvider);
    final instructorState = ref.watch(pitInstructorProvider);
    final teamsState = ref.watch(studentTeamsProvider);

    // Filter students
    final sectionStudents = cohortState.students.where((s) {
      final sSec = s['section']?.toString().trim() ?? '';
      final targetSec = widget.sectionName.trim();
      if (targetSec == 'Unassigned section') {
        return sSec.isEmpty || sSec == 'Unassigned section';
      }
      return _sectionKey(sSec) == _sectionKey(targetSec);
    }).toList();

    // Filter teams in this section
    final sectionTeams = teamsState.teams.where((t) {
      final tSec = t['section']?.toString().trim() ?? '';
      final targetSec = widget.sectionName.trim();
      if (targetSec == 'Unassigned section') {
        return tSec.isEmpty || tSec == 'Unassigned section';
      }
      return _sectionKey(tSec) == _sectionKey(targetSec);
    }).toList();

    final teamCount = sectionTeams.length;

    // Find active assignment
    final activeAssignment = instructorState.assignments.firstWhere(
      (a) =>
          _sectionKey(a['section']?.toString() ?? '') ==
              _sectionKey(widget.sectionName) &&
          a['is_active'] == true,
      orElse: () => <String, dynamic>{},
    );
    final hasInstructor = activeAssignment.isNotEmpty;

    final isAssignable = widget.sectionName != 'Unassigned section';

    // Faculty drop down items
    final facultyItems = instructorState.faculty
        .map((user) {
          final id = _asInt(user['id']);
          if (id == null) return null;
          final name =
              user['name']?.toString() ??
              user['username']?.toString() ??
              'Faculty';
          final role = user['displayRole'] is Map
              ? (user['displayRole']['label']?.toString() ?? 'Faculty')
              : 'Faculty';
          return DropdownMenuItem<int>(
            value: id,
            child: Text('$name ($role)'),
          );
        })
        .whereType<DropdownMenuItem<int>>()
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: DefensysUi.bgLight,
        body: SingleChildScrollView(
          padding: DefensysUi.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to sections',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: _maroon),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Section Details: ${widget.sectionName}',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'PIT Instructor, Student Roster & Teams',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (instructorState.error != null) ...[
                _notice(instructorState.error!, warning: true),
                const SizedBox(height: 16),
              ],
              if (instructorState.message != null) ...[
                _notice(instructorState.message!),
                const SizedBox(height: 16),
              ],

              // Tabs
              TabBar(
                labelColor: _maroon,
                unselectedLabelColor: _muted,
                indicatorColor: _maroon,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Overview & Instructor'),
                  Tab(text: 'Student Roster'),
                  Tab(text: 'Teams'),
                ],
              ),
              const SizedBox(height: 20),

              // TabBarView Content (simulated with Index or constraints since nested scroll can be tricky)
              // We'll use a dynamic Builder or widget that reads TabController to avoid height constraint issues.
              Consumer(
                builder: (context, ref, _) {
                  final tabController = DefaultTabController.of(context);
                  return AnimatedBuilder(
                    animation: tabController,
                    builder: (context, _) {
                      final index = tabController.index;
                      switch (index) {
                        case 0:
                          return _buildOverviewTab(
                            sectionStudents: sectionStudents,
                            teamCount: teamCount,
                            isAssignable: isAssignable,
                            activeAssignment: activeAssignment,
                            hasInstructor: hasInstructor,
                            instructorState: instructorState,
                            facultyItems: facultyItems,
                          );
                        case 1:
                          return _buildRosterTab(sectionStudents);
                        case 2:
                          return _buildTeamsTab(sectionTeams);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab({
    required List<Map<String, dynamic>> sectionStudents,
    required int teamCount,
    required bool isAssignable,
    required Map<String, dynamic> activeAssignment,
    required bool hasInstructor,
    required PitInstructorState instructorState,
    required List<DropdownMenuItem<int>> facultyItems,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stat cards Row
        Row(
          children: [
            Expanded(
              child: _statCard(
                title: '${sectionStudents.length}',
                subtitle: 'Enrolled Students',
                icon: Icons.people_alt_outlined,
                iconColor: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _statCard(
                title: '$teamCount',
                subtitle: teamCount == 1 ? 'Active Team' : 'Active Teams',
                icon: Icons.groups_outlined,
                iconColor: const Color(0xFF047857),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Instructor Assignment Card
        const Text(
          'PIT INSTRUCTOR',
          style: TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        DefensysCard(
          padding: const EdgeInsets.all(24),
          child: !isAssignable
              ? const Text(
                  'Instructor assignment is not available for Unassigned section.',
                  style: TextStyle(
                    color: _muted,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                )
              : _buildInstructorSection(
                  activeAssignment,
                  hasInstructor,
                  instructorState,
                  facultyItems,
                ),
        ),
      ],
    );
  }

  Widget _buildRosterTab(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: const Text(
          'No students enrolled in this section.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
      );
    }

    return DefensysCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Student Roster',
                style: DefensysUi.sectionTitle,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${students.length} total',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _tableHeader(const [
            _ColumnSpec('Name', 3.0),
            _ColumnSpec('Student ID', 2.0),
            _ColumnSpec('Team status', 2.5),
          ]),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: students.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
            itemBuilder: (context, index) {
              final student = students[index];
              final onTeam = student['team_status'] == 'on_team';
              final teamLabel = onTeam
                  ? (student['team_name']?.toString() ?? 'On team')
                  : 'Unassigned';

              return SizedBox(
                height: 54,
                child: Row(
                  children: [
                    _rowCell(
                      Text(
                        student['name']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      flex: 3.0,
                    ),
                    _rowCell(
                      Text(
                        student['username']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                      flex: 2.0,
                    ),
                    _rowCell(
                      onTeam
                          ? DefensysStatusBadge.success(
                              label: teamLabel,
                              showDot: false,
                            )
                          : const DefensysStatusBadge.inactive(
                              label: 'Unassigned',
                            ),
                      flex: 2.5,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTeamsTab(List<Map<String, dynamic>> teams) {
    if (teams.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: const Text(
          'No teams created in this section yet.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
      );
    }

    return DefensysCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Section Teams',
                style: DefensysUi.sectionTitle,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${teams.length} total',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _tableHeader(const [
            _ColumnSpec('Team Name', 2.0),
            _ColumnSpec('Project Title', 2.5),
            _ColumnSpec('Leader', 1.8),
            _ColumnSpec('Members', 3.5),
            _ColumnSpec('Team Result', 1.8),
            _ColumnSpec('Action', 1.2),
          ]),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: teams.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
            itemBuilder: (context, index) {
              final team = teams[index];
              final teamId = _asInt(team['id']);
              final leaderName = team['leader_name']?.toString() ?? '-';
              final projectTitle = team['project_title']?.toString() ?? team['name']?.toString() ?? '-';
              
              // extract members list
              final membersList = team['members'] as List? ?? const [];
              final memberNames = membersList
                  .map((m) => m['name']?.toString() ?? '')
                  .where((name) => name.isNotEmpty)
                  .join(', ');

              return SizedBox(
                height: 58,
                child: Row(
                  children: [
                    _rowCell(
                      Text(
                        team['name']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      flex: 2.0,
                    ),
                    _rowCell(
                      Text(
                        projectTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      flex: 2.5,
                    ),
                    _rowCell(
                      Text(
                        leaderName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _ink, fontSize: 13),
                      ),
                      flex: 1.8,
                    ),
                    _rowCell(
                      Text(
                        memberNames.isNotEmpty ? memberNames : '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                      flex: 3.5,
                    ),
                    _rowCell(
                      _teamStatusBadge(team['status']?.toString() ?? 'Pending'),
                      flex: 1.8,
                    ),
                    _rowCell(
                      Tooltip(
                        message: 'View team details',
                        child: InkWell(
                          onTap: teamId == null
                              ? null
                              : () {
                                  final route = FacultyRoutes.teamDetail(teamId);
                                  context.push(route);
                                },
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF2563EB),
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                      flex: 1.2,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructorSection(
    Map<String, dynamic> activeAssignment,
    bool hasInstructor,
    PitInstructorState instructorState,
    List<DropdownMenuItem<int>> facultyItems,
  ) {
    if (hasInstructor) {
      final name = activeAssignment['faculty_name']?.toString() ?? 'Faculty';
      final email = activeAssignment['faculty_email']?.toString() ?? '';

      if (!_isReplacing) {
        return Row(
          children: [
            CircleAvatar(
              backgroundColor: _maroon.withValues(alpha: 0.1),
              foregroundColor: _maroon,
              radius: 20,
              child: const Icon(Icons.person_rounded, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            const StatusBadge.success(label: 'Active'),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: _muted),
              onSelected: (val) {
                if (val == 'replace') {
                  setState(() => _isReplacing = true);
                } else if (val == 'remove') {
                  _removeInstructor(activeAssignment['id']);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'replace',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Replace Instructor'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Remove Assignment', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: _muted, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Replacing $name',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedFacultyId,
              hint: const Text('Select replacement faculty'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: facultyItems,
              onChanged: instructorState.isSaving
                  ? null
                  : (val) => setState(() => _selectedFacultyId = val),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: instructorState.isSaving
                      ? null
                      : () => setState(() {
                            _isReplacing = false;
                            _selectedFacultyId = null;
                          }),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectedFacultyId == null || instructorState.isSaving
                      ? null
                      : () => _replaceInstructor(
                            activeAssignment['id'],
                            _selectedFacultyId!,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: instructorState.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Assign Replacement'),
                ),
              ],
            ),
          ],
        );
      }
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: DefensysUi.warningText, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No instructor assigned to this section.',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              StatusBadge(
                label: 'Needs assignment',
                background: DefensysUi.warningBg,
                textColor: DefensysUi.warningText,
                borderColor: DefensysUi.warningBorder,
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _selectedFacultyId,
            hint: const Text('Select instructor faculty'),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: facultyItems,
            onChanged: instructorState.isSaving
                ? null
                : (val) => setState(() => _selectedFacultyId = val),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                icon: instructorState.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Assign Instructor'),
                onPressed: _selectedFacultyId == null || instructorState.isSaving
                    ? null
                    : () => _assignInstructor(_selectedFacultyId!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: columns.map(_tableHeaderCell).toList()),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            column.label,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _teamStatusBadge(String status) {
    final Color color;
    final Color bg;
    final Color border;

    switch (status) {
      case 'Approved':
        color = const Color(0xFF047857);
        bg = const Color(0xFFD1FAE5);
        border = const Color(0xFFA7F3D0);
        break;
      case 'Failed':
        color = const Color(0xFFB91C1C);
        bg = const Color(0xFFFEE2E2);
        border = const Color(0xFFFCA5A5);
        break;
      case 'Delayed/Extended':
        color = const Color(0xFFB45309);
        bg = const Color(0xFFFEF3C7);
        border = const Color(0xFFFDE68A);
        break;
      default:
        color = const Color(0xFFB45309);
        bg = const Color(0xFFFEF3C7);
        border = const Color(0xFFFDE68A);
        break;
    }

    return StatusBadge(
      label: status,
      background: bg,
      textColor: color,
      borderColor: border,
      showDot: false,
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning ? DefensysUi.warningBorder : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _assignInstructor(int facultyId) async {
    final ok = await ref
        .read(pitInstructorProvider.notifier)
        .assignInstructor(facultyId: facultyId, section: widget.sectionName);
    if (ok && mounted) {
      setState(() {
        _selectedFacultyId = null;
      });
    }
  }

  Future<void> _removeInstructor(int assignmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: const Text(
          'Are you sure you want to remove the instructor assignment for this section?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref
          .read(pitInstructorProvider.notifier)
          .setAssignmentActive(assignmentId, false);
    }
  }

  Future<void> _replaceInstructor(int currentAssignmentId, int newFacultyId) async {
    final deactivated = await ref
        .read(pitInstructorProvider.notifier)
        .setAssignmentActive(currentAssignmentId, false);
    if (!deactivated || !mounted) return;

    final assigned = await ref
        .read(pitInstructorProvider.notifier)
        .assignInstructor(facultyId: newFacultyId, section: widget.sectionName);

    if (assigned && mounted) {
      setState(() {
        _isReplacing = false;
        _selectedFacultyId = null;
      });
    }
  }
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}
