import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// Parsed faculty role information with base role and capability flags.
class ParsedFacultyRoles {
  final String baseRole; // 'admin' | 'faculty' | 'student'
  final bool isPanelist;
  final bool isAdviser;
  final bool isPitLead;
  final String? pitLeadYear;
  final bool isDocumenter;
  final bool isUploader;
  final String rawInput;

  const ParsedFacultyRoles({
    required this.baseRole,
    this.isPanelist = false,
    this.isAdviser = false,
    this.isPitLead = false,
    this.pitLeadYear,
    this.isDocumenter = false,
    this.isUploader = false,
    required this.rawInput,
  });

  /// Display assignments, falling back to the base role for unassigned accounts.
  /// This only affects labels; [baseRole] and upload capability flags stay intact.
  List<FacultyRoleBadge> get badges {
    final list = <FacultyRoleBadge>[];

    if (baseRole == 'admin') {
      list.add(
        const FacultyRoleBadge(
          label: 'Admin',
          bg: DefensysTokens.dangerBg,
          fg: DefensysTokens.maroon,
        ),
      );
      return list;
    }

    if (baseRole == 'student') {
      list.add(
        const FacultyRoleBadge(
          label: 'Student',
          bg: DefensysTokens.dangerBg,
          fg: DefensysTokens.dangerText,
        ),
      );
      return list;
    }

    if (isPitLead) {
      final yearStr = pitLeadYear != null && pitLeadYear!.isNotEmpty
          ? ' · $pitLeadYear'
          : '';
      list.add(
        FacultyRoleBadge(
          label: 'PIT Lead$yearStr',
          bg: DefensysTokens.warningBg,
          fg: DefensysTokens.warningText,
        ),
      );
    }

    if (isPanelist) {
      list.add(
        const FacultyRoleBadge(
          label: 'Panelist',
          bg: DefensysTokens.infoBg,
          fg: DefensysTokens.infoText,
        ),
      );
    }

    if (isAdviser) {
      list.add(
        const FacultyRoleBadge(
          label: 'Adviser',
          bg: DefensysTokens.successBg,
          fg: DefensysTokens.successText,
        ),
      );
    }

    if (isDocumenter) {
      list.add(
        const FacultyRoleBadge(
          label: 'Documenter',
          bg: DefensysTokens.neutralBg,
          fg: DefensysTokens.textSecondary,
        ),
      );
    }

    if (isUploader) {
      list.add(
        const FacultyRoleBadge(
          label: 'Uploader',
          bg: DefensysTokens.revisionBg,
          fg: DefensysTokens.revisionText,
        ),
      );
    }

    if (list.isEmpty) {
      list.add(
        const FacultyRoleBadge(
          label: 'Faculty',
          bg: DefensysTokens.neutralBg,
          fg: DefensysTokens.textSecondary,
        ),
      );
    }

    return list;
  }

  Map<String, dynamic> toMap() {
    return {
      'role': baseRole,
      'is_panelist': isPanelist,
      'is_adviser': isAdviser,
      'is_pit_lead': isPitLead,
      'pit_lead_year': pitLeadYear,
      'is_documenter': isDocumenter,
      'is_uploader': isUploader,
      'raw_role': rawInput,
    };
  }
}

class FacultyRoleBadge {
  final String label;
  final Color bg;
  final Color fg;

  const FacultyRoleBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });
}

/// Parse a raw role string (single or multi-role) into structured capability flags.
ParsedFacultyRoles parseFacultyRoles(String? rawRole) {
  final input = (rawRole ?? '').trim();
  if (input.isEmpty) {
    return ParsedFacultyRoles(baseRole: 'faculty', rawInput: input);
  }

  final lower = input.toLowerCase();

  // If role is explicitly admin
  if (lower.contains('admin')) {
    return ParsedFacultyRoles(baseRole: 'admin', rawInput: input);
  }

  // If role is explicitly student
  if (lower == 'student' || lower.contains('student')) {
    return ParsedFacultyRoles(baseRole: 'student', rawInput: input);
  }

  // Split tokens across comma, slash, semicolon, pipe, ampersand, plus, or newline
  final tokens = input
      .split(RegExp(r'[,/|;&+\n]'))
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  bool isPanelist = false;
  bool isAdviser = false;
  bool isPitLead = false;
  String? pitLeadYear;
  bool isDocumenter = false;
  bool isUploader = false;

  // Check whole string and individual tokens
  for (final token in tokens.isNotEmpty ? tokens : [lower]) {
    if (token.contains('panel')) {
      isPanelist = true;
    }
    if (token.contains('advis')) {
      isAdviser = true;
    }
    if (token.contains('lead') || token.contains('pit')) {
      isPitLead = true;
      final year = _extractYearLevel(token.isNotEmpty ? token : lower);
      if (year != null) {
        pitLeadYear = year;
      }
    }
    if (token.contains('doc') || token.contains('documenter')) {
      isDocumenter = true;
    }
    if (token.contains('upload')) {
      isUploader = true;
    }
  }

  // Also do a fallback scan on the entire input string
  if (lower.contains('panel')) isPanelist = true;
  if (lower.contains('advis')) isAdviser = true;
  if (lower.contains('pit') || lower.contains('lead')) {
    isPitLead = true;
    pitLeadYear ??= _extractYearLevel(lower);
  }
  if (lower.contains('documenter')) isDocumenter = true;
  if (lower.contains('uploader')) isUploader = true;

  return ParsedFacultyRoles(
    baseRole: 'faculty',
    isPanelist: isPanelist,
    isAdviser: isAdviser,
    isPitLead: isPitLead,
    pitLeadYear: isPitLead ? (pitLeadYear ?? '1st Year') : null,
    isDocumenter: isDocumenter,
    isUploader: isUploader,
    rawInput: input,
  );
}

String? _extractYearLevel(String text) {
  final clean = text.toLowerCase();
  if (clean.contains('1st') ||
      clean.contains('first') ||
      clean.contains('year 1') ||
      clean.contains('yr 1') ||
      clean.contains(' 1')) {
    return '1st Year';
  }
  if (clean.contains('2nd') ||
      clean.contains('second') ||
      clean.contains('year 2') ||
      clean.contains('yr 2') ||
      clean.contains(' 2')) {
    return '2nd Year';
  }
  if (clean.contains('3rd') ||
      clean.contains('third') ||
      clean.contains('year 3') ||
      clean.contains('yr 3') ||
      clean.contains(' 3')) {
    return '3rd Year';
  }
  if (clean.contains('4th') ||
      clean.contains('fourth') ||
      clean.contains('year 4') ||
      clean.contains('yr 4') ||
      clean.contains(' 4')) {
    return '4th Year';
  }
  return null;
}
