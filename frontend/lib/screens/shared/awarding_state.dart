import 'package:flutter/material.dart';

// ── Award slot enum ───────────────────────────────────────────────────────────

enum AwardSlot {
  firstPlacer,
  secondPlacer,
  thirdPlacer,
  bestUI,
  bestDatabase,
  mostInnovative,
}

extension AwardSlotExt on AwardSlot {
  String get label => switch (this) {
        AwardSlot.firstPlacer => '1st Placer',
        AwardSlot.secondPlacer => '2nd Placer',
        AwardSlot.thirdPlacer => '3rd Placer',
        AwardSlot.bestUI => 'Best UI',
        AwardSlot.bestDatabase => 'Best Database',
        AwardSlot.mostInnovative => 'Most Innovative',
      };

  IconData get icon => switch (this) {
        AwardSlot.firstPlacer => Icons.emoji_events,
        AwardSlot.secondPlacer => Icons.military_tech,
        AwardSlot.thirdPlacer => Icons.military_tech,
        AwardSlot.bestUI => Icons.palette,
        AwardSlot.bestDatabase => Icons.storage,
        AwardSlot.mostInnovative => Icons.lightbulb,
      };

  Color get color => switch (this) {
        AwardSlot.firstPlacer => const Color(0xFFD97706),
        AwardSlot.secondPlacer => const Color(0xFF6B7280),
        AwardSlot.thirdPlacer => const Color(0xFFB45309),
        AwardSlot.bestUI => const Color(0xFF8B5CF6),
        AwardSlot.bestDatabase => const Color(0xFF0EA5E9),
        AwardSlot.mostInnovative => const Color(0xFF10B981),
      };
}

// ── Team result model ─────────────────────────────────────────────────────────

class TeamResult {
  final String name;
  final String project;
  final double score;     // 0–100 panel score percentage
  final double rawScore;
  final double maxScore;

  const TeamResult({
    required this.name,
    required this.project,
    required this.score,
    required this.rawScore,
    required this.maxScore,
  });
}

// ── Awarding state singleton ──────────────────────────────────────────────────

class AwardingState extends ChangeNotifier {
  AwardingState._();
  static final AwardingState instance = AwardingState._();

  bool awardingStarted = false;

  /// Which slots have been revealed to students.
  final Map<AwardSlot, bool> revealed = {
    for (final s in AwardSlot.values) s: false,
  };

  // ── Computed winners (set from panelist data) ─────────────────────────────
  // Placer rankings — index 0 = 1st, 1 = 2nd, 2 = 3rd
  List<TeamResult> rankedTeams = [];

  // Category award winners (mock — in real app these come from rubric sub-scores)
  Map<AwardSlot, TeamResult?> categoryWinners = {
    AwardSlot.bestUI: null,
    AwardSlot.bestDatabase: null,
    AwardSlot.mostInnovative: null,
  };

  /// Called by panelist dashboard to push current scores into awarding state.
  void updateRankings(List<TeamResult> teams) {
    rankedTeams = [...teams]..sort((a, b) => b.score.compareTo(a.score));

    // Auto-assign category winners from top teams (mock logic)
    if (rankedTeams.isNotEmpty) {
      categoryWinners[AwardSlot.bestUI] = rankedTeams[0];
      categoryWinners[AwardSlot.bestDatabase] =
          rankedTeams.length > 1 ? rankedTeams[1] : rankedTeams[0];
      categoryWinners[AwardSlot.mostInnovative] =
          rankedTeams.length > 2 ? rankedTeams[2] : rankedTeams[0];
    }
    notifyListeners();
  }

  /// Returns the winner for a given slot (null if not enough teams).
  TeamResult? winnerFor(AwardSlot slot) {
    switch (slot) {
      case AwardSlot.firstPlacer:
        return rankedTeams.isNotEmpty ? rankedTeams[0] : null;
      case AwardSlot.secondPlacer:
        return rankedTeams.length > 1 ? rankedTeams[1] : null;
      case AwardSlot.thirdPlacer:
        return rankedTeams.length > 2 ? rankedTeams[2] : null;
      default:
        return categoryWinners[slot];
    }
  }

  void toggleAwarding(bool value) {
    awardingStarted = value;
    if (!value) {
      for (final s in AwardSlot.values) {
        revealed[s] = false;
      }
    }
    notifyListeners();
  }

  void revealSlot(AwardSlot slot) {
    revealed[slot] = true;
    notifyListeners();
  }

  void hideSlot(AwardSlot slot) {
    revealed[slot] = false;
    notifyListeners();
  }

  /// Used by leaderboard to resolve a generic label (e.g. "Team A") to real name.
  /// Only resolves if awarding started AND that placer slot is revealed.
  String resolveLabel(String genericLabel) {
    if (!awardingStarted) return genericLabel;
    final podiumMap = {
      'Team A': AwardSlot.firstPlacer,
      'Team B': AwardSlot.secondPlacer,
      'Team C': AwardSlot.thirdPlacer,
    };
    final slot = podiumMap[genericLabel];
    if (slot != null && revealed[slot] == true) {
      return winnerFor(slot)?.name ?? genericLabel;
    }
    return genericLabel;
  }

  /// Returns the real score string for a generic label if revealed, else null.
  String? resolveScore(String genericLabel) {
    if (!awardingStarted) return null;
    final podiumMap = {
      'Team A': AwardSlot.firstPlacer,
      'Team B': AwardSlot.secondPlacer,
      'Team C': AwardSlot.thirdPlacer,
    };
    final slot = podiumMap[genericLabel];
    if (slot != null && revealed[slot] == true) {
      final t = winnerFor(slot);
      if (t != null) return '${t.score.toStringAsFixed(1)}%';
    }
    return null;
  }

  int get revealedCount => revealed.values.where((v) => v).length;
}
