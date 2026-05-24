import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/bridge_service.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_snackbar.dart';

class PeerEvalTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final bool peerEvalAllowed;
  final List<Map<String, dynamic>> teammates; // from studentData members (excluding self)
  final List<Map<String, dynamic>> peerCriteria; // from peer rubric
  final String studentId;
  final String teamId;
  final int peerWeight;
  final List<Map<String, dynamic>> myPeerSubmissions;
  final VoidCallback? onPeerSubmitted;

  const PeerEvalTab({
    super.key,
    required this.isCapstone,
    required this.peerEvalAllowed,
    required this.teammates,
    required this.peerCriteria,
    this.myPeerSubmissions = const [],
    this.onPeerSubmitted,
    required this.studentId,
    required this.teamId,
    this.peerWeight = 20,
  });

  @override
  ConsumerState<PeerEvalTab> createState() => _PeerEvalTabState();
}

class _PeerEvalTabState extends ConsumerState<PeerEvalTab> {
  late Map<String, Map<String, double>> _scores;
  late Map<String, bool> _posted;

  List<Map<String, dynamic>> get _effectiveCriteria => widget.peerCriteria.isNotEmpty
      ? widget.peerCriteria
      : [
          {'name': 'Contribution', 'maxScore': 5},
          {'name': 'Teamwork', 'maxScore': 5},
          {'name': 'Communication', 'maxScore': 5},
          {'name': 'Reliability', 'maxScore': 5},
        ];

  @override
  void initState() {
    super.initState();
    _scores = {};
    _posted = {};
    _buildScores();
  }

  @override
  void didUpdateWidget(PeerEvalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teammates != widget.teammates ||
        oldWidget.peerCriteria != widget.peerCriteria ||
        oldWidget.myPeerSubmissions != widget.myPeerSubmissions) {
      _buildScores();
    }
  }

  void _buildScores() {
    for (final t in widget.teammates) {
      final name = t['name'] as String? ?? t['id'] as String? ?? '?';
      _posted.putIfAbsent(name, () => false);
      _scores.putIfAbsent(name, () => {
        for (final c in _effectiveCriteria)
          (c['name'] as String): 0.0,
      });
    }
    _hydrateFromSubmissions();
  }

  void _hydrateFromSubmissions() {
    for (final sub in widget.myPeerSubmissions) {
      final name = sub['evaluateeName'] as String? ?? '';
      if (name.isEmpty) continue;

      _posted[name] = true;
      _scores.putIfAbsent(name, () => {});

      final breakdown = (sub['breakdown'] as List? ?? []).cast<Map<String, dynamic>>();
      if (breakdown.isNotEmpty) {
        for (final item in breakdown) {
          final criteriaName =
              item['criteriaName'] as String? ?? item['name'] as String?;
          final score = (item['score'] as num?)?.toDouble();
          if (criteriaName != null && score != null) {
            _scores[name]![criteriaName] = score;
          }
        }
        continue;
      }

      final total = (sub['total'] as num?)?.toDouble();
      final max = (sub['max'] as num?)?.toDouble();
      if (total == null || max == null || max <= 0) continue;

      final ratio = total / max;
      for (final c in _effectiveCriteria) {
        final criteriaName = c['name'] as String;
        final cMax = ((c['maxScore'] as num?) ?? 5).toDouble();
        _scores[name]![criteriaName] = (ratio * cMax).clamp(0, cMax);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.peerEvalAllowed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_clock, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Peer evaluation is not yet open.',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 8),
            const Text('Wait for your PIT Lead to enable it.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    if (widget.teammates.isEmpty) {
      return const Center(
        child: Text('No teammates found for peer evaluation.',
            style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Peer Evaluation'),
          const SizedBox(height: 4),
          const Text('Rate each teammate per criterion. Once submitted, scores are locked.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DefensysTokens.gold.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DefensysTokens.gold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: DefensysTokens.gold, size: 16),
                const SizedBox(width: 8),
                Text('Peer evaluation weight: ${widget.peerWeight}% of final grade.',
                    style: TextStyle(fontSize: 12, color: DefensysTokens.gold)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...widget.teammates.map((t) {
            final name = t['name'] as String? ?? t['id'] as String? ?? '?';
            return _peerCard(name);
          }),
        ],
      ),
    );
  }

  Widget _peerCard(String name) {
    final scores  = _scores[name] ?? {};
    final isPosted = _posted[name] ?? false;
    final effectiveCriteria = widget.peerCriteria.isNotEmpty
        ? widget.peerCriteria
        : [
            {'name': 'Contribution', 'maxScore': 5},
            {'name': 'Teamwork', 'maxScore': 5},
            {'name': 'Communication', 'maxScore': 5},
            {'name': 'Reliability', 'maxScore': 5},
          ];
    final criteria = scores.keys.toList();
    final maxScore = effectiveCriteria.isNotEmpty
        ? (effectiveCriteria.first['maxScore'] as num?)?.toDouble() ?? 5.0
        : 5.0;
    final avg = scores.isEmpty ? 0.0 : scores.values.fold(0.0, (s, v) => s + v) / scores.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
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
                    CircleAvatar(
                      backgroundColor: DefensysTokens.maroon.withOpacity(0.1),
                      child: Text(name[0].toUpperCase(),
                          style: const TextStyle(color: DefensysTokens.maroon, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                if (isPosted)
                  const Row(children: [
                    Icon(Icons.lock, size: 14, color: Colors.red),
                    SizedBox(width: 4),
                    Text('Locked', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ]),
              ],
            ),
            if (isPosted)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(children: [
                  Icon(Icons.lock, size: 14, color: Colors.red),
                  SizedBox(width: 6),
                  Expanded(child: Text('Peer evaluation submitted and permanently locked.',
                      style: TextStyle(fontSize: 12, color: Colors.red))),
                ]),
              ),
            const Divider(height: 20),
            ...criteria.map((c) {
              final cMax = effectiveCriteria.firstWhere(
                (x) => (x['name'] as String?) == c, 
                orElse: () => <String, Object>{'maxScore': 5}
              )['maxScore'] as num? ?? 5;
              return _starRow(name, c, scores[c] ?? 0, cMax.toDouble(), isPosted);
            }),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Average', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Row(children: [
                  ...List.generate(maxScore.toInt(), (i) => Icon(
                    i < avg.round() ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 18,
                  )),
                  const SizedBox(width: 6),
                  Text(avg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            if (!isPosted)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock, size: 16),
                  label: const Text('Submit & Lock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _confirmPost(name, scores),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasUnratedCriteria(Map<String, double> scores) {
    for (final c in _effectiveCriteria) {
      final criteriaName = c['name'] as String;
      final score = scores[criteriaName] ?? 0;
      if (score <= 0) {
        return true;
      }
    }
    return false;
  }

  Future<void> _confirmPost(String name, Map<String, double> scores) async {
    if (_hasUnratedCriteria(scores)) {
      showValidationSnackBar(
        context,
        'Please rate every criterion before submitting.',
      );
      return;
    }

    final confirmed = await confirmDestructive(
      context,
      title: 'Submit Peer Evaluation?',
      message: 'Your evaluation for $name will be permanently locked.',
      confirmLabel: 'Submit & Lock',
    );
    if (!confirmed || !mounted) return;

    setState(() => _posted[name] = true);

    final breakdown = scores.entries.map((e) => {
      'criteriaName': e.key,
      'score': e.value,
      'max': _effectiveCriteria.firstWhere(
        (c) => (c['name'] as String?) == e.key,
        orElse: () => <String, Object>{'maxScore': 5},
      )['maxScore'],
    }).toList();
    final total = scores.values.fold(0.0, (s, v) => s + v);
    final max = _effectiveCriteria.fold(
      0.0,
      (s, c) => s + ((c['maxScore'] as num?)?.toDouble() ?? 5.0),
    );

    await BridgeService.submitPeerGrade(
      httpClient: ref.read(authenticatedHttpClientProvider),
      teamId: widget.teamId,
      evaluatorId: widget.studentId,
      evaluateeName: name,
      breakdown: breakdown,
      total: total,
      max: max,
    );

    widget.onPeerSubmitted?.call();

    if (mounted) {
      showSuccessSnackBar(context, 'Peer evaluation for $name submitted.');
    }
  }

  Widget _starRow(String name, String criterion, double value, double maxScore, bool locked) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(criterion, style: const TextStyle(fontSize: 13))),
          Row(
            children: List.generate(maxScore.toInt(), (i) => GestureDetector(
              onTap: locked ? null : () => setState(() => _scores[name]![criterion] = (i + 1).toDouble()),
              child: Icon(
                i < value ? Icons.star : Icons.star_border,
                color: locked ? Colors.grey.shade400 : Colors.amber,
                size: 22,
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 20,
            decoration: BoxDecoration(color: DefensysTokens.maroon, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DefensysTokens.maroon)),
      ],
    );
  }
}
