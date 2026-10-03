import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/import/faculty_role_parser.dart';

void main() {
  group('parseFacultyRoles', () {
    test('parses plain faculty', () {
      final res = parseFacultyRoles('faculty');
      expect(res.baseRole, 'faculty');
      expect(res.isPanelist, false);
      expect(res.isAdviser, false);
      expect(res.isPitLead, false);
      expect(res.badges.length, 1);
      expect(res.badges.first.label, 'Faculty');
    });

    test('parses admin', () {
      final res = parseFacultyRoles('Admin');
      expect(res.baseRole, 'admin');
      expect(res.badges.length, 1);
      expect(res.badges.first.label, 'Admin');
    });

    test('parses panelist single role', () {
      final res = parseFacultyRoles('Panelist');
      expect(res.baseRole, 'faculty');
      expect(res.isPanelist, true);
      expect(res.isAdviser, false);
      expect(res.badges.map((b) => b.label), ['Panelist']);
    });

    test('parses multi-role with comma: Panelist, Adviser', () {
      final res = parseFacultyRoles('Panelist, Adviser');
      expect(res.baseRole, 'faculty');
      expect(res.isPanelist, true);
      expect(res.isAdviser, true);
      expect(res.isPitLead, false);
      expect(res.badges.map((b) => b.label), ['Panelist', 'Adviser']);
    });

    test('parses PIT Lead with year level and slash separator', () {
      final res = parseFacultyRoles('PIT Lead 1st Year / Panelist');
      expect(res.baseRole, 'faculty');
      expect(res.isPitLead, true);
      expect(res.pitLeadYear, '1st Year');
      expect(res.isPanelist, true);
      expect(res.badges.map((b) => b.label), [
        'PIT Lead · 1st Year',
        'Panelist',
      ]);
    });

    test('parses PIT Lead with 3rd year and ampersand', () {
      final res = parseFacultyRoles('PIT Lead - 3rd Year & Adviser');
      expect(res.baseRole, 'faculty');
      expect(res.isPitLead, true);
      expect(res.pitLeadYear, '3rd Year');
      expect(res.isAdviser, true);
    });

    test('parses student role', () {
      final res = parseFacultyRoles('student');
      expect(res.baseRole, 'student');
      expect(res.badges.length, 1);
      expect(res.badges.first.label, 'Student');
    });

    test('parses empty or whitespace string as base faculty', () {
      final res = parseFacultyRoles('');
      expect(res.baseRole, 'faculty');
      expect(res.isPanelist, false);
      expect(res.isAdviser, false);
    });

    test('displaying assignments retains faculty in the upload payload', () {
      final res = parseFacultyRoles('PIT Lead 2nd Year / Panelist / Adviser');
      expect(res.badges.map((b) => b.label), [
        'PIT Lead · 2nd Year',
        'Panelist',
        'Adviser',
      ]);
      final payload = res.toMap();
      expect(payload['role'], 'faculty');
      expect(payload['is_pit_lead'], true);
      expect(payload['pit_lead_year'], '2nd Year');
      expect(payload['is_panelist'], true);
      expect(payload['is_adviser'], true);
      expect(payload['raw_role'], 'PIT Lead 2nd Year / Panelist / Adviser');
    });
  });
}
