import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/models/library_filters.dart';
import 'package:defensys/models/repository_library.dart';

VaultEntry tagged(
  String id, {
  String? project,
  String subject = 'sports-fitness',
  String technology = 'mobile',
  String language = 'kotlin',
  String year = '2026-2027',
}) => VaultEntry.fromJson({
  'id': id,
  'project_key': project ?? id,
  'academic_year': year,
  'library_tags': {
    'subject': subject.isEmpty
        ? []
        : [
            {
              'id': subject,
              'label': subject == 'sports-fitness'
                  ? 'Sports & Fitness'
                  : 'Health & Wellbeing',
            },
          ],
    'technology': technology.isEmpty
        ? []
        : [
            {
              'id': technology,
              'label': technology == 'mobile'
                  ? 'Mobile Applications'
                  : 'Web Applications',
            },
          ],
    'language': language.isEmpty
        ? []
        : [
            {
              'id': language,
              'label': language == 'kotlin' ? 'Kotlin' : 'Python',
              'status': 'proposed',
            },
          ],
  },
  'topics': ['approved', 'data'],
});

void main() {
  test(
    'tag identity and proposed status survive model parsing and copying',
    () {
      final entry = tagged('one');
      expect(entry.libraryTags['language']!.single.id, 'kotlin');
      expect(
        entry.copyWith(lastReadPage: 2).libraryTags['language']!.single.status,
        'proposed',
      );
      expect(entry.topics, ['approved', 'data']);
    },
  );

  test(
    'facets count projects once and raw keywords never become public options',
    () {
      final options = const LibraryFilterSelection().facets([
        tagged('one', project: 'same'),
        tagged('copy', project: 'same'),
      ], LibraryFilterGroup.subject);
      expect(options.single.tag.id, 'sports-fitness');
      expect(options.single.count, 1);
    },
  );

  test('selections are OR inside a group and AND across groups', () {
    const selection = LibraryFilterSelection(
      subjects: {'sports-fitness', 'health-wellbeing'},
      languages: {'python'},
    );
    expect(selection.matches(tagged('one')), isFalse);
    expect(
      selection.matches(
        tagged('two', subject: 'health-wellbeing', language: 'python'),
      ),
      isTrue,
    );
    expect(
      selection.query(LibraryFilterGroup.subject),
      'health-wellbeing,sports-fitness',
    );
  });

  test(
    'facets exclude their own selection and retain zero-count active values',
    () {
      final entries = [
        tagged('sports'),
        tagged('health', subject: 'health-wellbeing', year: '2025-2026'),
      ];
      const selection = LibraryFilterSelection(
        year: '2025-2026',
        subjects: {'sports-fitness'},
      );
      final options = selection.facets(entries, LibraryFilterGroup.subject);
      expect(
        {for (final option in options) option.tag.id: option.count},
        {'health-wellbeing': 1, 'sports-fitness': 0},
      );
      expect(selection.facets(entries, LibraryFilterGroup.language), isEmpty);
    },
  );

  test(
    'missing tags have an explicit Not specified option without guessing',
    () {
      final entry = tagged('one', subject: '', technology: '', language: '');
      final options = const LibraryFilterSelection().facets([
        entry,
      ], LibraryFilterGroup.language);
      expect(options.single.tag.label, 'Not specified');
      expect(
        const LibraryFilterSelection(languages: {'unspecified'}).matches(entry),
        isTrue,
      );
      expect(
        const LibraryFilterSelection(languages: {'python'}).matches(entry),
        isFalse,
      );
    },
  );

  test(
    'unavailable selected labels remain removable without mutating previous selections',
    () {
      const tag = LibraryTag(id: 'python', label: 'Python');
      const empty = LibraryFilterSelection();
      final selected = empty.toggle(LibraryFilterGroup.language, tag);
      expect(empty.languages, isEmpty);
      expect(
        selected.facets([], LibraryFilterGroup.language).single.tag.label,
        'Python',
      );
      expect(
        selected.remove(LibraryFilterGroup.language, 'python').isEmpty,
        isTrue,
      );
    },
  );
}
