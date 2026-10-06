import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'panelist_models.dart';
import '../../../models/defense_workflow_labels.dart';
import '../../web/admin/grade_center/defense_workflow_panel.dart';
import '../../../utils/universal_file_viewer.dart';
import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/authz_errors.dart';
import '../../../services/session_expired.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../widgets/tactile_button.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'widgets/evaluation_score_picker.dart';
import 'widgets/evaluation_review_screen.dart';
import 'widgets/team_grade_chooser.dart';
import 'widgets/defense_team_summary.dart';
import 'widgets/defense_materials_card.dart';

class GradeSheetTab extends ConsumerStatefulWidget {
  final List<TeamData> teams;
  final int selectedTeamIndex;
  final void Function(int) onTeamChanged;
  final VoidCallback? onGradesSubmitted;
  final VoidCallback? onEvaluationChanged;
  final Future<void> Function()? onRefresh;

  const GradeSheetTab({
    super.key,
    required this.teams,
    required this.selectedTeamIndex,
    required this.onTeamChanged,
    this.onGradesSubmitted,
    this.onEvaluationChanged,
    this.onRefresh,
  });

  @override
  ConsumerState<GradeSheetTab> createState() => GradeSheetTabState();
}

class GradeSheetTabState extends ConsumerState<GradeSheetTab> {
  List<Criterion> _criteria = [];
  TeamData? _lastTeam;
  int _formGeneration = 0;
  bool _isSavingDraft = false;
  bool _isSubmittingGrades = false;
  bool _isReviewingGrades = false;
  bool _isChoosingTeam = false;
  bool _showIndividualCriteria = false;
  String? _verifiedTeamIdentity;
  String? _draftSaveError;
  Timer? _autoSaveTimer;
  Future<bool>? _draftSaveFuture;
  final _scrollController = ScrollController();
  final _evaluationKey = GlobalKey();
  final _criterionKeys = <Criterion, GlobalKey>{};

  final Map<String, List<Criterion>> _studentCriteria = {};
  final Map<String, TextEditingController> _studentRemarksControllers = {};
  TextEditingController _teamRemarksController = TextEditingController();
  TextEditingController _verdictRemarksController = TextEditingController();
  String? _selectedVerdict;
  DateTime? _revisionDeadline;
  bool _redefenseVerificationRequired = false;
  bool _isSubmittingVerdict = false;
  int _selectedStudentIndex = 0;
  String _identity(TeamData team) => json.encode([
    team.scheduleId,
    team.teamId,
    team.evaluationContext.isNotEmpty
        ? team.evaluationContext
        : team.panelRubric,
  ]);

  bool _isVerified(TeamData team) => _verifiedTeamIdentity == _identity(team);

  @override
  void initState() {
    super.initState();
    _syncRubricForCurrentTeam();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _scrollController.dispose();
    for (var controller in _studentRemarksControllers.values) {
      controller.dispose();
    }
    _teamRemarksController.dispose();
    _verdictRemarksController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GradeSheetTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTeamIndex != widget.selectedTeamIndex ||
        oldWidget.teams != widget.teams) {
      _syncRubricForCurrentTeam();
    }
  }

  List<Criterion> _parseCriteriaFromRubricMap(
    Map<String, dynamic> rubric, {
    String? filterTargetType,
  }) {
    final list = rubric['criteria'] as List? ?? [];
    return list
        .where((c) {
          if (filterTargetType == null) return true;
          final t = c['target_type']?.toString() ?? 'team';
          return t == filterTargetType;
        })
        .map((c) {
          return Criterion(
            (c['name'] ?? 'Criterion').toString(),
            ((c['max_score'] as num?) ?? 10).toDouble(),
            id: int.tryParse(c['id']?.toString() ?? ''),
            description: (c['description'] ?? '').toString(),
          );
        })
        .toList();
  }

  void _syncRubricForCurrentTeam() {
    if (widget.teams.isEmpty) {
      return;
    }

    final team = widget.teams[widget.selectedTeamIndex];

    if (!identical(_lastTeam, team)) {
      _autoSaveTimer?.cancel();
      _lastTeam = team;
      _formGeneration++;
      _selectedStudentIndex = 0;
      _draftSaveError = null;
      _showIndividualCriteria = team.isIndividualTarget;

      _criteria = [];
      _criterionKeys.clear();
      _studentCriteria.clear();
      for (var controller in _studentRemarksControllers.values) {
        controller.dispose();
      }
      _studentRemarksControllers.clear();
      _teamRemarksController.dispose();
      _teamRemarksController = TextEditingController();
      _verdictRemarksController.dispose();
      _verdictRemarksController = TextEditingController(
        text: team.verdictRemarks ?? '',
      );
      _selectedVerdict = team.hasVerdict ? team.verdict : null;
      _redefenseVerificationRequired = team.redefenseVerificationRequired;
      _revisionDeadline = team.revisionDeadline != null
          ? DateTime.tryParse(team.revisionDeadline!)
          : null;

      final embedded = team.panelRubric;
      if (embedded != null) {
        if (team.targetType == 'both') {
          _criteria = _parseCriteriaFromRubricMap(
            embedded,
            filterTargetType: 'team',
          );
          for (var member in team.memberDetails) {
            _studentCriteria[member.id] = _parseCriteriaFromRubricMap(
              embedded,
              filterTargetType: 'individual',
            );
            _studentRemarksControllers[member.id] = TextEditingController();
          }
        } else if (team.isIndividualTarget) {
          for (var member in team.memberDetails) {
            _studentCriteria[member.id] = _parseCriteriaFromRubricMap(embedded);
            _studentRemarksControllers[member.id] = TextEditingController();
          }
        } else {
          _criteria = _parseCriteriaFromRubricMap(embedded);
        }
      } else {
        _criteria = [];
      }

      if (team.submittedSubmissions.isNotEmpty) {
        _hydrateSubmittedScores(team);
      } else if (team.draftSubmissions.isNotEmpty) {
        _hydrateSubmissions(team.draftSubmissions);
      }
      if (_criteria.isEmpty &&
          _studentCriteria.values.any((criteria) => criteria.isNotEmpty)) {
        _showIndividualCriteria = true;
      }
      if (team.hasUnsavedChanges) _scheduleAutoSave(team);
    }
  }

  void _hydrateSubmittedScores(TeamData team) {
    _hydrateSubmissions(team.submittedSubmissions);
  }

  void _hydrateSubmissions(List<Map<String, dynamic>> submissions) {
    for (final sub in submissions) {
      final rawStudentId = sub['student_id']?.toString();
      final remarks = (sub['remarks'] ?? '').toString();
      final scoresList = sub['criteria_scores'] as List? ?? [];
      final scoreMap = <int, double>{};
      for (final s in scoresList) {
        if (s is Map) {
          final cId = int.tryParse(s['criterion_id']?.toString() ?? '');
          final scoreVal = (s['score'] as num?)?.toDouble();
          if (cId != null && scoreVal != null) {
            scoreMap[cId] = scoreVal;
          }
        }
      }

      if (rawStudentId == null ||
          rawStudentId == 'null' ||
          rawStudentId.isEmpty) {
        _teamRemarksController.text = remarks;
        for (var c in _criteria) {
          if (c.id != null && scoreMap.containsKey(c.id)) {
            c.score = scoreMap[c.id]!;
          }
        }
      } else {
        if (_studentRemarksControllers.containsKey(rawStudentId)) {
          _studentRemarksControllers[rawStudentId]!.text = remarks;
        }
        final memberCriteria = _studentCriteria[rawStudentId] ?? [];
        for (var c in memberCriteria) {
          if (c.id != null && scoreMap.containsKey(c.id)) {
            c.score = scoreMap[c.id]!;
          }
        }
      }
    }
  }

  String? _panelRubricName(TeamData team) {
    return team.panelRubric?['name']?.toString();
  }

  List<Criterion> _requiredCriteria(TeamData team) => [
    ..._criteria,
    if (team.targetType != 'team')
      for (final member in team.memberDetails) ...?_studentCriteria[member.id],
  ];

  bool _isComplete(TeamData team) {
    final criteria = _requiredCriteria(team);
    if (team.targetType != 'team' && team.memberDetails.isEmpty) return false;
    return criteria.isNotEmpty && criteria.every((c) => c.isScored);
  }

  List<Map<String, dynamic>> _evaluationSubmissions(TeamData team) {
    List<Map<String, dynamic>> scores(List<Criterion> criteria) => [
      for (final c in criteria)
        if (c.isScored) {'criterion_id': c.id, 'score': c.score},
    ];
    return [
      if (_criteria.isNotEmpty)
        {
          'student_id': null,
          'criteria_scores': scores(_criteria),
          'remarks': _teamRemarksController.text,
        },
      if (team.targetType != 'team')
        for (final member in team.memberDetails)
          if ((_studentCriteria[member.id] ?? []).isNotEmpty)
            {
              'student_id': int.tryParse(member.id) ?? member.id,
              'criteria_scores': scores(_studentCriteria[member.id]!),
              'remarks': _studentRemarksControllers[member.id]?.text ?? '',
            },
    ];
  }

  void _rememberDraft() {
    final team = _lastTeam;
    if (team == null || !team.gradingAvailable) return;
    team.draftSubmissions = _evaluationSubmissions(team);
    team.hasUnsavedChanges = true;
    _draftSaveError = null;
    _scheduleAutoSave(team);
    widget.onEvaluationChanged?.call();
  }

  void _scheduleAutoSave(TeamData team) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && team.hasUnsavedChanges && !_isSubmittingGrades) {
        unawaited(_saveDraft(team));
      }
    });
  }

  TeamData _liveTeam(TeamData original) =>
      widget.teams
          .where((team) => _identity(team) == _identity(original))
          .firstOrNull ??
      original;

  /// Used by both the chooser and dashboard navigation. A failed save keeps the
  /// current sheet open; edits made during an in-flight save require another ACK.
  Future<bool> savePendingChanges() async {
    _autoSaveTimer?.cancel();
    if (_isSubmittingGrades || _isSubmittingVerdict) return false;
    final original = _lastTeam;
    if (original == null) return true;
    if (_draftSaveFuture != null && !await _draftSaveFuture!) return false;
    while (mounted && _liveTeam(original).hasUnsavedChanges) {
      if (!await _saveDraft(_liveTeam(original))) return false;
    }
    return mounted;
  }

  Future<bool> _saveDraft(TeamData team, {bool feedback = false}) async {
    if (_draftSaveFuture != null) return _draftSaveFuture!;
    if (!team.gradingAvailable || _isSubmittingGrades) {
      return !team.hasUnsavedChanges;
    }
    if (!team.hasDraft && !team.hasUnsavedChanges) return true;
    // Snapshot the draft owned by this schedule, not the currently displayed form.
    final submissions = json.decode(json.encode(team.draftSubmissions));
    final snapshot = json.encode(submissions);
    setState(() {
      _isSavingDraft = true;
      _draftSaveError = null;
    });
    final future = _persistDraft(team, submissions, snapshot, feedback);
    _draftSaveFuture = future;
    return future;
  }

  Future<bool> _persistDraft(
    TeamData team,
    dynamic submissions,
    String snapshot,
    bool feedback,
  ) async {
    bool saved = false;
    String? error;
    try {
      final isGuest = ref.read(authProvider).user?['role'] == 'guest_panelist';
      final path = isGuest ? 'guest-grade-draft/' : 'grade-draft/';
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse('${ApiConfig.defenseSchedulesUrl}/$path'),
            body: json.encode({
              'schedule_id': team.scheduleId,
              'evaluation_context': team.evaluationContext,
              'submissions': submissions,
            }),
          );
      if (!mounted) return false;
      if (response.statusCode == 200) {
        final draft = json.decode(response.body)['draft'] as Map;
        final current = _liveTeam(team);
        if (!current.isPosted) {
          setState(() {
            current.draftSavedAt = draft['saved_at']?.toString();
            current.hasUnsavedChanges =
                json.encode(current.draftSubmissions) != snapshot;
          });
        }
        saved = true;
        widget.onEvaluationChanged?.call();
        if (feedback) {
          showSuccessToast(context, 'Draft saved. You can continue later.');
        }
      } else {
        error = friendlyHttpErrorMessage(response.statusCode, response.body);
      }
    } on SessionExpiredException {
      error = 'Sign in again to save your draft. Your changes are still here.';
    } catch (_) {
      error = 'Draft could not be saved. Your changes are still here.';
    } finally {
      _draftSaveFuture = null;
      if (mounted) {
        setState(() {
          _isSavingDraft = false;
          if (_lastTeam != null && _identity(_lastTeam!) == _identity(team)) {
            _draftSaveError = error;
          }
        });
        if (saved && _liveTeam(team).hasUnsavedChanges) {
          _scheduleAutoSave(_liveTeam(team));
        }
      }
    }
    return saved;
  }

  /// Assignments uses this same verification flow rather than directly changing
  /// the selected index. The final lookup uses schedule/context identity so a
  /// refreshed or reordered assignment list cannot activate the wrong team.
  Future<bool> openTeam(int index) async {
    if (index < 0 || index >= widget.teams.length) return false;
    final candidate = widget.teams[index];
    if (_lastTeam != null &&
        _identity(candidate) == _identity(_lastTeam!) &&
        _isVerified(candidate)) {
      return savePendingChanges();
    }
    return _chooseTeam(initialPreview: candidate);
  }

  Future<bool> _chooseTeam({TeamData? initialPreview}) async {
    if (_isChoosingTeam ||
        _isReviewingGrades ||
        _isSubmittingGrades ||
        _isSubmittingVerdict ||
        widget.teams.isEmpty) {
      return false;
    }
    final current = widget.teams[widget.selectedTeamIndex];
    setState(() => _isChoosingTeam = true);
    try {
      final chosen = await Navigator.push<TeamData>(
        context,
        MaterialPageRoute(
          builder: (_) => TeamGradeChooser(
            teams: widget.teams,
            current: current,
            initialPreview: initialPreview,
            onConfirm: (candidate) async {
              if (!await savePendingChanges()) {
                return 'Your current draft could not be saved. Your team has not changed. Check your connection and retry.';
              }
              if (!mounted ||
                  !widget.teams.any(
                    (team) => _identity(team) == _identity(candidate),
                  )) {
                return 'This assignment changed. Close the chooser and refresh before grading.';
              }
              return null;
            },
          ),
        ),
      );
      if (!mounted || chosen == null) return false;
      final index = widget.teams.indexWhere(
        (team) => _identity(team) == _identity(chosen),
      );
      if (index < 0) return false;
      setState(() => _verifiedTeamIdentity = _identity(widget.teams[index]));
      widget.onTeamChanged(index);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return true;
    } finally {
      if (mounted) setState(() => _isChoosingTeam = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      return const Center(child: Text('No teams available'));
    }
    final team = widget.teams[widget.selectedTeamIndex];
    final complete = _isComplete(team);
    final unavailable = !team.gradingAvailable && !team.isPosted;
    final canScore = team.isPosted || _isVerified(team);
    final member = team.memberDetails.elementAtOrNull(_selectedStudentIndex);
    final displayed = [
      ..._criteria,
      if (member != null) ...?_studentCriteria[member.id],
    ];
    final total = displayed.fold(
      0.0,
      (sum, criterion) => sum + (criterion.score ?? 0),
    );
    final maximum = displayed.fold(
      0.0,
      (sum, criterion) => sum + criterion.maxScore,
    );
    final scrollContent = SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefenseTeamSummary(
            key: const ValueKey('team-defense-brief'),
            team: team,
          ),
          const SizedBox(height: 16),
          DefenseMaterialsCard(
            key: const ValueKey('defense-materials'),
            materials: team.defenseMaterials,
            onView: _viewDefenseMaterial,
          ),
          const SizedBox(height: 16),
          if (unavailable || team.isPosted) ...[
            _buildAvailabilityNotice(team),
            const SizedBox(height: 16),
          ],
          if (unavailable)
            _buildRubricPreview(team)
          else if (!canScore)
            _buildTeamEntry(team)
          else
            _buildEvaluationCard(team),
          if (canScore && complete) ...[
            const SizedBox(height: 14),
            if (member != null && team.targetType != 'team')
              Text(
                'Score summary for ${member.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            _buildScoreHero(
              total: total,
              maxTotal: maximum,
              panelPct: maximum > 0 ? total / maximum * 100 : 0,
              panelWeight: team.panelWeight,
              peerWeight: team.peerWeight,
              showAdviser: team.isCapstone && team.adviserWeight > 0,
              team: team,
              hasValidScope: team.hasValidScope,
            ),
          ],
          if (team.isCapstone && !team.isLockedByDate) ...[
            const SizedBox(height: 14),
            if (team.isChair)
              _buildChairVerdictCard(team)
            else
              _buildPanelistVerdictCard(team),
          ],
        ],
      ),
    );
    return DefensysShadcnScope(
      child: Column(
        children: [
          _buildGradingContext(team),
          Expanded(
            child: widget.onRefresh == null
                ? scrollContent
                : RefreshIndicator(
                    color: DefensysTokens.maroonOf(context),
                    onRefresh: () async {
                      if (await savePendingChanges()) await widget.onRefresh!();
                    },
                    child: scrollContent,
                  ),
          ),
          if (canScore && !unavailable) _buildEvaluationFooter(team),
        ],
      ),
    );
  }

  Widget _buildGradingContext(TeamData team) {
    final statusColor = team.isPosted
        ? (DefensysTokens.isDark(context)
              ? const Color(0xFF6EE7B7)
              : DefensysTokens.successText)
        : DefensysTokens.maroonTextOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border(
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  team.isPosted
                      ? Icons.check_circle_outline_rounded
                      : _isVerified(team)
                      ? Icons.edit_outlined
                      : Icons.groups_outlined,
                  size: 15,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  team.isPosted
                      ? 'Submitted grades'
                      : _isVerified(team)
                      ? 'Currently grading'
                      : 'Verify the presenting team',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ShadButton.outline(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                leading: Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                enabled:
                    !_isSubmittingGrades &&
                    !_isReviewingGrades &&
                    !_isChoosingTeam &&
                    !_isSubmittingVerdict,
                onPressed: () => _chooseTeam(),
                child: const Text(
                  'Change team',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            team.name,
            style: TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${team.displayStage} · ${team.formattedTime} · ${team.displayRoom}',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          if (_showIndividualCriteria &&
              team.memberDetails.isNotEmpty &&
              (team.isPosted || _isVerified(team))) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: DefensysTokens.maroonTextOf(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${team.isPosted ? 'Viewing' : 'Scoring'} ${team.memberDetails[_selectedStudentIndex].name}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamEntry(TeamData team) => ShadCard(
    backgroundColor: DefensysTokens.surfaceOf(context),
    radius: BorderRadius.circular(16),
    padding: const EdgeInsets.all(18),
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ready to evaluate?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Match the project and presenting members above before starting. These scores will belong to ${team.name}.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 16),
        ShadButton(
          key: const ValueKey('start-team-evaluation'),
          height: 0,
          expands: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          backgroundColor: DefensysTokens.maroonOf(context),
          foregroundColor: Colors.white,
          onPressed: () =>
              setState(() => _verifiedTeamIdentity = _identity(team)),
          child: Text(
            '${team.hasDraft ? 'Resume grading' : 'Start grading'} ${team.name}',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  Widget _buildEvaluationFooter(TeamData team) {
    final required = _requiredCriteria(team);
    final entered = required.where((criterion) => criterion.isScored).length;
    final complete = _isComplete(team);
    final busy =
        _isSubmittingGrades ||
        _isReviewingGrades ||
        _isChoosingTeam ||
        _isSubmittingVerdict;
    final saveLabel = team.isPosted
        ? 'Submitted · Locked'
        : _draftSaveError != null
        ? 'Couldn’t save draft. Your changes are still here.'
        : _isSavingDraft
        ? 'Saving draft…'
        : team.hasUnsavedChanges
        ? 'Changes pending'
        : team.draftSavedAt != null
        ? 'Draft saved'
        : 'No saved draft yet';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$entered of ${required.length} scores entered',
              key: const ValueKey('evaluation-progress'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                saveLabel,
                key: const ValueKey('draft-save-state'),
                style: TextStyle(
                  fontSize: 12,
                  color: _draftSaveError == null
                      ? DefensysTokens.textSecondaryOf(context)
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!team.isPosted)
                  ShadButton.outline(
                    key: const ValueKey('save-evaluation-draft'),
                    height: 44,
                    enabled:
                        !busy &&
                        !_isSavingDraft &&
                        (team.hasDraft || team.hasUnsavedChanges),
                    onPressed: () => _saveDraft(team, feedback: true),
                    child: Text(
                      _draftSaveError != null ? 'Retry save' : 'Save Draft',
                    ),
                  ),
                ShadButton(
                  key: const ValueKey('review-evaluation'),
                  height: 44,
                  enabled: !busy && required.isNotEmpty && team.hasValidScope,
                  backgroundColor: DefensysTokens.maroonOf(context),
                  foregroundColor: Colors.white,
                  onPressed: () => _confirmPost(team),
                  child: Text(
                    _isSubmittingGrades
                        ? 'Submitting…'
                        : team.isPosted
                        ? 'View scores'
                        : complete
                        ? 'Review & Submit'
                        : 'Review grades',
                  ),
                ),
                if (!team.isPosted && !complete)
                  ShadButton.ghost(
                    height: 44,
                    enabled: !busy,
                    onPressed: () => _goToNextUnscored(team),
                    child: const Text('Next unscored'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _goToNextUnscored(TeamData team) {
    Criterion? next;
    setState(() {
      if (_criteria.any((criterion) => !criterion.isScored)) {
        _showIndividualCriteria = false;
        next = _criteria.where((criterion) => !criterion.isScored).first;
      } else {
        final index = team.memberDetails.indexWhere(
          (member) => (_studentCriteria[member.id] ?? []).any(
            (criterion) => !criterion.isScored,
          ),
        );
        if (index >= 0) {
          _showIndividualCriteria = true;
          _selectedStudentIndex = index;
          next = _studentCriteria[team.memberDetails[index].id]!
              .where((criterion) => !criterion.isScored)
              .first;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target =
          _criterionKeys[next]?.currentContext ?? _evaluationKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  Widget _buildAvailabilityNotice(TeamData team) {
    final upcoming = team.isLockedByDate && team.scheduledDate != null;
    final title = upcoming
        ? 'Upcoming defense'
        : team.isPosted
        ? 'Your grades are submitted'
        : team.gradingAvailable
        ? (team.isToday ? 'Today · Grading available' : 'Grading available')
        : 'Grading unavailable';
    final message = upcoming
        ? 'Grading opens on ${DateFormat('MMMM d, yyyy').format(team.scheduledDate!)}. Review the materials and rubric below to prepare.'
        : team.isPosted
        ? 'Your scores are saved and locked. The official verdict is shown separately.'
        : team.gradingAvailable
        ? 'Evaluate when this team presents. The allotted time does not limit grading.'
        : team.gradingUnavailableReason.isNotEmpty
        ? team.gradingUnavailableReason
        : 'The schedule must be configured before grading is available.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildRubricPreview(TeamData team) => Card(
    child: ExpansionTile(
      title: const Text('Rubric preview'),
      subtitle: Text(_panelRubricName(team) ?? 'No panel rubric configured'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final raw in team.panelRubric?['criteria'] as List? ?? [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(raw['name']?.toString() ?? 'Criterion'),
            subtitle: Text(
              [
                raw['target_type'] == 'individual'
                    ? 'Per student'
                    : 'Team criterion',
                if ((raw['description']?.toString() ?? '').isNotEmpty)
                  raw['description'].toString(),
              ].join(' · '),
            ),
            trailing: Text('${raw['max_score']} pts'),
          ),
      ],
    ),
  );

  Widget _buildEvaluationCard(TeamData team) {
    final locked =
        team.isPosted ||
        !team.gradingAvailable ||
        !_isVerified(team) ||
        _isSubmittingGrades ||
        _isReviewingGrades ||
        _isChoosingTeam;
    final hasStudents = _studentCriteria.values.any(
      (criteria) => criteria.isNotEmpty,
    );
    final member = team.memberDetails.elementAtOrNull(_selectedStudentIndex);
    final showStudents =
        hasStudents && (_showIndividualCriteria || _criteria.isEmpty);
    final visible = showStudents && member != null
        ? _studentCriteria[member.id] ?? <Criterion>[]
        : _criteria;
    final entered = visible.where((criterion) => criterion.isScored).length;
    return ShadCard(
      key: _evaluationKey,
      backgroundColor: DefensysTokens.surfaceOf(context),
      width: double.infinity,
      radius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(
                    context,
                  ).withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  size: 20,
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _panelRubricName(team) ?? 'Panel rubric',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      team.targetType == 'team'
                          ? 'Team evaluation'
                          : team.targetType == 'individual'
                          ? 'Individual evaluation'
                          : 'Team & individual evaluation',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (team.isPosted) ...[
                const SizedBox(width: 8),
                const ShadBadge.outline(
                  child: Text('Read only', style: TextStyle(fontSize: 10)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (_criteria.isNotEmpty && hasStudents) ...[
            LayoutBuilder(
              builder: (context, constraints) => ShadTabs<String>(
                value: showStudents ? 'students' : 'team',
                onChanged: (value) => setState(
                  () => _showIndividualCriteria = value == 'students',
                ),
                tabs: [
                  ShadTab(
                    value: 'team',
                    selectedBackgroundColor: DefensysTokens.surfaceOf(context),
                    selectedForegroundColor: DefensysTokens.maroonTextOf(
                      context,
                    ),
                    selectedDecoration: ShadDecoration(
                      border: ShadBorder.all(
                        color: DefensysTokens.maroonOf(
                          context,
                        ).withValues(alpha: .20),
                        radius: BorderRadius.circular(8),
                      ),
                    ),
                    selectedShadows: const [],
                    height: 52,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: SizedBox(
                      width: (constraints.maxWidth - 24) / 2 - 16,
                      child: Text(
                        'Team · ${_criteria.where((c) => c.isScored).length}/${_criteria.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  ShadTab(
                    value: 'students',
                    selectedBackgroundColor: DefensysTokens.surfaceOf(context),
                    selectedForegroundColor: DefensysTokens.maroonTextOf(
                      context,
                    ),
                    selectedDecoration: ShadDecoration(
                      border: ShadBorder.all(
                        color: DefensysTokens.maroonOf(
                          context,
                        ).withValues(alpha: .20),
                        radius: BorderRadius.circular(8),
                      ),
                    ),
                    selectedShadows: const [],
                    height: 52,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: SizedBox(
                      width: (constraints.maxWidth - 24) / 2 - 16,
                      child: Text(
                        'Students · ${_studentCriteria.values.where((cs) => cs.isNotEmpty && cs.every((c) => c.isScored)).length}/${team.memberDetails.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (showStudents) ...[
            _buildStudentSelector(team),
            const SizedBox(height: 16),
          ],
          Text(
            showStudents && member != null ? member.name : 'Team criteria',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '$entered/${visible.length} scored${visible.isNotEmpty && entered == visible.length ? ' · Scores complete' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No panel rubric criteria are configured. Ask the PIT lead or admin to configure this schedule.',
              ),
            ),
          for (final criterion in visible) _criterionRow(criterion, locked),
          if (visible.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Optional feedback',
                style: TextStyle(fontSize: 13),
              ),
              children: [
                TextField(
                  key: ValueKey(
                    'remarks-$_formGeneration-${showStudents ? member?.id : 'team'}',
                  ),
                  controller: showStudents && member != null
                      ? _studentRemarksControllers[member.id]
                      : _teamRemarksController,
                  readOnly: locked,
                  maxLines: 3,
                  onChanged: (_) => setState(_rememberDraft),
                  decoration: InputDecoration(
                    labelText: showStudents && member != null
                        ? 'Feedback for ${member.name}'
                        : 'Team remarks / feedback',
                  ),
                ),
              ],
            ),
          Text(
            'Blank means unanswered. Zero is a valid score.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPost(TeamData team) async {
    if (_isReviewingGrades ||
        _isSubmittingGrades ||
        _isSubmittingVerdict ||
        _isChoosingTeam ||
        (!team.isPosted && (!team.gradingAvailable || !_isVerified(team)))) {
      return;
    }
    final identity = _identity(team);
    setState(() => _isReviewingGrades = true);
    try {
      if (!team.isPosted && !await savePendingChanges()) return;
      if (!mounted || _lastTeam == null || _identity(_lastTeam!) != identity) {
        return;
      }
      final submissions = _evaluationSubmissions(team);
      final result = await Navigator.push<EvaluationReviewAction>(
        context,
        MaterialPageRoute(
          builder: (_) => EvaluationReviewScreen(
            team: team,
            teamCriteria: _criteria,
            studentCriteria: Map.of(_studentCriteria),
            complete: _isComplete(team),
          ),
        ),
      );
      if (!mounted ||
          result == null ||
          _lastTeam == null ||
          _identity(_lastTeam!) != identity) {
        return;
      }
      if (result.submit) {
        if (!team.hasValidScope || !_isComplete(team)) return;
        await _submitGrades(team, submissions);
      } else {
        setState(() {
          _showIndividualCriteria = result.studentId != null;
          if (result.studentId != null) {
            final index = team.memberDetails.indexWhere(
              (member) => member.id == result.studentId,
            );
            if (index >= 0) _selectedStudentIndex = index;
          }
        });
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _isReviewingGrades = false);
    }
  }

  Future<void> _submitGrades(
    TeamData team,
    List<Map<String, dynamic>> submissions,
  ) async {
    if (!team.gradingAvailable || !_isComplete(team) || _isSubmittingGrades) {
      return;
    }
    setState(() => _isSubmittingGrades = true);
    try {
      final isGuest = ref.read(authProvider).user?['role'] == 'guest_panelist';
      final path = isGuest ? 'guest-submit-grades/' : 'submit-grades/';
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse('${ApiConfig.defenseSchedulesUrl}/$path'),
            body: json.encode({
              'team_id': int.tryParse(team.teamId) ?? team.teamId,
              'schedule_id': int.tryParse(team.scheduleId) ?? team.scheduleId,
              'evaluation_context': team.evaluationContext,
              'submissions': submissions,
            }),
          );
      if (!mounted) return;
      if (response.statusCode == 201) {
        setState(() {
          team.isPosted = true;
          team.submittedSubmissions = submissions;
          team.draftSubmissions = [];
          team.draftSavedAt = null;
          team.hasUnsavedChanges = false;
        });
        widget.onEvaluationChanged?.call();
        widget.onGradesSubmitted?.call();
        showSuccessToast(context, 'Your grades are submitted and locked.');
      } else {
        showErrorToast(
          context,
          friendlyHttpErrorMessage(response.statusCode, response.body),
        );
      }
    } on SessionExpiredException {
      // Entered scores remain available if submission did not complete.
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Grades could not be submitted. Your changes are still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingGrades = false);
    }
  }

  Widget _criterionRow(Criterion criterion, bool locked) {
    final scope = _criteria.contains(criterion)
        ? 'team'
        : _lastTeam!.memberDetails[_selectedStudentIndex].id;
    return Padding(
      key: _criterionKeys.putIfAbsent(criterion, GlobalKey.new),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      criterion.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      criterion.isScored ? 'Score entered' : 'Not scored',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${criterion.isScored ? formatEvaluationScore(criterion.score!) : '—'} / ${formatEvaluationScore(criterion.maxScore)}',
                key: ValueKey('score-display-$scope-${criterion.id}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (criterion.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                criterion.description,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          if (!locked) ...[
            const SizedBox(height: 10),
            EvaluationScorePicker(
              key: ValueKey('score-$_formGeneration-$scope-${criterion.id}'),
              label: criterion.name,
              maximum: criterion.maxScore,
              value: criterion.score,
              onChanged: (score) {
                if (!mounted ||
                    _lastTeam == null ||
                    !_isVerified(_lastTeam!) ||
                    !_lastTeam!.gradingAvailable ||
                    _isReviewingGrades ||
                    _isChoosingTeam) {
                  return;
                }
                setState(() {
                  criterion.score = score;
                  _rememberDraft();
                });
              },
            ),
          ],
          const Divider(height: 20),
        ],
      ),
    );
  }

  Widget _weightChip(String label, String weight, Color color) {
    return Column(
      children: [
        Text(
          weight,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 15,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Future<void> _viewDefenseMaterial(Map<String, dynamic> item) async {
    final sub = item['submission'] is Map ? item['submission'] as Map : null;
    final fileUrl = (item['file_url']?.toString().isNotEmpty == true)
        ? item['file_url']?.toString()
        : sub?['file_url']?.toString();
    final String fileName =
        (item['file_name']?.toString().isNotEmpty == true &&
            item['file_name'] != 'File')
        ? item['file_name']!.toString()
        : (sub?['file_name']?.toString() ??
              item['name']?.toString() ??
              item['label']?.toString() ??
              'Document');
    if (fileUrl == null || fileUrl.isEmpty) {
      showErrorToast(context, 'No file URL available for this material');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      ),
    );

    var loadingOpen = true;
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      if (!mounted) return;
      Navigator.pop(context);
      loadingOpen = false;
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (!mounted) return;
      if (loadingOpen && Navigator.canPop(context)) Navigator.pop(context);
      showErrorToast(context, 'Error opening file: $e');
    }
  }

  Widget _buildScoreHero({
    required double total,
    required double maxTotal,
    required double panelPct,
    required int panelWeight,
    required int peerWeight,
    required bool showAdviser,
    required TeamData team,
    required bool hasValidScope,
  }) {
    final weightedPts = (panelPct * panelWeight / 100);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PANEL RAW SCORE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${total.toStringAsFixed(1)} / ${maxTotal.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroon.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${panelPct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasValidScope) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'WEIGHTED SCORE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${weightedPts.toStringAsFixed(1)} / $panelWeight pts',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Weights:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              _weightChip('Panel', '$panelWeight%', DefensysTokens.maroon),
              const SizedBox(width: 6),
              _weightChip('Peer', '$peerWeight%', const Color(0xFF10B981)),
              if (showAdviser) ...[
                const SizedBox(width: 6),
                _weightChip(
                  'Adviser',
                  '${team.adviserWeight}%',
                  DefensysTokens.gold,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSelector(TeamData team) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in team.memberDetails.asMap().entries)
            SizedBox(
              width: width,
              child: Semantics(
                selected: entry.key == _selectedStudentIndex,
                label:
                    '${entry.value.name}, ${team.progressFor(entry.value.id).label}',
                child: ShadButton.outline(
                  key: ValueKey('student-selector-${entry.value.id}'),
                  height: 0,
                  expands: true,
                  padding: const EdgeInsets.all(10),
                  backgroundColor: entry.key == _selectedStudentIndex
                      ? DefensysTokens.surfaceHigherOf(context)
                      : null,
                  onPressed: () =>
                      setState(() => _selectedStudentIndex = entry.key),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.value.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (entry.key == _selectedStudentIndex)
                        const Text('Viewing', style: TextStyle(fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${(_studentCriteria[entry.value.id] ?? []).isNotEmpty && _studentCriteria[entry.value.id]!.every((c) => c.isScored) ? 'Complete · ' : ''}${(_studentCriteria[entry.value.id] ?? []).where((c) => c.isScored).length}/${(_studentCriteria[entry.value.id] ?? []).length} scored',
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                      if (entry.value.isLeader)
                        const Text('Leader', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildChairVerdictCard(TeamData team) {
    final hasVerdict = team.hasVerdict;
    final canEditVerdict = team.canIssueVerdict && !_isSubmittingVerdict;
    final unavailableReason = team.verdictUnavailableReason.isNotEmpty
        ? team.verdictUnavailableReason
        : team.gradingUnavailableReason.isNotEmpty
        ? team.gradingUnavailableReason
        : !team.isPosted
        ? 'Panel grading must be submitted before issuing a verdict.'
        : 'The official verdict is currently unavailable. Refresh this assignment for the latest status.';
    final isForRedefense = _selectedVerdict == 'for_redefense';
    final isRevisions = _selectedVerdict == 'approved_with_revisions';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hasVerdict
              ? (['for_redefense', 'failed', 'project_rejected'].contains(team.verdict)
                    ? Colors.red.shade300
                    : team.isApprovedWithRevisions
                    ? Colors.amber.shade300
                    : Colors.green.shade300)
              : DefensysTokens.borderOf(context),
          width: 1.5,
        ),
      ),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: RadioGroup<String>(
          groupValue: _selectedVerdict,
          onChanged: (value) {
            if (canEditVerdict) setState(() => _selectedVerdict = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      size: 20,
                      color: DefensysTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Panel Chair Official Verdict',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: DefensysTokens.maroon,
                          ),
                        ),
                        Text(
                          'Issue the official stage decision for ${team.name}.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasVerdict) _verdictStatusChip(team.verdict!),
                ],
              ),

              if (team.hasVerdict && team.workflowGrade != null) ...[
                const SizedBox(height: 12),
                DefenseWorkflowPanel(grade: team.workflowGrade!, onUpdated: widget.onGradesSubmitted),
              ],
              if (!team.canIssueVerdict) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('chair-verdict-unavailable'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: DefensysTokens.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          unavailableReason,
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (team.isForRedefense) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Team marked for Re-defense (Attempt #${team.attemptCount}). The team is now eligible for Attempt #${team.attemptCount + 1} re-scheduling in the Defense Scheduler.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(height: 24),
              const Text(
                'OFFICIAL STAGE VERDICT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 8),

              // Radio Options
              _verdictRadioOption(
                enabled: canEditVerdict,
                value: 'approved',
                title: 'Approved',
                description:
                    'The team successfully passed with no mandatory re-defense.',
                icon: Icons.check_circle,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: 8),
              _verdictRadioOption(
                enabled: canEditVerdict,
                value: 'approved_with_revisions',
                title: 'Approved with Revisions',
                description:
                    'Passed, but required manuscript or system changes must be submitted.',
                icon: Icons.edit_calendar,
                color: const Color(0xFFD97706),
              ),
              const SizedBox(height: 8),
              _verdictRadioOption(
                enabled: canEditVerdict,
                value: 'for_redefense',
                title: 'For Re-defense',
                description:
                    'A new panel assessment is required. Retain adviser and peer grades and the prior endorsement.',
                icon: Icons.replay_rounded,
                color: const Color(0xFFEF4444),
              ),

              const SizedBox(height: 8),
              _verdictRadioOption(enabled: canEditVerdict, value: 'failed',
                title: 'Failed', description: 'No progression. Another attempt requires institution-authorized recovery recorded by the admin.',
                icon: Icons.cancel_outlined, color: const Color(0xFFEF4444)),
              const SizedBox(height: 8),
              _verdictRadioOption(enabled: canEditVerdict, value: 'project_rejected',
                title: 'Project Rejected', description: 'The concept must be replaced after an admin records authorization. Keep the team and adviser.',
                icon: Icons.block_outlined, color: const Color(0xFFEF4444)),
              if (isForRedefense)
                CheckboxListTile(contentPadding: EdgeInsets.zero,
                  title: const Text('Require adviser verification of corrections'),
                  subtitle: const Text('Optional correction check before scheduling. No new adviser endorsement.'),
                  value: _redefenseVerificationRequired,
                  onChanged: canEditVerdict ? (value) => setState(() => _redefenseVerificationRequired = value ?? false) : null),

              if (isRevisions) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event,
                        size: 18,
                        color: DefensysTokens.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Revision Deadline (Optional)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textSecondary,
                              ),
                            ),
                            Text(
                              _revisionDeadline != null
                                  ? DateFormat(
                                      'MMMM d, yyyy',
                                    ).format(_revisionDeadline!)
                                  : 'No deadline set',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: !canEditVerdict
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _revisionDeadline ??
                                      DateTime.now().add(
                                        const Duration(days: 14),
                                      ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null) {
                                  setState(() => _revisionDeadline = picked);
                                }
                              },
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(
                          _revisionDeadline != null ? 'Change' : 'Set Date',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              const Text(
                'PANEL INSTRUCTIONS & DIRECTIVES FOR TEAM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _verdictRemarksController,
                readOnly: !canEditVerdict,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: isForRedefense
                      ? 'Enter reasons for re-defense and specific instructions for Attempt #${team.attemptCount + 1}...'
                      : 'Enter panel directives, recommendations, or required manuscript updates...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TactileButton.primary(
                  label: _isSubmittingVerdict
                      ? 'Submitting...'
                      : (hasVerdict ? 'Update Verdict' : 'Submit Verdict'),
                  onPressed:
                      _isSubmittingVerdict ||
                          _selectedVerdict == null ||
                          !team.canIssueVerdict
                      ? null
                      : () => _confirmSubmitVerdict(team),
                  icon: const Icon(
                    Icons.gavel_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verdictRadioOption({
    required bool enabled,
    required String value,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedVerdict == value;
    return InkWell(
      onTap: enabled ? () => setState(() => _selectedVerdict = value) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(value: value, enabled: enabled, activeColor: color),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelistVerdictCard(TeamData team) {
    if (!team.hasVerdict) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        color: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The official defense stage verdict will be rendered by the Panel Chair.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: team.isForRedefense
              ? Colors.red.shade300
              : team.isApprovedWithRevisions
              ? Colors.amber.shade300
              : Colors.green.shade300,
          width: 1.5,
        ),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.gavel_rounded,
                      size: 18,
                      color: DefensysTokens.maroon,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Official Stage Verdict',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ],
                ),
                _verdictStatusChip(team.verdict!),
              ],
            ),
            if (team.verdictByName != null &&
                team.verdictByName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Issued by Panel Chair: ${team.verdictByName}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            if (team.verdictRemarks != null &&
                team.verdictRemarks!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Panel Directives / Instructions:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      team.verdictRemarks!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verdictStatusChip(String verdict) {
    final isApproved = verdict == 'approved';
    final isRevisions = verdict == 'approved_with_revisions';
    final isForRedefense = ['for_redefense', 'failed', 'project_rejected'].contains(verdict);

    final Color color = isApproved
        ? const Color(0xFF10B981)
        : isRevisions
        ? const Color(0xFFD97706)
        : isForRedefense
        ? const Color(0xFFEF4444)
        : Colors.grey;

    final String label = isRevisions ? 'APPROVED W/ REVISIONS' : defenseVerdictLabel(verdict).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Future<void> _confirmSubmitVerdict(TeamData team) async {
    if (!team.canIssueVerdict ||
        _selectedVerdict == null ||
        _isSubmittingVerdict) {
      return;
    }
    final directives = _verdictRemarksController.text.trim();
    if (['for_redefense', 'failed', 'project_rejected'].contains(_selectedVerdict) && directives.isEmpty) {
      showValidationToast(
        context,
        'Record the reason and required action for this outcome.',
      );
      return;
    }

    if (_selectedVerdict == 'for_redefense') {
      final confirmed = await confirmDestructive(
        context,
        title: 'Issue Re-defense Verdict?',
        message:
            'This attempt requires a new panel assessment. When the next attempt is scheduled, panel grades and the verdict reset; adviser and peer grades stay. ${_redefenseVerificationRequired ? 'The adviser must verify corrections before scheduling.' : 'No new adviser endorsement is required.'}',
        confirmLabel: 'Issue Re-defense',
      );
      if (!confirmed || !mounted) return;
    }

    if (_selectedVerdict != 'for_redefense') {
      final title = defenseVerdictLabel(_selectedVerdict);
      final confirmed = await confirmLock(
        context,
        title: 'Confirm Official Verdict',
        message:
            '${team.name}: $title.\n\nThis records the official stage decision.',
        confirmLabel: 'Submit Verdict',
      );
      if (!confirmed || !mounted) return;
    }

    await _submitVerdict(team);
  }

  Future<void> _submitVerdict(TeamData team) async {
    if (team.scheduleId.isEmpty) {
      showValidationToast(context, 'Schedule ID is missing for this team.');
      return;
    }

    final directives = _verdictRemarksController.text.trim();
    setState(() => _isSubmittingVerdict = true);
    showInfoToast(context, 'Submitting official defense verdict...');

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final verdictUrl = Uri.parse(
        '${ApiConfig.defenseSchedulesUrl}/${team.scheduleId}/verdict/',
      );

      final payload = <String, dynamic>{
        'verdict': _selectedVerdict,
        'verdict_remarks': directives,
        'redefense_verification_required': _redefenseVerificationRequired,
        if (_revisionDeadline != null &&
            _selectedVerdict == 'approved_with_revisions')
          'revision_deadline': DateFormat(
            'yyyy-MM-dd',
          ).format(_revisionDeadline!),
      };

      final response = await httpClient.patch(
        verdictUrl,
        body: json.encode(payload),
      );

      if (!mounted) return;
      dismissFeedbackToasts();
      setState(() => _isSubmittingVerdict = false);

      if (response.statusCode == 200) {
        setState(() {
          team.verdict = _selectedVerdict;
          team.verdictRemarks = directives;
          team.redefenseVerificationRequired = _redefenseVerificationRequired;
          if (_revisionDeadline != null &&
              _selectedVerdict == 'approved_with_revisions') {
            team.revisionDeadline = DateFormat(
              'yyyy-MM-dd',
            ).format(_revisionDeadline!);
          }
        });

        widget.onGradesSubmitted?.call();

        if (_selectedVerdict == 'for_redefense') {
          showSuccessToast(
            context,
            _redefenseVerificationRequired ? 'Re-defense recorded. Adviser verification is required before scheduling.' : 'Re-defense recorded. Ready to schedule the next panel attempt.',
          );
        } else if (_selectedVerdict == 'approved_with_revisions') {
          showSuccessToast(
            context,
            'Verdict recorded: Approved with Revisions.',
          );
        } else {
          showSuccessToast(context, 'Verdict recorded: ${defenseVerdictLabel(_selectedVerdict)}.');
        }
      } else {
        showErrorToast(
          context,
          friendlyHttpErrorMessage(response.statusCode, response.body),
        );
      }
    } on SessionExpiredException {
      if (mounted) setState(() => _isSubmittingVerdict = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmittingVerdict = false);
        dismissFeedbackToasts();
        showErrorToast(context, 'Error submitting verdict: $e');
      }
    }
  }
}
