import 'package:defensys/screens/web/admin/user_management/components/faculty_staff_view.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/table/table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _MixedDirectoryNotifier extends UserManagementNotifier {
  late List<Map<String, dynamic>> roster;

  @override
  UserManagementState build() {
    roster = [
      for (var i = 1; i <= 10; i++)
        {
          'id': i,
          'username': 'FAC-${i.toString().padLeft(2, '0')}',
          'first_name': 'Faculty',
          'last_name': i.toString().padLeft(2, '0'),
          'email': 'faculty$i@example.edu',
          'role': 'faculty',
          'is_active': true,
          'is_adviser': i <= 4,
        },
      {
        'id': 11,
        'username': 'admin',
        'first_name': 'System',
        'last_name': 'Admin',
        'email': 'admin@example.edu',
        'role': 'admin',
        'is_active': true,
      },
      for (var i = 1; i <= 256; i++)
        {
          'id': 1000 + i,
          'username': 'STU-$i',
          'first_name': 'Student',
          'last_name': '$i',
          'role': 'student',
          'is_active': true,
        },
    ];
    return UserManagementState(
      users: roster,
      counts: const {'all': 267, 'faculty': 11, 'advisers': 4, 'admins': 1},
    );
  }

  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {
    final nextRole = role ?? state.role;
    state = state.copyWith(
      role: nextRole,
      search: search ?? state.search,
      users: roster.where((user) {
        if (nextRole == 'adviser') return user['is_adviser'] == true;
        if (nextRole == 'admin') return user['role'] == 'admin';
        return true;
      }).toList(),
    );
  }

  void removeAdmin() {
    roster = roster.where((user) => user['role'] != 'admin').toList();
    state = state.copyWith(users: roster);
  }
}

Finder _pageNumber(String number) => find.descendant(
  of: find.byType(DefensysTablePagination),
  matching: find.text(number),
);

Future<_MixedDirectoryNotifier> _pumpDirectory(
  WidgetTester tester, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpDefensysWidget(
    tester,
    SingleChildScrollView(
      child: FacultyStaffView(
        onOpenBulkImport: () {},
        onOpenAccessControl: (_) {},
      ),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      userManagementProvider.overrideWith(_MixedDirectoryNotifier.new),
    ],
  );
  return ProviderScope.containerOf(
        tester.element(find.byType(FacultyStaffView)),
      ).read(userManagementProvider.notifier)
      as _MixedDirectoryNotifier;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'faculty pagination excludes students in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pumpDirectory(tester, dark: dark);

        expect(find.text('Showing 1–10 of 11 users'), findsOneWidget);
        expect(_pageNumber('2'), findsOneWidget);
        expect(_pageNumber('3'), findsNothing);
        expect(find.textContaining('of 267 users'), findsNothing);
        expect(find.text('Faculty 01'), findsOneWidget);
        expect(find.text('Student 1'), findsNothing);

        await tester.tap(_pageNumber('2'));
        await tester.pumpAndSettle();

        expect(find.text('Showing 11–11 of 11 users'), findsOneWidget);
        expect(find.text('System Admin'), findsOneWidget);
        expect(find.text('Faculty 01'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'full-name search resets the page and counts only matching faculty',
    (tester) async {
      await _pumpDirectory(tester);
      await tester.tap(_pageNumber('2'));
      await tester.pumpAndSettle();

      await _search(tester, 'Faculty 04');

      expect(find.text('Showing 1–1 of 1 users'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DefensysDataTable<Map<String, dynamic>>),
          matching: find.text('Faculty 04'),
        ),
        findsOneWidget,
      );
      expect(_pageNumber('2'), findsNothing);

      await _search(tester, 'Student');

      expect(find.text('Showing 0–0 of 0 users'), findsOneWidget);
      expect(find.text('No Matching Users Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'role and search filters share the pagination total and Clear restores it',
    (tester) async {
      await _pumpDirectory(tester);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adviser').last);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1–4 of 4 users'), findsOneWidget);
      expect(_pageNumber('2'), findsNothing);

      await _search(tester, 'Faculty 02');
      expect(find.text('Showing 1–1 of 1 users'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 1–10 of 11 users'), findsOneWidget);
      expect(find.text('All Faculty Roles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing page size shows all faculty without counting students',
    (tester) async {
      await _pumpDirectory(tester);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1–11 of 11 users'), findsOneWidget);
      expect(find.text('System Admin'), findsOneWidget);
      expect(_pageNumber('2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refreshing a shortened directory clamps rows and footer to the same page',
    (tester) async {
      final notifier = await _pumpDirectory(tester);
      await tester.tap(_pageNumber('2'));
      await tester.pumpAndSettle();
      notifier.removeAdmin();
      await tester.pumpAndSettle();

      expect(find.text('Showing 1–10 of 10 users'), findsOneWidget);
      expect(find.text('Faculty 01'), findsOneWidget);
      expect(find.text('Faculty 10'), findsOneWidget);
      expect(find.text('System Admin'), findsNothing);
      expect(_pageNumber('2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
