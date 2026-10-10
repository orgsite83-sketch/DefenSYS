import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../auth_provider.dart';
import '../authenticated_client.dart';

final panelistRequestsProvider = NotifierProvider.autoDispose
    .family<PanelistRequestsNotifier, PanelistRequestsState, String>(
      PanelistRequestsNotifier.new,
    );

class PanelistRequestsState {
  const PanelistRequestsState({
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.total = 0,
    this.pending = 0,
    this.reviewed = 0,
    this.nextPage,
    this.search = '',
    this.error,
  });
  final List<Map<String, dynamic>> items;
  final bool loading, loadingMore;
  final int total, pending, reviewed;
  final int? nextPage;
  final String search;
  final String? error;
}

class PanelistRequestsNotifier extends Notifier<PanelistRequestsState> {
  PanelistRequestsNotifier(this.selection);
  final String selection;
  int _epoch = 0, _request = 0;
  @override
  PanelistRequestsState build() {
    final userId = ref.watch(authProvider.select((s) => s.user?['id']));
    final epoch = ++_epoch;
    if (userId != null) {
      Future.microtask(() {
        if (ref.mounted && epoch == _epoch) fetch();
      });
    }
    return PanelistRequestsState(loading: userId != null);
  }

  Future<void> fetch({String? search, bool more = false}) async {
    if (ref.read(authProvider).user?['id'] == null) return;
    if (more &&
        (state.nextPage == null || state.loading || state.loadingMore)) {
      return;
    }
    final query = search ?? state.search;
    final page = more ? state.nextPage! : 1;
    final previous = state;
    final epoch = _epoch, request = ++_request;
    state = PanelistRequestsState(
      items: query == previous.search ? previous.items : [],
      loading: !more,
      loadingMore: more,
      total: previous.total,
      pending: previous.pending,
      reviewed: previous.reviewed,
      search: query,
      nextPage: previous.nextPage,
    );
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse('${ApiConfig.usersUrl}/panelist-requests/').replace(
              queryParameters: {
                'status': selection,
                'page': '$page',
                if (query.isNotEmpty) 'search': query,
              },
            ),
          );
      if (!ref.mounted || epoch != _epoch || request != _request) return;
      if (response.statusCode != 200) throw Exception('Request failed');
      final data = jsonDecode(response.body) as Map;
      final incoming = List<Map<String, dynamic>>.from(
        data['panelist_requests'] ?? [],
      );
      final nextPage = data['next'] == null
          ? null
          : int.tryParse(Uri.parse(data['next']).queryParameters['page'] ?? '');
      state = PanelistRequestsState(
        items: <int, Map<String, dynamic>>{
          if (more)
            for (final item in previous.items) item['id'] as int: item,
          for (final item in incoming) item['id'] as int: item,
        }.values.toList(),
        total: data['count'] as int? ?? incoming.length,
        pending: data['pending_count'] as int? ?? 0,
        reviewed: data['reviewed_count'] as int? ?? 0,
        nextPage: nextPage,
        search: query,
      );
    } catch (_) {
      if (ref.mounted && epoch == _epoch && request == _request) {
        state = PanelistRequestsState(
          items: state.items,
          total: previous.total,
          pending: previous.pending,
          reviewed: previous.reviewed,
          nextPage: previous.nextPage,
          search: query,
          error: 'Could not load requests. Please try again.',
        );
      }
    }
  }
}
