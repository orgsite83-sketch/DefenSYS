import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// User-facing message for HTTP errors (403 permission vs other failures).
String friendlyHttpErrorMessage(int statusCode, String body, {AppLocalizations? l10n}) {
  if (statusCode == 403) {
    final decoded = _tryDecodeMap(body);
    final detail = decoded?['detail'] ?? decoded?['error'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    return l10n?.errorForbidden ??
        "You don't have permission to perform this action.";
  }
  if (statusCode == 401) {
    return l10n?.errorUnauthorized ??
        'Your session ended. Please sign in again.';
  }
  final decoded = _tryDecodeMap(body);
  final detail = decoded?['detail'] ?? decoded?['error'];
  if (detail is String && detail.isNotEmpty) {
    return detail;
  }
  return l10n?.errorGeneric ?? 'Request failed ($statusCode).';
}

String friendlyHttpErrorMessageFromContext(
  BuildContext context,
  int statusCode,
  String body,
) {
  return friendlyHttpErrorMessage(
    statusCode,
    body,
    l10n: AppLocalizations.of(context),
  );
}

Map<String, dynamic>? _tryDecodeMap(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
