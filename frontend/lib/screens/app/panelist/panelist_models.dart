import 'package:flutter/material.dart';

class TeamMember {
  final String id;
  final String name;
  final bool isLeader;
  const TeamMember({
    required this.id,
    required this.name,
    this.isLeader = false,
  });
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
  final String stageName;
  final String eventName;
  final String startTime;
  final String room;
  final String leaderName;
  final String adviserName;
  final String instructorName;
  final String section;
  final String level;

  bool get isLockedByDate {
    if (scheduledDate == null) return true;
    return manilaToday.isBefore(scheduledDate!);
  }

  final DateTime? scheduledDate;
  final bool? serverGradingAvailable;
  final String gradingUnavailableReason;
  final String evaluationContext;
  final bool? serverCanIssueVerdict;
  final String verdictUnavailableReason;
  final String scheduleStatus;
  List<Map<String, dynamic>> draftSubmissions;
  String? draftSavedAt;
  bool hasUnsavedChanges = false;
  bool isPosted;
  List<Map<String, dynamic>> submittedSubmissions;
  final List<Map<String, dynamic>> defenseMaterials;

  final bool isChair;
  String? verdict;
  String? verdictRemarks;
  String? verdictByName;
  String? revisionDeadline;
  bool redefenseVerificationRequired;
  Map<String, dynamic>? workflowGrade;
  int attemptCount;
  int? gradeId;

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
    this.stageName = '',
    this.eventName = '',
    this.startTime = '',
    this.room = '',
    this.leaderName = '',
    this.adviserName = '',
    this.instructorName = '',
    this.section = '',
    this.level = '',
    this.submittedSubmissions = const [],
    this.defenseMaterials = const [],
    this.panelWeight = 50,
    this.peerWeight = 20,
    this.adviserWeight = 0,
    this.panelRubric,
    DateTime? scheduledDate,
    this.serverGradingAvailable,
    this.gradingUnavailableReason = '',
    this.evaluationContext = '',
    this.serverCanIssueVerdict,
    this.verdictUnavailableReason = '',
    this.scheduleStatus = 'scheduled',
    this.draftSubmissions = const [],
    this.draftSavedAt,
    this.isChair = false,
    this.verdict,
    this.verdictRemarks,
    this.verdictByName,
    this.revisionDeadline,
    this.redefenseVerificationRequired = false,
    this.workflowGrade,
    this.attemptCount = 1,
    this.gradeId,
  }) : scheduledDate =
           scheduledDate ??
           DateTime.tryParse(
             RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(defenseDate)?.group(0) ??
                 '',
           );

  static DateTime get manilaToday {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime(now.year, now.month, now.day);
  }

  bool get isToday => scheduledDate == manilaToday;
  bool get gradingAvailable =>
      !isPosted &&
      !isLockedByDate &&
      scheduleStatus == 'scheduled' &&
      (serverGradingAvailable ?? true);
  bool get canIssueVerdict =>
      isChair &&
      !isLockedByDate &&
      scheduleStatus == 'scheduled' &&
      (serverCanIssueVerdict ?? isPosted);
  bool get hasDraft => draftSubmissions.any(
    (s) =>
        (s['criteria_scores'] as List? ?? []).isNotEmpty ||
        (s['remarks']?.toString().trim() ?? '').isNotEmpty,
  );
  String get evaluationStatus {
    if (isPosted) return 'Submitted';
    if (isLockedByDate && scheduledDate != null) return 'Upcoming';
    if (!gradingAvailable) return 'Unavailable';
    return hasDraft ? 'Draft' : 'Ready to evaluate';
  }

  bool get hasVerdict => verdict != null && verdict!.isNotEmpty;
  bool get isApproved => verdict == 'approved';
  bool get isApprovedWithRevisions => verdict == 'approved_with_revisions';
  bool get isForRedefense => verdict == 'for_redefense';

  bool get hasValidScope => scope == 'capstone' || scope == 'pit';
  String get scopeLabel {
    if (scope == 'capstone') return 'Capstone';
    if (scope == 'pit') return 'PIT';
    return 'Scope missing';
  }

  String get targetType => panelRubric?['target_type']?.toString() ?? 'team';
  bool get isIndividualTarget => targetType == 'individual';

  /// Counts valid answers for the configured target, including deliberate zero.
  /// Team criteria are counted once; individual criteria once per member.
  EvaluationProgress progressFor(String? studentId) {
    final definitions = (panelRubric?['criteria'] as List? ?? [])
        .whereType<Map>()
        .where((criterion) {
          final target = targetType == 'both'
              ? criterion['target_type']?.toString() ?? 'team'
              : targetType;
          return target == (studentId == null ? 'team' : 'individual');
        })
        .toList();
    final answers = isPosted ? submittedSubmissions : draftSubmissions;
    final scores = <String, num>{};
    for (final submission in answers) {
      if (submission['student_id']?.toString() != studentId) continue;
      for (final item
          in (submission['criteria_scores'] as List? ?? []).whereType<Map>()) {
        final score = item['score'];
        if (score is num) scores[item['criterion_id'].toString()] = score;
      }
    }
    final entered = definitions.where((criterion) {
      final score = scores[criterion['id'].toString()];
      final maximum = criterion['max_score'] as num? ?? 10;
      return score != null && score.isFinite && score >= 0 && score <= maximum;
    }).length;
    return EvaluationProgress(entered, definitions.length);
  }

  EvaluationProgress get evaluationProgress {
    final team = progressFor(null);
    final individuals = targetType == 'team'
        ? <EvaluationProgress>[]
        : memberDetails.map((member) => progressFor(member.id));
    return EvaluationProgress(
      team.entered +
          individuals.fold(0, (sum, progress) => sum + progress.entered),
      team.required +
          individuals.fold(0, (sum, progress) => sum + progress.required),
    );
  }

  String get displayStage {
    if (stageName.isNotEmpty && stageName != 'No stage') return stageName;
    if (defenseDate.contains(' - ')) {
      final part = defenseDate.split(' - ').first.trim();
      if (part.isNotEmpty && part != 'No stage') return part;
    }
    return isCapstone ? 'Capstone Defense' : 'PIT Presentation';
  }

  String get displaySupervisorLabel => isCapstone ? 'Adviser' : 'Instructor';

  String get displayInstructor => instructorName.isNotEmpty
      ? instructorName
      : (adviserName.isNotEmpty ? adviserName : 'No instructor assigned');

  String get displaySupervisor =>
      isCapstone ? displayAdviser : displayInstructor;

  String get displayAdviser =>
      adviserName.isNotEmpty ? adviserName : 'No adviser assigned';

  String get displayLeader {
    if (leaderName.isNotEmpty) return leaderName;
    final leader = memberDetails.where((m) => m.isLeader).firstOrNull;
    if (leader != null) return leader.name;
    return members.isNotEmpty ? members.first : 'Leader TBD';
  }

  String get displayEvent {
    if (eventName.isNotEmpty) return eventName;
    return isCapstone ? 'Capstone Defense Session' : 'PIT Project Expo';
  }

  String get displayRoom {
    if (room.isNotEmpty) return room;
    return 'Room TBD';
  }

  String get formattedTime {
    if (startTime.isNotEmpty) {
      final parts = startTime.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final min = parts[1];
        if (hour != null) {
          final isPm = hour >= 12;
          final h12 = hour % 12 == 0 ? 12 : hour % 12;
          return '$h12:$min ${isPm ? 'PM' : 'AM'}';
        }
      }
      return startTime;
    }
    if (defenseDate.isNotEmpty) {
      final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(defenseDate);
      if (match != null) {
        final timeStr = match.group(1)!;
        final parts = timeStr.split(':');
        final hour = int.tryParse(parts[0]);
        if (hour != null) {
          final isPm = hour >= 12;
          final h12 = hour % 12 == 0 ? 12 : hour % 12;
          return '$h12:${parts[1]} ${isPm ? 'PM' : 'AM'}';
        }
        return timeStr;
      }
    }
    return '--:--';
  }
}

class Criterion {
  final int? id;
  final String name;
  final double maxScore;
  final String description;
  double? score;
  Criterion(
    this.name,
    this.maxScore, {
    this.id,
    this.score,
    this.description = '',
  });
  bool get isScored =>
      score != null && score!.isFinite && score! >= 0 && score! <= maxScore;
}

class EvaluationProgress {
  const EvaluationProgress(this.entered, this.required);
  final int entered, required;
  bool get complete => required > 0 && entered == required;
  String get label => '$entered/$required scored';
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
