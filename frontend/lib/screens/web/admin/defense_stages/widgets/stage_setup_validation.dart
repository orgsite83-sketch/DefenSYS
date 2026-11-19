import '../../../../../services/defense/template_configuration.dart';
import 'stage_outcome_settings.dart';
import 'stage_weekly_settings.dart';

/// A validation result keeps its destination, including the exact unsaved row.
class StageSetupIssue {
  const StageSetupIssue(
    this.step,
    this.target,
    this.message, {
    this.deliverable,
    this.publicationOnly = false,
  });

  final int step;
  final String target, message;
  final Map<String, dynamic>? deliverable;
  final bool publicationOnly;
}

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
    bool structureLocked = false,
  }) {
    void add(
      int step,
      String target,
      String message, {
      Map<String, dynamic>? item,
      bool publicationOnly = false,
    }) {
      details.add(
        StageSetupIssue(
          step,
          target,
          message,
          deliverable: item,
          publicationOnly: publicationOnly,
        ),
      );
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
    deferredRubricRoles.addAll(roles.where((role) => rubricIds[role] == null));

    if (!structureLocked) {
      if (name.trim().isEmpty) add(0, 'name', 'Enter a stage name.');
      final weeklyError = weeklySettingsError(weekly, weeklyTemplate);
      if (weeklyError != null) {
        final scheduleValid =
            weeklySettingsError(weekly, {}, requireTemplate: false) == null;
        add(0, scheduleValid ? 'weekly-template' : 'weekly', weeklyError);
      }
      if (minutesRequired && minutesNumber.trim().isEmpty) {
        add(
          2,
          'minutes',
          'Enter the signed-minutes deliverable number.',
          publicationOnly: true,
        );
      }
      if (semesterId == null) {
        add(1, 'grading', 'Activate a semester to configure grading.');
      }
      if (StageOutcomeSettings.validateScore(qualifyingScore) != null) {
        add(1, 'score', 'Set a qualifying panel score from 0 to 100%.');
      }
      if (weights.values.any((weight) => weight < 0 || weight > 100) ||
          weights.values.fold(0, (sum, weight) => sum + weight) != 100) {
        final invalid = weights.entries
            .where((entry) => entry.value < 0 || entry.value > 100)
            .firstOrNull;
        add(
          1,
          '${invalid?.key.replaceAll('_weight', '') ?? 'panel'}-weight',
          'Grade weights must total 100%.',
        );
      }
      for (final role in roles) {
        final id = rubricIds[role];
        // "Select later" defers assignment; scheduling still requires rubrics.
        if (id == null) {
          continue;
        }
        final rubric = rubrics
            .where((rubric) => '${rubric['id']}' == '$id')
            .firstOrNull;
        final assignedStage = rubric?['defense_stage_id'];
        if (rubric == null ||
            rubric['status'] != 'published' ||
            rubric['scope'] != 'capstone' ||
            rubric['evaluation_type'] != role ||
            '${rubric['semester_id']}' != '$semesterId' ||
            (assignedStage != null && '$assignedStage' != '$stageId') ||
            (rubric['is_locked'] == true &&
                (stageId == null || '$assignedStage' != '$stageId'))) {
          add(
            1,
            '$role-rubric',
            'Attach an available published $role evaluation rubric.',
            publicationOnly: true,
          );
        }
      }
    }
    if (deliverables.isEmpty && weekly['enabled'] != true) {
      add(
        2,
        'submissions',
        'Add student file submission requirements.',
        publicationOnly: true,
      );
    }
    for (final item in deliverables) {
      if (item['is_locked'] == true || item['has_data'] == true) continue;
      final label = '${item['label'] ?? ''}'.trim();
      final target = deliverableTarget(item);
      if (label.isEmpty) {
        add(2, target, 'Enter a name for this deliverable.', item: item);
      }
      final templateError = templateSelectionError(item);
      if (templateError != null) {
        add(2, '$target-template', templateError, item: item);
      }
      if (item['deliverable_type'] == 'post' &&
          RegExp(
                r'\{[a-zA-Z0-9_]+\}',
              ).allMatches('${item['archive_file_template'] ?? ''}').length >
              3) {
        add(
          2,
          '$target-archive',
          'Use at most 3 archive file-name variables for "$label".',
          item: item,
        );
      }
      if (minutesRequired &&
          '${item['deliverable_id']}'.trim() == minutesNumber.trim()) {
        add(
          2,
          'minutes',
          'Use a separate number for signed minutes and student deliverables.',
          item: item,
          publicationOnly: true,
        );
      }
    }
  }

  final details = <StageSetupIssue>[];
  final deferredRubricRoles = <String>[];
  List<List<String>> get issues => [
    for (var step = 0; step < 3; step++)
      details
          .where((issue) => issue.step == step)
          .map((issue) => issue.message)
          .toList(),
  ];
  bool get ready => details.isEmpty;
  bool stepComplete(int step) =>
      issues[step].isEmpty && (step != 1 || deferredRubricRoles.isEmpty);
  int get firstIncompleteTab =>
      issues.indexWhere((section) => section.isNotEmpty);

  String? errorFor(String target, Set<int> revealedSteps) => details
      .where(
        (issue) => issue.target == target && revealedSteps.contains(issue.step),
      )
      .firstOrNull
      ?.message;

  /// Incomplete server drafts keep the existing relaxed publication rules.
  List<StageSetupIssue> issuesForSave({
    required bool publishing,
    required String? weeklyError,
  }) => details.where((issue) {
    if (publishing) return true;
    if (issue.target.startsWith('weekly')) return weeklyError != null;
    return !issue.publicationOnly;
  }).toList();

  static String deliverableTarget(Map<String, dynamic> item) =>
      'deliverable-${identityHashCode(item)}';
}
