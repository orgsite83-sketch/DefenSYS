import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';
import 'package:defensys/toasts/feedback_toast.dart';

void main() {
  group('Error Sanitizer & Humanization', () {
    test('handles raw socket and connection exceptions', () {
      final res = humanizeErrorMessage(
        'DioException [connection error]: SocketException: OS Error: Connection refused, errno = 111, address = 192.168.1.13, port = 8000',
      );
      expect(res.title, 'Connection Failed');
      expect(res.description, contains('Unable to reach the server'));
      expect(res.rawDetails, contains('192.168.1.13'));
    });

    test('handles JSON detail payload', () {
      final res = humanizeErrorMessage('{"detail": "Academic period already exists for this semester"}');
      expect(res.title, 'Operation Failed');
      expect(res.description, 'Academic period already exists for this semester');
    });

    test('handles 401 unauthorized session expiry', () {
      final res = humanizeErrorMessage('DioException [bad response]: 401 Unauthorized token_not_valid');
      expect(res.title, 'Session Expired');
      expect(res.description, contains('session has expired'));
    });

    test('handles 403 forbidden access denied', () {
      final res = humanizeErrorMessage('403 Forbidden: Permission denied for role student');
      expect(res.title, 'Access Denied');
      expect(res.description, contains('permission'));
    });

    test('handles 500 internal server error', () {
      final res = humanizeErrorMessage('500 Internal Server Error: Database deadlock');
      expect(res.title, 'Server Error');
      expect(res.description, contains('server error occurred'));
    });

    test('strips technical Exception prefixes cleanly', () {
      final res = humanizeErrorMessage('Exception: Please select a valid student candidate.');
      expect(res.title, 'Operation Failed');
      expect(res.description, 'Please select a valid student candidate.');
    });

    test('handles empty message gracefully', () {
      final res = humanizeErrorMessage('');
      expect(res.title, 'Operation Failed');
      expect(res.description, contains('unexpected error occurred'));
    });
  });

  group('Feedback Toast UI Invocations', () {
    testWidgets('triggers success, validation, error, and info toasts without crash', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => showSuccessToast(context, 'Success message'),
                        child: const Text('Success'),
                      ),
                      ElevatedButton(
                        onPressed: () => showValidationToast(context, 'Validation warning'),
                        child: const Text('Validation'),
                      ),
                      ElevatedButton(
                        onPressed: () => showErrorToast(context, 'DioException: SocketException: Connection refused'),
                        child: const Text('Error'),
                      ),
                      ElevatedButton(
                        onPressed: () => showInfoToast(context, 'Info message'),
                        child: const Text('Info'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Success'));
      await tester.pump();

      await tester.tap(find.text('Validation'));
      await tester.pump();

      await tester.tap(find.text('Error'));
      await tester.pump();

      await tester.tap(find.text('Info'));
      await tester.pump();

      dismissFeedbackToasts();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('renders action button with Material ancestor in toast overlay', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showErrorToast(
                      context,
                      'Choose another semester to activate instead of deactivating the active semester directly.',
                    ),
                    child: const Text('Trigger Long Error'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Long Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Material), findsWidgets);

      dismissFeedbackToasts();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
  });
}
