import 'package:flutter/material.dart';

class TeamMember {
  final String id;
  final String name;
  const TeamMember({required this.id, required this.name});
}

class TeamData {
  final String name, project, defenseDate;
  final String teamId;
  final String scheduleId;
  final String scope;
  final bool isCapstone;
  final List<String> members;
  final List<TeamMember> memberDetails;
  final List<Criterion> criteria;
  final int panelWeight;
  final int peerWeight;
  final int adviserWeight;
  final Map<String, dynamic>? panelRubric;
  bool get isLockedByDate {
    if (scheduledDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.isBefore(scheduledDate!);
  }
  final DateTime? scheduledDate;
  bool isPosted;

  TeamData({
    required this.name,
    required this.project,
    required this.defenseDate,
    required this.teamId,
    this.scheduleId = '',
    required this.scope,
    required this.isCapstone,
    required this.members,
    required this.memberDetails,
    required this.criteria,
    required this.isPosted,
    this.panelWeight = 50,
    this.peerWeight = 20,
    this.adviserWeight = 0,
    this.panelRubric,
    this.scheduledDate,
  });

  bool get hasValidScope => scope == 'capstone' || scope == 'pit';
  String get scopeLabel {
    if (scope == 'capstone') return 'Capstone';
    if (scope == 'pit') return 'PIT';
    return 'Scope missing';
  }

  String get targetType => panelRubric?['target_type']?.toString() ?? 'team';
  bool get isIndividualTarget => targetType == 'individual';
}

class Criterion {
  final int? id;
  final String name;
  final double maxScore;
  double score;
  Criterion(this.name, this.maxScore, {this.id}) : score = maxScore * 0.8;
}

class Award {
  final String category, team, project;
  final IconData icon;
  final Color color;
  Award(this.category, this.icon, this.color, this.team, this.project);
}

/// Scores submitted by one panelist for one team.
class PanelistScore {
  final String panelistName;
  final Map<String, double> criteriaScores; // criterion name → score
  final bool isPosted;

  const PanelistScore({
    required this.panelistName,
    required this.criteriaScores,
    this.isPosted = true,
  });

  double get total => criteriaScores.values.fold(0, (s, v) => s + v);
}

/// Mock overall results for a team across 4 panelists.
class TeamOverallResult {
  final String teamName;
  final String project;
  final List<PanelistScore> panelistScores;
  final double maxScore;

  const TeamOverallResult({
    required this.teamName,
    required this.project,
    required this.panelistScores,
    required this.maxScore,
  });

  double get average => panelistScores.isEmpty
      ? 0
      : panelistScores.map((p) => p.total).reduce((a, b) => a + b) /
            panelistScores.length;

  double get averagePct => average / maxScore * 100;
}
