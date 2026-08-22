import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/utils/csv_file_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StudentBatchDraftProvider Tests', () {
    test('initial state has empty draft and hasFreshDraft/hasRolloverDraft are false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(studentBatchDraftProvider);
      expect(state.hasFreshDraft, isFalse);
      expect(state.hasRolloverDraft, isFalse);
      expect(state.freshStagedFiles, isEmpty);
      expect(state.freshParsedStudents, isEmpty);
    });

    test('saves and clears fresh draft in memory and preferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final testFile = PickedTabularFile(
        name: 'BSIT-4A.csv',
        extension: 'csv',
        bytes: utf8.encode('id_number,name\n2021-0001,Dela Cruz'),
        text: 'id_number,name\n2021-0001,Dela Cruz',
      );

      final testStudents = [
        {
          'id_number': '2021-0001',
          'name': 'Dela Cruz, Juan',
          'section': 'BSIT-4A',
          'year_level': '4th Year',
        }
      ];

      container.read(studentBatchDraftProvider.notifier).saveFreshDraft(
            stagedFiles: [testFile],
            parsedStudents: testStudents,
            sectionFilter: 'BSIT-4A',
          );

      var state = container.read(studentBatchDraftProvider);
      expect(state.hasFreshDraft, isTrue);
      expect(state.freshStagedFiles.length, 1);
      expect(state.freshStagedFiles.first.name, 'BSIT-4A.csv');
      expect(state.freshParsedStudents.length, 1);
      expect(state.freshSectionFilter, 'BSIT-4A');

      // Clear fresh draft
      container.read(studentBatchDraftProvider.notifier).clearFreshDraft();
      state = container.read(studentBatchDraftProvider);
      expect(state.hasFreshDraft, isFalse);
      expect(state.freshStagedFiles, isEmpty);
      expect(state.freshParsedStudents, isEmpty);
    });

    test('saves and clears rollover draft in memory and preferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final testFile = PickedTabularFile(
        name: 'BSIT-3A.csv',
        extension: 'csv',
        bytes: utf8.encode('id_number,name\n2022-0001,Santos'),
        text: 'id_number,name\n2022-0001,Santos',
      );

      final actions = {'2022-0001': 'promote', '2022-0002': 'retain'};

      container.read(studentBatchDraftProvider.notifier).saveRolloverDraft(
            stagedFiles: [testFile],
            actions: actions,
            sectionFilter: 'BSIT-3A',
            yearFilter: '3rd Year',
            hasRolloverCsv: true,
          );

      var state = container.read(studentBatchDraftProvider);
      expect(state.hasRolloverDraft, isTrue);
      expect(state.rolloverStagedFiles.length, 1);
      expect(state.rolloverActions['2022-0001'], 'promote');
      expect(state.rolloverActions['2022-0002'], 'retain');
      expect(state.hasRolloverCsv, isTrue);

      // Clear rollover draft
      container.read(studentBatchDraftProvider.notifier).clearRolloverDraft();
      state = container.read(studentBatchDraftProvider);
      expect(state.hasRolloverDraft, isFalse);
      expect(state.rolloverStagedFiles, isEmpty);
      expect(state.rolloverActions, isEmpty);
      expect(state.hasRolloverCsv, isFalse);
    });
  });
}
