import 'library_filters.dart';
import 'repository_library.dart';

/// Topic membership belongs to a project, including its non-text outputs.
class LibraryTopicCollection {
  const LibraryTopicCollection(this.tag, this.projects);
  final LibraryTag tag;
  final List<LibraryProject> projects;
  String get title =>
      tag.id == unspecifiedLibraryTag.id ? 'More research' : tag.label;
  List<VaultEntry> get entries => [
    for (final project in projects) ...project.entries,
  ];

  /// Introduce different formats before repeating a format. Older manuscript
  /// stages remain available in View all and the parent project.
  List<VaultEntry> get previewEntries {
    final buckets = <String, List<VaultEntry>>{};
    int priority(VaultEntry e) => switch (e.outputKind) {
      'final' => 3,
      'chapters' => 2,
      'concept' => 1,
      _ => 0,
    };
    for (final project in projects) {
      final files = [...project.entries];
      files.sort((a, b) => priority(b).compareTo(priority(a)));
      final seen = <String>{};
      for (final entry in files) {
        final kind = entry.isDocument ? 'document' : entry.outputKind;
        if (seen.add(kind)) {
          buckets.putIfAbsent(kind, () => []).add(entry);
        }
      }
    }
    final kinds = [
      for (final kind in ['document', 'poster', 'video', 'other'])
        if (buckets.containsKey(kind)) kind,
      ...buckets.keys.where(
        (key) => !['document', 'poster', 'video', 'other'].contains(key),
      ),
    ];
    return [
      for (var i = 0; buckets.values.any((items) => i < items.length); i++)
        for (final kind in kinds)
          if (i < buckets[kind]!.length) buckets[kind]![i],
    ];
  }

  static List<LibraryTopicCollection> group(List<VaultEntry> entries) {
    final groups = <String, List<LibraryProject>>{};
    final tags = <String, LibraryTag>{};
    for (final project in LibraryProject.group(entries)) {
      final subjects = <String, LibraryTag>{};
      for (final entry in project.entries) {
        for (final tag in entry.libraryTags['subject'] ?? <LibraryTag>[]) {
          if (tag.id != unspecifiedLibraryTag.id) subjects[tag.id] = tag;
        }
      }
      if (subjects.isEmpty) {
        subjects[unspecifiedLibraryTag.id] = unspecifiedLibraryTag;
      }
      for (final tag in subjects.values) {
        tags[tag.id] = tag;
        groups.putIfAbsent(tag.id, () => []).add(project);
      }
    }
    final result = [
      for (final group in groups.entries)
        LibraryTopicCollection(tags[group.key]!, group.value),
    ];
    result.sort((a, b) {
      if (a.tag.id == unspecifiedLibraryTag.id) return 1;
      if (b.tag.id == unspecifiedLibraryTag.id) return -1;
      final size = b.projects.length.compareTo(a.projects.length);
      return size != 0 ? size : a.title.compareTo(b.title);
    });
    return result;
  }
}
