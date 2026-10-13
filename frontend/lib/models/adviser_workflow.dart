import 'team_defense_record.dart';

enum AdviserWorkflowTone { success, waiting, neutral }

/// Presentation of the backend's availability decision, never a new grading gate.
class AdviserGradingStatus {
  const AdviserGradingStatus(
    this.badge,
    this.title,
    this.detail,
    this.tone, {
    this.canGrade = false,
    this.needsGrade = false,
  });

  final String badge, title, detail;
  final AdviserWorkflowTone tone;
  final bool canGrade, needsGrade;

  factory AdviserGradingStatus.fromGrade(
    Map<String, dynamic>? grade, {
    bool enabled = true,
    bool loading = false,
    String? error,
    bool officiallyComplete = false,
  }) {
    if (grade?['status'] == 'published' ||
        grade?['is_officially_complete'] == true ||
        officiallyComplete) {
      return const AdviserGradingStatus(
        'Locked',
        'Grades finalized — read only',
        'You can view the recorded scores. Adviser grades can no longer be edited.',
        AdviserWorkflowTone.neutral,
      );
    }
    if (!enabled) {
      return const AdviserGradingStatus(
        'Disabled',
        'Adviser grading is disabled',
        'The administrator has turned off adviser grading for this academic term.',
        AdviserWorkflowTone.neutral,
      );
    }
    if (loading && grade?['adviser_grading_available'] == null) {
      return const AdviserGradingStatus(
        'Checking',
        'Checking grading availability',
        'Loading the grading rules and assigned rubric for this team.',
        AdviserWorkflowTone.neutral,
      );
    }
    if (error != null) {
      return const AdviserGradingStatus(
        'Retry',
        'Unable to check grading availability',
        'Refresh the workspace to check whether this team can be graded.',
        AdviserWorkflowTone.waiting,
      );
    }
    final reason =
        grade?['adviser_grading_unavailable_reason']?.toString().trim() ?? '';
    if (grade?['adviser_grading_available'] != true) {
      final submitted = grade?['adviser_score'] != null;
      return AdviserGradingStatus(
        submitted ? 'Submitted · locked' : 'Not open',
        submitted
            ? 'Adviser grade submitted — read only'
            : 'Grading is not open yet',
        reason.isNotEmpty
            ? reason
            : grade == null || grade.isEmpty
            ? 'The team must be endorsed and scheduled for this stage before grading opens.'
            : 'Refresh the workspace to check grading availability for this stage.',
        AdviserWorkflowTone.neutral,
      );
    }
    if (grade?['assigned_adviser_rubric_id'] == null ||
        (grade?['assigned_adviser_criteria'] as List? ?? []).isEmpty) {
      return const AdviserGradingStatus(
        'Setup needed',
        'Adviser rubric needed',
        'Ask the administrator to assign an adviser rubric with scoring criteria for this stage.',
        AdviserWorkflowTone.waiting,
      );
    }
    if (grade?['adviser_score'] != null) {
      return const AdviserGradingStatus(
        'Submitted',
        'Adviser grade submitted — editable',
        'Your grade is saved. You can update it before grades are finalized.',
        AdviserWorkflowTone.success,
        canGrade: true,
      );
    }
    return const AdviserGradingStatus(
      'Ready to grade',
      'You can grade this team now',
      'Grade before or after the defense. You do not need to wait for panel or peer scores. Choose any eligible team in any order.',
      AdviserWorkflowTone.success,
      canGrade: true,
      needsGrade: true,
    );
  }
}

Map<String, dynamic>? adviserGradeForTeam(
  Map<String, dynamic> team,
  String stage,
  List<Map<String, dynamic>> grades,
) {
  bool matches(Map grade) =>
      defenseRecordId(grade['team_id']) == defenseRecordId(team['id']) &&
      grade['stage_label']?.toString().trim().toLowerCase() ==
          stage.trim().toLowerCase() &&
      (team['project_version'] == null ||
          grade['project_version'] == null ||
          defenseRecordId(team['project_version']) ==
              defenseRecordId(grade['project_version'])) &&
      (team['semester_id'] == null ||
          grade['semester_id'] == null ||
          defenseRecordId(team['semester_id']) ==
              defenseRecordId(grade['semester_id']));
  for (final grade in grades) {
    if (matches(grade)) return grade;
  }
  for (final raw in [
    team['grade'],
    ...(team['stages'] as List? ?? [])
        .whereType<Map>()
        .where((s) => s['stage_label'] == stage)
        .map((s) => s['grade']),
  ]) {
    if (raw is Map && raw['stage_label'] == stage) {
      final candidate = <String, dynamic>{
        'team_id': team['id'],
        ...Map<String, dynamic>.from(raw),
      };
      if (matches(candidate)) return candidate;
    }
  }
  return null;
}

class AdviserMinutesStatus {
  const AdviserMinutesStatus(
    this.badge,
    this.title,
    this.detail,
    this.tone, {
    this.needsSignature = false,
  });
  final String badge, title, detail;
  final AdviserWorkflowTone tone;
  final bool needsSignature;

  factory AdviserMinutesStatus.fromSchedule(Map<String, dynamic> schedule) {
    if (schedule['status'] == 'cancelled') {
      return const AdviserMinutesStatus(
        'Cancelled',
        'Defense cancelled',
        'This record is kept for reference. There are no minutes to sign for this cancelled defense.',
        AdviserWorkflowTone.neutral,
      );
    }
    if (schedule['minutes_required'] == false) {
      return const AdviserMinutesStatus(
        'Not required',
        'Minutes are not required',
        'There is no adviser signature required for this defense.',
        AdviserWorkflowTone.neutral,
      );
    }
    switch (schedule['minutes_status']) {
      case 'submitted':
        return AdviserMinutesStatus(
          'Sign minutes',
          'Minutes ready for your signature',
          'The documenter has submitted the minutes. Review the record, then sign as project adviser.',
          AdviserWorkflowTone.success,
          needsSignature: defenseRecordId(schedule['id']) != null,
        );
      case 'adviser_signed':
        return const AdviserMinutesStatus(
          'Signed',
          'Your adviser signature is recorded',
          'Waiting for the chair to add the final signature. You can view your signed minutes below.',
          AdviserWorkflowTone.success,
        );
      case 'completed':
        return const AdviserMinutesStatus(
          'Finalized',
          'Minutes finalized',
          'All required signatures are complete. The final minutes are available below.',
          AdviserWorkflowTone.success,
        );
      case 'draft':
        return const AdviserMinutesStatus(
          'Minutes draft',
          'Waiting for the documenter',
          'The minutes are still a draft. You can sign once the documenter submits them.',
          AdviserWorkflowTone.waiting,
        );
      default:
        return const AdviserMinutesStatus(
          'Minutes pending',
          'Minutes are not ready yet',
          'The documenter will prepare and submit the minutes after the defense. Your signature reminder will appear here.',
          AdviserWorkflowTone.neutral,
        );
    }
  }
}

List<Map<String, dynamic>> adviserMinutesToSign(
  Map<String, dynamic> team,
  String stage,
  List<Map<String, dynamic>> schedules,
) => schedules
    .where(
      (s) =>
          s['scope'] == 'capstone' &&
          defenseRecordId(s['team_id']) == defenseRecordId(team['id']) &&
          s['stage_label']?.toString().trim().toLowerCase() ==
              stage.trim().toLowerCase() &&
          (team['project_version'] == null ||
              defenseRecordId(s['project_version']) ==
                  defenseRecordId(team['project_version'])) &&
          (team['semester_id'] == null ||
              defenseRecordId(s['semester_id']) ==
                  defenseRecordId(team['semester_id'])) &&
          AdviserMinutesStatus.fromSchedule(s).needsSignature,
    )
    .toList();
