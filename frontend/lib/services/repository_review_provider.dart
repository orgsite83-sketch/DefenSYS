import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import 'network/authenticated_client.dart';
import 'admin/repository_provider.dart';
import '../models/repository_library.dart';
import 'auth_provider.dart';

class LibraryActivityPayload {
  const LibraryActivityPayload({
    this.recent = const [],
    this.saved = const [],
    this.activity = const [],
  });
  final List<VaultEntry> recent;
  final List<VaultEntry> saved;
  final List<Map<String, dynamic>> activity;
  factory LibraryActivityPayload.fromJson(Map<String, dynamic> json) {
    List<VaultEntry> entries(String key) => (json[key] as List? ?? [])
        .whereType<Map>()
        .map((entry) => VaultEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    return LibraryActivityPayload(
      recent: entries('recent'),
      saved: entries('saved'),
      activity: (json['activity'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }
}

final repositoryLibraryActivityProvider =
    FutureProvider<LibraryActivityPayload>((ref) {
      final user = ref.watch(authProvider.select((state) => state.user?['id']));
      if (user == null) return const LibraryActivityPayload();
      return _fetchLibraryActivity(ref.watch(authenticatedHttpClientProvider));
    });

Future<LibraryActivityPayload> _fetchLibraryActivity(
  AuthenticatedHttpClient client,
) async {
  final response = await client.get(Uri.parse(ApiConfig.repositoryShelfUrl));
  if (response.statusCode != 200) {
    throw Exception('Could not load your library activity.');
  }
  return LibraryActivityPayload.fromJson(
    Map<String, dynamic>.from(jsonDecode(response.body)),
  );
}

typedef LibrarySearchQuery = ({
  String search,
  String type,
  String year,
  String documentKind,
});
final repositoryLibrarySearchProvider = FutureProvider.autoDispose
    .family<List<VaultEntry>, LibrarySearchQuery>((ref, query) async {
      final client = ref.watch(authenticatedHttpClientProvider);
      final uri = Uri.parse(ApiConfig.repositoryUrl).replace(
        queryParameters: {
          if (query.search.isNotEmpty) 'search': query.search,
          if (query.type.isNotEmpty) 'type': query.type,
          if (query.year.isNotEmpty) 'academic_year': query.year,
          if (query.documentKind.isNotEmpty)
            'document_kind': query.documentKind,
        },
      );
      final response = await client.get(uri);
      if (response.statusCode != 200) {
        throw Exception(
          'Could not search the library (${response.statusCode}).',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['entries'] as List? ?? [])
          .whereType<Map>()
          .map((entry) => VaultEntry.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    });

class ReviewItem {
  final int id;
  final int userId;
  final String userName;
  final String userRole;
  final int rating;
  final String remark;
  final String createdAt;
  final String updatedAt;
  final bool isOwner;

  const ReviewItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.rating,
    required this.remark,
    required this.createdAt,
    required this.updatedAt,
    this.isOwner = false,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
    id: j['id'] is int
        ? j['id']
        : int.tryParse(j['id']?.toString() ?? '0') ?? 0,
    userId: j['user_id'] is int
        ? j['user_id']
        : int.tryParse(j['user_id']?.toString() ?? '0') ?? 0,
    userName: j['user_name']?.toString() ?? 'Anonymous Student',
    userRole: j['user_role']?.toString() ?? 'Student',
    rating: j['rating'] is int
        ? j['rating']
        : int.tryParse(j['rating']?.toString() ?? '5') ?? 5,
    remark: j['remark']?.toString() ?? '',
    createdAt: j['created_at']?.toString() ?? '',
    updatedAt: j['updated_at']?.toString() ?? '',
    isOwner: j['is_owner'] == true,
  );
}

class ReviewsPayload {
  final String targetId;
  final double averageRating;
  final int ratingsCount;
  final int reviewsCount;
  final Map<int, int> distribution;
  final ReviewItem? userReview;
  final List<ReviewItem> reviews;

  const ReviewsPayload({
    required this.targetId,
    required this.averageRating,
    required this.ratingsCount,
    required this.reviewsCount,
    required this.distribution,
    this.userReview,
    required this.reviews,
  });

  factory ReviewsPayload.fromJson(Map<String, dynamic> j) {
    final distMap = <int, int>{};
    if (j['distribution'] is Map) {
      (j['distribution'] as Map).forEach((k, v) {
        final key = int.tryParse(k.toString()) ?? 0;
        final val = int.tryParse(v.toString()) ?? 0;
        if (key > 0) distMap[key] = val;
      });
    }

    final rawReviews =
        (j['reviews'] as List?)
            ?.map((r) => ReviewItem.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        [];

    ReviewItem? userRev;
    if (j['user_review'] is Map) {
      userRev = ReviewItem.fromJson(
        Map<String, dynamic>.from(j['user_review']),
      );
    }

    return ReviewsPayload(
      targetId: j['target_id']?.toString() ?? '',
      averageRating: (j['average_rating'] is num)
          ? (j['average_rating'] as num).toDouble()
          : double.tryParse(j['average_rating']?.toString() ?? '0.0') ?? 0.0,
      ratingsCount: j['ratings_count'] is int
          ? j['ratings_count']
          : int.tryParse(j['ratings_count']?.toString() ?? '0') ?? 0,
      reviewsCount: j['reviews_count'] is int
          ? j['reviews_count']
          : int.tryParse(j['reviews_count']?.toString() ?? '0') ?? 0,
      distribution: distMap,
      userReview: userRev,
      reviews: rawReviews,
    );
  }
}

class ShelfItem {
  final int id;
  final String targetId;
  final String status;
  final int lastReadPage;
  final int totalPages;
  final double progressPercent;
  final String updatedAt;

  const ShelfItem({
    required this.id,
    required this.targetId,
    required this.status,
    required this.lastReadPage,
    required this.totalPages,
    required this.progressPercent,
    required this.updatedAt,
  });

  factory ShelfItem.fromJson(Map<String, dynamic> j) => ShelfItem(
    id: j['id'] is int
        ? j['id']
        : int.tryParse(j['id']?.toString() ?? '0') ?? 0,
    targetId: j['target_id']?.toString() ?? '',
    status: j['status']?.toString() ?? 'reading',
    lastReadPage: j['last_read_page'] is int
        ? j['last_read_page']
        : int.tryParse(j['last_read_page']?.toString() ?? '1') ?? 1,
    totalPages: j['total_pages'] is int
        ? j['total_pages']
        : int.tryParse(j['total_pages']?.toString() ?? '1') ?? 1,
    progressPercent: (j['progress_percent'] is num)
        ? (j['progress_percent'] as num).toDouble()
        : double.tryParse(j['progress_percent']?.toString() ?? '0.0') ?? 0.0,
    updatedAt: j['updated_at']?.toString() ?? '',
  );
}

final repositoryReviewServiceProvider = Provider<RepositoryReviewService>((
  ref,
) {
  return RepositoryReviewService(ref);
});

class RepositoryReviewService {
  final Ref _ref;

  RepositoryReviewService(this._ref);

  AuthenticatedHttpClient get _client =>
      _ref.read(authenticatedHttpClientProvider);

  Future<ReviewsPayload?> fetchReviews(String targetId) async {
    try {
      final uri = Uri.parse(
        ApiConfig.repositoryReviewsUrl,
      ).replace(queryParameters: {'target_id': targetId});
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          return ReviewsPayload.fromJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<ReviewsPayload?> submitReview({
    required String targetId,
    required int rating,
    required String remark,
  }) async {
    try {
      final uri = Uri.parse(ApiConfig.repositoryReviewsUrl);
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'target_id': targetId,
          'rating': rating,
          'remark': remark,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          // Trigger silent refresh of repository entries to update aggregate scores
          _ref.read(repositoryProvider.notifier).fetchForStudent();
          _ref.invalidate(repositoryLibraryActivityProvider);
          return ReviewsPayload.fromJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteReview({
    required int reviewId,
    required String targetId,
  }) async {
    try {
      final uri = Uri.parse(ApiConfig.repositoryReviewsUrl);
      final response = await _client.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'review_id': reviewId}),
      );
      if (response.statusCode == 200) {
        _ref.read(repositoryProvider.notifier).fetchForStudent();
        _ref.invalidate(repositoryLibraryActivityProvider);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<List<ShelfItem>> fetchShelf() async {
    try {
      final uri = Uri.parse(ApiConfig.repositoryShelfUrl);
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['items'] is List) {
          return (data['items'] as List)
              .map((i) => ShelfItem.fromJson(Map<String, dynamic>.from(i)))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<ShelfItem?> updateShelfProgress({
    required String targetId,
    String? status,
    int? lastReadPage,
    int? totalPages,
    double? progressPercent,
    bool? isSaved,
    bool opened = false,
  }) async {
    try {
      final uri = Uri.parse(ApiConfig.repositoryShelfUrl);
      final payload = <String, dynamic>{'target_id': targetId};
      if (status != null) payload['status'] = status;
      if (lastReadPage != null) payload['last_read_page'] = lastReadPage;
      if (totalPages != null) payload['total_pages'] = totalPages;
      if (progressPercent != null) {
        payload['progress_percent'] = progressPercent;
      }
      if (isSaved != null) payload['is_saved'] = isSaved;
      if (opened) payload['opened'] = true;

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          _ref.invalidate(repositoryLibraryActivityProvider);
          return ShelfItem.fromJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LibraryActivityPayload> fetchLibraryActivity() async {
    return _fetchLibraryActivity(_client);
  }

  Future<bool> clearReadingHistory() async {
    try {
      final response = await _client.delete(
        Uri.parse(ApiConfig.repositoryShelfUrl),
      );
      if (response.statusCode != 200) return false;
      _ref.invalidate(repositoryLibraryActivityProvider);
      return true;
    } catch (_) {
      return false;
    }
  }
}
