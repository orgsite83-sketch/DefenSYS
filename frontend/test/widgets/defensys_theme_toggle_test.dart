import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/widgets/buttons/defensys_theme_toggle.dart';
import 'package:defensys/services/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('DefensysThemeToggle renders moon in light mode and toggles to sun in dark mode',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: DefensysThemeToggle(),
            ),
          ),
        ),
      ),
    );

    // Initial state: light mode (moon icon)
    expect(find.byKey(const ValueKey('moon_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('sun_icon')), findsNothing);

    // Tap the toggle
    await tester.tap(find.byType(DefensysThemeToggle));
    await tester.pumpAndSettle();

    // After tap: themeModeProvider should be dark
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DefensysThemeToggle)));
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
