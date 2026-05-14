import 'package:flutter/material.dart';

import 'admin_shell.dart';

class AdminDashboard extends StatelessWidget {
  final Map<String, dynamic>? userData;

  const AdminDashboard({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    return AdminShell(userData: userData);
  }
}
