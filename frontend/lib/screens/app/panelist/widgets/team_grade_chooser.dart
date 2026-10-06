import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../panelist_models.dart';

/// Browsing never activates another team's rubric. The named confirmation
/// delegates persistence/availability checks to the grade sheet before closing.
class TeamGradeChooser extends StatefulWidget {
  const TeamGradeChooser({
    super.key,
    required this.teams,
    required this.current,
    required this.onConfirm,
    this.initialPreview,
  });
  final List<TeamData> teams;
  final TeamData current;
  final TeamData? initialPreview;
  final Future<String?> Function(TeamData) onConfirm;

  @override
  State<TeamGradeChooser> createState() => _TeamGradeChooserState();
}

class _TeamGradeChooserState extends State<TeamGradeChooser> {
  TeamData? _preview;
  bool _saving = false;
  String? _error;
  final _search = TextEditingController();
  String _query = '';
  String _stage = '';

  String _stageKey(TeamData team) =>
      '${team.scope}|${team.displayStage}|${team.displayEvent}';

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isCurrent(TeamData team) =>
      team.scheduleId == widget.current.scheduleId &&
      team.teamId == widget.current.teamId;

  Future<void> _confirm(TeamData team) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onConfirm(team);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, team);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  Widget _status(TeamData team) {
    final progress = team.evaluationProgress;
    final label = team.isPosted
        ? 'Submitted · Locked'
        : !team.gradingAvailable
        ? team.evaluationStatus
        : progress.entered > 0
        ? 'Draft · ${progress.label}'
        : 'Not started';
    return ShadBadge.outline(child: Text(label));
  }

  Widget _identity(TeamData team) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        team.name,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        team.project,
        style: TextStyle(
          fontSize: 13,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ShadBadge.outline(child: Text(team.displayStage)),
          if (!team.isCapstone)
            ShadBadge.outline(child: Text(team.displayEvent)),
          ShadBadge.outline(
            child: Text(team.isChair ? 'Panel Chair' : 'Panelist'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          if (team.scheduledDate != null)
            Text(DateFormat('MMM d, yyyy').format(team.scheduledDate!)),
          Text(team.formattedTime),
          Text(team.displayRoom),
          if (team.section.isNotEmpty) Text(team.section),
        ],
      ),
    ],
  );

  Widget _context(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        color: DefensysTokens.textSecondaryOf(context),
      ),
    ),
  );

  String get _currentDraftLabel => widget.current.isPosted
      ? 'Submitted scores stay with this team.'
      : widget.current.hasUnsavedChanges
      ? 'Your current draft will be saved before switching.'
      : widget.current.draftSavedAt != null
      ? 'Draft saved. Your scores stay with this team.'
      : 'No saved draft yet.';

  Widget _teamCard(TeamData team) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ShadCard(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isCurrent(team)) ...[
            const Text(
              'Current sheet',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
          ],
          _identity(team),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: _status(team)),
          const SizedBox(height: 8),
          Text(
            '${team.memberDetails.length} members · Leader: ${team.displayLeader}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          ShadButton.outline(
            key: ValueKey('preview-team-${team.scheduleId}-${team.teamId}'),
            height: 0,
            expands: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabled: !_saving,
            onPressed: _saving
                ? null
                : () {
                    if (_isCurrent(team)) {
                      _confirm(team);
                    } else {
                      setState(() {
                        _preview = team;
                        _error = null;
                      });
                    }
                  },
            child: Text(
              _isCurrent(team)
                  ? (team.isPosted ? 'View submitted scores' : 'Resume grading')
                  : team.isPosted
                  ? 'View ${team.name}'
                  : 'Preview ${team.name}',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _lineup() {
    final stages = <String, String>{
      for (final team in widget.teams)
        _stageKey(team): '${team.displayStage} · ${team.displayEvent}',
    };
    final teams = widget.teams.where((team) {
      final haystack =
          '${team.name} ${team.project} ${team.displayStage} ${team.displayEvent} ${team.displayRoom} ${team.members.join(' ')}'
              .toLowerCase();
      return haystack.contains(_query) &&
          (_stage.isEmpty || _stageKey(team) == _stage);
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _context('Open sheet: ${widget.current.name}\n$_currentDraftLabel'),
        const SizedBox(height: 16),
        if (stages.length > 1) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('team-stage-filter'),
            initialValue: _stage,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter stage / event',
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('All stages / events'),
              ),
              for (final stage in stages.entries)
                DropdownMenuItem(
                  value: stage.key,
                  child: Text(
                    stage.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _stage = value ?? ''),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.teams.length > 5) ...[
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Find a team or project',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[_errorNotice(), const SizedBox(height: 12)],
        for (final team in teams) _teamCard(team),
        if (teams.isEmpty) const Text('No matching teams.'),
        _context(
          'Scheduled times help identify teams. Confirm who is presenting.',
        ),
      ],
    );
  }

  Widget _errorNotice() => ShadAlert.destructive(
    key: const ValueKey('team-switch-error'),
    title: const Text('Team was not changed'),
    description: Text(_error!),
  );

  Widget _previewTeam(TeamData team) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      ShadButton.ghost(
        height: 44,
        enabled: !_saving,
        onPressed: _saving
            ? null
            : () => setState(() {
                _preview = null;
                _error = null;
              }),
        child: const Text('Back to teams'),
      ),
      const SizedBox(height: 12),
      _identity(team),
      const SizedBox(height: 20),
      const Text(
        'Presenting members',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final member in team.memberDetails)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(child: Text(member.name)),
              if (member.isLeader)
                const ShadBadge.outline(child: Text('Leader')),
            ],
          ),
        ),
      const Divider(height: 24),
      _context('Is this the team presenting? Match their project and members.'),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: _status(team)),
      const SizedBox(height: 12),
      _context('${widget.current.name}: $_currentDraftLabel'),
      if (!team.gradingAvailable && !team.isPosted) ...[
        const SizedBox(height: 12),
        _context(
          team.gradingUnavailableReason.isNotEmpty
              ? team.gradingUnavailableReason
              : 'You can review the defense materials and rubric. Scoring is currently unavailable.',
        ),
      ],
      if (_error != null) ...[const SizedBox(height: 12), _errorNotice()],
    ],
  );

  Widget _confirmation(TeamData team) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ShadButton(
        key: const ValueKey('confirm-team-selection'),
        height: 0,
        expands: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabled: !_saving,
        backgroundColor: DefensysTokens.maroonOf(context),
        foregroundColor: Colors.white,
        onPressed: _saving ? null : () => _confirm(team),
        child: Text(
          _saving
              ? 'Saving current draft…'
              : team.isPosted
              ? 'View submitted grades for ${team.name}'
              : !team.gradingAvailable
              ? 'View defense for ${team.name}'
              : team.hasDraft
              ? 'Resume grading ${team.name}'
              : 'Start grading ${team.name}',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: DefensysTokens.surfaceOf(context),
        appBar: AppBar(
          title: Text(_preview == null ? 'Choose a team' : 'Team preview'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Keep current team',
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        body: _preview == null ? _lineup() : _previewTeam(_preview!),
        bottomNavigationBar: _preview == null ? null : _confirmation(_preview!),
      ),
    ),
  );
}
