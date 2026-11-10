import 'package:flutter/material.dart';
import 'package:defensys/utils/rubric_scoring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/bridge_service.dart';
import '../../../theme/defensys_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';

class PeerEvalTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final bool peerEvalAllowed;
  final String? peerEvalUnavailableReason;
  final List<Map<String, dynamic>> members; // All team members, including self.
  final List<Map<String, dynamic>> peerCriteria; // from peer rubric
  final String studentId;
  final String teamId;
  final int peerWeight;
  final List<Map<String, dynamic>> myPeerSubmissions;
  final VoidCallback? onPeerSubmitted;
  final Future<void> Function()? onRefresh;
  final bool isEmbedded;
  final bool hideHistory;
  final String? stage;

  const PeerEvalTab({
    super.key,
    required this.isCapstone,
    required this.peerEvalAllowed,
    this.peerEvalUnavailableReason,
    required this.members,
    required this.peerCriteria,
    this.myPeerSubmissions = const [],
    this.onPeerSubmitted,
    this.onRefresh,
    required this.studentId,
    required this.teamId,
    this.peerWeight = 20,
    this.isEmbedded = false,
    this.hideHistory = false,
    this.stage,
  });

  @override
  ConsumerState<PeerEvalTab> createState() => _PeerEvalTabState();
}

class _PeerEvalTabState extends ConsumerState<PeerEvalTab> {
  late Map<String, Map<String, double>> _scores;
  late Map<String, bool> _posted;
  late Map<String, bool> _submitting;

  List<Map<String, dynamic>> get _effectiveCriteria =>
      widget.peerCriteria.isNotEmpty
      ? widget.peerCriteria
      : [
          {'name': 'Contribution', 'maxScore': 5},
          {'name': 'Teamwork', 'maxScore': 5},
          {'name': 'Communication', 'maxScore': 5},
          {'name': 'Reliability', 'maxScore': 5},
        ];

  String _teammateId(Map<String, dynamic> teammate) =>
      teammate['id']?.toString() ?? teammate['name']?.toString() ?? '?';

  String _teammateName(Map<String, dynamic> teammate) =>
      teammate['name']?.toString() ?? _teammateId(teammate);

  String? _submissionKey(Map<String, dynamic> submission) {
    final id =
        submission['evaluateeId']?.toString() ??
        submission['evaluatee_id']?.toString();
    final name =
        (submission['evaluateeName']?.toString() ??
                submission['evaluatee_name']?.toString() ??
                '')
            .trim()
            .toLowerCase();

    if (id != null && id.isNotEmpty) {
      for (final teammate in widget.members) {
        if (_teammateId(teammate) == id) return _teammateId(teammate);
      }
    }

    if (name.isNotEmpty) {
      for (final teammate in widget.members) {
        if (_teammateName(teammate).trim().toLowerCase() == name) {
          return _teammateId(teammate);
        }
      }
    }

    return (id != null && id.isNotEmpty) ? id : (name.isNotEmpty ? name : null);
  }

  @override
  void initState() {
    super.initState();
    _scores = {};
    _posted = {};
    _submitting = {};
    _buildScores();
  }

  @override
  void didUpdateWidget(PeerEvalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged =
        oldWidget.teamId != widget.teamId ||
        oldWidget.studentId != widget.studentId ||
        oldWidget.stage != widget.stage;
    if (contextChanged) {
      _scores.clear();
      _posted.clear();
      _submitting.clear();
    }
    if (contextChanged ||
        oldWidget.members != widget.members ||
        oldWidget.peerCriteria != widget.peerCriteria ||
        oldWidget.myPeerSubmissions != widget.myPeerSubmissions ||
        oldWidget.peerEvalAllowed != widget.peerEvalAllowed) {
      _buildScores();
      if (oldWidget.peerEvalAllowed != widget.peerEvalAllowed) {
        setState(() {});
      }
    }
  }

  String _criterionKey(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? '';
    final sec = (c['section'] ?? '').toString().trim();
    return sec.isNotEmpty ? '$sec::$name' : name;
  }

  void _buildScores() {
    for (final t in widget.members) {
      final id = _teammateId(t);
      _posted.putIfAbsent(id, () => false);

      final teammateScores = _scores[id] ?? <String, double>{};

      // Ensure all current effective criteria are present in the teammate's scores
      for (final c in _effectiveCriteria) {
        final key = _criterionKey(c);
        final name = c['name']?.toString() ?? '';
        teammateScores.putIfAbsent(key, () => teammateScores[name] ?? 0.0);
      }

      // Remove any criteria that are no longer part of the current effective criteria
      final allowedKeys = _effectiveCriteria.map(_criterionKey).toSet();
      teammateScores.removeWhere((key, _) => !allowedKeys.contains(key));

      _scores[id] = teammateScores;
    }
    _hydrateFromSubmissions();
  }

  void _hydrateFromSubmissions() {
    for (final sub in widget.myPeerSubmissions) {
      final key = _submissionKey(sub);
      if (key == null || key.isEmpty) continue;

      _posted[key] = true;
      _scores.putIfAbsent(key, () => {});

      final breakdown = (sub['breakdown'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      if (breakdown.isNotEmpty) {
        for (final item in breakdown) {
          final itemId = item['criterion_id'];
          final criteriaName =
              item['criteriaName'] as String? ?? item['name'] as String?;
          final itemSec = (item['section'] ?? '').toString().trim();
          final score = (item['score'] as num?)?.toDouble();
          if (score == null) continue;
          Map<String, dynamic>? matchedCrit;
          if (itemId != null) {
            matchedCrit = _effectiveCriteria
                .where((c) => c['id']?.toString() == itemId.toString())
                .firstOrNull;
          }
          matchedCrit ??= _effectiveCriteria.where((c) {
            final cName = c['name']?.toString() ?? '';
            final cSec = (c['section'] ?? '').toString().trim();
            if (itemSec.isNotEmpty) {
              return cSec == itemSec && cName == criteriaName;
            }
            return cName == criteriaName;
          }).firstOrNull;
          if (matchedCrit != null) {
            _scores[key]![_criterionKey(matchedCrit)] = score;
          } else if (criteriaName != null) {
            final secKey =
                itemSec.isNotEmpty ? '$itemSec::$criteriaName' : criteriaName;
            _scores[key]![secKey] = score;
          }
        }
        continue;
      }

      final total = (sub['total'] as num?)?.toDouble();
      final max = (sub['max'] as num?)?.toDouble();
      if (total == null || max == null || max <= 0) continue;

      final ratio =
          ((sub['percentage'] as num?)?.toDouble() ?? total / max * 100) / 100;
      for (final c in _effectiveCriteria) {
        final cKey = _criterionKey(c);
        final cMax = ((c['maxScore'] as num?) ?? 5).toDouble();
        _scores[key]![cKey] = (ratio * cMax).clamp(0, cMax);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      DefensysShadcnScope(child: Builder(builder: _buildContent));

  Widget _buildContent(BuildContext context) {
    Widget refreshWrapper(Widget child) {
      if (widget.isEmbedded || widget.onRefresh == null) return child;
      return LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            color: DefensysTokens.maroonOf(context),
            onRefresh: widget.onRefresh!,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: child,
              ),
            ),
          );
        },
      );
    }

    if (widget.hideHistory) {
      return refreshWrapper(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  size: 56,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Peer Evaluation Archived',
                  style: TextStyle(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Peer evaluation history for past events is archived and hidden.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final scopeName = widget.isCapstone ? 'defense stage' : 'event';

    if (!widget.peerEvalAllowed && widget.myPeerSubmissions.isEmpty) {
      return refreshWrapper(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Card(
            elevation: 0,
            color: DefensysTokens.surfaceOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: DefensysTokens.borderOf(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: DefensysTokens.textSecondaryOf(context),
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Peer evaluation is locked for this $scopeName.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.peerEvalUnavailableReason ??
                              (widget.isCapstone
                                  ? 'It opens after your team is endorsed, scheduled, and every assigned panelist finishes grading.'
                                  : 'With peer access enabled, you must grade yourself and every teammate after all assigned panelists finish evaluating your scheduled defense.'),
                          style: TextStyle(
                            color: DefensysTokens.textSecondaryOf(context),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.members.isEmpty) {
      return refreshWrapper(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'No team members found for evaluation.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ),
      );
    }

    final total = widget.members.length;
    final done = widget.members
        .where((t) => _posted[_teammateId(t)] == true)
        .length;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Peer & Self-Evaluation'),
        const SizedBox(height: 8),
        Text(
          'Rate yourself and every teammate. Scores lock after submission.',
          style: DefensysTokens.subtitle.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 20),
        _buildPeerProgressBlock(done, total),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${widget.peerWeight}% of final grade',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                text: '. Self and teammate ratings count equally.',
              ),
            ],
          ),
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (done == total && total > 0) ...[
          const SizedBox(height: 12),
          Text(
            'All peer and self-evaluations submitted and locked for this event.',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
        const SizedBox(height: 24),
        ...widget.members.map((t) {
          final id = _teammateId(t);
          final name = _teammateName(t);
          return _peerCard(id, name);
        }),
      ],
    );

    if (widget.isEmbedded) {
      return column;
    }

    final mainContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: column,
    );

    if (widget.onRefresh == null) return mainContent;
    return RefreshIndicator(
      color: DefensysTokens.maroonOf(context),
      onRefresh: widget.onRefresh!,
      child: mainContent,
    );
  }

  Widget _buildPeerProgressBlock(int done, int total) {
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final color = DefensysTokens.maroonOf(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                'Required evaluations',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              Text(
                total > 0 ? '$done / $total Complete' : 'No Team Members',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: DefensysTokens.borderOf(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peerCard(String teammateId, String name) {
    final isSelf = teammateId == widget.studentId;
    final scores = _scores[teammateId] ?? {};
    final isPosted = _posted[teammateId] ?? false;
    final effectiveCriteria = widget.peerCriteria.isNotEmpty
        ? widget.peerCriteria
        : [
            {'name': 'Contribution', 'maxScore': 5},
            {'name': 'Teamwork', 'maxScore': 5},
            {'name': 'Communication', 'maxScore': 5},
            {'name': 'Reliability', 'maxScore': 5},
          ];
    final hasVariableMax = effectiveCriteria
            .map((c) => (c['maxScore'] as num?)?.toDouble() ?? 5.0)
            .toSet()
            .length >
        1;
    final hasSections = effectiveCriteria
        .any((c) => (c['section']?.toString().trim() ?? '').isNotEmpty);
    final totalEarned = effectiveCriteria.fold(
      0.0,
      (s, c) => s + (scores[_criterionKey(c)] ?? scores[c['name']] ?? 0.0),
    );
    final totalMax = effectiveCriteria.fold(
      0.0,
      (s, c) => s + ((c['maxScore'] as num?)?.toDouble() ?? 5.0),
    );
    final weightedPct =
        rubricPercentage(
          effectiveCriteria.map(
            (c) => RubricScore(
              scores[_criterionKey(c)] ?? scores[c['name']] ?? 0.0,
              ((c['maxScore'] as num?) ?? 5).toDouble(),
              rubricWeight(c['weight']),
            ),
          ),
        ) ??
        (totalMax > 0 ? (totalEarned / totalMax) * 100.0 : 0.0);
    final maxScore = effectiveCriteria.isNotEmpty
        ? (effectiveCriteria.first['maxScore'] as num?)?.toDouble() ?? 5.0
        : 5.0;
    final avg = effectiveCriteria.isEmpty
        ? 0.0
        : totalEarned / effectiveCriteria.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: DefensysTokens.surfaceHigherOf(
                          context,
                        ),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: DefensysTokens.textSecondaryOf(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isSelf ? '$name (You)' : name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isPosted ? 'Locked' : 'To do',
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (isPosted)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isSelf
                            ? 'Self-evaluation submitted and locked.'
                            : 'Peer evaluation submitted and locked.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 28, color: DefensysTokens.borderOf(context)),
            ...effectiveCriteria.map((critDef) {
              final cKey = _criterionKey(critDef);
              final cName = critDef['name']?.toString() ?? '';
              final cMax = (critDef['maxScore'] as num?) ?? 5;
              final cSec = (critDef['section'] ?? '').toString().trim();
              return _criterionRatingRow(
                teammateId,
                cKey,
                scores[cKey] ?? scores[cName] ?? 0,
                cMax.toDouble(),
                isPosted || !widget.peerEvalAllowed,
                displayLabel: cName,
                section: cSec.isNotEmpty ? cSec : null,
              );
            }),
            Divider(height: 28, color: DefensysTokens.borderOf(context)),
            _evaluationSummaryRow(
              avg,
              maxScore,
              customLabel:
                  (hasVariableMax || hasSections) ? 'Evaluation Total' : null,
              customValue: (hasVariableMax || hasSections)
                  ? '${totalEarned.toStringAsFixed(0)} / ${totalMax.toStringAsFixed(0)} pts (${weightedPct.toStringAsFixed(1)}%)'
                  : null,
            ),
            const SizedBox(height: 14),
            if (!isPosted)
              SizedBox(
                width: double.infinity,
                child: ShadButton(
                  expands: true,
                  height: DefensysTokens.buttonHeightPrimary,
                  backgroundColor: DefensysTokens.maroonOf(context),
                  hoverBackgroundColor: DefensysTokens.maroonDark,
                  foregroundColor: Colors.white,
                  enabled:
                      widget.peerEvalAllowed && _submitting[teammateId] != true,
                  leading: _submitting[teammateId] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_outline_rounded, size: 16),
                  onPressed: () => _confirmPost(teammateId, name, scores),
                  child: Text(
                    _submitting[teammateId] == true
                        ? 'Submitting...'
                        : 'Submit Evaluation',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasUnratedCriteria(Map<String, double> scores) {
    for (final c in _effectiveCriteria) {
      final cKey = _criterionKey(c);
      final cName = c['name']?.toString() ?? '';
      final score = scores[cKey] ?? scores[cName] ?? 0;
      if (score <= 0) {
        return true;
      }
    }
    return false;
  }

  Future<void> _confirmPost(
    String teammateId,
    String name,
    Map<String, double> scores,
  ) async {
    if (!widget.peerEvalAllowed) return;
    if (_hasUnratedCriteria(scores)) {
      showValidationToast(
        context,
        'Please rate every criterion before submitting.',
      );
      return;
    }

    final preview = rubricPercentage(
      _effectiveCriteria.map(
        (criterion) => RubricScore(
          scores[_criterionKey(criterion)] ?? scores[criterion['name']] ?? 0,
          ((criterion['maxScore'] as num?) ?? 5).toDouble(),
          rubricWeight(criterion['weight']),
        ),
      ),
    );
    final confirmed = await confirmLock(
      context,
      title: teammateId == widget.studentId
          ? 'Submit Self-Evaluation?'
          : 'Submit Peer Evaluation?',
      message:
          'Your evaluation for $name will be saved and permanently locked.${preview == null ? '' : ' Evaluation score: ${preview.toStringAsFixed(2)}%.'}',
      confirmLabel: 'Submit',
      icon: Icons.save_rounded,
      confirmColor: DefensysTokens.saveActionBg,
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting[teammateId] = true);

    try {
      final breakdown = _effectiveCriteria
          .map((criterion) {
            final cKey = _criterionKey(criterion);
            final cName = criterion['name']?.toString() ?? '';
            final cSec = (criterion['section'] ?? '').toString().trim();
            final cScore = scores[cKey] ?? scores[cName] ?? 0.0;
            return {
              'criterion_id': criterion['id'],
              'criteriaName': cName,
              if (cSec.isNotEmpty) 'section': cSec,
              'score': cScore,
              'max': criterion['maxScore'] ?? 5,
            };
          })
          .toList();
      final total = _effectiveCriteria.fold(
        0.0,
        (s, c) => s + (scores[_criterionKey(c)] ?? scores[c['name']] ?? 0.0),
      );
      final max = _effectiveCriteria.fold(
        0.0,
        (s, c) => s + ((c['maxScore'] as num?)?.toDouble() ?? 5.0),
      );

      await BridgeService.submitPeerGrade(
        httpClient: ref.read(authenticatedHttpClientProvider),
        teamId: widget.teamId,
        evaluatorId: widget.studentId,
        evaluateeId: teammateId,
        breakdown: breakdown,
        total: total,
        max: max,
        stage: widget.stage,
      );

      if (mounted) {
        setState(() {
          _posted[teammateId] = true;
          _submitting[teammateId] = false;
        });
      }

      widget.onPeerSubmitted?.call();

      if (mounted) {
        showSuccessToast(context, 'Peer evaluation for $name submitted.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting[teammateId] = false);
        showValidationToast(context, 'Failed to submit peer evaluation.');
      }
    }
  }

  Widget _criterionRatingRow(
    String teammateId,
    String criterion,
    double value,
    double maxScore,
    bool locked, {
    String? displayLabel,
    String? section,
  }) {
    final isRated = value > 0;
    final intMax = maxScore.toInt();
    final isPillScale = intMax <= 10;
    final labelText = displayLabel ?? criterion;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section != null && section.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                section,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
            ),
          ],
          // Row 1: Criterion Title & Score Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  labelText,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRated ? '${value.toInt()} / $intMax' : 'Unrated',
                style: DefensysTokens.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Adaptive Rating Control
          if (isPillScale) ...[
            Wrap(
              spacing: 6,
              runSpacing: 8,
              children: List.generate(intMax, (i) {
                final scoreVal = i + 1;
                final isSelected = value.toInt() == scoreVal;
                return Semantics(
                  label: '$criterion, $scoreVal of $intMax',
                  selected: isSelected,
                  child: ShadButton.outline(
                    width: 44,
                    height: 44,
                    padding: EdgeInsets.zero,
                    enabled: !locked,
                    backgroundColor: isSelected
                        ? (locked
                              ? DefensysTokens.textSecondaryOf(context)
                              : DefensysTokens.maroonOf(context))
                        : DefensysTokens.surfaceOf(context),
                    hoverBackgroundColor: isSelected
                        ? DefensysTokens.maroonDark
                        : DefensysTokens.surfaceHigherOf(context),
                    foregroundColor: isSelected
                        ? Colors.white
                        : DefensysTokens.textPrimaryOf(context),
                    onPressed: () => setState(
                      () =>
                          _scores[teammateId]![criterion] = scoreVal.toDouble(),
                    ),
                    child: Text('$scoreVal'),
                  ),
                );
              }),
            ),
          ] else ...[
            // Tactile Slider + Steppers for scales > 10
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: DefensysTokens.maroonOf(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: (locked || value <= 1)
                      ? null
                      : () => setState(
                          () => _scores[teammateId]![criterion] = (value - 1)
                              .clamp(1.0, maxScore),
                        ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: DefensysTokens.maroonOf(context),
                      thumbColor: DefensysTokens.maroonOf(context),
                      overlayColor: DefensysTokens.maroonOf(
                        context,
                      ).withValues(alpha: 0.15),
                      inactiveTrackColor: DefensysTokens.borderOf(context),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: Slider(
                      value: value > 0 ? value : 1.0,
                      min: 1.0,
                      max: maxScore,
                      divisions: (intMax - 1) > 0 ? (intMax - 1) : 1,
                      onChanged: locked
                          ? null
                          : (v) => setState(
                              () => _scores[teammateId]![criterion] = v
                                  .roundToDouble(),
                            ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: DefensysTokens.maroonOf(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: (locked || value >= maxScore)
                      ? null
                      : () => setState(
                          () => _scores[teammateId]![criterion] = (value + 1)
                              .clamp(1.0, maxScore),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _evaluationSummaryRow(
    double avg,
    double maxScore, {
    String? customLabel,
    String? customValue,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            customLabel ?? 'Evaluation Average',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
        Text(
          customValue ??
              '${avg.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(0)}',
          style: DefensysTokens.body.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) => Text(
    title,
    style: DefensysTokens.sectionTitle.copyWith(
      fontSize: 18,
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );
}
