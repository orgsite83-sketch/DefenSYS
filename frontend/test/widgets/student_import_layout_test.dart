import 'dart:convert';

import 'package:defensys/screens/web/admin/user_management/bulk_import/official_class_list_parser.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/capture_preview.dart';

const _semester = {
  'id': 2,
  'label': '1st Semester',
  'school_year': '2026-2027',
  'display_name': '1st Semester, A.Y. 2026-2027',
};

class _Periods extends AcademicPeriodNotifier {
  _Periods(this.active);
  final bool active;

  @override
  AcademicPeriodState build() =>
      AcademicPeriodState(activeSemester: active ? _semester : null);
}

class _Records extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() => const StudentAcademicRecordsState();

  @override
  Future<bool> fetchRolloverPreview({
    List<Map<String, dynamic>>? students,
  }) async => true;
}

class _Users extends UserManagementNotifier {
  _Users(this.blockedIds, this.statusCodes);
  final Set<String> blockedIds;
  final Map<String, String> statusCodes;

  @override
  UserManagementState build() => const UserManagementState();

  @override
  Future<List<Map<String, dynamic>>> previewEnrollmentSections(
    List<Map<String, dynamic>> students,
    int semesterId,
  ) async => [
    for (final row in students)
      {
        'id_number': row['id_number'],
        'section': row['section'] ?? '',
        'source': blockedIds.contains(row['id_number']) ? 'review' : 'explicit',
        'blocking': blockedIds.contains(row['id_number']),
        'status_code': statusCodes[row['id_number']] ?? 'ready',
        'message': blockedIds.contains(row['id_number'])
            ? 'Review the enrollment section.'
            : 'Official section.',
      },
  ];
}

class _Draft extends StudentBatchDraftNotifier {
  _Draft(this.initial);
  final StudentBatchDraftState initial;

  @override
  StudentBatchDraftState build() => initial;
}

PickedTabularFile _file(
  String name,
  List<String> ids, {
  String section = 'BSIT-3A',
  String year = '3rd Year',
}) {
  final csv =
      'Subject Code,IT311\nClass Section,$section\nYear Level,$year\n'
      'Instructor,Prof. Alan Turing\n\n'
      'Student Number,Full Name,Email,Year Level\n'
      '${ids.map((id) => '$id,"RIVERA, Student$id",$id@ustp.edu.ph,$year').join('\n')}\n';
  return PickedTabularFile(
    name: name,
    extension: 'csv',
    bytes: Uint8List.fromList(utf8.encode(csv)),
    text: csv,
  );
}

StudentBatchDraftState _draft(List<PickedTabularFile> files) =>
    StudentBatchDraftState(
      freshStagedFiles: files,
      freshParsedStudents: [
        for (final file in files)
          ...parseOfficialClassListCsv(file.text!).students,
      ],
    );

Future<ProviderContainer> _open(
  WidgetTester tester, {
  StudentBatchDraftState draft = const StudentBatchDraftState(),
  Set<String> blockedIds = const {},
  Map<String, String> statusCodes = const {},
  Future<List<PickedTabularFile>> Function()? pickFiles,
  Future<PickedTabularFile?> Function()? replaceFile,
  Future<bool> Function(List<Map<String, dynamic>>, Map<String, dynamic>?)?
  confirm,
  Size size = const Size(1400, 1000),
  bool dark = false,
  bool saving = false,
  bool activeSemester = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        academicPeriodProvider.overrideWith(() => _Periods(activeSemester)),
        studentAcademicRecordsProvider.overrideWith(_Records.new),
        userManagementProvider.overrideWith(
          () => _Users(blockedIds, statusCodes),
        ),
        studentBatchDraftProvider.overrideWith(() => _Draft(draft)),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        home: Scaffold(
          body: StudentBatchEnrollmentHubView(
            userState: UserManagementState(isSaving: saving),
            academicState: const AcademicPeriodState(),
            onBack: () {},
            onDownloadSample: null,
            onPickFreshFiles: pickFiles,
            onPickFreshReplacement: replaceFile,
            onConfirmFreshImport: confirm ?? (_, __) async => false,
          ),
        ),
      ),
    ),
  );
  // Saving uses an indeterminate indicator, so it must not pumpAndSettle.
  if (saving) {
    await tester.pump(const Duration(milliseconds: 400));
  } else {
    await tester.pumpAndSettle();
  }
  return ProviderScope.containerOf(
    tester.element(find.byType(StudentBatchEnrollmentHubView)),
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

ShadButton _confirmation(WidgetTester tester) => tester.widget<ShadButton>(
  find.byKey(const ValueKey('confirm-student-enrollment')),
);

Finder _filterFinder(String name) => find.byKey(ValueKey('fresh-$name-filter'));

Future<void> _selectFilter(
  WidgetTester tester,
  String name,
  String value,
) async {
  await _tap(tester, _filterFinder(name));
  final option = find
      .byWidgetPredicate(
        (widget) => widget is ShadOption<String> && widget.value == value,
      )
      .last;
  await _tap(tester, option);
}

StudentBatchDraftState _mixedDraft() {
  final draft = _draft([
    _file('mixed.csv', ['101', '102', '103', '104', '105', '106']),
  ]);
  for (var i = 0; i < draft.freshParsedStudents.length; i++) {
    draft.freshParsedStudents[i]['year_level'] = i.isEven
        ? '3rd Year'
        : '4th Year';
    draft.freshParsedStudents[i]['section'] = [0, 1, 4].contains(i)
        ? 'BSIT-A'
        : 'BSIT-B';
  }
  return draft;
}

const _statusCodes = {
  '102': 'already_enrolled',
  '103': 'update_section',
  '104': 'existing_student',
  '105': 'unknown_nonblocking_code',
  '106': 'already_enrolled',
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'search and dropdowns combine before pagination without changing global counts or draft',
    (tester) async {
      final container = await _open(
        tester,
        draft: _mixedDraft(),
        statusCodes: _statusCodes,
        blockedIds: {'106'},
      );
      await _selectFilter(tester, 'year-level', '3rd Year');
      await _selectFilter(tester, 'section', 'BSIT-A');
      await _selectFilter(tester, 'status', 'ready');
      await tester.enterText(find.byType(EditableText), '105');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fresh-student-row-105')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fresh-student-row-101')), findsNothing);
      expect(find.text('Showing 1 of 6 students'), findsOneWidget);
      expect(find.text('6 students'), findsOneWidget);
      expect(find.text('5 ready'), findsOneWidget);
      expect(find.text('1 needs attention'), findsOneWidget);
      expect(find.text('Applies to all 6 students'), findsOneWidget);
      expect(
        _confirmation(tester).enabled,
        isFalse,
      ); // The hidden blocker still matters.
      await _tap(tester, find.text('Clear filters'));
      expect(find.text('Clear filters'), findsNothing);
      expect(
        find.byKey(const ValueKey('fresh-student-row-106')),
        findsOneWidget,
      );
      expect(
        container.read(studentBatchDraftProvider).freshParsedStudents,
        hasLength(6),
      );
      expect(
        container.read(studentBatchDraftProvider).freshStagedFiles.single.name,
        'mixed.csv',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every status code uses its own group and blockers take precedence',
    (tester) async {
      await _open(
        tester,
        draft: _mixedDraft(),
        statusCodes: _statusCodes,
        blockedIds: {'106'},
      );
      for (final entry in {
        'ready': ['101', '105'],
        'existingStudent': ['104'],
        'alreadyEnrolled': ['102'],
        'updatesSection': ['103'],
        'needsAttention': ['106'],
      }.entries) {
        await _selectFilter(tester, 'status', entry.key);
        for (final id in ['101', '102', '103', '104', '105', '106']) {
          expect(
            find.byKey(ValueKey('fresh-student-row-$id')),
            entry.value.contains(id) ? findsOneWidget : findsNothing,
          );
        }
        expect(find.text('5 ready'), findsOneWidget);
        expect(_confirmation(tester).enabled, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filtering already enrolled rows preserves full-batch confirmation',
    (tester) async {
      List<Map<String, dynamic>>? submitted;
      await _open(
        tester,
        draft: _mixedDraft(),
        statusCodes: _statusCodes,
        confirm: (rows, _) async {
          submitted = rows;
          return false;
        },
      );
      await _selectFilter(tester, 'status', 'alreadyEnrolled');
      expect(find.text('Showing 2 of 6 students'), findsOneWidget);
      expect(find.text('6 ready'), findsOneWidget);
      expect(_confirmation(tester).enabled, isTrue);
      await _tap(tester, find.text('Confirm enrollment (6)'));
      expect(submitted, hasLength(6));
      expect(
        submitted!.map((row) => row['id_number']),
        containsAll(['101', '102', '103', '104', '105', '106']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple same-year files hide the year filter and invalid/missing years remain visible',
    (tester) async {
      await _open(
        tester,
        draft: _draft([
          _file('a.csv', ['101']),
          _file('b.csv', ['201']),
        ]),
      );
      expect(_filterFinder('year-level'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final draft = _draft([
        _file('mixed.csv', ['101', '102', '103', '104']),
      ]);
      final values = ['3rd Yr.', '1st Year', '', 'Unknown'];
      for (var i = 0; i < values.length; i++) {
        draft.freshParsedStudents[i]['year_level'] = values[i];
      }
      final container = await _open(tester, draft: draft);
      final picker = tester.widget<ShadSelect<String>>(
        _filterFinder('year-level'),
      );
      expect(
        picker.options!.whereType<ShadOption<String>>().map(
          (option) => option.value,
        ),
        ['ALL', '1st Year', '3rd Year', 'Unknown', 'Unspecified'],
      );
      await _selectFilter(tester, 'year-level', 'Unspecified');
      expect(
        find.byKey(const ValueKey('fresh-student-row-103')),
        findsOneWidget,
      );
      expect(find.text('Showing 1 of 4 students'), findsOneWidget);
      expect(
        container
            .read(studentBatchDraftProvider)
            .freshParsedStudents
            .map((row) => row['year_level']),
        values,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zero matches retain filters and missing semester is attention without removal candidates',
    (tester) async {
      await _open(
        tester,
        draft: _draft([
          _file('a.csv', ['101']),
        ]),
        activeSemester: false,
        statusCodes: {'101': 'already_enrolled'},
      );
      expect(find.text('0 ready'), findsOneWidget);
      expect(find.text('1 needs attention'), findsOneWidget);
      expect(find.textContaining('Exclude all'), findsNothing);
      await _selectFilter(tester, 'status', 'ready');
      expect(find.text('No students match these filters.'), findsOneWidget);
      expect(find.text('Showing 0 of 1 students'), findsOneWidget);
      expect(_confirmation(tester).enabled, isFalse);
      await _tap(tester, find.text('Clear filters'));
      expect(find.text('Blocked (No Active Term)'), findsOneWidget);
      expect(find.text('Open Academic Periods'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted file changes reset filters while canceled review and replacement preserve them',
    (tester) async {
      final a = _file('a.csv', ['101']);
      final b = _file('b.csv', ['201'], year: '4th Year');
      final c = _file('c.csv', ['301'], year: '2nd Year');
      final container = await _open(
        tester,
        draft: _draft([a, b]),
        pickFiles: () async => [c],
        replaceFile: () async => c,
      );
      await _selectFilter(tester, 'year-level', '4th Year');
      await _selectFilter(tester, 'status', 'ready');
      for (final action in ['Review files', 'Replace', 'Add files']) {
        await _tap(tester, find.text(action).first);
        await _tap(
          tester,
          find.descendant(
            of: find.byType(FileImportStagingModal),
            matching: find.text('Cancel'),
          ),
        );
        expect(
          tester
              .widget<ShadSelect<String>>(_filterFinder('year-level'))
              .initialValue,
          '4th Year',
        );
        expect(
          tester
              .widget<ShadSelect<String>>(_filterFinder('status'))
              .initialValue,
          'ready',
        );
        expect(
          container.read(studentBatchDraftProvider).freshStagedFiles,
          hasLength(2),
        );
      }
      await _tap(tester, find.text('Add files'));
      await _tap(tester, find.text('Generate Preview Table (3 rows)'));
      expect(
        tester
            .widget<ShadSelect<String>>(_filterFinder('year-level'))
            .initialValue,
        'ALL',
      );
      expect(
        tester.widget<ShadSelect<String>>(_filterFinder('status')).initialValue,
        'ALL',
      );
      expect(find.text('Clear filters'), findsNothing);
      expect(
        container.read(studentBatchDraftProvider).freshParsedStudents,
        hasLength(3),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'filter changes reset pagination and row exclusion reconciles vanished options',
    (tester) async {
      final a = _file('a.csv', List.generate(12, (i) => '${101 + i}'));
      final b = _file(
        'b.csv',
        List.generate(12, (i) => '${201 + i}'),
        year: '4th Year',
      );
      await _open(tester, draft: _draft([a, b]));
      await _tap(tester, find.byTooltip('Next page'));
      expect(find.text('11 - 20 of 24'), findsOneWidget);
      await _selectFilter(tester, 'year-level', '3rd Year');
      expect(find.text('1 - 10 of 12'), findsOneWidget);
      await _tap(tester, find.byTooltip('Next page'));
      for (final id in ['111', '112']) {
        await _tap(
          tester,
          find.descendant(
            of: find.byKey(ValueKey('fresh-student-row-$id')),
            matching: find.byTooltip('Exclude student from intake'),
          ),
        );
      }
      expect(find.text('1 - 10 of 10'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'section edit removes obsolete filter options without removing students',
    (tester) async {
      final a = _file('a.csv', ['101'], section: 'BSIT-A');
      final b = _file('b.csv', ['201'], section: 'BSIT-B');
      final container = await _open(tester, draft: _draft([a, b]));
      await _selectFilter(tester, 'section', 'BSIT-A');
      await _tap(tester, find.byTooltip('Edit enrollment section'));
      await tester.enterText(find.byType(TextField).last, 'BSIT-B');
      await _tap(tester, find.text('Apply'));
      expect(_filterFinder('section'), findsNothing);
      expect(
        find.byKey(const ValueKey('fresh-student-row-201')),
        findsOneWidget,
      );
      expect(find.text('Clear filters'), findsNothing);
      expect(
        container.read(studentBatchDraftProvider).freshParsedStudents,
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rows use one surface and year/header columns align', (
    tester,
  ) async {
    await _open(
      tester,
      draft: _draft([
        _file('a.csv', ['101', '102']),
      ]),
    );
    final first = find.byKey(const ValueKey('fresh-student-row-101'));
    final second = find.byKey(const ValueKey('fresh-student-row-102'));
    expect(
      tester.widget<Container>(first).color,
      tester.widget<Container>(second).color,
    );
    final yearHeader = find.descendant(
      of: find.byKey(const ValueKey('fresh-review-header')),
      matching: find.text('Year level'),
    );
    final yearCell = find.descendant(
      of: first,
      matching: find.text('3rd Year'),
    );
    expect(tester.getTopLeft(yearHeader).dx, tester.getTopLeft(yearCell).dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adding files merges and deduplicates the batch before saving the preview',
    (tester) async {
      final a = _file('section-a.csv', ['101']);
      final b = _file('section-b.csv', ['201'], section: 'BSIT-3B');
      final container = await _open(
        tester,
        draft: _draft([a]),
        pickFiles: () async => [a, b],
      );
      await _tap(tester, find.text('Add files'));
      expect(
        tester
            .widget<FileImportStagingModal>(find.byType(FileImportStagingModal))
            .initialFiles
            .map((file) => file.name),
        ['section-a.csv', 'section-b.csv'],
      );
      await _tap(tester, find.text('Generate Preview Table (2 rows)'));
      final saved = container.read(studentBatchDraftProvider);
      expect(saved.freshStagedFiles.map((file) => file.name), [
        'section-a.csv',
        'section-b.csv',
      ]);
      expect(saved.freshParsedStudents.map((row) => row['id_number']), [
        '101',
        '201',
      ]);
      expect(find.text('2 ready'), findsOneWidget);
      expect(_confirmation(tester).enabled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('bulk exclusion removes hidden blockers from the full batch', (
    tester,
  ) async {
    final container = await _open(
      tester,
      draft: _mixedDraft(),
      statusCodes: _statusCodes,
      blockedIds: {'106'},
    );
    await _selectFilter(tester, 'year-level', '3rd Year');
    expect(find.byKey(const ValueKey('fresh-student-row-106')), findsNothing);
    await _tap(tester, find.text('Exclude all 1 blocked'));
    expect(
      container.read(studentBatchDraftProvider).freshParsedStudents,
      hasLength(5),
    );
    expect(
      container
          .read(studentBatchDraftProvider)
          .freshParsedStudents
          .map((row) => row['id_number']),
      isNot(contains('106')),
    );
    expect(find.text('5 ready'), findsOneWidget);
    expect(_confirmation(tester).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing a file resets selected filters and hides single-year control',
    (tester) async {
      await _open(
        tester,
        draft: _draft([
          _file('a.csv', ['101']),
          _file('b.csv', ['201'], year: '4th Year'),
        ]),
      );
      await _selectFilter(tester, 'year-level', '4th Year');
      await _selectFilter(tester, 'status', 'ready');
      await _tap(tester, find.text('Remove').first);
      expect(_filterFinder('year-level'), findsNothing);
      expect(
        tester.widget<ShadSelect<String>>(_filterFinder('status')).initialValue,
        'ALL',
      );
      expect(find.text('Clear filters'), findsNothing);
      expect(
        find.byKey(const ValueKey('fresh-student-row-201')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('term mismatch takes precedence over an already-enrolled code', (
    tester,
  ) async {
    final draft = _draft([
      _file('old-term.csv', ['101']),
    ]);
    draft.freshParsedStudents.single['_fileMetadata'] = {
      'semester': '2nd Semester',
      'school_year': '2026-2027',
    };
    await _open(tester, draft: draft, statusCodes: {'101': 'already_enrolled'});
    await _selectFilter(tester, 'status', 'needsAttention');
    expect(find.text('Blocked (Term Mismatch)'), findsOneWidget);
    expect(find.text('0 ready'), findsOneWidget);
    expect(_confirmation(tester).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [390.0, 1400.0]) {
      testWidgets(
        'mixed-year filters and long section fit $width in ${dark ? 'dark' : 'light'}',
        (tester) async {
          final draft = _mixedDraft();
          const longSection = 'BSIT-4A-official-class-section-with-a-long-name';
          draft.freshParsedStudents.first['section'] = longSection;
          await _open(
            tester,
            draft: draft,
            statusCodes: _statusCodes,
            dark: dark,
            size: Size(width, 1000),
          );
          expect(_filterFinder('year-level'), findsOneWidget);
          expect(_filterFinder('section'), findsOneWidget);
          expect(_filterFinder('status'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'student-table-mixed-${dark ? 'dark' : 'light'}-${width.toInt()}',
            viewport: true,
          );
          await _selectFilter(tester, 'section', longSection);
          expect(find.text('Showing 1 of 6 students'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, isNotNull);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'student-table-filtered-${dark ? 'dark' : 'light'}-${width.toInt()}',
            viewport: true,
          );
        },
      );
    }
  }

  testWidgets(
    'replacement cancel preserves the batch; acceptance rebuilds only the candidate batch',
    (tester) async {
      final a = _file('original.csv', ['101']);
      final b = _file('replacement.csv', ['202']);
      PickedTabularFile? picked;
      final container = await _open(
        tester,
        draft: _draft([a]),
        replaceFile: () async => picked,
      );
      await _tap(tester, find.text('Replace'));
      expect(find.byType(FileImportStagingModal), findsNothing);
      expect(
        container.read(studentBatchDraftProvider).freshStagedFiles.single.name,
        a.name,
      );
      picked = b;
      await _tap(tester, find.text('Replace'));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(FileImportStagingModal),
          matching: find.text('Cancel'),
        ),
      );
      expect(
        container
            .read(studentBatchDraftProvider)
            .freshParsedStudents
            .single['id_number'],
        '101',
      );
      expect(find.text(a.name), findsOneWidget);
      await _tap(tester, find.text('Replace'));
      await _tap(tester, find.text('Generate Preview Table (1 rows)'));
      expect(
        container.read(studentBatchDraftProvider).freshStagedFiles.single.name,
        b.name,
      );
      expect(
        container
            .read(studentBatchDraftProvider)
            .freshParsedStudents
            .single['id_number'],
        '202',
      );
      expect(find.text(a.name), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('canceling Add and Review leaves the saved batch unchanged', (
    tester,
  ) async {
    final a = _file('existing.csv', ['101']);
    final b = _file('new.csv', ['201']);
    final container = await _open(
      tester,
      draft: _draft([a]),
      pickFiles: () async => [b],
    );
    for (final label in ['Add files', 'Review files']) {
      await _tap(tester, find.text(label));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(FileImportStagingModal),
          matching: find.text('Cancel'),
        ),
      );
      final saved = container.read(studentBatchDraftProvider);
      expect(saved.freshStagedFiles.single.name, 'existing.csv');
      expect(saved.freshParsedStudents.single['id_number'], '101');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing a file rebuilds the roster and removing the final file clears the draft',
    (tester) async {
      final a = _file('first.csv', ['101', '999']);
      final b = _file('second.csv', ['201', '999']);
      final container = await _open(tester, draft: _draft([a, b]));
      await _tap(tester, find.text('Remove').first);
      var saved = container.read(studentBatchDraftProvider);
      expect(saved.freshStagedFiles.single.name, b.name);
      expect(saved.freshParsedStudents.map((row) => row['id_number']), [
        '201',
        '999',
      ]);
      expect(find.text('2 ready'), findsOneWidget);
      await _tap(tester, find.text('Remove'));
      saved = container.read(studentBatchDraftProvider);
      expect(saved.hasFreshDraft, isFalse);
      expect(saved.freshSectionFilter, 'ALL');
      expect(find.text('Choose files'), findsOneWidget);
      expect(find.text('0 students'), findsOneWidget);
      expect(_confirmation(tester).enabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'batch counts ignore search and blocked rows keep confirmation disabled',
    (tester) async {
      final file = _file('review.csv', ['101', '201']);
      var imports = 0;
      await _open(
        tester,
        draft: _draft([file]),
        blockedIds: {'201'},
        confirm: (_, __) async {
          imports++;
          return false;
        },
      );
      expect(find.text('2 students'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);
      expect(find.text('1 needs attention'), findsOneWidget);
      expect(_confirmation(tester).enabled, isFalse);
      expect(_confirmation(tester).onPressed, isNull);
      await tester.enterText(find.byType(EditableText), '101');
      await tester.pumpAndSettle();
      expect(find.text('2 students'), findsOneWidget);
      expect(find.text('1 ready'), findsOneWidget);
      expect(find.text('1 needs attention'), findsOneWidget);
      expect(_confirmation(tester).enabled, isFalse);
      expect(_confirmation(tester).onPressed, isNull);
      expect(imports, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('conflicting sections across added files remain blocking', (
    tester,
  ) async {
    final a = _file('a.csv', ['101']);
    final b = _file('b.csv', ['101'], section: 'BSIT-3B');
    final container = await _open(
      tester,
      draft: _draft([a]),
      pickFiles: () async => [b],
    );
    await _tap(tester, find.text('Add files'));
    await _tap(tester, find.text('Generate Preview Table (2 rows)'));
    expect(
      container.read(studentBatchDraftProvider).freshParsedStudents,
      hasLength(1),
    );
    expect(find.text('0 ready'), findsOneWidget);
    expect(find.text('1 needs attention'), findsOneWidget);
    expect(_confirmation(tester).enabled, isFalse);
    expect(_confirmation(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('accepted file removal resets the current review page', (
    tester,
  ) async {
    final a = _file('first.csv', List.generate(12, (i) => '${100 + i}'));
    final b = _file('second.csv', ['201']);
    final container = await _open(tester, draft: _draft([a, b]));
    await _tap(tester, find.byTooltip('Next page'));
    expect(find.text('11 - 13 of 13'), findsOneWidget);
    await _tap(tester, find.text('Remove').first);
    expect(
      container
          .read(studentBatchDraftProvider)
          .freshParsedStudents
          .single['id_number'],
      '201',
    );
    expect(find.text('1 - 1 of 1'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(_confirmation(tester).enabled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
    'restored rows without files can still be confirmed and explicitly cleared',
    (tester) async {
      final rows = _draft([
        _file('restored.csv', ['101']),
      ]).freshParsedStudents;
      var imports = 0;
      final container = await _open(
        tester,
        draft: StudentBatchDraftState(freshParsedStudents: rows),
        confirm: (submitted, _) async {
          imports++;
          expect(submitted.single['id_number'], '101');
          return false;
        },
      );
      expect(find.text('Choose files'), findsOneWidget);
      expect(_confirmation(tester).enabled, isTrue);
      await _tap(tester, find.text('Confirm enrollment (1)'));
      expect(imports, 1);
      expect(container.read(studentBatchDraftProvider).hasFreshDraft, isTrue);
      await _tap(tester, find.text('Clear files'));
      expect(container.read(studentBatchDraftProvider).hasFreshDraft, isFalse);
      expect(_confirmation(tester).enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing active semester disables confirmation and keeps recovery available',
    (tester) async {
      await _open(
        tester,
        draft: _draft([
          _file('list.csv', ['101']),
        ]),
        activeSemester: false,
      );
      expect(find.text('Open Academic Periods'), findsOneWidget);
      expect(find.text('Active semester required'), findsOneWidget);
      expect(_confirmation(tester).enabled, isFalse);
      expect(_confirmation(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1400.0]) {
      for (final state in [
        'empty',
        'files',
        'restored',
        'blocked',
        'pending',
      ]) {
        testWidgets('$state layout fits $width in ${dark ? 'dark' : 'light'} theme', (
          tester,
        ) async {
          final files = [
            _file(
              'university-official-enrollment-list-with-a-very-long-filename-semester-one-section-three-a.csv',
              ['101', '201'],
            ),
          ];
          final rows = _draft(files).freshParsedStudents;
          await _open(
            tester,
            draft: state == 'empty'
                ? const StudentBatchDraftState()
                : StudentBatchDraftState(
                    freshStagedFiles: state == 'restored' ? [] : files,
                    freshParsedStudents: rows,
                  ),
            dark: dark,
            size: Size(width, 1000),
            saving: state == 'pending',
            blockedIds: state == 'blocked' ? {'201'} : {},
          );
          expect(find.text('Official Class List Specification'), findsNothing);
          expect(find.text('View Sheet Layout Blueprint'), findsNothing);
          expect(find.text('Download Sample Template'), findsNothing);
          expect(
            find.text('Enrollment term: 1st Semester, A.Y. 2026-2027'),
            findsOneWidget,
          );
          expect(
            _confirmation(tester).enabled,
            state == 'files' || state == 'restored',
          );
          // Exercise focus without submitting, including when confirmation is disabled.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, isNotNull);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'student-import-$state-${dark ? 'dark' : 'light'}-${width.toInt()}',
            viewport: true,
          );
          if (state != 'pending') {
            await tester.ensureVisible(
              find.byKey(const ValueKey('confirm-student-enrollment')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }

  testWidgets('rollover keeps its blueprint and template controls', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, find.text('Semester rollover'));
    expect(find.text('View Sheet Layout Blueprint'), findsOneWidget);
    expect(find.text('Download Sample Template'), findsOneWidget);
    await _tap(tester, find.text('Import class lists'));
    expect(find.text('Review students'), findsOneWidget);
    expect(find.text('View Sheet Layout Blueprint'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
