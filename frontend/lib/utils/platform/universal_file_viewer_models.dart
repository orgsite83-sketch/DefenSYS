import 'package:flutter/material.dart';

enum FileCategory {
  pdf,
  video,
  audio,
  image,
  spreadsheet,
  codeOrText,
  officeDoc,
  officePresentation,
  archive,
  other,
}

class FileViewerMetadata {
  static FileCategory detectCategory(String fileName) {
    final lower = fileName.toLowerCase().trim();

    if (lower.endsWith('.pdf')) {
      return FileCategory.pdf;
    }

    // Video
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.ogv')) {
      return FileCategory.video;
    }

    // Audio
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wma')) {
      return FileCategory.audio;
    }

    // Image
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.ico')) {
      return FileCategory.image;
    }

    // Spreadsheet
    if (lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.tsv')) {
      return FileCategory.spreadsheet;
    }

    // Word / Documents
    if (lower.endsWith('.docx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.rtf') ||
        lower.endsWith('.odt')) {
      return FileCategory.officeDoc;
    }

    // Presentations
    if (lower.endsWith('.pptx') ||
        lower.endsWith('.ppt') ||
        lower.endsWith('.odp')) {
      return FileCategory.officePresentation;
    }

    // Archives
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz')) {
      return FileCategory.archive;
    }

    // Code & Text
    if (lower.endsWith('.txt') ||
        lower.endsWith('.json') ||
        lower.endsWith('.sql') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.py') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.html') ||
        lower.endsWith('.css') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.log') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.bat')) {
      return FileCategory.codeOrText;
    }

    return FileCategory.other;
  }

  static String getMimeType(String fileName) {
    final lower = fileName.toLowerCase().trim();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.csv')) return 'text/csv;charset=utf-8';
    if (lower.endsWith('.tsv')) return 'text/tab-separated-values';
    if (lower.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.pptx')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt') || lower.endsWith('.log')) return 'text/plain;charset=utf-8';
    return 'application/octet-stream';
  }

  static Color getCategoryColor(FileCategory category) {
    switch (category) {
      case FileCategory.pdf:
        return const Color(0xFFEF4444); // Red
      case FileCategory.video:
        return const Color(0xFF8B5CF6); // Purple / Violet
      case FileCategory.audio:
        return const Color(0xFFF43F5E); // Rose
      case FileCategory.image:
        return const Color(0xFF06B6D4); // Cyan / Teal
      case FileCategory.spreadsheet:
        return const Color(0xFF10B981); // Emerald / Forest
      case FileCategory.codeOrText:
        return const Color(0xFFF59E0B); // Amber
      case FileCategory.officeDoc:
        return const Color(0xFF2563EB); // Royal Blue
      case FileCategory.officePresentation:
        return const Color(0xFFEA580C); // Warm Orange
      case FileCategory.archive:
        return const Color(0xFF64748B); // Slate
      case FileCategory.other:
        return const Color(0xFF6B7280); // Gray
    }
  }

  static IconData getCategoryIcon(FileCategory category) {
    switch (category) {
      case FileCategory.pdf:
        return Icons.picture_as_pdf_outlined;
      case FileCategory.video:
        return Icons.video_library_outlined;
      case FileCategory.audio:
        return Icons.audiotrack_outlined;
      case FileCategory.image:
        return Icons.image_outlined;
      case FileCategory.spreadsheet:
        return Icons.table_chart_outlined;
      case FileCategory.codeOrText:
        return Icons.code_outlined;
      case FileCategory.officeDoc:
        return Icons.description_outlined;
      case FileCategory.officePresentation:
        return Icons.slideshow_outlined;
      case FileCategory.archive:
        return Icons.folder_zip_outlined;
      case FileCategory.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  static String getCategoryLabel(FileCategory category, String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final ext = dotIndex != -1 ? fileName.substring(dotIndex + 1).toUpperCase() : '';

    switch (category) {
      case FileCategory.pdf:
        return 'PDF DOCUMENT';
      case FileCategory.video:
        return ext.isNotEmpty ? '$ext VIDEO' : 'VIDEO';
      case FileCategory.audio:
        return ext.isNotEmpty ? '$ext AUDIO' : 'AUDIO';
      case FileCategory.image:
        return ext.isNotEmpty ? '$ext IMAGE' : 'IMAGE';
      case FileCategory.spreadsheet:
        return ext.isNotEmpty ? '$ext SPREADSHEET' : 'SPREADSHEET';
      case FileCategory.codeOrText:
        return ext.isNotEmpty ? '$ext FILE' : 'TEXT DOCUMENT';
      case FileCategory.officeDoc:
        return 'WORD DOCUMENT';
      case FileCategory.officePresentation:
        return 'PRESENTATION';
      case FileCategory.archive:
        return 'ARCHIVE';
      case FileCategory.other:
        return ext.isNotEmpty ? '$ext FILE' : 'FILE';
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }
}

class DeliverableFormatInfo {
  final String label;
  final IconData icon;
  final Color color;
  final List<String> extensions;
  final String description;

  const DeliverableFormatInfo({
    required this.label,
    required this.icon,
    required this.color,
    required this.extensions,
    required this.description,
  });

  static DeliverableFormatInfo fromFormat(String? format) {
    switch ((format ?? 'any').toLowerCase()) {
      case 'pdf':
        return const DeliverableFormatInfo(
          label: 'PDF Document',
          icon: Icons.picture_as_pdf_outlined,
          color: Color(0xFFDC2626),
          extensions: ['pdf'],
          description: 'PDF Document (*.pdf)',
        );
      case 'video':
        return const DeliverableFormatInfo(
          label: 'Video',
          icon: Icons.videocam_outlined,
          color: Color(0xFF7C3AED),
          extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
          description: 'Video (*.mp4, *.mov, *.webm, *.avi)',
        );
      case 'image':
        return const DeliverableFormatInfo(
          label: 'Image',
          icon: Icons.image_outlined,
          color: Color(0xFF0284C7),
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'],
          description: 'Image (*.png, *.jpg, *.webp, *.gif)',
        );
      case 'presentation':
        return const DeliverableFormatInfo(
          label: 'Presentation',
          icon: Icons.slideshow_outlined,
          color: Color(0xFFD97706),
          extensions: ['pptx', 'ppt', 'pdf'],
          description: 'Presentation (*.pptx, *.ppt, *.pdf)',
        );
      case 'document':
        return const DeliverableFormatInfo(
          label: 'Document',
          icon: Icons.description_outlined,
          color: Color(0xFF2563EB),
          extensions: ['docx', 'doc', 'pdf', 'txt', 'rtf', 'odt'],
          description: 'Document (*.docx, *.doc, *.pdf)',
        );
      case 'spreadsheet':
        return const DeliverableFormatInfo(
          label: 'Spreadsheet',
          icon: Icons.table_chart_outlined,
          color: Color(0xFF059669),
          extensions: ['xlsx', 'xls', 'csv'],
          description: 'Spreadsheet (*.xlsx, *.xls, *.csv)',
        );
      case 'archive':
        return const DeliverableFormatInfo(
          label: 'Archive',
          icon: Icons.folder_zip_outlined,
          color: Color(0xFFEA580C),
          extensions: ['zip', 'rar', '7z', 'tar', 'gz'],
          description: 'Archive (*.zip, *.rar, *.7z)',
        );
      case 'audio':
        return const DeliverableFormatInfo(
          label: 'Audio',
          icon: Icons.audiotrack_outlined,
          color: Color(0xFF9333EA),
          extensions: ['mp3', 'wav', 'aac', 'ogg', 'm4a', 'flac'],
          description: 'Audio (*.mp3, *.wav, *.ogg, *.m4a)',
        );
      case 'any':
      default:
        return const DeliverableFormatInfo(
          label: 'Any File Format',
          icon: Icons.insert_drive_file_outlined,
          color: Color(0xFF64748B),
          extensions: [
            'pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg',
            'mp4', 'mov', 'avi', 'mkv', 'webm', 'mp3', 'wav',
            'zip', 'rar', '7z', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'csv', 'txt'
          ],
          description: 'Any standard format (PDF, media, office, zip)',
        );
    }
  }
}

