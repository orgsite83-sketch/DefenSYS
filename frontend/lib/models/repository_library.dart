class VaultEntry {
  final String id;
  final String fileName;
  final String? fileUrl;
  final String teamName;
  final String uploadedBy;
  final String academicYear;
  final String status;
  final String timestamp;
  final String yearLevel;
  final String stage;
  final String type; // 'pit', 'capstone', 'uploader'
  final String? deliverableLabel;
  final String extractedText;
  final List<String> topics;
  final String summary;
  final String category;
  final double averageRating;
  final int ratingsCount;
  final int reviewsCount;
  final int? userRating;
  final String? userRemark;
  final String? shelfStatus;
  final int lastReadPage;
  final int totalPages;
  final double readingProgress;
  final String projectTitle;
  final String projectKey;
  final String teamId;
  final int projectVersion;
  final String documentKind;
  final String documentLabel;
  final String overviewLabel;
  final String overviewText;
  final String overviewSource;
  final int? overviewPage;
  final bool isSaved;
  final String? lastOpenedAt;
  final List<VaultEntry> projectEntries;

  const VaultEntry({
    required this.id,
    required this.fileName,
    this.fileUrl,
    required this.teamName,
    required this.uploadedBy,
    required this.academicYear,
    required this.status,
    required this.timestamp,
    required this.yearLevel,
    required this.stage,
    required this.type,
    this.deliverableLabel,
    this.extractedText = '',
    this.topics = const [],
    this.summary = '',
    this.category = '',
    this.averageRating = 0.0,
    this.ratingsCount = 0,
    this.reviewsCount = 0,
    this.userRating,
    this.userRemark,
    this.shelfStatus,
    this.lastReadPage = 1,
    this.totalPages = 1,
    this.readingProgress = 0.0,
    this.projectTitle = '',
    this.projectKey = '',
    this.teamId = '',
    this.projectVersion = 1,
    this.documentKind = '',
    this.documentLabel = '',
    this.overviewLabel = 'Document excerpt',
    this.overviewText = '',
    this.overviewSource = '',
    this.overviewPage,
    this.isSaved = false,
    this.lastOpenedAt,
    this.projectEntries = const [],
  });

  factory VaultEntry.fromJson(Map<String, dynamic> j) {
    return VaultEntry(
      id: j['id']?.toString() ?? '',
      fileName: (j['file_name'] ?? j['fileName'])?.toString() ?? '',
      fileUrl: j['file_url']?.toString(),
      teamName: (j['team_name'] ?? j['teamName'])?.toString() ?? '—',
      uploadedBy: (j['uploaded_by'] ?? j['uploadedBy'])?.toString() ?? '—',
      academicYear:
          (j['academic_year'] ?? j['academicYear'])?.toString() ?? '—',
      status: j['status']?.toString() ?? 'Approved',
      timestamp: (j['uploaded_at'] ?? j['timestamp'])?.toString() ?? '',
      yearLevel: (j['year_level'] ?? j['yearLevel'])?.toString() ?? '—',
      stage: j['stage']?.toString() ?? '—',
      type: j['type']?.toString() ?? 'pit',
      deliverableLabel: (j['deliverable_label'] ?? j['deliverableLabel'])
          ?.toString(),
      extractedText: j['extracted_text']?.toString() ?? '',
      topics: (j['topics'] as List?)?.map((e) => e.toString()).toList() ?? [],
      summary: j['summary']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      averageRating: (j['average_rating'] is num)
          ? (j['average_rating'] as num).toDouble()
          : double.tryParse(j['average_rating']?.toString() ?? '0.0') ?? 0.0,
      ratingsCount: j['ratings_count'] is int
          ? j['ratings_count']
          : int.tryParse(j['ratings_count']?.toString() ?? '0') ?? 0,
      reviewsCount: j['reviews_count'] is int
          ? j['reviews_count']
          : int.tryParse(j['reviews_count']?.toString() ?? '0') ?? 0,
      userRating: j['user_rating'] is int
          ? j['user_rating']
          : int.tryParse(j['user_rating']?.toString() ?? ''),
      userRemark: j['user_remark']?.toString(),
      shelfStatus: j['shelf_status']?.toString(),
      lastReadPage: j['last_read_page'] is int
          ? j['last_read_page']
          : int.tryParse(j['last_read_page']?.toString() ?? '1') ?? 1,
      totalPages: j['total_pages'] is int
          ? j['total_pages']
          : int.tryParse(j['total_pages']?.toString() ?? '1') ?? 1,
      readingProgress: (j['reading_progress'] is num)
          ? (j['reading_progress'] as num).toDouble()
          : double.tryParse(j['reading_progress']?.toString() ?? '0.0') ?? 0.0,
      projectTitle:
          (j['display_title'] ?? j['project_title'])?.toString() ?? '',
      projectKey: j['project_key']?.toString() ?? '',
      teamId: j['team_id']?.toString() ?? '',
      projectVersion:
          int.tryParse(j['project_version']?.toString() ?? '1') ?? 1,
      documentKind: j['document_kind']?.toString() ?? '',
      documentLabel: j['document_label']?.toString() ?? '',
      overviewLabel: j['overview_label']?.toString() ?? 'Document excerpt',
      overviewText: j['overview_text']?.toString() ?? '',
      overviewSource: j['overview_source']?.toString() ?? '',
      overviewPage: int.tryParse(j['overview_page']?.toString() ?? ''),
      isSaved: j['is_saved'] == true,
      lastOpenedAt: j['last_opened_at']?.toString(),
      projectEntries: (j['project_entries'] as List? ?? [])
          .whereType<Map>()
          .map((item) => VaultEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  VaultEntry copyWith({
    double? averageRating,
    int? ratingsCount,
    int? reviewsCount,
    int? userRating,
    String? userRemark,
    String? shelfStatus,
    int? lastReadPage,
    int? totalPages,
    double? readingProgress,
  }) {
    return VaultEntry(
      id: id,
      fileName: fileName,
      fileUrl: fileUrl,
      teamName: teamName,
      uploadedBy: uploadedBy,
      academicYear: academicYear,
      status: status,
      timestamp: timestamp,
      yearLevel: yearLevel,
      stage: stage,
      type: type,
      deliverableLabel: deliverableLabel,
      extractedText: extractedText,
      topics: topics,
      summary: summary,
      category: category,
      averageRating: averageRating ?? this.averageRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      userRating: userRating ?? this.userRating,
      userRemark: userRemark ?? this.userRemark,
      shelfStatus: shelfStatus ?? this.shelfStatus,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      totalPages: totalPages ?? this.totalPages,
      readingProgress: readingProgress ?? this.readingProgress,
      projectTitle: projectTitle,
      projectKey: projectKey,
      teamId: teamId,
      projectVersion: projectVersion,
      documentKind: documentKind,
      documentLabel: documentLabel,
      overviewLabel: overviewLabel,
      overviewText: overviewText,
      overviewSource: overviewSource,
      overviewPage: overviewPage,
      isSaved: isSaved,
      lastOpenedAt: lastOpenedAt,
      projectEntries: projectEntries,
    );
  }

  String get extension => fileName.toLowerCase().split('.').last;
  bool get isPdf => extension == 'pdf';
  bool get isImage =>
      const ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension);
  String get outputKind {
    if (documentKind.isNotEmpty) return documentKind;
    if (const ['mp4', 'mov', 'webm', 'm4v', 'avi', 'mkv'].contains(extension)) {
      return 'video';
    }
    final label = '${deliverableLabel ?? ''} $fileName'
        .toLowerCase()
        .replaceAll('_', ' ');
    if (label.contains('poster')) return 'poster';
    if (isImage) return 'other';
    if (label.contains('concept')) return 'concept';
    if (RegExp(r'chapters?\s*1\s*[-–to ]+\s*[23]').hasMatch(label)) {
      return 'chapters';
    }
    if (label.contains('manuscript')) return 'final';
    return const ['pdf', 'docx', 'doc', 'txt', 'odt', 'rtf'].contains(extension)
        ? 'document'
        : 'other';
  }

  bool get isDocument =>
      const ['concept', 'chapters', 'final', 'document'].contains(outputKind);
  String get outputLabel => documentLabel.isNotEmpty
      ? documentLabel
      : switch (outputKind) {
          'concept' => 'Concept Paper',
          'chapters' => 'Chapters 1–3',
          'final' => 'Final Manuscript',
          'poster' => 'Poster',
          'video' => 'Video',
          'document' => 'Document',
          _ => 'Other Output',
        };
  String get displayTitle {
    if (projectTitle.trim().isNotEmpty) return projectTitle.trim();
    final name = fileName
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceAll('_', ' ')
        .trim();
    if (name.isNotEmpty &&
        !RegExp(
          r'approved concept|concept paper|final manuscript',
          caseSensitive: false,
        ).hasMatch(name)) {
      return name;
    }
    return teamName.isNotEmpty && teamName != '—'
        ? teamName
        : 'Research project';
  }

  String get groupingKey => projectKey.isNotEmpty
      ? projectKey
      : teamId.isEmpty
      ? 'entry:$id'
      : '$type:$teamId:$projectVersion:$academicYear';
  String get openLabel => outputKind == 'video'
      ? 'Watch video'
      : outputKind == 'poster'
      ? 'View poster'
      : isDocument
      ? 'Read document'
      : 'Open output';
  String get previewText => overviewText.isNotEmpty
      ? overviewText
      : summary.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

enum LibraryBrowse {
  projects('Projects', ''),
  concept('Concept Papers', 'concept'),
  chapters('Chapters 1–3', 'chapters'),
  finalManuscripts('Final Manuscripts', 'final'),
  documents('All Documents', 'documents'),
  posters('Posters', 'poster'),
  videos('Videos', 'video'),
  other('Other Outputs', 'other');

  const LibraryBrowse(this.label, this.value);
  final String label;
  final String value;
  bool matches(VaultEntry entry) =>
      value.isEmpty ||
      (value == 'documents' ? entry.isDocument : entry.outputKind == value);
}

class LibraryProject {
  LibraryProject(this.key, this.entries);
  final String key;
  final List<VaultEntry> entries;
  VaultEntry get representative => entries.first;
  String get title => representative.displayTitle;
  VaultEntry? get overview {
    final docs = entries
        .where((entry) => entry.isDocument && entry.previewText.isNotEmpty)
        .toList();
    int priority(VaultEntry entry) => switch (entry.outputKind) {
      'final' => 3,
      'chapters' => 2,
      'concept' => 1,
      _ => 0,
    };
    int overviewPriority(VaultEntry entry) =>
        (const [
              'Abstract',
              'Background of the Study',
            ].contains(entry.overviewLabel)
            ? 10
            : 0) +
        priority(entry);
    docs.sort((a, b) => overviewPriority(b).compareTo(overviewPriority(a)));
    return docs.isEmpty ? null : docs.first;
  }

  static List<LibraryProject> group(List<VaultEntry> entries) {
    final groups = <String, List<VaultEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.groupingKey, () => []).add(entry);
    }
    return groups.entries
        .map((group) => LibraryProject(group.key, group.value))
        .toList();
  }
}
