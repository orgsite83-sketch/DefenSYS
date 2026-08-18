import 'dart:math' as math;

enum MatchConfidence {
  exact,
  canonical,
  fuzzy,
  none,
}

class MatchResult<T> {
  const MatchResult({
    required this.item,
    required this.label,
    required this.confidence,
    required this.similarity,
    required this.sourceText,
  });

  final T? item;
  final String label;
  final MatchConfidence confidence;
  final double similarity;
  final String sourceText;

  bool get isMatched => item != null && confidence != MatchConfidence.none;
  bool get isExact => confidence == MatchConfidence.exact;
  bool get isCanonical => confidence == MatchConfidence.canonical;
  bool get isFuzzy => confidence == MatchConfidence.fuzzy;
}

/// Normalizes academic and common event/stage names by expanding or standardizing
/// numbers, ordinals, and common abbreviations.
String canonicalizeEventOrStageName(String input) {
  var text = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  // Ordinal and numeric words to digits
  text = text
      .replaceAll(RegExp(r'\b(1st|first)\b'), '1')
      .replaceAll(RegExp(r'\b(2nd|second)\b'), '2')
      .replaceAll(RegExp(r'\b(3rd|third)\b'), '3')
      .replaceAll(RegExp(r'\b(4th|fourth)\b'), '4');

  // Academic period and event words
  text = text
      .replaceAll(RegExp(r'\b(yr|years?)\b'), 'year')
      .replaceAll(RegExp(r'\b(exp|expos?|exhibition)\b'), 'expo')
      .replaceAll(RegExp(r'\b(prop|proposals?)\b'), 'proposal')
      .replaceAll(RegExp(r'\b(redef|redefense|re-defense)\b'), 'redefense')
      .replaceAll(RegExp(r'\b(mid|midterms?)\b'), 'midterm')
      .replaceAll(RegExp(r'\b(fin|finals?)\b'), 'final')
      .replaceAll(RegExp(r'\b(sem|semesters?)\b'), 'semester');

  // Remove common filler words for stages
  text = text
      .replaceAll(RegExp(r'\b(defense|project|and|research)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return text;
}

/// Calculates similarity score between 0.0 (no match) and 1.0 (exact match)
/// using Damerau-Levenshtein edit distance (including transpositions).
double stringSimilarity(String s1, String s2) {
  final a = s1.trim().toLowerCase();
  final b = s2.trim().toLowerCase();
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;

  final dp = List.generate(
    a.length + 1,
    (i) => List.filled(b.length + 1, 0),
  );
  for (var i = 0; i <= a.length; i++) dp[i][0] = i;
  for (var j = 0; j <= b.length; j++) dp[0][j] = j;

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var minCost = math.min(
        dp[i - 1][j] + 1,
        math.min(
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ),
      );

      // Transposition check
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1]) {
        minCost = math.min(minCost, dp[i - 2][j - 2] + 1);
      }

      dp[i][j] = minCost;
    }
  }

  final maxLen = math.max(a.length, b.length);
  return 1.0 - (dp[a.length][b.length] / maxLen);
}

/// Finds the best matching candidate from a list of items given a source string.
MatchResult<T> findBestMatch<T>({
  required String source,
  required List<T> items,
  required String Function(T item) labelGetter,
  double fuzzyThreshold = 0.80,
}) {
  final cleanSource = source.trim();
  if (cleanSource.isEmpty || items.isEmpty) {
    return MatchResult<T>(
      item: null,
      label: '',
      confidence: MatchConfidence.none,
      similarity: 0.0,
      sourceText: cleanSource,
    );
  }

  final lowerSource = cleanSource.toLowerCase();
  final canonicalSource = canonicalizeEventOrStageName(cleanSource);

  // 1. Exact match (case-insensitive)
  for (final item in items) {
    final label = labelGetter(item).trim();
    if (label.toLowerCase() == lowerSource) {
      return MatchResult<T>(
        item: item,
        label: label,
        confidence: MatchConfidence.exact,
        similarity: 1.0,
        sourceText: cleanSource,
      );
    }
  }

  // 2. Canonical / Alias match (handles 1st Year Expo <-> 1st Yr Expo, Capstone 1 <-> Capstone Project 1)
  for (final item in items) {
    final label = labelGetter(item).trim();
    final canonicalLabel = canonicalizeEventOrStageName(label);
    if (canonicalLabel.isNotEmpty && canonicalLabel == canonicalSource) {
      return MatchResult<T>(
        item: item,
        label: label,
        confidence: MatchConfidence.canonical,
        similarity: 0.98,
        sourceText: cleanSource,
      );
    }
  }

  // 3. Fuzzy similarity matching (handles typos like DigiSlove <-> DigiSolve)
  T? bestItem;
  String bestLabel = '';
  double maxSim = 0.0;

  for (final item in items) {
    final label = labelGetter(item).trim();
    final directSim = stringSimilarity(cleanSource, label);
    final canonicalSim = stringSimilarity(canonicalSource, canonicalizeEventOrStageName(label));
    final score = math.max(directSim, canonicalSim);

    if (score > maxSim) {
      maxSim = score;
      bestItem = item;
      bestLabel = label;
    }
  }

  if (bestItem != null && maxSim >= fuzzyThreshold) {
    return MatchResult<T>(
      item: bestItem,
      label: bestLabel,
      confidence: MatchConfidence.fuzzy,
      similarity: maxSim,
      sourceText: cleanSource,
    );
  }

  return MatchResult<T>(
    item: null,
    label: '',
    confidence: MatchConfidence.none,
    similarity: maxSim,
    sourceText: cleanSource,
  );
}
