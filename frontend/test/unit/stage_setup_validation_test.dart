import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_setup_validation.dart';
import 'package:flutter_test/flutter_test.dart';

const panelRubric = <String, dynamic>{
  'id': 1,
  'scope': 'capstone',
  'evaluation_type': 'panel',
  'semester_id': 3,
  'status': 'published',
};

StageSetupValidation review({
  bool concept = true,
  Map<String, dynamic> semester = const {},
  Map<String, int?> rubricIds = const {'panel': 1},
  List<Map<String, dynamic>> rubrics = const [panelRubric],
  List<Map<String, dynamic>> deliverables = const [
    {
      'label': 'Concept Paper',
      'deliverable_id': 'PAPER',
      'deliverable_type': 'pre',
    },
  ],
  Map<String, dynamic> weekly = const {'enabled': false},
}) => StageSetupValidation(
  name: 'Concept Proposal',
  semesterId: 3,
  semester: semester,
  qualifyingScore: '75',
  weights: concept
      ? {'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0}
      : {'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20},
  conceptSelection: concept,
  rubricIds: rubricIds,
  rubrics: rubrics,
  deliverables: deliverables,
  weekly: weekly,
  weeklyTemplate: {},
  minutesRequired: true,
  minutesNumber: 'MINUTES',
);

void main() {
  test('concept selection can publish with panel rubric alone', () {
    expect(review().ready, isTrue);
    final standard = review(concept: false);
    expect(standard.ready, isTrue);
  });

  test('Select later allows concept and standard setup without rubrics', () {
    for (final concept in [false, true]) {
      final result = review(concept: concept, rubricIds: {}, rubrics: []);
      expect(result.ready, isTrue);
      expect(result.issues[1], isEmpty);
    }
  });

  test('only applicable selected rubrics are validated', () {
    const rubricIds = {'panel': 1, 'adviser': 2, 'peer': 3};
    expect(review(rubricIds: rubricIds).ready, isTrue);
    final standard = review(concept: false, rubricIds: rubricIds);
    expect(standard.ready, isFalse);
    expect(standard.issues[1], hasLength(2));
    expect(
      review(
        concept: false,
        rubricIds: rubricIds,
        semester: {
          'capstone_adviser_grading_enabled': false,
          'capstone_peer_evaluation_enabled': false,
        },
      ).ready,
      isTrue,
    );
  });

  test(
    'unpublished, wrong-term, and unavailable rubrics prevent publication',
    () {
      for (final change in [
        {'status': 'draft'},
        {'scope': 'pit'},
        {'evaluation_type': 'peer'},
        {'semester_id': 4},
        {'defense_stage_id': 99},
        {'is_locked': true},
      ]) {
        final result = review(
          rubrics: [
            {...panelRubric, ...change},
          ],
        );
        expect(result.ready, isFalse);
        expect(result.firstIncompleteTab, 1);
      }
    },
  );

  test(
    'a selected rubric missing from the available list blocks publication',
    () {
      final result = review(rubrics: []);
      expect(result.ready, isFalse);
      expect(result.firstIncompleteTab, 1);
    },
  );

  test('minutes alone do not satisfy student submission setup', () {
    final result = review(deliverables: []);
    expect(result.ready, isFalse);
    expect(result.firstIncompleteTab, 2);
  });

  test(
    'a restored template selection must be attached again before publishing',
    () {
      final result = review(
        deliverables: [
          {
            'label': 'Concept Paper',
            'deliverable_id': 'PAPER',
            'deliverable_type': 'pre',
            'template_action': 'replace',
            'template_selection_name': 'Paper.docx',
            'template_selection_size': 8,
          },
        ],
      );
      expect(result.ready, isFalse);
      expect(result.issues[2].single, contains('again'));
    },
  );

  test('weekly reporting requires its template before publication', () {
    final result = review(
      deliverables: [],
      weekly: {
        'enabled': true,
        'starts_on': '2026-10-25',
        'total_weeks': 8,
        'required_start': 1,
        'required_end': 8,
        'due_weekday': 6,
        'due_time': '23:59',
      },
    );
    expect(result.ready, isFalse);
    expect(result.issues[0], contains('Attach a weekly report template.'));
    expect(result.issues[2], isEmpty);
  });
}
