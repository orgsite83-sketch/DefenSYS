import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/screens/login_screen.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/login_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05));
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(760, 800),
    const Size(1440, 900),
  ]) {
    testWidgets('login switches themes without losing form state at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'defensys_has_seen_getting_started': true,
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mode = ValueNotifier(ThemeMode.dark);
      addTearDown(mode.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: authTestOverrides(),
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: mode,
            builder: (context, themeMode, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.mistDarkTheme,
              themeMode: themeMode,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const LoginScreen(
                sessionMessage: 'Your session has expired.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final palette = LoginPalette.of(tester.element(find.byType(LoginScreen)));
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey('login_form_surface')),
      );
      expect((surface.decoration! as BoxDecoration).color, palette.surface);
      expect(
        tester.widget<Text>(find.text('Welcome back')).style!.color,
        size.width >= 760 && kIsWeb
            ? palette.primaryText
            : palette.secondaryText,
      );
      expect(
        tester
            .widget<Text>(find.text('Your session has expired.'))
            .style!
            .color,
        palette.warningText,
      );
      for (final color in [
        palette.primaryText,
        palette.label,
        palette.secondaryText,
        palette.muted,
        palette.link,
      ]) {
        expect(contrast(color, palette.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(color, palette.inputFill), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(Colors.white, palette.action), greaterThanOrEqualTo(4.5));
      expect(
        contrast(palette.focus, palette.inputFill),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrast(palette.inputBorder, palette.inputFill),
        greaterThanOrEqualTo(3),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'sample-user');
      await tester.enterText(fields.last, 'sample-password');
      expect(
        tester.widget<TextField>(fields.first).style!.color,
        palette.primaryText,
      );
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.last).obscureText, isFalse);

      mode.value = ThemeMode.light;
      await tester.pumpAndSettle();
      final light = LoginPalette.of(tester.element(find.byType(LoginScreen)));
      final lightSurface = tester.widget<Container>(
        find.byKey(const ValueKey('login_form_surface')),
      );
      expect((lightSurface.decoration! as BoxDecoration).color, light.surface);
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        'sample-user',
      );
      expect(
        tester.widget<TextField>(fields.last).controller!.text,
        'sample-password',
      );
      expect(tester.widget<TextField>(fields.last).obscureText, isFalse);
      expect(tester.takeException(), isNull);

      mode.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        palette.surface,
      );
      expect(
        tester.widget<Text>(find.text('Reset Password')).style!.color,
        palette.primaryText,
      );
      await tester.tap(find.text('SMS / Text'));
      await tester.pumpAndSettle();
      expect(find.text('ID or Mobile Number'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
