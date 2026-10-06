import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/login_screen.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('LoginScreen shows DefenSYS branding and sign-in controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': true,
    });

    await pumpDefensysWidget(
      tester,
      const LoginScreen(),
      overrides: authTestOverrides(),
    );
    await tester.pumpAndSettle();

    expect(find.text('DefenSYS'), findsWidgets);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    // Open Forgot Password dialog
    final forgotPasswordBtn = find.text('Forgot password?');
    expect(forgotPasswordBtn, findsOneWidget);
    await tester.tap(forgotPasswordBtn);
    await tester.pumpAndSettle();

    // Verify Step 1: Verification Dialog with 6-digit OTP prompt
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Step 1 of 3: Verification'), findsOneWidget);
    expect(find.text('Gmail / Email'), findsOneWidget);
    expect(find.text('SMS / Text'), findsOneWidget);
    expect(find.text('ID or Email Address'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);

    // Switch to SMS tab
    await tester.tap(find.text('SMS / Text'));
    await tester.pumpAndSettle();

    expect(find.text('ID or Mobile Number'), findsOneWidget);
    expect(find.textContaining('SMS text message'), findsOneWidget);

    // Switch back to Email tab
    await tester.tap(find.text('Gmail / Email'));
    await tester.pumpAndSettle();

    expect(find.text('ID or Email Address'), findsOneWidget);
    expect(find.textContaining('Gmail inbox'), findsOneWidget);
  });

  testWidgets('Mobile LoginScreen shows Getting Started on first launch and transitions to login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': false,
    });

    // Set small phone dimensions to trigger mobile layout
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpDefensysWidget(
      tester,
      const LoginScreen(),
      overrides: authTestOverrides(),
    );
    await tester.pumpAndSettle();

    // Verify State 1: Getting Started Card
    expect(find.text('Empowering Capstone\n& PIT Research'), findsOneWidget);
    expect(find.text('Get Started / Sign In'), findsOneWidget);

    // Tap "Get Started / Sign In" to transition into State 2
    await tester.tap(find.text('Get Started / Sign In'));
    await tester.pumpAndSettle();

    // Verify State 2: Login Form Card
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Student ID or Email'), findsOneWidget);
    expect(find.text('Password'), findsWidgets);
    expect(find.text('Sign In'), findsOneWidget);

    // Tap "Getting Started" in footer to return to Welcome view
    final gettingStartedLink = find.text('Getting Started');
    expect(gettingStartedLink, findsOneWidget);
    await tester.tap(gettingStartedLink);
    await tester.pumpAndSettle();

    // Verify returned to Getting Started Card
    expect(find.text('Empowering Capstone\n& PIT Research'), findsOneWidget);
  });

  testWidgets('phone login slides automatically without rebuilding the form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': true,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, const LoginScreen(), overrides: authTestOverrides());
    final carousel = find.descendant(
      of: find.byKey(const ValueKey('mobile_hero_carousel')),
      matching: find.byType(PageView),
    );
    final controller = tester.widget<PageView>(carousel).controller!;
    final field = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(controller.page, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.page, greaterThan(0));
    expect(
      identical(field, tester.widget<TextFormField>(find.byType(TextFormField).first)),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone carousel pauses for the keyboard and resumes after dismissal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': true,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await pumpDefensysWidget(tester, const LoginScreen(), overrides: authTestOverrides());
    final carousel = find.descendant(
      of: find.byKey(const ValueKey('mobile_hero_carousel')),
      matching: find.byType(PageView),
    );
    final controller = tester.widget<PageView>(carousel).controller!;
    await tester.enterText(find.byType(TextField).first, 'student-user');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(find.text('student-user'), findsOneWidget);
    await tester.tap(carousel);
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(find.text('student-user'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone carousel pauses in the background and resumes on return', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': true,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      if (tester.binding.lifecycleState == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await pumpDefensysWidget(tester, const LoginScreen(), overrides: authTestOverrides());
    final carousel = find.descendant(
      of: find.byKey(const ValueKey('mobile_hero_carousel')),
      matching: find.byType(PageView),
    );
    final controller = tester.widget<PageView>(carousel).controller!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(controller.page, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone header animation retains the form between animation frames', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'defensys_has_seen_getting_started': false,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, const LoginScreen(), overrides: authTestOverrides());
    await tester.tap(find.text('Get Started / Sign In'));
    await tester.pump();
    final field = tester.widget<TextFormField>(find.byType(TextFormField).first);
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      identical(field, tester.widget<TextFormField>(find.byType(TextFormField).first)),
      isTrue,
    );
    await tester.pumpAndSettle();
  });
}

