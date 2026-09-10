import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';

/// Single Signatory representation for report certification blocks.
class DefensysSignatory {
  final String label;
  final String name;
  final String role;

  const DefensysSignatory({
    required this.label,
    required this.name,
    required this.role,
  });

  DefensysSignatory copyWith({
    String? label,
    String? name,
    String? role,
  }) {
    return DefensysSignatory(
      label: label ?? this.label,
      name: name ?? this.name,
      role: role ?? this.role,
    );
  }

  Map<String, String> toJson() {
    return {
      'label': label,
      'name': name,
      'role': role,
    };
  }

  factory DefensysSignatory.fromJson(Map<String, dynamic> json) {
    return DefensysSignatory(
      label: (json['label'] ?? 'Prepared by:').toString(),
      name: (json['name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
    );
  }
}

/// Metadata descriptor for available export file formats.
class DefensysExportFormat {
  final String id;
  final String label;
  final String ext;
  final IconData icon;
  final Color color;

  const DefensysExportFormat({
    required this.id,
    required this.label,
    required this.ext,
    required this.icon,
    required this.color,
  });

  static const pdf = DefensysExportFormat(
    id: 'pdf',
    label: 'PDF Document',
    ext: '.pdf',
    icon: Icons.picture_as_pdf_outlined,
    color: DefensysTokens.maroon,
  );

  static const xlsx = DefensysExportFormat(
    id: 'xlsx',
    label: 'Excel Spreadsheet',
    ext: '.xlsx',
    icon: Icons.table_view_rounded,
    color: Color(0xFF16A34A),
  );

  static const csv = DefensysExportFormat(
    id: 'csv',
    label: 'CSV File',
    ext: '.csv',
    icon: Icons.grid_on_rounded,
    color: Color(0xFF2563EB),
  );

  static const doc = DefensysExportFormat(
    id: 'doc',
    label: 'Word Document',
    ext: '.doc',
    icon: Icons.description_outlined,
    color: Color(0xFF0284C7),
  );

  static List<DefensysExportFormat> get all => [pdf, xlsx, csv, doc];

  static DefensysExportFormat fromId(String id) {
    return all.firstWhere(
      (f) => f.id == id.toLowerCase(),
      orElse: () => pdf,
    );
  }
}

/// Configuration bundle for launching the Centralized DefenSYS Export Dialog.
class DefensysExportConfig {
  /// Header Title (e.g. "CURRICULUM ANALYTICS & DECISION SUPPORT PROPOSAL")
  final String title;

  /// Subtitle description (e.g. "Evidence-Based Academic Improvement Report")
  final String subtitle;

  /// Badge tag text shown next to title (e.g. "EXECUTIVE REPORT", "ACADEMIC AUDIT")
  final String tag;

  /// Leading icon in modal header
  final IconData icon;

  /// Default downloaded filename without extension
  final String defaultFilename;

  /// Supported formats (e.g. ['pdf', 'xlsx', 'csv', 'doc'] or ['pdf', 'doc'])
  final List<String> supportedFormats;

  /// Default format selected initially
  final String initialFormat;

  /// Initial list of signatories
  final List<DefensysSignatory> initialSignatories;

  /// Whether signatures can be toggled and customized
  final bool allowSignatoryCustomization;

  /// Initial state of include signatures toggle
  final bool initialIncludeSignatures;

  /// Initial query/filter parameters
  final Map<String, String> initialParams;

  /// Callback to fetch structured live preview data for the right pane / main pane
  final Future<ReportPreviewData?> Function(Map<String, String> currentParams) onFetchPreview;

  /// Callback triggered when user clicks "Download Export"
  final Future<bool> Function(
    Map<String, String> currentParams,
    String format,
    List<DefensysSignatory> signatories,
    bool includeSignatures,
  ) onDownload;

  /// Optional builder for Left Filter / Selector Pane (enables 2-pane Master-Detail Mode)
  final Widget Function(
    BuildContext context,
    Map<String, String> currentParams,
    void Function(Map<String, String> updatedParams) updateParams,
    VoidCallback refreshPreview,
  )? leftPaneBuilder;

  /// Width of the left pane if leftPaneBuilder is provided
  final double leftPaneWidth;

  const DefensysExportConfig({
    required this.title,
    required this.subtitle,
    this.tag = 'OFFICIAL RECORD',
    this.icon = Icons.file_download_outlined,
    required this.defaultFilename,
    this.supportedFormats = const ['pdf', 'xlsx', 'csv', 'doc'],
    this.initialFormat = 'pdf',
    this.initialSignatories = const [],
    this.allowSignatoryCustomization = true,
    this.initialIncludeSignatures = true,
    this.initialParams = const {},
    required this.onFetchPreview,
    required this.onDownload,
    this.leftPaneBuilder,
    this.leftPaneWidth = 380,
  });
}
