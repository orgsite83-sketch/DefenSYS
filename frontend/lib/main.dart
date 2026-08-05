import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';

import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/realtime_sync_service.dart';
import 'package:defensys/services/session_keepalive_service.dart';
import 'package:defensys/theme/app_theme.dart';

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
        child: ToastificationWrapper(
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
      ),
    );
  }
}
