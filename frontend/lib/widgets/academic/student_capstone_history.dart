import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/api_config.dart';
import '../../navigation/admin_route_paths.dart';
import '../../services/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

String capstoneParticipationLabel(int? number) {
  if (number == null) return 'History needs review';
  final suffix = number % 100 >= 11 && number % 100 <= 13
      ? 'th'
      : switch (number % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$number$suffix participation';
}

Future<void> showStudentCapstoneHistory(
  BuildContext context,
  int studentId,
  String name,
) => showDialog<void>(
  context: context,
  builder: (_) => _StudentCapstoneHistory(studentId: studentId, name: name),
);

class StudentCapstoneParticipationButton extends StatelessWidget {
  const StudentCapstoneParticipationButton({
    super.key,
    required this.studentId,
    required this.name,
    required this.number,
    this.canOpenHistory = true,
  });
  final int studentId;
  final String name;
  final int? number;
  final bool canOpenHistory;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadButton.ghost(
      onPressed: canOpenHistory
          ? () => showStudentCapstoneHistory(context, studentId, name)
          : null,
      child: Text(
        capstoneParticipationLabel(number),
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
    ),
  );
}

class _StudentCapstoneHistory extends ConsumerStatefulWidget {
  const _StudentCapstoneHistory({required this.studentId, required this.name});
  final int studentId;
  final String name;
  @override
  ConsumerState<_StudentCapstoneHistory> createState() =>
      _StudentCapstoneHistoryState();
}

class _StudentCapstoneHistoryState
    extends ConsumerState<_StudentCapstoneHistory> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse(
              '${ApiConfig.teamsUrl}/students/${widget.studentId}/capstone-history/',
            ),
          );
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw Exception('Student Capstone history could not be loaded.');
      }
      final data = jsonDecode(response.body) as Map;
      setState(() {
        _rows = (data['participations'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Student Capstone history could not be loaded.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 640),
      title: Text(widget.name),
      description: const Text('Capstone participation history'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: SizedBox(
        width: 580,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        ShadButton.ghost(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : _rows.isEmpty
                  ? const Text(
                      'No confirmed Capstone participation is recorded.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: _rows.reversed
                          .map(
                            (row) => Padding(
                              padding: const EdgeInsets.only(bottom: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 12,
                                    children: [
                                      Text(
                                        capstoneParticipationLabel(
                                          (row['number'] as num?)?.toInt(),
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        switch (row['state']) {
                                          'failed' => 'Failed',
                                          'completed' => 'Completed',
                                          'active' => 'Active',
                                          _ => 'Needs review',
                                        },
                                        style: TextStyle(
                                          color: DefensysTokens.textSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    row['intake']?.toString() ?? '',
                                    style: TextStyle(
                                      color: DefensysTokens.textSecondaryOf(
                                        context,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                  ...((row['placements'] as List? ?? []).map((
                                    raw,
                                  ) {
                                    final placement = raw as Map;
                                    final id = (placement['team_id'] as num?)
                                        ?.toInt();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            placement['team_name']
                                                    ?.toString() ??
                                                '',
                                          ),
                                          if (id != null)
                                            ShadButton.ghost(
                                              onPressed: () {
                                                Navigator.pop(context);
                                                context.go(
                                                  AdminRoutes.teamDetail(id),
                                                );
                                              },
                                              child: const Text('View team'),
                                            ),
                                        ],
                                      ),
                                    );
                                  })),
                                  Divider(
                                    color: DefensysTokens.borderOf(context),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
