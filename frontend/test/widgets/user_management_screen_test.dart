import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/user_management_screen.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
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

class FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() {
    return const UserManagementState(
      isLoading: false,
      users: [
        {
          'id': 1,
          'username': 'admin',
          'email': 'admin@defensys.edu',
          'name': 'System Admin',
          'first_name': 'System',
          'last_name': 'Admin',
          'role': 'admin',
          'is_active': true,
          'is_panelist': false,
          'is_pit_lead': false,
          'is_adviser': false,
          'is_documenter': false,
        }
      ],
      guestCodes: [],
    );
  }

  @override
  Future<void> fetchUsers({String? search, String? role, String? successMessage}) async {}
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState();
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

void main() {
  testWidgets('UserManagementScreen renders properly with 1 user and original table design', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen()),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('System Role'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);

    expect(find.text('admin'), findsWidgets);
    expect(find.text('System Admin'), findsOneWidget);
    expect(find.text('admin@defensys.edu'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);

    expect(find.byIcon(Icons.edit_square), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.lock_reset_rounded), findsNothing);
  });

  testWidgets('UserManagementScreen opens Bulk Import Users view with original format card and dropzone', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen()),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    // Click on Bulk Import CSV button in header
    final bulkImportButton = find.text('Bulk Import CSV');
    expect(bulkImportButton, findsOneWidget);
    await tester.tap(bulkImportButton);
    await tester.pumpAndSettle();

    // Verify Bulk Import View elements
    expect(find.text('Bulk Import Users'), findsOneWidget);
    expect(find.text('CSV Format'), findsOneWidget);
    expect(find.text('Official Class List Structure (CSV / XLSX)'), findsOneWidget);
    expect(find.text('Download Sample Template'), findsOneWidget);
    expect(find.text('Upload CSV'), findsOneWidget);
    expect(find.text('IMPORT BATCH TYPE'), findsOneWidget);
    expect(find.text('Student Batch Options'), findsOneWidget);
    expect(find.text('Preflight Review'), findsOneWidget);
    expect(find.text('Click to choose file or drag & drop'), findsOneWidget);
    expect(find.text('Accepts .csv and .xlsx files'), findsOneWidget);
    expect(find.text('Back to Users'), findsOneWidget);

    // Click Back to Users
    await tester.tap(find.text('Back to Users'));
    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
  });
}
