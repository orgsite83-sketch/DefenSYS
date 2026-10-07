import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';
import 'package:defensys/utils/scheduler/defense_scheduler_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefenseSchedulerDraft', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('draft json round-trip preserves all fields', () {
      final now = DateTime.now();
      final draft = DefenseSchedulerDraft(
        scope: 'capstone',
        savedAt: now,
        semesterId: 12,
        stageId: 3,
        eventName: 'Proposal Defense',
        rubricId: 10,
        adviserRubricId: 11,
        capstonePeerRubricId: 12,
        peerRubricId: 13,
        panelWeight: '75',
        peerWeight: '25',
        pitTemplate: 'template.docx',
        documenterId: 103,
        selectedPanelistIds: [101, 102],
        selectedChairId: 101,
        externalIds: [201],
        sessions: [
          {
            'key': 'session-1',
            'date': '2026-10-07',
            'start': '08:00',
            'end': '17:00',
            'duration': '60',
            'room': 'Room 301',
            'team_ids': [1, 2, 3, 4],
          }
        ],
        planSlots: [
          {
            'team_id': 1,
            'session_key': 'session-1',
            'start_time': '08:00',
            'room': 'Room 301',
          }
        ],
        showFinalPreview: true,
      );

      final json = draft.toJson();
      final reconstructed = DefenseSchedulerDraft.fromJson(json);

      expect(reconstructed.scope, 'capstone');
      expect(reconstructed.semesterId, 12);
      expect(reconstructed.stageId, 3);
      expect(reconstructed.eventName, 'Proposal Defense');
      expect(reconstructed.rubricId, 10);
      expect(reconstructed.panelWeight, '75');
      expect(reconstructed.documenterId, 103);
      expect(reconstructed.selectedPanelistIds, [101, 102]);
      expect(reconstructed.selectedChairId, 101);
      expect(reconstructed.externalIds, [201]);
      expect(reconstructed.sessions.length, 1);
      expect(reconstructed.sessions.first['room'], 'Room 301');
      expect(reconstructed.planSlots.length, 1);
      expect(reconstructed.showFinalPreview, isTrue);
      expect(reconstructed.hasContent, isTrue);
    });

    test('hasContent returns false for empty draft', () {
      final draft = DefenseSchedulerDraft(
        scope: 'capstone',
        savedAt: DateTime.now(),
        sessions: [],
        planSlots: [],
      );
      expect(draft.hasContent, isFalse);
    });

    test('session draft serialization and deserialization roundtrip', () {
      final dateCtrl = TextEditingController(text: '2026-10-08');
      final startCtrl = TextEditingController(text: '09:00');
      final durationCtrl = TextEditingController(text: '45');
      final roomCtrl = TextEditingController(text: 'Lab 2');

      final session = ScheduleSessionDraft(
        key: 'session-2',
        date: dateCtrl,
        start: startCtrl,
        duration: durationCtrl,
        room: roomCtrl,
        end: '16:00',
      );
      session.teamIds = {5, 6};
      session.customStaff = true;
      session.panelists = {101};
      session.chair = 101;
      session.externals = {201};
      session.documenter = 103;

      final map = serializeSessionDraft(session);
      expect(map['key'], 'session-2');
      expect(map['room'], 'Lab 2');
      expect(map['team_ids'], [5, 6]);
      expect(map['custom_staff'], isTrue);
      expect(map['chair'], 101);

      final deserialized = deserializeSessionDraft(map, ownsFields: true);
      expect(deserialized.key, 'session-2');
      expect(deserialized.room.text, 'Lab 2');
      expect(deserialized.teamIds, {5, 6});
      expect(deserialized.customStaff, isTrue);
      expect(deserialized.chair, 101);
      expect(deserialized.documenter, 103);
      expect(deserialized.blocks.length, session.blocks.length);

      session.dispose();
      deserialized.dispose();
    });

    test('shared room and date controllers are populated when ownsFields is false', () {
      final sharedRoom = TextEditingController(text: '');
      final sharedDate = TextEditingController(text: '');
      final map = {
        'key': 'session-1',
        'date': '2026-10-07',
        'start': '08:00',
        'end': '17:00',
        'duration': '60',
        'room': 'Room 301',
        'team_ids': [1, 2],
      };

      final deserialized = deserializeSessionDraft(
        map,
        sharedRoom: sharedRoom,
        sharedDate: sharedDate,
        ownsFields: false,
      );

      expect(sharedRoom.text, 'Room 301');
      expect(sharedDate.text, '2026-10-07');
      expect(deserialized.room.text, 'Room 301');
      expect(deserialized.date.text, '2026-10-07');

      deserialized.dispose();
      sharedRoom.dispose();
      sharedDate.dispose();
    });

    test('save, load, and clear defense scheduler draft', () async {
      final draft = DefenseSchedulerDraft(
        scope: 'capstone',
        savedAt: DateTime.now(),
        semesterId: 5,
        stageId: 2,
        sessions: [
          {
            'key': 'session-1',
            'room': 'Room 101',
            'team_ids': [10, 11],
          }
        ],
      );

      await saveDefenseSchedulerDraft(draft);

      final loaded = await loadDefenseSchedulerDraft(scope: 'capstone', semesterId: 5);
      expect(loaded, isNotNull);
      expect(loaded!.stageId, 2);
      expect(loaded.sessions.first['room'], 'Room 101');

      // Loading with different semester returns null
      final wrongTerm = await loadDefenseSchedulerDraft(scope: 'capstone', semesterId: 99);
      expect(wrongTerm, isNull);

      // Clearing draft
      await clearDefenseSchedulerDraft(scope: 'capstone', semesterId: 5);
      final cleared = await loadDefenseSchedulerDraft(scope: 'capstone', semesterId: 5);
      expect(cleared, isNull);
    });
  });
}
