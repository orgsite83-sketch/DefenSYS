import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/login_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';

class RestoringAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isRestoring: true);
}

void main() {
  group('LoginSkeletonScreen', () {
    testWidgets('renders mobile skeleton layout with shimmer and branding', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginSkeletonScreen(),
        ),
      );

      // Verify wave background painter
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify DefensysShimmer instances are present
      expect(find.byType(DefensysShimmer), findsWidgets);

      // Verify no circular progress indicator is shown
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Let animation tick once without errors
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('renders web skeleton layout on wide screen', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginSkeletonScreen(),
        ),
      );

      expect(find.byType(DefensysShimmer), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('DefensysSkeleton.loginScreen helper produces LoginSkeletonScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefensysSkeleton.loginScreen(),
        ),
      );

      expect(find.byType(LoginSkeletonScreen), findsOneWidget);
    });

    testWidgets(
      'LoginScreen shows LoginSkeletonScreen instead of CircularProgressIndicator when isRestoring is true',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(RestoringAuthNotifier.new),
            ],
            child: const MaterialApp(
              home: LoginScreen(),
            ),
          ),
        );

        // Skeleton screen must be displayed
        expect(find.byType(LoginSkeletonScreen), findsOneWidget);

        // Must NOT display CircularProgressIndicator
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
