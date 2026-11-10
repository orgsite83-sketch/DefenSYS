/// Allocates hundredths of a percent without losing weight to rounding.
/// Largest fractional remainders receive the spare units; ties follow row order.
List<int> allocateRubricWeight(int totalBasisPoints, List<int> proportions) {
  if (totalBasisPoints < 0 || proportions.any((value) => value < 0)) {
    throw ArgumentError('Weight and proportions must be non-negative.');
  }
  if (proportions.isEmpty) return [];
  final sum = proportions.fold<int>(0, (sum, value) => sum + value);
  final basis = sum == 0
      ? List<int>.filled(proportions.length, 1)
      : proportions;
  final divisor = sum == 0 ? proportions.length : sum;
  final allocations = [
    for (final value in basis) totalBasisPoints * value ~/ divisor,
  ];
  final remainders = [
    for (final value in basis) totalBasisPoints * value % divisor,
  ];
  final order = List<int>.generate(basis.length, (index) => index)
    ..sort((a, b) {
      final comparison = remainders[b].compareTo(remainders[a]);
      return comparison == 0 ? a.compareTo(b) : comparison;
    });
  final remaining =
      totalBasisPoints - allocations.fold<int>(0, (sum, value) => sum + value);
  for (var i = 0; i < remaining; i++) {
    allocations[order[i]]++;
  }
  return allocations;
}

String formatRubricWeight(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = basisPoints % 100;
  return fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}
