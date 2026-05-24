import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:user/services/auth_provider.dart';

/// Access token with far-future `exp` so proactive refresh does not run in tests.
String get testAccessToken {
  final payload = base64Url.encode(utf8.encode('{"exp":9999999999}'));
  return 'header.$payload.sig';
}

final testAuthState = AuthState(
  isRestoring: false,
  token: testAccessToken,
  user: const {'id': 1, 'role': 'admin', 'username': 'admin'},
);

class TestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => testAuthState;
}

List<Override> authTestOverrides() => [
      authProvider.overrideWith(TestAuthNotifier.new),
    ];
