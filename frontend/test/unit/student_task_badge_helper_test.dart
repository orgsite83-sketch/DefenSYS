import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';

void main() {
  group('StudentTaskBadgeHelper', () {
    test('isDeliverablePending returns true when required and not uploaded', () {
      final item = {
        'id': 'concept_paper',
        'required': true,
        'uploaded': false,
        'submission': null,
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(item), isTrue);
    });

    test('isDeliverablePending returns false when optional and not uploaded', () {
      final item = {
        'id': 'extra_doc',
        'required': false,
        'uploaded': false,
        'submission': null,
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(item), isFalse);
    });

    test('isDeliverablePending returns false when required and uploaded successfully', () {
      final item = {
        'id': 'concept_paper',
        'required': true,
        'uploaded': true,
        'submission': {
          'file_name': 'paper.pdf',
          'status': 'accepted',
        },
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(item), isFalse);
    });

    test('isDeliverablePending returns true when uploaded but marked Needs Revision or rejected', () {
      final itemNeedsRevision = {
        'id': 'concept_paper',
        'required': true,
        'uploaded': true,
        'submission': {
          'file_name': 'paper.pdf',
          'status': 'Needs Revision',
        },
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(itemNeedsRevision), isTrue);

      final itemRejected = {
        'id': 'concept_paper',
        'required': true,
        'uploaded': true,
        'submission': {
          'file_name': 'paper.pdf',
          'status': 'rejected',
        },
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(itemRejected), isTrue);
    });

    test('hasPendingPreDeliverables identifies pending pre-defense items', () {
      final stageWithPending = {
        'deliverables': [
          {'type': 'pre', 'required': true, 'uploaded': false},
          {'type': 'pre', 'required': false, 'uploaded': false},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPreDeliverables(stageWithPending), isTrue);

      final stageComplete = {
        'deliverables': [
          {'type': 'pre', 'required': true, 'uploaded': true, 'submission': {'status': 'accepted'}},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPreDeliverables(stageComplete), isFalse);
    });

    test('hasPendingPostDeliverables suppresses dot when locked even if missing items exist', () {
      final lockedStageWithMissingItems = {
        'vault_unlocked': false,
        'archive_unlocked': false,
        'deliverables': [
          {'type': 'post', 'required': true, 'uploaded': false},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPostDeliverables(lockedStageWithMissingItems), isFalse);
    });

    test('hasPendingPostDeliverables shows dot when unlocked and required items are missing', () {
      final unlockedStageWithMissingItems = {
        'vault_unlocked': true,
        'deliverables': [
          {'type': 'post', 'required': true, 'uploaded': false},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPostDeliverables(unlockedStageWithMissingItems), isTrue);

      final unlockedStageComplete = {
        'vault_unlocked': true,
        'deliverables': [
          {'type': 'post', 'required': true, 'uploaded': true, 'submission': {'status': 'accepted'}},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPostDeliverables(unlockedStageComplete), isFalse);
    });

    test('hasPendingPeerEval detects incomplete peer evaluations', () {
      final studentDataDisabled = {
        'peerEvalEnabled': false,
        'student': {'id': '1'},
        'members': [{'id': '1'}, {'id': '2'}],
        'myPeerSubmissions': [],
      };
      expect(StudentTaskBadgeHelper.hasPendingPeerEval(studentDataDisabled), isFalse);

      final studentDataPending = {
        'peerEvalEnabled': true,
        'student': {'id': '1'},
        'members': [{'id': '1'}, {'id': '2'}, {'id': '3'}],
        'myPeerSubmissions': [
          {'evaluateeId': '2'},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPeerEval(studentDataPending), isTrue);

      final studentDataComplete = {
        'peerEvalEnabled': true,
        'student': {'id': '1'},
        'members': [{'id': '1'}, {'id': '2'}, {'id': '3'}],
        'myPeerSubmissions': [
          {'evaluateeId': '2'},
          {'evaluateeId': '3'},
        ],
      };
      expect(StudentTaskBadgeHelper.hasPendingPeerEval(studentDataComplete), isFalse);
    });

    test('hasPendingEvents aggregates deliverables and peer eval', () {
      final completeStage = {
        'deliverables': [
          {'type': 'pre', 'required': true, 'uploaded': true, 'submission': {'status': 'accepted'}},
        ],
      };
      final completeStudent = {
        'peerEvalEnabled': false,
      };
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
        'members': [{'id': '1'}, {'id': '2'}],
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
