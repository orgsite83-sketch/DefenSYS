import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/student_academic_records/student_academic_records_screen.dart';
import 'package:defensys/services/student_academic_records_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';

import '../helpers/pump_app.dart';

class FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() {
    return const NotificationsState(
      notifications: [],
      unreadCount: 0,
    );
  }

  @override
  Future<void> fetchNotifications() async {}
}

class FakeStudentAcademicRecordsNotifier extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() {
    return const StudentAcademicRecordsState(
      isLoading: false,
      records: [],
      students: [],
      schoolYears: [],
    );
  }

  @override
  Future<void> fetchRecords({String? schoolYear, String? semester, String? yearLevel, String? search, String? successMessage}) async {}
}

void main() {
  testWidgets('StudentAcademicRecordsScreen renders properly with empty records', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: StudentAcademicRecordsScreen()),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    expect(find.text('Student Academic Records'), findsOneWidget);
  });
}
