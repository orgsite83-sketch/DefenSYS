import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

class FacultyTeamsOverviewExport extends ConsumerStatefulWidget {
  const FacultyTeamsOverviewExport({
    super.key,
    required this.teams,
    required this.workspace,
    required this.selectedStage,
  });

  final List<Map<String, dynamic>> teams;
  final String workspace;
  final String selectedStage;

  @override
  ConsumerState<FacultyTeamsOverviewExport> createState() =>
      _FacultyTeamsOverviewExportState();
}

class _FacultyTeamsOverviewExportState
    extends ConsumerState<FacultyTeamsOverviewExport> {
  final _popoverController = ShadPopoverController();

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
  }

  Future<void> _download(String format) async {
    _popoverController.hide();
    final ids = widget.teams
        .map((team) => int.tryParse('${team['id']}') ?? 0)
        .where((id) => id > 0)
        .join(',');
    if (ids.isEmpty) return;
    final success = await ref
        .read(reportsProvider.notifier)
        .downloadReport(
          endpoint: 'faculty-teams-overview/',
          queryParams: {
            'workspace': widget.workspace,
            'team_ids': ids,
            if (widget.selectedStage.isNotEmpty) 'stage': widget.selectedStage,
          },
          defaultFilename: 'DefenSYS_Assigned_Teams_Overview.$format',
          exportFormat: format,
        );
    if (!mounted) return;
    if (success) {
      showSuccessToast(context, 'Assigned teams overview downloaded.');
    } else {
      showErrorToast(
        context,
        ref.read(reportsProvider).error ?? 'Unable to download the overview.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.teams.isNotEmpty && !ref.watch(reportsProvider).isLoading;
    final compact = MediaQuery.sizeOf(context).width < 420;
    return DefensysShadcnScope(
      child: ShadPopover(
        controller: _popoverController,
        padding: const EdgeInsets.all(6),
        popover: (context) => SizedBox(
          width: 248,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadButton.ghost(
                width: 248,
                size: ShadButtonSize.sm,
                mainAxisAlignment: MainAxisAlignment.start,
                leading: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                onPressed: () => _download('pdf'),
                child: const Text('Download PDF'),
              ),
              ShadButton.ghost(
                width: 248,
                size: ShadButtonSize.sm,
                mainAxisAlignment: MainAxisAlignment.start,
                leading: const Icon(Icons.table_chart_outlined, size: 16),
                onPressed: () => _download('xlsx'),
                child: const Text('Download Excel'),
              ),
            ],
          ),
        ),
        child: Tooltip(
          message: 'Export summary for the teams shown in this list',
          child: ShadButton.outline(
            enabled: enabled,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: enabled ? _popoverController.toggle : null,
            leading: const Icon(Icons.download_outlined, size: 15),
            trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
            child: Text(
              compact ? 'Export' : 'Export teams',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
