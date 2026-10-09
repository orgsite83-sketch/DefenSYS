import 'package:flutter/material.dart';
import '../../../../widgets/minutes/documenter_assignments_view.dart';

class DocumenterDashboardContent extends StatelessWidget {
  const DocumenterDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenMinutes,
  });
  final Map<String, dynamic>? data;
  final String facultyName;
  final ValueChanged<int> onOpenMinutes;

  @override
  Widget build(BuildContext context) =>
      DocumenterAssignmentsView(onOpenMinutes: onOpenMinutes);
}
