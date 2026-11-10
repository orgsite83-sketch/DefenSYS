import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';

void main() {
  group('StudentTaskBadgeHelper', () {
    test(
      'Team dot follows editable leader tasks and clears when titles are complete',
      () {
        Map<String, dynamic> data({
          bool leader = true,
          bool locked = false,
          bool complete = false,
          int teamId = 5,
        }) => {
          'student': {'id': 10, 'is_leader': leader},
          'team': {'id': 5, 'currentStage': 'Concept Proposal'},
          'stages': [
            {
              'stage_label': 'Concept Proposal',
              'team_id': teamId,
              'concept_workflow': {
                'enabled': true,
                'can_edit_titles': !locked,
                'status': locked ? 'scheduled' : 'concepts_needed',
                'concepts': [
                  {'key': 'c1', 'title': 'Imported idea'},
                  {'key': 'c2', 'title': complete ? 'Second idea' : ''},
                ],
              },
            },
          ],
        };
        expect(StudentTaskBadgeHelper.hasPendingTeamTasks(data()), isTrue);
        expect(
          StudentTaskBadgeHelper.hasPendingTeamTasks(data(leader: false)),
          isFalse,
        );
        expect(
          StudentTaskBadgeHelper.hasPendingTeamTasks(data(complete: true)),
          isFalse,
        );
        expect(
          StudentTaskBadgeHelper.hasPendingTeamTasks(data(locked: true)),
          isFalse,
        );
        expect(
          StudentTaskBadgeHelper.hasPendingTeamTasks(data(teamId: 99)),
          isFalse,
        );
        expect(
          StudentTaskBadgeHelper.hasPendingTeamTasks(
            data(complete: true),
            setup: {
              'event_teams': [
                {'needs_details': true},
              ],
            },
          ),
          isTrue,
        );
      },
    );
    test(
      'Integration dot owns actionable manager tasks and excludes waiting states',
      () {
        for (final status in [
          'papers_missing',
          'corrections_requested',
          'shared_revisions_pending',
          'final_paper_pending',
          'awaiting_faculty_review',
          'awaiting_name_confirmation',
          'section_defense_pending',
          'cleared',
        ]) {
          final setup = {
            'section_tasks': [
              {'role': 'project_manager', 'status': status},
            ],
          };
          expect(
            StudentTaskBadgeHelper.hasPendingTeamTasks(null, setup: setup),
            isFalse,
          );
          expect(
            StudentTaskBadgeHelper.pendingIntegrationTasks(setup).isNotEmpty,
            [
              'papers_missing',
              'corrections_requested',
              'shared_revisions_pending',
              'final_paper_pending',
            ].contains(status),
          );
        }
      },
    );
    test(
      'Integration uses server action capability and assigned manager role',
      () {
        for (final task in [
          {
            'role': 'project_manager',
            'status': 'awaiting_name_confirmation',
            'needs_title': true,
            'requires_action': true,
          },
          {
            'role': 'project_manager',
            'status': 'final_paper_pending',
            'requires_action': false,
          },
          {
            'role': 'reviewer',
            'status': 'papers_missing',
            'requires_action': true,
          },
        ]) {
          expect(
            StudentTaskBadgeHelper.pendingIntegrationTasks({
              'section_tasks': [task],
            }).isNotEmpty,
            task['role'] == 'project_manager' &&
                task['requires_action'] == true,
          );
        }
      },
    );
    test(
      'isDeliverablePending returns true when required and not uploaded',
      () {
        final item = {
          'id': 'concept_paper',
          'required': true,
          'uploaded': false,
          'submission': null,
        };
        expect(StudentTaskBadgeHelper.isDeliverablePending(item), isTrue);
      },
    );

    test(
      'isDeliverablePending returns false when optional and not uploaded',
      () {
        final item = {
          'id': 'extra_doc',
          'required': false,
          'uploaded': false,
          'submission': null,
        };
        expect(StudentTaskBadgeHelper.isDeliverablePending(item), isFalse);
      },
    );

    test(
      'isDeliverablePending returns false when required and uploaded successfully',
      () {
        final item = {
          'id': 'concept_paper',
          'required': true,
          'uploaded': true,
          'submission': {'file_name': 'paper.pdf', 'status': 'accepted'},
        };
        expect(StudentTaskBadgeHelper.isDeliverablePending(item), isFalse);
      },
    );

    test(
      'isDeliverablePending returns true when uploaded but marked Needs Revision or rejected',
      () {
        final itemNeedsRevision = {
          'id': 'concept_paper',
          'required': true,
          'uploaded': true,
          'submission': {'file_name': 'paper.pdf', 'status': 'Needs Revision'},
        };
        expect(
          StudentTaskBadgeHelper.isDeliverablePending(itemNeedsRevision),
          isTrue,
        );

        final itemRejected = {
          'id': 'concept_paper',
          'required': true,
          'uploaded': true,
          'submission': {'file_name': 'paper.pdf', 'status': 'rejected'},
        };
        expect(
          StudentTaskBadgeHelper.isDeliverablePending(itemRejected),
          isTrue,
        );
      },
    );

    test('hasPendingPreDeliverables identifies pending pre-defense items', () {
      final stageWithPending = {
        'deliverables': [
          {'type': 'pre', 'required': true, 'uploaded': false},
          {'type': 'pre', 'required': false, 'uploaded': false},
        ],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingPreDeliverables(stageWithPending),
        isTrue,
      );

      final stageComplete = {
        'deliverables': [
          {
            'type': 'pre',
            'required': true,
            'uploaded': true,
            'submission': {'status': 'accepted'},
          },
        ],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingPreDeliverables(stageComplete),
        isFalse,
      );
    });

    test(
      'hasPendingPostDeliverables suppresses dot when locked even if missing items exist',
      () {
        final lockedStageWithMissingItems = {
          'vault_unlocked': false,
          'archive_unlocked': false,
          'deliverables': [
            {'type': 'post', 'required': true, 'uploaded': false},
          ],
        };
        expect(
          StudentTaskBadgeHelper.hasPendingPostDeliverables(
            lockedStageWithMissingItems,
          ),
          isFalse,
        );
      },
    );

    test(
      'hasPendingPostDeliverables shows dot when unlocked and required items are missing',
      () {
        final unlockedStageWithMissingItems = {
          'vault_unlocked': true,
          'deliverables': [
            {'type': 'post', 'required': true, 'uploaded': false},
          ],
        };
        expect(
          StudentTaskBadgeHelper.hasPendingPostDeliverables(
            unlockedStageWithMissingItems,
          ),
          isTrue,
        );

        final unlockedStageComplete = {
          'vault_unlocked': true,
          'deliverables': [
            {
              'type': 'post',
              'required': true,
              'uploaded': true,
              'submission': {'status': 'accepted'},
            },
          ],
        };
        expect(
          StudentTaskBadgeHelper.hasPendingPostDeliverables(
            unlockedStageComplete,
          ),
          isFalse,
        );
      },
    );

    test('hasPendingPeerEval detects incomplete peer evaluations', () {
      final studentDataDisabled = {
        'peerEvalEnabled': false,
        'student': {'id': '1'},
        'members': [
          {'id': '1'},
          {'id': '2'},
        ],
        'myPeerSubmissions': [],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingPeerEval(studentDataDisabled),
        isFalse,
      );

      final studentDataPending = {
        'peerEvalEnabled': true,
        'student': {'id': '1'},
        'members': [
          {'id': '1'},
          {'id': '2'},
          {'id': '3'},
        ],
        'myPeerSubmissions': [
          {'evaluateeId': '2'},
        ],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingPeerEval(studentDataPending),
        isTrue,
      );

      final studentDataComplete = {
        'peerEvalEnabled': true,
        'student': {'id': '1'},
        'members': [
          {'id': '1'},
          {'id': '2'},
          {'id': '3'},
        ],
        'myPeerSubmissions': [
          {'evaluateeId': '1'},
          {'evaluateeId': '2'},
          {'evaluateeId': '3'},
        ],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingPeerEval(studentDataComplete),
        isFalse,
      );
    });

    group('event-scoped peer indicators', () {
      const members = [
        {'id': 1, 'name': 'Alex'},
        {'id': 2, 'name': 'Sam'},
      ];
      const completeSubmissions = [
        {'evaluateeId': 1},
        {'evaluateeId': 2},
      ];

      Map<String, dynamic> dashboard({
        bool enabled = false,
        List<Map<String, dynamic>> submissions = const [],
        List<Map<String, dynamic>> stages = const [],
      }) => {
        'team': {'id': 7, 'currentStage': 'Current event'},
        'members': members,
        'peerEvalEnabled': enabled,
        'myPeerSubmissions': submissions,
        'stages': stages,
      };

      test(
        'red starts with zero submissions and clears only after self and peer',
        () {
          for (final submissions in [
            <Map<String, dynamic>>[],
            <Map<String, dynamic>>[
              {'evaluateeId': 2},
            ],
            completeSubmissions,
          ]) {
            final data = dashboard(
              stages: [
                {
                  'stage_label': 'Current event',
                  'peer_eval_allowed': true,
                  'my_peer_submissions': submissions,
                },
              ],
            );
            expect(
              StudentTaskBadgeHelper.hasPendingPeerEval(data),
              submissions.length < members.length,
            );
            expect(
              StudentTaskBadgeHelper.hasPendingEvents(studentData: data),
              submissions.length < members.length,
            );
          }
        },
      );

      test('completed history cannot satisfy an empty current event', () {
        expect(
          StudentTaskBadgeHelper.hasPendingPeerEval(
            dashboard(
              enabled: true,
              submissions: completeSubmissions,
              stages: [
                {
                  'stage_label': 'Earlier event',
                  'peer_eval_allowed': false,
                  'my_peer_submissions': completeSubmissions,
                },
                {
                  'stage_label': 'Current event',
                  'peer_eval_allowed': true,
                  'my_peer_submissions': <Map<String, dynamic>>[],
                },
              ],
            ),
          ),
          isTrue,
        );
      });

      test('closed event overrides stale top-level availability', () {
        expect(
          StudentTaskBadgeHelper.hasPendingPeerEval(
            dashboard(
              enabled: true,
              stages: [
                {
                  'stage_label': 'Current event',
                  'peer_eval_allowed': false,
                  'my_peer_submissions': <Map<String, dynamic>>[],
                },
              ],
            ),
          ),
          isFalse,
        );
      });

      test('legacy submissions from another stage do not clear the dot', () {
        expect(
          StudentTaskBadgeHelper.hasPendingPeerEval(
            dashboard(
              enabled: true,
              submissions: [
                for (final sub in completeSubmissions)
                  {...sub, 'stage': 'Earlier event'},
              ],
            ),
          ),
          isTrue,
        );
      });

      test(
        'event dot follows the selected event while navigation includes all',
        () {
          final data = dashboard(
            stages: [
              {
                'stage_label': 'Earlier event',
                'team_id': 8,
                'team': {'id': 8, 'members': members},
                'peer_eval_allowed': true,
                'my_peer_submissions': <Map<String, dynamic>>[],
              },
              {'stage_label': 'Current event', 'peer_eval_allowed': false},
            ],
          );
          expect(StudentTaskBadgeHelper.hasPendingPeerEval(data), isTrue);
          expect(
            StudentTaskBadgeHelper.hasPendingPeerEval(
              data,
              stageLabel: 'Current event',
              teamId: '7',
            ),
            isFalse,
          );
          expect(
            StudentTaskBadgeHelper.hasPendingPeerEval(
              data,
              stageLabel: 'Earlier event',
              teamId: '8',
            ),
            isTrue,
          );
        },
      );

      test('teams in the same event retain independent completion', () {
        final data = dashboard(
          stages: [
            for (final id in [8, 9])
              {
                'stage_label': 'Earlier event',
                'team_id': id,
                'team': {'id': id, 'members': members},
                'peer_eval_allowed': true,
                'my_peer_submissions': id == 8
                    ? completeSubmissions
                    : <Map<String, dynamic>>[],
              },
          ],
        );
        for (final id in [8, 9]) {
          expect(
            StudentTaskBadgeHelper.hasPendingPeerEval(
              data,
              stageLabel: 'Earlier event',
              teamId: '$id',
            ),
            id == 9,
          );
        }
      });
    });

    test('hasPendingEvents aggregates deliverables and peer eval', () {
      final completeStage = {
        'deliverables': [
          {
            'type': 'pre',
            'required': true,
            'uploaded': true,
            'submission': {'status': 'accepted'},
          },
        ],
      };
      final completeStudent = {'peerEvalEnabled': false};
      expect(
        StudentTaskBadgeHelper.hasPendingEvents(
          selectedStage: completeStage,
          studentData: completeStudent,
        ),
        isFalse,
      );

      final pendingStudent = {
        'peerEvalEnabled': true,
        'student': {'id': '1'},
        'members': [
          {'id': '1'},
          {'id': '2'},
        ],
        'myPeerSubmissions': [],
      };
      expect(
        StudentTaskBadgeHelper.hasPendingEvents(
          selectedStage: completeStage,
          studentData: pendingStudent,
        ),
        isTrue,
      );
    });
  });
}
