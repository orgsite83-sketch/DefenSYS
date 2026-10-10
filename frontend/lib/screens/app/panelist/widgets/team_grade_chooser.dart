import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../panelist_models.dart';
import 'defense_team_summary.dart';

/// Browsing never activates another team's rubric. The named confirmation
/// delegates persistence/availability checks to the grade sheet before closing.
class TeamGradeChooser extends StatefulWidget {
  const TeamGradeChooser({
    super.key,
    required this.teams,
    required this.current,
    required this.onConfirm,
    this.initialPreview,
    this.stageScoped = false,
  });
  final List<TeamData> teams;
  final TeamData current;
  final TeamData? initialPreview;
  final bool stageScoped;
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
    _stage = _stageKey(widget.initialPreview ?? widget.current);
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

  Widget _context(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: DefensysTokens.borderOf(context)),
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

  Widget _teamCard(TeamData team) {
    final current = _isCurrent(team);
    final borderColor = current
        ? DefensysTokens.maroonOf(context).withValues(alpha: .42)
        : DefensysTokens.borderOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShadCard(
        backgroundColor: DefensysTokens.surfaceOf(context),
        radius: BorderRadius.circular(12),
        border: ShadBorder.all(
          color: borderColor,
          radius: BorderRadius.circular(12),
        ),
        shadows: const [],
        padding: const EdgeInsets.all(14),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (current)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: DefensysTokens.maroonTextOf(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Current sheet',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                      ),
                    ],
                  ),
                _status(team),
                if (team.isChair)
                  const ShadBadge.outline(child: Text('Panel Chair')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              team.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -.25,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              team.project,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (!widget.stageScoped)
                  _meta(Icons.school_outlined, team.displayStage),
                if (team.scheduledDate != null)
                  _meta(
                    Icons.event_outlined,
                    DateFormat('MMM d').format(team.scheduledDate!),
                  ),
                _meta(Icons.schedule_outlined, team.formattedTime),
                _meta(Icons.place_outlined, team.displayRoom),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${team.memberDetails.length} members · Leader: ${team.displayLeader}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            if (current) ...[
              const SizedBox(height: 4),
              Text(
                _currentDraftLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ShadButton.outline(
              key: ValueKey('preview-team-${team.scheduleId}-${team.teamId}'),
              height: 44,
              expands: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              enabled: !_saving,
              onPressed: _saving
                  ? null
                  : () {
                      if (current) {
                        _confirm(team);
                      } else {
                        setState(() {
                          _preview = team;
                          _error = null;
                        });
                      }
                    },
              child: Text(
                current
                    ? (team.isPosted
                          ? 'View submitted scores'
                          : 'Open current sheet')
                    : team.isPosted
                    ? 'View ${team.name}'
                    : 'Preview ${team.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: DefensysTokens.textSecondaryOf(context)),
      const SizedBox(width: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 11,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
    ],
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
        if (widget.current.hasUnsavedChanges) ...[
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 16,
                color: DefensysTokens.warningText,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _currentDraftLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (widget.stageScoped) ...[
          Row(
            children: [
              Icon(
                Icons.school_outlined,
                size: 17,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${widget.current.scopeLabel} · ${widget.current.isCapstone ? widget.current.displayStage : widget.current.displayEvent}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
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
      DefenseTeamSummary(
        team: team,
        showDetailsInitially: true,
        previewMode: true,
      ),
      const SizedBox(height: 12),
      _context('Is this the team presenting? Match their project and members.'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _status(team),
          Text(
            _isCurrent(team)
                ? _currentDraftLabel
                : 'Current: ${widget.current.name} · $_currentDraftLabel',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
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
            icon: Icon(_preview == null ? Icons.close : Icons.arrow_back),
            tooltip: _preview == null ? 'Keep current team' : 'Back to teams',
            onPressed: _saving
                ? null
                : _preview == null
                ? () => Navigator.pop(context)
                : () => setState(() {
                    _preview = null;
                    _error = null;
                  }),
          ),
          actions: [
            if (_preview != null)
              IconButton(
                tooltip: 'Keep current team',
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
          ],
        ),
        body: _preview == null ? _lineup() : _previewTeam(_preview!),
        bottomNavigationBar: _preview == null ? null : _confirmation(_preview!),
      ),
    ),
  );
}
