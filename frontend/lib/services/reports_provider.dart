import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'authenticated_client.dart';
import '../utils/csv_file_io.dart'; // Contains our downloadBinaryFile utility

final reportsProvider = NotifierProvider<ReportsNotifier, ReportsState>(
  ReportsNotifier.new,
);

class ReportsState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  const ReportsState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
  });

  ReportsState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isSuccess,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class ReportsNotifier extends Notifier<ReportsState> {
  @override
  ReportsState build() => const ReportsState();

  Future<bool> downloadReport({
    required String endpoint, // e.g., 'team-grade/1/', 'semester-grades/'
    required Map<String, String> queryParams,
    required String defaultFilename,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, isSuccess: false);
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/reports/$endpoint').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    
    try {
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Attempt to parse error detail from body
        String detail = 'Unable to generate PDF report.';
        try {
          final body = response.body;
          if (body.contains('detail')) {
            // Very simple fallback parser for JSON error detail
            final RegExp reg = RegExp(r'"detail"\s*:\s*"([^"]+)"');
            final match = reg.firstMatch(body);
            if (match != null && match.groupCount >= 1) {
              detail = match.group(1)!;
            }
          }
        } catch (_) {}
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
          // Alternative layout without quotes
          final regExpNoQuote = RegExp(r'filename=([^;]+)');
          final matchNoQuote = regExpNoQuote.firstMatch(cd);
          if (matchNoQuote != null && matchNoQuote.groupCount >= 1) {
            filename = matchNoQuote.group(1)!.trim();
          }
        }
      }
      
      final bytes = response.bodyBytes;
      await downloadBinaryFile(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }
}
