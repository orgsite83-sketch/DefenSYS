import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'navigation/app_router.dart';
import 'services/auth_provider.dart';
import 'services/realtime_sync_service.dart';
import 'services/session_keepalive_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: DefenSYSApp()));
}

class DefenSYSApp extends ConsumerWidget {
  const DefenSYSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider);
    final router = ref.watch(appRouterProvider);

    return SessionKeepaliveHost(
      child: RealtimeSyncHost(
        child: MaterialApp.router(
        title: 'DefenSYS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        ),
      ),
    );
  }
}

