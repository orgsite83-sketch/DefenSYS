import 'package:flutter/foundation.dart';
import 'package:defensys/config/web_app_config.dart';

String guestPortalUrl({Uri? base, String webOrigin = WebAppConfig.origin}) {
  const configured = String.fromEnvironment('GUEST_PORTAL_URL');
  if (configured.isNotEmpty) return configured;
  if (!kIsWeb && base == null) return '';
  final page = base ?? Uri.base;
  final current =
      WebAppConfig.canonicalUrl(page, configuredOrigin: webOrigin) ?? page;
  return Uri(
    scheme: current.scheme,
    userInfo: current.userInfo,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: current.path,
    fragment: '/guest/evaluate',
  ).toString();
}

String guestInvitationUrl(String code, {String? portal}) {
  final address = portal ?? guestPortalUrl();
  if (address.isEmpty) return '';
  final uri = Uri.parse(address);
  if (uri.hasFragment) {
    final route = Uri.parse(uri.fragment).replace(
      queryParameters: {
        ...Uri.parse(uri.fragment).queryParameters,
        'code': code,
      },
    );
    return uri.replace(fragment: route.toString()).toString();
  }
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'code': code})
      .toString();
}

String guestInvitationText(Map<String, dynamic> invitation) {
  final portal = guestPortalUrl();
  final code = invitation['code']?.toString() ?? '';
  final defenses = (invitation['schedules'] as List? ?? [])
      .map((s) => '${s['team_name']} · ${s['stage_label']} · ${s['date']}')
      .join('\n');
  return 'DefenSYS evaluation invitation for ${invitation['guest_name']}\n'
      '${portal.isEmpty ? '' : 'Open: ${guestInvitationUrl(code)}\nIf the link fails: $portal\n'}'
      'Access code: $code\nAccess expires: ${invitation['expires_at']}\n$defenses\n'
      'Open in a browser on your phone or laptop. No app download required.';
}
