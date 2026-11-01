import '../../../../../services/defense/template_configuration.dart';
import 'stage_outcome_settings.dart';
import 'stage_weekly_settings.dart';

/// Checks the current form, including unsaved edits, before publishing.
class StageSetupValidation {
  StageSetupValidation({
    required String name,
    required int? semesterId,
    required Map<String, dynamic>? semester,
    required String qualifyingScore,
    required Map<String, int> weights,
    required bool conceptSelection,
    required Map<String, int?> rubricIds,
    required List<Map<String, dynamic>> rubrics,
    required List<Map<String, dynamic>> deliverables,
    required Map<String, dynamic> weekly,
    required Map<String, dynamic> weeklyTemplate,
    required bool minutesRequired,
    required String minutesNumber,
    int? stageId,
  }) {
    if (name.trim().isEmpty) issues[0].add('Enter a stage name.');
    final weeklyError = weeklySettingsError(weekly, weeklyTemplate);
    if (weeklyError != null) issues[0].add(weeklyError);
    if (minutesRequired && minutesNumber.trim().isEmpty) {
      issues[0].add('Enter the signed-minutes deliverable number.');
    }
    if (semesterId == null) {
      issues[1].add('Activate a semester to configure grading.');
    }
    if (StageOutcomeSettings.validateScore(qualifyingScore) != null) {
      issues[1].add('Set a qualifying panel score from 0 to 100%.');
    }
    if (weights.values.any((weight) => weight < 0 || weight > 100) ||
        weights.values.fold(0, (sum, weight) => sum + weight) != 100) {
      issues[1].add('Grade weights must total 100%.');
    }
    final roles = [
      'panel',
      if (!conceptSelection &&
          semester?['capstone_adviser_grading_enabled'] != false &&
          (weights['adviser_weight'] ?? 0) > 0)
        'adviser',
      if (!conceptSelection &&
          semester?['capstone_peer_evaluation_enabled'] != false &&
          (weights['peer_weight'] ?? 0) > 0)
        'peer',
    ];
    for (final role in roles) {
      final id = rubricIds[role];
      final rubric = rubrics
          .where((rubric) => '${rubric['id']}' == '$id')
          .firstOrNull;
      final assignedStage = rubric?['defense_stage_id'];
      if (id == null ||
          rubric == null ||
          rubric['status'] != 'published' ||
          rubric['scope'] != 'capstone' ||
          rubric['evaluation_type'] != role ||
          '${rubric['semester_id']}' != '$semesterId' ||
          (assignedStage != null && '$assignedStage' != '$stageId') ||
          (rubric['is_locked'] == true &&
              (stageId == null || '$assignedStage' != '$stageId'))) {
        issues[1].add('Attach an available published $role evaluation rubric.');
      }
    }
    if (deliverables.isEmpty && weekly['enabled'] != true) {
      issues[2].add('Add student file submission requirements.');
    }
    for (final item in deliverables) {
      final label = '${item['label'] ?? ''}'.trim();
      if (label.isEmpty) issues[2].add('Enter a name for each deliverable.');
      final templateError = templateSelectionError(item);
      if (templateError != null) issues[2].add(templateError);
      if (item['deliverable_type'] == 'post' &&
          RegExp(
                r'\{[a-zA-Z0-9_]+\}',
              ).allMatches('${item['archive_file_template'] ?? ''}').length >
              3) {
        issues[2].add(
          'Use at most 3 archive file-name variables for "$label".',
        );
      }
      if (minutesRequired &&
          '${item['deliverable_id']}'.trim() == minutesNumber.trim()) {
        issues[2].add(
          'Use a separate number for signed minutes and student deliverables.',
        );
      }
    }
  }

  final List<List<String>> issues = [[], [], []];
  bool get ready => issues.every((section) => section.isEmpty);
  int get firstIncompleteTab =>
      issues.indexWhere((section) => section.isNotEmpty);
}
