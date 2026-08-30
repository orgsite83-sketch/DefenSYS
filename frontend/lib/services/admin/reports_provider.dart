import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../../utils/csv_file_io.dart'; // Contains our downloadBinaryFile utility

final reportsProvider = NotifierProvider<ReportsNotifier, ReportsState>(
  ReportsNotifier.new,
);

class ReportPreviewData {
  final String title;
  final String subtitle;
  final String generatedAt;
  final List<Map<String, dynamic>> summaryKpis;
  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final int totalRows;

  const ReportPreviewData({
    required this.title,
    required this.subtitle,
    required this.generatedAt,
    required this.summaryKpis,
    required this.columns,
    required this.rows,
    required this.totalRows,
  });

  factory ReportPreviewData.fromJson(Map<String, dynamic> json) {
    final kpis = <Map<String, dynamic>>[];
    if (json['summary_kpis'] is List) {
      for (final item in json['summary_kpis'] as List) {
        if (item is Map) kpis.add(Map<String, dynamic>.from(item));
      }
    }

    final cols = <Map<String, dynamic>>[];
    if (json['columns'] is List) {
      for (final item in json['columns'] as List) {
        if (item is Map) cols.add(Map<String, dynamic>.from(item));
      }
    }

    final rws = <Map<String, dynamic>>[];
    if (json['rows'] is List) {
      for (final item in json['rows'] as List) {
        if (item is Map) rws.add(Map<String, dynamic>.from(item));
      }
    }

    return ReportPreviewData(
      title: json['title']?.toString() ?? 'Report Preview',
      subtitle: json['subtitle']?.toString() ?? '',
      generatedAt: json['generated_at']?.toString() ?? '',
      summaryKpis: kpis,
      columns: cols,
      rows: rws,
      totalRows: (json['total_rows'] as num?)?.toInt() ?? rws.length,
    );
  }
}

class ReportsState {
  final bool isLoading;
  final bool isPreviewLoading;
  final String? error;
  final bool isSuccess;
  final ReportPreviewData? previewData;

  const ReportsState({
    this.isLoading = false,
    this.isPreviewLoading = false,
    this.error,
    this.isSuccess = false,
    this.previewData,
  });

  ReportsState copyWith({
    bool? isLoading,
    bool? isPreviewLoading,
    String? error,
    bool clearError = false,
    bool? isSuccess,
    ReportPreviewData? previewData,
    bool clearPreview = false,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      isPreviewLoading: isPreviewLoading ?? this.isPreviewLoading,
      error: clearError ? null : error ?? this.error,
      isSuccess: isSuccess ?? this.isSuccess,
      previewData: clearPreview ? null : (previewData ?? this.previewData),
    );
  }
}

class ReportsNotifier extends Notifier<ReportsState> {
  @override
  ReportsState build() => const ReportsState();

  /// Fetches live structured dataset for in-modal preview
  Future<ReportPreviewData?> fetchReportPreview({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    state = state.copyWith(isPreviewLoading: true, clearError: true);

    final params = Map<String, String>.from(queryParams);
    params['export_format'] = 'json';

    final uri = Uri.parse('${ApiConfig.baseUrl}/reports/$endpoint').replace(
      queryParameters: params.isEmpty ? null : params,
    );

    try {
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = 'Unable to fetch report preview.';
        try {
          final bodyJson = jsonDecode(response.body);
          if (bodyJson is Map && bodyJson['detail'] != null) {
            detail = bodyJson['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }

      final bodyJson = jsonDecode(utf8.decode(response.bodyBytes));
      if (bodyJson is Map<String, dynamic>) {
        final preview = ReportPreviewData.fromJson(bodyJson);
        state = state.copyWith(isPreviewLoading: false, previewData: preview);
        return preview;
      }

      throw Exception('Malformed preview response.');
    } catch (e) {
      state = state.copyWith(
        isPreviewLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return null;
    }
  }

  /// Downloads report in requested format (PDF, CSV, XLSX, DOC)
  Future<bool> downloadReport({
    required String endpoint, // e.g., 'team-grade/1/', 'semester-grades/'
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf', // 'pdf', 'csv', 'xlsx', 'doc'
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, isSuccess: false);

    final params = Map<String, String>.from(queryParams);
    params['export_format'] = exportFormat;

    final uri = Uri.parse('${ApiConfig.baseUrl}/reports/$endpoint').replace(
      queryParameters: params.isEmpty ? null : params,
    );

    try {
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = 'Unable to generate export.';
        try {
          final bodyJson = jsonDecode(response.body);
          if (bodyJson is Map && bodyJson['detail'] != null) {
            detail = bodyJson['detail'].toString();
          }
        } catch (_) {
          final body = response.body;
          if (body.contains('detail')) {
            final RegExp reg = RegExp(r'"detail"\s*:\s*"([^"]+)"');
            final match = reg.firstMatch(body);
            if (match != null && match.groupCount >= 1) {
              detail = match.group(1)!;
            }
          }
        }
        throw Exception(detail);
      }

      // Parse filename from Content-Disposition header if available
      String filename = defaultFilename;
      final cd = response.headers['content-disposition'];
      if (cd != null && cd.contains('filename=')) {
        final regExp = RegExp(r'filename="([^"]+)"');
        final match = regExp.firstMatch(cd);
        if (match != null && match.groupCount >= 1) {
          filename = match.group(1)!;
        } else {
          final regExpNoQuote = RegExp(r'filename=([^;]+)');
          final matchNoQuote = regExpNoQuote.firstMatch(cd);
          if (matchNoQuote != null && matchNoQuote.groupCount >= 1) {
            filename = matchNoQuote.group(1)!.trim();
          }
        }
      } else {
        // Enforce extension based on format
        final ext = exportFormat == 'xlsx'
            ? '.xlsx'
            : exportFormat == 'csv'
                ? '.csv'
                : exportFormat == 'doc' || exportFormat == 'docx'
                    ? '.doc'
                    : '.pdf';
        if (!filename.toLowerCase().endsWith(ext)) {
          filename = '${filename.replaceAll(RegExp(r'\.(pdf|csv|xlsx|doc|docx)$', caseSensitive: false), '')}$ext';
        }
      }

      String mimeType;
      switch (exportFormat.toLowerCase()) {
        case 'csv':
          mimeType = 'text/csv;charset=utf-8';
          break;
        case 'xlsx':
        case 'excel':
          mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
        case 'doc':
        case 'docx':
        case 'word':
          mimeType = 'application/msword';
          break;
        case 'pdf':
        default:
          mimeType = 'application/pdf';
          break;
      }

      final bytes = response.bodyBytes;
      await downloadBinaryFile(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );

      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }
}
