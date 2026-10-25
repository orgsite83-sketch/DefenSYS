import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/models/library_topics.dart';
import 'package:defensys/models/repository_library.dart';

VaultEntry file(String id, String project, String kind, {bool tagged = true}) =>
    VaultEntry(
      id: id,
      projectKey: project,
      projectTitle: project,
      fileName: '$id.pdf',
      documentKind: kind,
      teamName: project,
      uploadedBy: '',
      academicYear: '2026-2027',
      status: 'Approved',
      timestamp: '',
      yearLevel: '',
      stage: '',
      type: 'pit',
      libraryTags: tagged
          ? {
              'subject': [
                const LibraryTag(id: 'education', label: 'Education'),
              ],
            }
          : {},
    );

void main() {
  test(
    'a project topic includes its media without inventing file-level tags',
    () {
      final topics = LibraryTopicCollection.group([
        file('paper', 'project-a', 'concept'),
        file('poster', 'project-a', 'poster', tagged: false),
        file('video', 'project-a', 'video', tagged: false),
      ]);
      expect(topics, hasLength(1));
      expect(topics.single.title, 'Education');
      expect(topics.single.projects, hasLength(1));
      expect(topics.single.entries, hasLength(3));
      expect(topics.single.previewEntries.map((e) => e.outputKind), [
        'concept',
        'poster',
        'video',
      ]);
      expect(topics.single.entries[1].libraryTags, isEmpty);
    },
  );

  test(
    'unclassified projects stay visible and sort after available topics',
    () {
      final topics = LibraryTopicCollection.group([
        file('unknown', 'unknown-project', 'video', tagged: false),
        file('known', 'known-project', 'concept'),
      ]);
      expect(topics.map((t) => t.title), ['Education', 'More research']);
      expect(topics.last.entries.single.id, 'unknown');
    },
  );

  test(
    'rows introduce media before repeating documents and keep latest manuscript',
    () {
      final topic = LibraryTopicCollection.group([
        file('concept', 'a', 'concept'),
        file('final', 'a', 'final'),
        file('other-paper', 'b', 'concept'),
        file('video', 'b', 'video'),
        file('poster', 'a', 'poster'),
      ]).single;
      expect(topic.entries, hasLength(5));
      expect(topic.previewEntries.map((e) => e.id), [
        'final',
        'poster',
        'video',
        'other-paper',
      ]);
    },
  );

  test(
    'topic counts deduplicate projects and empty repositories have no fake rows',
    () {
      expect(LibraryTopicCollection.group([]), isEmpty);
      final topic = LibraryTopicCollection.group([
        file('a', 'p', 'concept'),
        file('b', 'p', 'poster'),
      ]).single;
      expect(topic.projects, hasLength(1));
      expect(topic.entries, hasLength(2));
    },
  );
}
