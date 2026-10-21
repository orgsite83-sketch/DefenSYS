import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'shadcn/defensys_shadcn_scope.dart';
import '../utils/csv_file_io.dart';
import '../utils/export/team_roster_excel_generator.dart';
import '../utils/import/team_bulk_import_csv.dart';

/// Shared presentation; the caller owns scope, validation and commit.
class TeamImportFormatGuide extends StatelessWidget {
  const TeamImportFormatGuide({
    super.key,
    required this.isCapstone,
    required this.contextLabel,
    required this.onDownload,
    this.section,
    this.instructorName,
  });
  final bool isCapstone;
  final String contextLabel;
  final VoidCallback? onDownload;
  final String? section, instructorName;

  @override
  Widget build(BuildContext context) =>
      DefensysShadcnScope(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final faculty = isCapstone ? 'Adviser' : 'Instructor';
    Widget headers(String project) => Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(.9),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1.4),
      },
      border: TableBorder.all(color: colors.border),
      children: [
        TableRow(
          decoration: BoxDecoration(color: colors.muted),
          children: [
            for (final label in [
              'Team Name',
              project,
              'Section',
              faculty,
              'Team Members',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return ShadCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: const Text(
        'Excel format',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      description: Text(contextLabel, style: const TextStyle(fontSize: 12)),
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Different systems',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            headers(isCapstone ? 'Capstone Project' : 'PIT Project'),
            const SizedBox(height: 18),
            const Text(
              'Shared system',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(4.7),
              },
              border: TableBorder.all(color: colors.border),
              children: [
                for (final row in const [
                  ['System Name:', 'Campus Services'],
                  ['Project Manager:', 'Carlo Ramos'],
                ])
                  TableRow(
                    children: [
                      for (final value in row)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 9,
                          ),
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.mutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            headers('Module'),
            const SizedBox(height: 16),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 14),
            TeamImportSetupHelp(isCapstone: isCapstone),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => showTeamImportBlueprint(
                    context,
                    isCapstone: isCapstone,
                    contextLabel: contextLabel,
                    section: section,
                    instructorName: instructorName,
                  ),
                  leading: const Icon(Icons.visibility_outlined, size: 14),
                  child: const Flexible(
                    child: Text(
                      'View Sheet Layout Blueprint',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: onDownload != null,
                  onPressed: onDownload,
                  leading: const Icon(Icons.download_outlined, size: 14),
                  child: const Flexible(
                    child: Text(
                      'Download Sample Template',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Help stays on the import page, outside the downloaded sheet and blueprint.
class TeamImportSetupHelp extends StatelessWidget {
  const TeamImportSetupHelp({super.key, required this.isCapstone});
  final bool isCapstone;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'No team name or project title yet?',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 5),
      Text(
        'Leave Team Name, ${isCapstone ? 'Capstone Project' : 'PIT Project'}, or Module blank. '
        'The team leader will complete only the missing details in DefenSYS.',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'List the leader first. Use the Excel template for unnamed teams.',
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      ),
    ],
  );
}

class TeamImportDropArea extends StatelessWidget {
  const TeamImportDropArea({
    super.key,
    required this.onPick,
    this.fileLabel,
    this.dragging = false,
    this.teamCount = 0,
  });
  final VoidCallback? onPick;
  final String? fileLabel;
  final bool dragging;
  final int teamCount;
  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(
      builder: (context) {
        final colors = ShadTheme.of(context).colorScheme;
        return Semantics(
          button: true,
          enabled: onPick != null,
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 180),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dragging ? colors.muted : colors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: dragging ? colors.foreground : colors.border,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 28,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dragging
                        ? 'Drop your spreadsheet here'
                        : fileLabel ??
                              'Drop a spreadsheet here or choose a file',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    teamCount > 0
                        ? '$teamCount teams staged · Choose a file to replace'
                        : 'CSV or XLSX',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showTeamImportBlueprint(
  BuildContext context, {
  required bool isCapstone,
  required String contextLabel,
  String? section,
  String? instructorName,
}) async {
  final bytes = generateOfficialTeamRosterExcelBytes(
    isCapstone: isCapstone,
    assignedSection: section,
    instructorName: instructorName,
  );
  final csv = officialTeamRosterCsv(
    isCapstone: isCapstone,
    assignedSection: section,
    instructorName: instructorName,
  );
  final sheet = xl.Excel.decodeBytes(bytes).tables.values.first;
  final stem = isCapstone
      ? 'defensys_team_roster_template'
      : 'defensys_pit_team_roster_template';
  await showShadDialog<void>(
    context: context,
    builder: (ctx) => DefensysShadcnScope(
      child: Builder(
        builder: (ctx) => ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 1350,
            maxHeight: MediaQuery.sizeOf(ctx).height - 48,
          ),
          titlePinned: true,
          actionsPinned: true,
          title: Text(
            'Official ${isCapstone ? 'Capstone' : 'PIT'} Team Sheet Blueprint',
          ),
          description: Text(contextLabel),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton(
                  size: ShadButtonSize.sm,
                  onPressed: () => downloadBinaryFile(
                    filename: '$stem.xlsx',
                    bytes: bytes,
                    mimeType:
                        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  ),
                  leading: const Icon(Icons.table_chart_outlined, size: 14),
                  child: const Flexible(
                    child: Text(
                      'Download Excel Template (.xlsx)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () =>
                      downloadTextFile(filename: '$stem.csv', content: csv),
                  leading: const Icon(Icons.download_outlined, size: 14),
                  child: const Flexible(
                    child: Text(
                      'Download Team Roster Template (.csv)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: csvToTsv(csv))),
                  leading: const Icon(Icons.copy_outlined, size: 14),
                  child: const Flexible(
                    child: Text(
                      'Copy for Excel / Sheets',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  color: ShadTheme.of(ctx).colorScheme.muted,
                  child: Text(
                    '$stem.xlsx  ·  Different & Shared Systems',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _WorkbookPreview(sheet: sheet),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Render the workbook's actual coordinates and merged cells, so the blueprint
/// cannot drift from either downloadable format.
class _WorkbookPreview extends StatelessWidget {
  const _WorkbookPreview({required this.sheet});
  final xl.Sheet sheet;
  static const widths = [
    24.0,
    114.0,
    160.0,
    70.0,
    120.0,
    125.0,
    24.0,
    114.0,
    146.0,
    70.0,
    120.0,
    125.0,
  ];
  @override
  Widget build(BuildContext context) {
    const height = 26.0, gutter = 34.0;
    final spans = sheet.spannedItems
        .map((span) => span.split(':').map(xl.CellIndex.indexByString).toList())
        .toList();
    final colors = ShadTheme.of(context).colorScheme;
    double left(int col) =>
        gutter + widths.take(col).fold(0.0, (a, b) => a + b);
    Widget cell(
      String value,
      double x,
      double y,
      double w,
      double h, {
      bool heading = false,
    }) => Positioned(
      left: x,
      top: y,
      width: w,
      height: h,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: heading ? colors.muted : colors.background,
          border: Border.all(color: colors.border, width: .5),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: heading ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
    final cells = <Widget>[cell('', 0, 0, gutter, height, heading: true)];
    for (var c = 0; c < widths.length; c++) {
      cells.add(
        cell(
          String.fromCharCode(65 + c),
          left(c),
          0,
          widths[c],
          height,
          heading: true,
        ),
      );
    }
    for (var r = 0; r < sheet.maxRows; r++) {
      cells.add(
        cell('${r + 1}', 0, (r + 1) * height, gutter, height, heading: true),
      );
      for (var c = 0; c < widths.length; c++) {
        List<xl.CellIndex>? merged;
        for (final span in spans) {
          if (r >= span.first.rowIndex &&
              r <= span.last.rowIndex &&
              c >= span.first.columnIndex &&
              c <= span.last.columnIndex) {
            merged = span;
            break;
          }
        }
        if (merged != null &&
            (r != merged.first.rowIndex || c != merged.first.columnIndex)) {
          continue;
        }
        final value =
            sheet
                .cell(
                  xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
                )
                .value
                ?.toString() ??
            '';
        final w = merged == null
            ? widths[c]
            : widths
                  .sublist(c, merged.last.columnIndex + 1)
                  .fold(0.0, (a, b) => a + b);
        final h = merged == null
            ? height
            : (merged.last.rowIndex - r + 1) * height;
        cells.add(
          cell(
            value,
            left(c),
            (r + 1) * height,
            w,
            h,
            heading: (r == 3 && c >= 1 && c <= 5) || (r == 5 && c >= 7),
          ),
        );
      }
    }
    return SizedBox(
      width: left(widths.length),
      height: (sheet.maxRows + 1) * height,
      child: Stack(children: cells),
    );
  }
}
