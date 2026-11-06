import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const studentLibraryPath = '/student/library';

bool isStudentLibraryRoute(BuildContext context) =>
    GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path
        .startsWith(studentLibraryPath) ?? false;

/// Library readers live in the student shell, but must also be represented in
/// browser history. Other workspaces can still open the same screens locally.
Future<T?> pushLibraryPage<T>(
  BuildContext context, {
  required String page,
  required WidgetBuilder builder,
  bool fullscreen = false,
}) {
  if (isStudentLibraryRoute(context)) {
    return context.push<T>(
      '$studentLibraryPath/$page',
      extra: LibraryPage(builder),
    );
  }
  return Navigator.of(
    context,
    rootNavigator: fullscreen,
  ).push<T>(MaterialPageRoute(builder: builder));
}

/// Transient reader state is kept in go_router's in-memory history. Reloading
/// an internal reader URL without this state returns to the library safely.
class LibraryPage {
  const LibraryPage(this.builder);
  final WidgetBuilder builder;
}

/// Browser history serializes route extras. Keep transient reader builders in
/// this router session and put only an opaque key in history.state. Reloaded or
/// very old entries have no reader state and safely return to the library.
class LibraryPageCodec extends Codec<Object?, Object?> {
  final _pages = <String, LibraryPage>{};
  int _nextId = 0;
  final _session = DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Converter<Object?, Object?> get encoder => _LibraryPageConverter((value) {
    if (value is! LibraryPage) return {'value': value};
    final existing = _pages.entries.where(
      (item) => identical(item.value, value),
    );
    final key = existing.isNotEmpty
        ? existing.first.key
        : '$_session:${_nextId++}';
    _pages[key] = value;
    while (_pages.length > 128) {
      _pages.remove(_pages.keys.first);
    }
    return {'libraryPage': key};
  });

  @override
  Converter<Object?, Object?> get decoder => _LibraryPageConverter((value) {
    if (value is! Map) return null;
    return value.containsKey('libraryPage')
        ? _pages[value['libraryPage']]
        : value['value'];
  });
}

class _LibraryPageConverter extends Converter<Object?, Object?> {
  const _LibraryPageConverter(this.convertValue);
  final Object? Function(Object?) convertValue;
  @override
  Object? convert(Object? input) => convertValue(input);
}
