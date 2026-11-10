/// Preserve all name parts when importing the school's surname-first lists.
({String firstName, String lastName}) splitOfficialPersonName(String value) {
  final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  final comma = clean.indexOf(',');
  if (comma >= 0) {
    return (
      firstName: clean
          .substring(comma + 1)
          .replaceAll(',', ' ')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' '),
      lastName: clean.substring(0, comma).trim(),
    );
  }
  final space = clean.indexOf(' ');
  return space < 0
      ? (firstName: clean, lastName: '')
      : (
          firstName: clean.substring(0, space),
          lastName: clean.substring(space + 1),
        );
}

/// Formatting comparison for review labels and batch mappings. Backend matching
/// remains authoritative and supplies reference_key when a preview is available.
List<String> personNameTokens(String value, {bool surnameFirst = true}) {
  final parts = <List<String>>[];
  final suffixes = <String>[];
  final segments = value.trim().split(',');
  for (var i = 0; i < segments.length; i++) {
    final words = segments[i]
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final kept = <String>[];
    for (var j = 0; j < words.length; j++) {
      final word = words[j];
      final bare = word.replaceFirst(RegExp(r'\.$'), '');
      final roman =
          const ['ii', 'iii', 'iv', 'v'].contains(bare) &&
          j == words.length - 1 &&
          (bare != 'v' ||
              words.length >= 3 ||
              surnameFirst && segments.length > 1 && i == 0);
      if (bare == 'jr' || bare == 'sr' || roman) {
        if (!suffixes.contains(bare)) suffixes.add(bare);
      } else {
        kept.add(RegExp(r'^[a-z]\.$').hasMatch(word) ? bare : word);
      }
    }
    if (kept.isNotEmpty) parts.add(kept);
  }
  final ordered = surnameFirst && parts.length > 1
      ? [...parts.skip(1), parts.first]
      : parts;
  return [...ordered.expand((part) => part), ...suffixes];
}

String personNameKey(String value, {bool surnameFirst = true}) =>
    personNameTokens(value, surnameFirst: surnameFirst).join(' ');
