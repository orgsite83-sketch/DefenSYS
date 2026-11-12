import 'package:defensys/screens/web/admin/user_management/components/user_management_table.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  final cases = [
    (
      name: 'admin adviser includes both roles',
      user: <String, dynamic>{'role': 'admin', 'is_adviser': true},
      labels: ['Administrator', 'Adviser'],
    ),
    (
      name: 'plain admin retains only administrator',
      user: <String, dynamic>{'role': 'admin'},
      labels: ['Administrator'],
    ),
    (
      name: 'admin includes every assigned staff duty',
      user: <String, dynamic>{
        'role': 'admin',
        'is_pit_lead': true,
        'pit_lead_year': '1st Year',
        'is_adviser': true,
        'is_panelist': true,
        'is_documenter': true,
        'instructor_assignments': [
          {'year_level': '1st Year'},
        ],
      },
      labels: [
        'Administrator',
        'PIT Lead: 1st Year',
        'Adviser',
        'Panelist',
        'Documenter',
        'Instructor: 1st Year',
      ],
    ),
    (
      name: 'faculty adviser retains its existing badge',
      user: <String, dynamic>{'role': 'faculty', 'is_adviser': true},
      labels: ['Adviser'],
    ),
    (
      name: 'student retains its academic label',
      user: <String, dynamic>{
        'role': 'student',
        'year_level': '4th Year',
        'is_adviser': true,
      },
      labels: ['4th Year'],
    ),
  ];

  for (final scenario in cases) {
    testWidgets(scenario.name, (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);
      final user = {
        'id': 1,
        'username': 'staff-1',
        'name': 'Test User',
        'email': 'staff@example.com',
        ...scenario.user,
      };

      await pumpDefensysWidget(
        tester,
        UserManagementTable(
          state: UserManagementState(users: [user]),
          visibleUsers: [user],
          totalItems: 1,
          searchController: searchController,
          currentPage: 1,
          rowsPerPage: 10,
          rowsPerPageOptions: const [10],
          onSearchSubmitted: (_) {},
          onClearFilters: () {},
          onRoleFilterChanged: (_) {},
          onPageChanged: (_) {},
          onRowsPerPageChanged: (_) {},
          onEditUser: (_) {},
          onOpenAccessControl: (_) {},
        ),
      );

      final message =
          'Active Roles:\n${scenario.labels.map((label) => '• $label').join('\n')}';
      final tooltip = find.byTooltip(message);
      expect(tooltip, findsOneWidget);
      expect(
        find.descendant(
          of: tooltip,
          matching: find.text(scenario.labels.first),
        ),
        findsOneWidget,
      );
      if (scenario.labels.length > 1) {
        expect(find.text('+${scenario.labels.length - 1}'), findsOneWidget);
      } else {
        expect(find.textContaining(RegExp(r'^\+\d+$')), findsNothing);
      }
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
