import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../../config/api_config.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../services/network/authenticated_client.dart';
import '../../../../../utils/platform/universal_file_viewer.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// The report uses the exact selected workflow and period, and shares the same
/// backend calculation as the charts. No inferred course prescriptions.
Future<void> openCurriculumMeetingExport(
  BuildContext context,
  WidgetRef ref,
  CurriculumExplorerQuery query,
  String tab,
) async {
  var format = 'pdf', busy = false;
  String? error;
  final client = ref.read(authenticatedHttpClientProvider);
  await showShadDialog(
    context: context,
    barrierLabel: 'Close meeting report export',
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => DefensysShadcnScope(
        child: ShadDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('Export meeting report'),
          description: Text(
            '${query.scope == 'pit' ? 'PIT / Year ${query.yearLevel}' : 'Capstone'} / ${query.year.isEmpty ? 'All academic years' : query.year}',
          ),
          actions: [
            ShadButton.outline(
              enabled: !busy,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ShadButton(
              enabled: !busy,
              onPressed: () async {
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  final response = await client.get(
                    Uri.parse(
                      '${ApiConfig.curriculumAnalyticsUrl}/explorer/report/',
                    ).replace(
                      queryParameters: {
                        ...query.toParams(),
                        'export_format': format,
                        'tab': tab,
                      },
                    ),
                  );
                  if (response.statusCode != 200) {
                    throw Exception(
                      'The report could not be generated. Try again.',
                    );
                  }
                  await downloadBytesFile(
                    bytes: response.bodyBytes,
                    fileName:
                        'Curriculum_${query.scope}_${query.year.isEmpty ? 'all-years' : query.year}.$format',
                    mimeType: format == 'pdf'
                        ? 'application/pdf'
                        : format == 'xlsx'
                        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                        : 'text/csv;charset=utf-8',
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    setState(() {
                      busy = false;
                      error = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                }
              },
              child: Text(busy ? 'Preparing report…' : 'Download'),
            ),
          ],
          child: SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Recorded results, assessment coverage, unique project counts and ML category estimates for this selection.',
                ),
                const SizedBox(height: 18),
                ShadSelect<String>(
                  initialValue: format,
                  onChanged: (v) {
                    if (v != null) setState(() => format = v);
                  },
                  selectedOptionBuilder: (_, value) =>
                      Text(value.toUpperCase()),
                  options: ['pdf', 'xlsx', 'csv'].map(
                    (v) => ShadOption(value: v, child: Text(v.toUpperCase())),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: ShadAlert.destructive(description: Text(error!)),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
