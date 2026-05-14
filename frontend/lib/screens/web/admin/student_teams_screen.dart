import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/student_teams_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../utils/csv_file_io.dart';
import 'widgets/defensys_admin_shell.dart';

class StudentTeamsScreen extends ConsumerStatefulWidget {
  const StudentTeamsScreen({super.key});

  @override
  ConsumerState<StudentTeamsScreen> createState() => _StudentTeamsScreenState();
}

class _StudentTeamsScreenState extends ConsumerState<StudentTeamsScreen> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _blue = DefensysUi.techBlue;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studentTeamsProvider.notifier).fetchTeams();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentTeamsProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.groups_2_rounded,
            title: 'Student Teams',
            subtitle:
                'Manage all capstone project teams, assign advisers, and review defense context.',
            actions: _headerActions(state),
          ),
          const SizedBox(height: 26),
          _summaryCards(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          const SizedBox(height: 22),
          _teamsTableCard(state),
        ],
      ),
    );
  }

  Widget _headerActions(StudentTeamsState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _secondaryButton(
          icon: Icons.description_rounded,
          label: 'CSV Template',
          onTap: _downloadCsvTemplate,
        ),
        const SizedBox(width: 14),
        _secondaryButton(
          icon: Icons.input_rounded,
          label: 'Import Teams',
          onTap: state.isSaving ? null : _pickTeamsCsv,
        ),
        const SizedBox(width: 14),
        _primaryButton(
          icon: Icons.add_rounded,
          label: 'Create New Team',
          onTap: state.isSaving ? null : () => _showTeamDialog(),
        ),
      ],
    );
  }

  Widget _summaryCards(StudentTeamsState state) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'All Teams',
            value: _count(state, 'all'),
            subtitle: '',
            icon: Icons.groups_2_rounded,
            selected: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Result Pending',
            value: _count(state, 'pending'),
            subtitle: 'Awaiting decision',
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFFB45309),
            iconBg: const Color(0xFFFEF3C7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Approved',
            value: _count(state, 'approved'),
            subtitle: 'Passed',
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF047857),
            iconBg: const Color(0xFFD1FAE5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Failed',
            value: _count(state, 'failed'),
            subtitle: 'Teams',
            icon: Icons.cancel_rounded,
            iconColor: const Color(0xFFB91C1C),
            iconBg: const Color(0xFFFEE2E2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Adviser Review',
            value: _count(state, 'no_adviser'),
            subtitle: 'Needs Review',
            icon: Icons.warning_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required int value,
    required String subtitle,
    required IconData icon,
    bool selected = false,
    Color iconColor = _blue,
    Color iconBg = const Color(0xFFEFF6FF),
  }) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF1F2F4) : iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: selected ? _ink : iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamsTableCard(StudentTeamsState state) {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _levelFilter(state),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator(color: _maroon)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: 1515, child: _teamsTable(state)),
            ),
          const SizedBox(height: 18),
          Container(height: 1, color: _line),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Showing ${state.teams.length} of ${_count(state, 'filtered')} teams',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField(StudentTeamsState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
          hintText: 'Search by project title, leader, or adviser...',
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _maroon),
          ),
        ),
        onSubmitted: (value) {
          ref.read(studentTeamsProvider.notifier).fetchTeams(search: value);
        },
      ),
    );
  }

  Widget _levelFilter(StudentTeamsState state) {
    final levelItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'Capstone',
        child: Text('All Capstone Teams'),
      ),
      const DropdownMenuItem(value: '', child: Text('All Teams')),
      ...state.levels.map(
        (level) => DropdownMenuItem(value: level, child: Text(level)),
      ),
    ];
    final values = levelItems.map((item) => item.value).toSet();
    final safeValue = values.contains(state.level) ? state.level : 'Capstone';

    return Container(
      width: 220,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: levelItems,
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(studentTeamsProvider.notifier)
                      .fetchTeams(level: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _teamsTable(StudentTeamsState state) {
    return Column(
      children: [
        _tableHeader(const [
          _ColumnSpec('Project Title', 1.45),
          _ColumnSpec('Year Level', 1.0),
          _ColumnSpec('Team Result', 1.12),
          _ColumnSpec('Defense Context', 1.42),
          _ColumnSpec('Leader', 0.78),
          _ColumnSpec('Adviser', 0.85),
          _ColumnSpec('Members', 0.98),
          _ColumnSpec('Action', 0.74),
        ]),
        if (state.teams.isEmpty)
          _emptyRows()
        else
          ...state.teams.map((team) => _teamRow(state, team)),
      ],
    );
  }

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: columns.map(_tableHeaderCell).toList()),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            column.label,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _teamRow(StudentTeamsState state, Map<String, dynamic> team) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          _tableCell(
            Text(
              _projectTitle(team),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            flex: 1.45,
          ),
          _tableCell(_bodyText(team['year_level']?.toString() ?? '-'), flex: 1),
          _tableCell(
            _statusBadge(team['status']?.toString() ?? 'Pending'),
            flex: 1.12,
          ),
          _tableCell(_bodyText(_defenseContext(team)), flex: 1.42),
          _tableCell(
            _bodyText(team['leader_name']?.toString() ?? '-'),
            flex: 0.78,
          ),
          _tableCell(
            _bodyText(team['adviser_name']?.toString() ?? '-'),
            flex: 0.85,
          ),
          _tableCell(_bodyText('${team['member_count'] ?? 0}'), flex: 0.98),
          _tableCell(_rowActions(state, team), flex: 0.74),
        ],
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _emptyRows() {
    return Container(
      height: 84,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Text(
        'No teams found.',
        style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'Approved' => _green,
      'Failed' => _red,
      'Delayed/Extended' => _gold,
      _ => const Color(0xFFB45309),
    };
    final bg = switch (status) {
      'Approved' => const Color(0xFFD1FAE5),
      'Failed' => const Color(0xFFFEE2E2),
      'Delayed/Extended' => const Color(0xFFFEF3C7),
      _ => const Color(0xFFFEF3C7),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _rowActions(StudentTeamsState state, Map<String, dynamic> team) {
    final teamId = _asInt(team['id']);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving ? null : () => _showTeamDialog(team),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.edit_square, color: _blue, size: 18),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || teamId == null
              ? null
              : () =>
                    _confirmDelete(teamId, team['name']?.toString() ?? 'team'),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.delete_rounded, color: _red, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: _gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning
        ? DefensysUi.warningBorder
        : DefensysUi.successBorder;

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
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _downloadCsvTemplate() async {
    await downloadTextFile(
      filename: 'defensys-team-import-template.csv',
      content: _sampleTeamCsvTemplate,
    );
  }

  Future<void> _pickTeamsCsv() async {
    try {
      final csv = await pickCsvTextFile();
      if (!mounted || csv == null) {
        return;
      }

      final rows = _parseCsv(csv);
      if (rows.isEmpty) {
        _snack('Selected file is not a valid DefenSYS team CSV template.');
        return;
      }

      await ref.read(studentTeamsProvider.notifier).bulkImport(rows);
    } catch (e) {
      _snack('Could not read CSV file: $e');
    }
  }

  Future<void> _showTeamDialog([Map<String, dynamic>? team]) async {
    final editing = team != null;
    final state = ref.read(studentTeamsProvider);
    
    // Check if user is PIT Lead (from dashboard provider)
    final dashState = ref.read(dashboardProvider('faculty'));
    final roles = (dashState.data?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    final isPitLead = roles['pit_lead'] == true;
    final isAdviser = roles['adviser'] == true;
    
    // Filter level options based on user role
    List<String> levelOptions;
    if (isPitLead && !isAdviser) {
      // PIT Lead only - show only PIT levels
      levelOptions = state.levels.where((level) => level.toUpperCase().contains('PIT')).toList();
      if (levelOptions.isEmpty) {
        levelOptions = const ['1st Year PIT', '2nd Year PIT', '3rd Year PIT'];
      }
    } else {
      // Admin or Adviser - show all levels
      levelOptions = state.levels.isEmpty
          ? const ['3rd Year Capstone', '4th Year Capstone']
          : state.levels;
    }
    
    final statusOptions = state.statuses.isEmpty
        ? const ['Pending', 'Approved', 'Failed', 'Delayed/Extended']
        : state.statuses;
    final name = TextEditingController(text: team?['name']?.toString() ?? '');
    final projectTitle = TextEditingController(
      text: team?['project_title']?.toString() ?? '',
    );
    var level =
        team?['level']?.toString() ??
        (levelOptions.isNotEmpty ? levelOptions.first : '3rd Year Capstone');
    if (!levelOptions.contains(level)) {
      level = levelOptions.first;
    }
    var status = team?['status']?.toString() ?? 'Pending';
    if (!statusOptions.contains(status)) {
      status = statusOptions.first;
    }
    var adviserId = _asInt(team?['adviser_id']);
    final selectedMembers = <int>{..._readIntList(team?['member_ids'])};
    var leaderId =
        _asInt(team?['leader_id']) ??
        (selectedMembers.isNotEmpty ? selectedMembers.first : null);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editing ? 'Edit Team' : 'Create New Team'),
              content: SizedBox(
                width: 660,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Team Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectTitle,
                        decoration: const InputDecoration(
                          labelText: 'Project Title',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: level,
                              decoration: const InputDecoration(
                                labelText: 'Year Level',
                              ),
                              items: levelOptions
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  level = value ?? level;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: status,
                              decoration: const InputDecoration(
                                labelText: 'Team Result',
                              ),
                              items: statusOptions
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  status = value ?? status;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Hide adviser dropdown for PIT Leads (they don't assign advisers)
                      if (!isPitLead || isAdviser) ...[
                        DropdownButtonFormField<int?>(
                          initialValue: adviserId,
                          decoration: const InputDecoration(labelText: 'Adviser'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Unassigned'),
                            ),
                            ...state.advisers.map(
                              (adviser) => DropdownMenuItem<int?>(
                                value: _asInt(adviser['id']),
                                child: Text(
                                  '${adviser['name']} (${adviser['username']})',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              adviserId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Members (${selectedMembers.length}/4)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _line),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: state.students.map((student) {
                            final studentId = _asInt(student['id'])!;
                            final selected = selectedMembers.contains(
                              studentId,
                            );
                            return CheckboxListTile(
                              value: selected,
                              title: Text(
                                '${student['name']} (${student['username']})',
                              ),
                              subtitle: leaderId == studentId
                                  ? const Text('Team Leader')
                                  : null,
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    if (selectedMembers.length >= 4 &&
                                        !selected) {
                                      return;
                                    }
                                    selectedMembers.add(studentId);
                                    leaderId ??= studentId;
                                  } else {
                                    selectedMembers.remove(studentId);
                                    if (leaderId == studentId) {
                                      leaderId = selectedMembers.isEmpty
                                          ? null
                                          : selectedMembers.first;
                                    }
                                  }
                                });
                              },
                              secondary: selected
                                  ? IconButton(
                                      tooltip: 'Set as leader',
                                      icon: Icon(
                                        leaderId == studentId
                                            ? Icons.workspace_premium_rounded
                                            : Icons.circle_outlined,
                                        color: leaderId == studentId
                                            ? _gold
                                            : _muted,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          leaderId = studentId;
                                        });
                                      },
                                    )
                                  : null,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select up to 4 members. Use the medal button to choose the leader.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedMembers.isEmpty ||
                          leaderId == null ||
                          name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: Text(editing ? 'Save Changes' : 'Create Team'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || saved != true) {
      name.dispose();
      projectTitle.dispose();
      return;
    }

    final payload = {
      'name': name.text.trim(),
      'project_title': projectTitle.text.trim().isEmpty
          ? name.text.trim()
          : projectTitle.text.trim(),
      'level': level,
      'year_level': _yearLevelFor(level),
      'leader_id': leaderId,
      'member_ids': selectedMembers.toList(),
      'adviser_id': adviserId,
      'status': status,
    };

    name.dispose();
    projectTitle.dispose();

    if (editing) {
      await ref
          .read(studentTeamsProvider.notifier)
          .updateTeam(_asInt(team['id'])!, payload);
    } else {
      await ref.read(studentTeamsProvider.notifier).addTeam(payload);
    }
  }

  Future<void> _confirmDelete(int teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Team'),
        content: Text('Delete $teamName? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await ref.read(studentTeamsProvider.notifier).deleteTeam(teamId);
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return [];
    }

    final headers = lines.first
        .split(',')
        .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
        .toList();
    int index(String name) => headers.indexOf(name);
    final teamNameIndex = index('team_name');
    final projectTitleIndex = index('project_title');
    final levelIndex = index('level');
    final yearLevelIndex = index('year_level');
    final memberIdsIndex = index('member_ids');
    final leaderIdIndex = index('leader_id');
    final adviserIdIndex = index('adviser_id');

    if ([
      teamNameIndex,
      levelIndex,
      memberIdsIndex,
      leaderIdIndex,
    ].contains(-1)) {
      return [];
    }

    return lines
        .skip(1)
        .map((line) {
          final columns = line.split(',').map((cell) => cell.trim()).toList();
          String read(int columnIndex) =>
              columnIndex >= 0 && columnIndex < columns.length
              ? columns[columnIndex]
              : '';

          return {
            'team_name': read(teamNameIndex),
            'project_title': read(projectTitleIndex),
            'level': read(levelIndex),
            'year_level': read(yearLevelIndex),
            'member_ids': read(memberIdsIndex)
                .split('|')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
            'leader_id': read(leaderIdIndex),
            'adviser_id': read(adviserIdIndex),
          };
        })
        .where((row) => row['team_name'].toString().isNotEmpty)
        .toList();
  }

  String _projectTitle(Map<String, dynamic> team) {
    final title = team['project_title']?.toString();
    if (title != null && title.trim().isNotEmpty) {
      return title;
    }
    return team['name']?.toString() ?? '-';
  }

  String _defenseContext(Map<String, dynamic> team) {
    final context = team['defense_context'];
    if (context is Map) {
      final stage = context['current_stage']?.toString();
      if (stage != null && stage.isNotEmpty) {
        return stage;
      }
      final readyForStage = context['ready_for_stage']?.toString();
      if (readyForStage != null && readyForStage.isNotEmpty) {
        return readyForStage;
      }
    }
    if (context is String && context.trim().isNotEmpty) {
      return context;
    }
    return 'No defense scheduled';
  }

  String _yearLevelFor(String level) {
    if (level.startsWith('1st Year')) return '1st Year';
    if (level.startsWith('2nd Year')) return '2nd Year';
    if (level.startsWith('3rd Year')) return '3rd Year';
    if (level.startsWith('4th Year')) return '4th Year';
    return '';
  }

  List<int> _readIntList(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value.map(_asInt).whereType<int>().toList();
  }

  int _count(StudentTeamsState state, String key) {
    final value = state.counts[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static const _sampleTeamCsvTemplate =
      'team_name,project_title,level,year_level,member_ids,leader_id,adviser_id\n'
      'Team VaultSync,Cloud File Sync,3rd Year Capstone,3rd Year,2024-0001|2024-0002,2024-0001,faculty-1\n';
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}
