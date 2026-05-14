import 'package:flutter/material.dart';
import 'awarding_state.dart';

const _primaryColor = Color(0xFF7F1D1D);
const _goldColor = Color(0xFFD97706);

class LeaderEntry {
  final String label;
  final String score;
  final double sortValue;
  final String? subtitle;
  final bool isDraft;

  const LeaderEntry({
    required this.label,
    required this.score,
    required this.sortValue,
    this.subtitle,
    this.isDraft = false,
  });
}

class LeaderAward {
  final String category, team, project;
  final IconData icon;
  final Color color;
  const LeaderAward(this.category, this.icon, this.color, this.team, this.project);
}

const _defaultAwards = [
  LeaderAward('Best UI', Icons.palette, Color(0xFF8B5CF6), 'Team Alpha',
      'AI-Based Attendance System'),
  LeaderAward('Best Database', Icons.storage, Color(0xFF0EA5E9), 'Team Beta',
      'Smart Inventory Management'),
  LeaderAward('Most Innovative', Icons.lightbulb, Color(0xFF10B981), 'Team Gamma',
      'Online Voting System'),
];

class LeaderboardTab extends StatefulWidget {
  final List<LeaderEntry> entries;
  final String subtitle;
  final List<LeaderAward> awards;
  final bool showStars;

  const LeaderboardTab({
    super.key,
    required this.entries,
    required this.subtitle,
    this.awards = _defaultAwards,
    this.showStars = false,
  });

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  final _awarding = AwardingState.instance;

  @override
  void initState() {
    super.initState();
    _awarding.addListener(_rebuild);
  }

  @override
  void dispose() {
    _awarding.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  /// Resolves the display label — generic or real depending on awarding state.
  String _resolve(String label) => _awarding.resolveLabel(label);

  /// Resolves award team name for category awards section.
  String _resolveAwardTeam(LeaderAward award) {
    if (!_awarding.awardingStarted) return '???';
    final slotMap = {
      'Best UI': AwardSlot.bestUI,
      'Best Database': AwardSlot.bestDatabase,
      'Most Innovative': AwardSlot.mostInnovative,
    };
    final slot = slotMap[award.category];
    if (slot != null && _awarding.revealed[slot] == true) {
      return _awarding.winnerFor(slot)?.name ?? '???';
    }
    return '???';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.entries]
      ..sort((a, b) => b.sortValue.compareTo(a.sortValue));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('Leaderboard'),
        const SizedBox(height: 4),
        Text(widget.subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        // Awarding status banner
        if (!_awarding.awardingStarted) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_clock, size: 14, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Awarding has not started. Team names are hidden.',
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildPodium(sorted),
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: _goldColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Category Awards',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _goldColor)),
          ],
        ),
        const SizedBox(height: 12),
        ...widget.awards.map((a) => _awardCard(a)),
        if (sorted.length > 3) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 10),
            child: Text('Other Teams',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
          ),
          ...sorted.skip(3).toList().asMap().entries.map(
                (e) => _leaderRow(e.key + 4, e.value),
              ),
        ],
      ],
    );
  }

  Widget _buildPodium(List<LeaderEntry> sorted) {
    const rankColors = [Color(0xFFD97706), Color(0xFF6B7280), Color(0xFFB45309)];
    const rankIcons = [Icons.emoji_events, Icons.military_tech, Icons.military_tech];
    const heights = [110.0, 85.0, 70.0];
    const podiumOrder = [1, 0, 2];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: podiumOrder.map((i) {
        if (i >= sorted.length) return const Expanded(child: SizedBox());
        final entry = sorted[i];
        final color = rankColors[i];
        final isFirst = i == 0;
        final displayLabel = _resolve(entry.label);
        final resolvedScore = _awarding.resolveScore(entry.label);
        final displayScore = resolvedScore ?? entry.score;
        final isScoreResolved = resolvedScore != null;

        return Expanded(
          child: Column(
            children: [
              Text(displayScore,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isFirst ? 18 : 15,
                      color: color)),
              const SizedBox(height: 2),
              if (widget.showStars && !isScoreResolved)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (s) => Icon(
                      s < entry.sortValue.round()
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: isFirst ? 14 : 11,
                    ),
                  ),
                )
              else if (entry.subtitle != null)
                Text(entry.subtitle!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 6),
              CircleAvatar(
                radius: isFirst ? 28 : 22,
                backgroundColor: color,
                child: Icon(rankIcons[i], color: Colors.white,
                    size: isFirst ? 24 : 18),
              ),
              const SizedBox(height: 6),
              Text(displayLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isFirst ? 13 : 11,
                      color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (entry.isDraft)
                const Text('Draft',
                    style: TextStyle(fontSize: 10, color: Colors.blue)),
              const SizedBox(height: 4),
              Container(
                height: heights[i],
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text('#${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isFirst ? 22 : 18,
                          color: color)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _awardCard(LeaderAward award) {
    final teamName = _resolveAwardTeam(award);
    final isRevealed = _awarding.awardingStarted &&
        teamName != '???';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [award.color.withOpacity(0.08), Colors.white],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: award.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: award.color.withOpacity(0.3)),
                ),
                child: Icon(award.icon, color: award.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(award.category,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: award.color)),
                    const SizedBox(height: 2),
                    isRevealed
                        ? Text(teamName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14))
                        : Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 12, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              const Text('To be announced',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                  ],
                ),
              ),
              Icon(
                Icons.workspace_premium,
                color: isRevealed ? _goldColor : Colors.grey.shade300,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leaderRow(int rank, LeaderEntry entry) {
    final displayLabel = _resolve(entry.label);
    final resolvedScore = _awarding.resolveScore(entry.label);
    final displayScore = resolvedScore ?? entry.score;
    final isScoreResolved = resolvedScore != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Center(
                child: Text('#$rank',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _primaryColor)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(displayLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(displayScore,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _primaryColor)),
                if (widget.showStars && !isScoreResolved)
                  Row(
                    children: List.generate(
                      5,
                      (s) => Icon(
                        s < entry.sortValue.round()
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 12,
                      ),
                    ),
                  )
                else if (entry.subtitle != null)
                  Text(entry.subtitle!,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
                color: _primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
      ],
    );
  }
}
