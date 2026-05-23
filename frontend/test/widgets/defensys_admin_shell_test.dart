import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/screens/web/admin/widgets/defensys_admin_shell.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('DefensysAdminShell renders sidebar and child content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      DefensysAdminShell(
        activeSection: DefensysAdminSection.studentTeams,
        activeSemesterLabel: 'Active Sem: 2026-2027',
        onNavigate: (_) {},
        onLogout: () {},
        child: const Center(child: Text('Shell child content')),
      ),
    );

    expect(find.text('Shell child content'), findsOneWidget);
    expect(find.text('Student Teams'), findsWidgets);
  });
}
