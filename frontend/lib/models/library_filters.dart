import 'repository_library.dart';

enum LibraryFilterGroup {
  subject('Subject area', 'Any subject'),
  technology('Technology area', 'Any technology'),
  language('Programming language', 'Any language');

  const LibraryFilterGroup(this.label, this.anyLabel);
  final String label, anyLabel;
}

const unspecifiedLibraryTag = LibraryTag(
  id: 'unspecified',
  label: 'Not specified',
);

class LibraryFacetOption {
  const LibraryFacetOption(this.tag, this.count);
  final LibraryTag tag;
  final int count;
}

/// OR within each group, AND between groups. IDs come from the backend taxonomy.
class LibraryFilterSelection {
  const LibraryFilterSelection({
    this.year = '',
    this.subjects = const {},
    this.technologies = const {},
    this.languages = const {},
    this.labels = const {},
  });
  final String year;
  final Set<String> subjects, technologies, languages;
  final Map<String, String> labels;
  bool get isEmpty =>
      year.isEmpty &&
      subjects.isEmpty &&
      technologies.isEmpty &&
      languages.isEmpty;
  Set<String> values(LibraryFilterGroup group) => switch (group) {
    LibraryFilterGroup.subject => subjects,
    LibraryFilterGroup.technology => technologies,
    LibraryFilterGroup.language => languages,
  };
  String query(LibraryFilterGroup group) =>
      (values(group).toList()..sort()).join(',');
  LibraryFilterSelection copyWith({
    String? year,
    Set<String>? subjects,
    Set<String>? technologies,
    Set<String>? languages,
    Map<String, String>? labels,
  }) => LibraryFilterSelection(
    year: year ?? this.year,
    subjects: Set.unmodifiable(subjects ?? this.subjects),
    technologies: Set.unmodifiable(technologies ?? this.technologies),
    languages: Set.unmodifiable(languages ?? this.languages),
    labels: Map.unmodifiable(labels ?? this.labels),
  );

  LibraryFilterSelection toggle(LibraryFilterGroup group, LibraryTag tag) {
    final next = {...values(group)};
    next.contains(tag.id) ? next.remove(tag.id) : next.add(tag.id);
    return _replace(
      group,
      next,
    ).copyWith(labels: {...labels, '${group.name}:${tag.id}': tag.label});
  }

  LibraryFilterSelection clear(LibraryFilterGroup group) => _replace(group, {});
  LibraryFilterSelection remove(LibraryFilterGroup group, String id) =>
      _replace(group, {...values(group)}..remove(id));
  LibraryFilterSelection _replace(LibraryFilterGroup group, Set<String> ids) =>
      switch (group) {
        LibraryFilterGroup.subject => copyWith(subjects: ids),
        LibraryFilterGroup.technology => copyWith(technologies: ids),
        LibraryFilterGroup.language => copyWith(languages: ids),
      };

  String label(LibraryFilterGroup group, String id, List<VaultEntry> entries) {
    if (id == unspecifiedLibraryTag.id) return unspecifiedLibraryTag.label;
    for (final entry in entries) {
      for (final tag in entry.libraryTags[group.name] ?? <LibraryTag>[]) {
        if (tag.id == id) return tag.label;
      }
    }
    return labels['${group.name}:$id'] ?? id;
  }

  bool matches(
    VaultEntry entry, {
    LibraryFilterGroup? except,
    bool ignoreYear = false,
  }) {
    if (!ignoreYear && year.isNotEmpty && entry.academicYear != year) {
      return false;
    }
    for (final group in LibraryFilterGroup.values) {
      if (group == except || values(group).isEmpty) continue;
      final ids = (entry.libraryTags[group.name] ?? <LibraryTag>[])
          .map((tag) => tag.id)
          .toSet();
      if (ids.isEmpty) ids.add(unspecifiedLibraryTag.id);
      if (!ids.any(values(group).contains)) return false;
    }
    return true;
  }

  List<LibraryFacetOption> facets(
    List<VaultEntry> entries,
    LibraryFilterGroup group,
  ) {
    final projects = <String, Set<String>>{};
    final tags = <String, LibraryTag>{};
    for (final entry in entries.where(
      (entry) => matches(entry, except: group),
    )) {
      final available = entry.libraryTags[group.name] ?? [];
      for (final tag
          in available.isEmpty ? [unspecifiedLibraryTag] : available) {
        tags[tag.id] = tag;
        projects.putIfAbsent(tag.id, () => {}).add(entry.groupingKey);
      }
    }
    for (final id in values(group)) {
      projects.putIfAbsent(id, () => {});
      tags.putIfAbsent(
        id,
        () => LibraryTag(id: id, label: label(group, id, entries)),
      );
    }
    return [
      for (final item in projects.entries)
        LibraryFacetOption(tags[item.key]!, item.value.length),
    ]..sort(
      (a, b) => a.count == b.count
          ? a.tag.label.compareTo(b.tag.label)
          : b.count.compareTo(a.count),
    );
  }
}
