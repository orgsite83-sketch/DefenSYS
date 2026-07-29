import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/widgets/feedback_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class RepositoryUploadDialogs {
  static List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }

  static List<String> _pendingSuggestedFileNames(RepositoryAuditState state) {
    final queue = state.uploadWindow['queue'];
    if (queue is! List) {
      return const [];
    }
    return queue
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((row) => row['archive_status'] == 'pending')
        .map((row) => row['suggested_file_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static List<String> _pendingCapstoneSuggestedFileNames(
      RepositoryAuditState state) {
    final queue = state.capstoneUploadWindow['queue'];
    if (queue is! List) {
      return const [];
    }
    return queue
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .map((row) => row['suggested_file_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static String _pitFilenameExample(String yearLevel) {
    switch (yearLevel) {
      case '1st Year':
        return '1stYear.PIT101.ProjectTitle.1stSemester.pdf';
      case '2nd Year':
        return '2ndYear.PIT201.ProjectTitle.1stSemester.pdf';
      default:
        return '3rdYear.PIT301.ProjectTitle.1stSemester.pdf';
    }
  }

  static Future<void> showUploadSkippedDialog(
    BuildContext context,
    UploadPitResult result,
  ) async {
    final lines = result.skipped
        .map((item) {
          final name = item['file_name']?.toString() ?? 'File';
          final reason = item['reason']?.toString() ?? 'Unknown reason';
          return '$name\n$reason';
        })
        .join('\n\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.savedAny ? 'Some files were not saved' : 'Upload failed',
        ),
        content: SingleChildScrollView(child: Text(lines)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Future<void> showUploadDialog({
    required BuildContext context,
    required WidgetRef ref,
    required RepositoryAuditState state,
  }) async {
    final yearLevel =
        state.scope['pit_year_level']?.toString().isNotEmpty == true
            ? state.scope['pit_year_level'].toString()
            : '3rd Year';
    final academicYear = state.academicYear.isNotEmpty
        ? state.academicYear
        : (_stringList(state.options['academic_years']).isNotEmpty
            ? _stringList(state.options['academic_years']).first
            : '');
    final pendingNames = _pendingSuggestedFileNames(state);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload PIT PDF'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Each PDF must use this exact pattern (no spaces):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _pitFilenameExample(yearLevel),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF374151),
                ),
              ),
              if (pendingNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Use these names from the upload queue:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...pendingNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
              if (pendingNames.length == 1) ...[
                const SizedBox(height: 10),
                const Text(
                  'A single PDF will be renamed automatically to the queue filename.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose Files'),
          ),
        ],
      ),
    );
    if (!context.mounted || proceed != true) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'mp4',
        'mov',
        'avi',
        'mkv',
        'zip',
        'rar',
        '7z',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'csv'
      ],
      allowMultiple: true,
      withData: true,
    );
    if (!context.mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final autoRename = pendingNames.length == 1 && picked.files.length == 1
        ? pendingNames.first
        : null;

    const allowedExts = [
      'pdf',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'zip',
      'rar',
      '7z',
      'doc',
      'docx',
      'ppt',
      'pptx',
      'xls',
      'xlsx',
      'csv'
    ];
    bool isAllowedFile(String name) {
      final ext = name.split('.').last.toLowerCase();
      return allowedExts.contains(ext);
    }

    final multipartFiles = <http.MultipartFile>[];
    for (final platformFile in picked.files) {
      final bytes = platformFile.bytes;
      final originalName = platformFile.name;
      if (bytes == null || !isAllowedFile(originalName)) {
        continue;
      }
      final uploadName = autoRename ?? originalName;
      multipartFiles.add(
        http.MultipartFile.fromBytes('files', bytes, filename: uploadName),
      );
    }

    if (multipartFiles.isEmpty) {
      if (context.mounted) {
        showValidationToast(context, 'Select at least one valid file.');
      }
      return;
    }

    final result = await ref
        .read(repositoryAuditProvider.notifier)
        .uploadPit(
          multipartFiles: multipartFiles,
          yearLevel: yearLevel,
          academicYear: academicYear,
        );
    if (!context.mounted) {
      return;
    }
    if (result.skipped.isNotEmpty) {
      await showUploadSkippedDialog(context, result);
    }
  }

  static Future<void> showCapstoneUploadDialog({
    required BuildContext context,
    required WidgetRef ref,
    required RepositoryAuditState state,
  }) async {
    final academicYear = state.academicYear.isNotEmpty
        ? state.academicYear
        : (_stringList(state.options['academic_years']).isNotEmpty
            ? _stringList(state.options['academic_years']).first
            : '');
    final pendingNames = _pendingCapstoneSuggestedFileNames(state);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload Capstone PDF'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Each PDF must use this exact pattern (no spaces):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '3rdYear.CAP301.ProjectTitle.1stSemester.pdf',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF374151),
                ),
              ),
              if (pendingNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Use these names from the upload queue:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...pendingNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
              if (pendingNames.length == 1) ...[
                const SizedBox(height: 10),
                const Text(
                  'A single PDF will be renamed automatically to the queue filename.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose Files'),
          ),
        ],
      ),
    );
    if (!context.mounted || proceed != true) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'mp4',
        'mov',
        'avi',
        'mkv',
        'zip',
        'rar',
        '7z',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'csv'
      ],
      allowMultiple: true,
      withData: true,
    );
    if (!context.mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final autoRename = pendingNames.length == 1 && picked.files.length == 1
        ? pendingNames.first
        : null;

    const allowedExts = [
      'pdf',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'zip',
      'rar',
      '7z',
      'doc',
      'docx',
      'ppt',
      'pptx',
      'xls',
      'xlsx',
      'csv'
    ];
    bool isAllowedFile(String name) {
      final ext = name.split('.').last.toLowerCase();
      return allowedExts.contains(ext);
    }

    final multipartFiles = <http.MultipartFile>[];
    for (final platformFile in picked.files) {
      final bytes = platformFile.bytes;
      final originalName = platformFile.name;
      if (bytes == null || !isAllowedFile(originalName)) {
        continue;
      }
      final uploadName = autoRename ?? originalName;
      multipartFiles.add(
        http.MultipartFile.fromBytes('files', bytes, filename: uploadName),
      );
    }

    if (multipartFiles.isEmpty) {
      if (context.mounted) {
        showValidationToast(context, 'Select at least one valid file.');
      }
      return;
    }

    final result = await ref
        .read(repositoryAuditProvider.notifier)
        .uploadCapstoneMultipart(
          multipartFiles: multipartFiles,
          academicYear: academicYear,
        );
    if (!context.mounted) {
      return;
    }
    if (result.skipped.isNotEmpty) {
      await showUploadSkippedDialog(context, result);
    }
  }
}
