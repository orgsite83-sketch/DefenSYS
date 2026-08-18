import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/string_matching_utils.dart';

void main() {
  group('canonicalizeEventOrStageName', () {
    test('standardizes ordinal numbers and academic terms', () {
      expect(canonicalizeEventOrStageName('1st Year Expo'), equals('1 year expo'));
      expect(canonicalizeEventOrStageName('1st Yr Expo'), equals('1 year expo'));
      expect(canonicalizeEventOrStageName('Year 1 Expo'), equals('year 1 expo'));
      expect(canonicalizeEventOrStageName('First Year Expo'), equals('1 year expo'));
      expect(canonicalizeEventOrStageName('3rd Year Expo'), equals('3 year expo'));
      expect(canonicalizeEventOrStageName('2nd Yr Exhibition'), equals('2 year expo'));
    });

    test('standardizes capstone stages and abbreviations', () {
      expect(
        canonicalizeEventOrStageName('REDEFENSE - Capstone Project and Research 1'),
        equals('redefense capstone 1'),
      );
      expect(
        canonicalizeEventOrStageName('Concept Proposal'),
        equals('concept proposal'),
      );
      expect(
        canonicalizeEventOrStageName('Proposal Defense'),
        equals('proposal'),
      );
    });
  });

  group('stringSimilarity', () {
    test('returns 1.0 for identical or case-differing strings', () {
      expect(stringSimilarity('DigiSolve', 'DigiSolve'), equals(1.0));
      expect(stringSimilarity('DigiSolve', 'digisolve'), equals(1.0));
      expect(stringSimilarity('DIGISOLVE', 'digisolve'), equals(1.0));
      expect(stringSimilarity('  DigiSolve  ', 'digisolve'), equals(1.0));
    });

    test('returns high similarity for common typos', () {
      // 1 transposition/letter change
      final sim1 = stringSimilarity('DigiSlove', 'DigiSolve');
      expect(sim1, greaterThanOrEqualTo(0.85));

      final sim2 = stringSimilarity('DigSolve', 'DigiSolve');
      expect(sim2, greaterThanOrEqualTo(0.85));

      final sim3 = stringSimilarity('Team NovaPath', 'Team NovaPat');
      expect(sim3, greaterThanOrEqualTo(0.90));
    });

    test('returns low similarity for completely different strings', () {
      final sim = stringSimilarity('CyberSecurity Expo', 'DigiSolve');
      expect(sim, lessThan(0.30));
    });
  });

  group('findBestMatch', () {
    final pitEvents = [
      {'event_name': '1st Yr Expo'},
      {'event_name': '2nd Yr Expo'},
      {'event_name': '3rd Yr Expo'},
      {'event_name': 'DigiSolve'},
      {'event_name': 'InnoVenture Challenge'},
    ];

    test('finds exact match with Exact confidence', () {
      final result = findBestMatch<Map<String, dynamic>>(
        source: '1st Yr Expo',
        items: pitEvents,
        labelGetter: (e) => e['event_name'] as String,
      );

      expect(result.isMatched, isTrue);
      expect(result.confidence, equals(MatchConfidence.exact));
      expect(result.label, equals('1st Yr Expo'));
    });

    test('matches 1st Year Expo to 1st Yr Expo with Canonical confidence', () {
      final result = findBestMatch<Map<String, dynamic>>(
        source: '1st Year Expo',
        items: pitEvents,
        labelGetter: (e) => e['event_name'] as String,
      );

      expect(result.isMatched, isTrue);
      expect(result.confidence, equals(MatchConfidence.canonical));
      expect(result.label, equals('1st Yr Expo'));
    });

    test('matches case differences in custom names (digisolve -> DigiSolve)', () {
      final result = findBestMatch<Map<String, dynamic>>(
        source: 'digisolve',
        items: pitEvents,
        labelGetter: (e) => e['event_name'] as String,
      );

      expect(result.isMatched, isTrue);
      expect(result.confidence, equals(MatchConfidence.exact));
      expect(result.label, equals('DigiSolve'));
    });

    test('matches typos in custom names (DigiSlove -> DigiSolve) with Fuzzy confidence', () {
      final result = findBestMatch<Map<String, dynamic>>(
        source: 'DigiSlove',
        items: pitEvents,
        labelGetter: (e) => e['event_name'] as String,
      );

      expect(result.isMatched, isTrue);
      expect(result.confidence, equals(MatchConfidence.fuzzy));
      expect(result.label, equals('DigiSolve'));
      expect(result.similarity, greaterThanOrEqualTo(0.85));
    });

    test('returns None confidence for unrecognized event names', () {
      final result = findBestMatch<Map<String, dynamic>>(
        source: 'Unknown Tech Fest 2026',
        items: pitEvents,
        labelGetter: (e) => e['event_name'] as String,
      );

      expect(result.isMatched, isFalse);
      expect(result.confidence, equals(MatchConfidence.none));
    });
  });
}
