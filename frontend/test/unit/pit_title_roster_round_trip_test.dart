import 'dart:io';

import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/excel_safe_decode.dart';
import 'package:excel/excel.dart' as xl;
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin-edited roster keeps multiline quoted titles as literal text', () {
    final workbook = safeDecodeExcel(
      File('test/fixtures/pit_title_roster.xlsx').readAsBytesSync(),
    );
    const title = '=Records, "Peña"\nCampus service';
    workbook.tables.values.first.updateCell(
      xl.CellIndex.indexByString('B4'),
      xl.TextCellValue(title),
    );
    final result = parseTeamBulkCsv(teamXlsxToCsv(workbook.encode()!));
    expect(result.rows, hasLength(2));
    expect(result.rows.first['project_title'], title);
    expect(result.rows.first['member_ids'], ['2094-001', '2094-002']);
  });
  test(
    'Report Center API roster parses with stable students and blank adviser',
    () {
      // Produced by ConceptProjectReportTests through the real XLSX endpoint.
      final result = parseTeamBulkCsv(
        teamXlsxToCsv(
          File('test/fixtures/pit_title_roster.xlsx').readAsBytesSync(),
        ),
      );
      expect(result.rows, hasLength(2));
      expect(result.rows[0]['team_name'], 'Alpha');
      expect(result.rows[0]['project_title'], 'Campus Records');
      expect(result.rows[0]['member_ids'], ['2094-001', '2094-002']);
      expect(result.rows[0]['leader_id'], '2094-001');
      expect(result.rows[0]['section'], 'BSIT-3A');
      expect(result.rows[0]['adviser_name'] ?? '', '');
      expect(result.rows[1]['team_name'], 'Beta');
      expect(result.rows[1]['project_title'] ?? '', '');
      expect(result.rows[1]['member_ids'], ['2094-003']);
    },
  );

  test('concept reporting belongs to Projects & Concepts for managers', () {
    final report = ReportCatalog.find('concept-projects')!;
    expect(report.category, 'projects');
    expect(report.endpointFor({}), 'concept-projects/');
    expect(
      report.filters,
      containsAll([
        'pit_event_config_id',
        'stage_id',
        'concept_status',
        'include_history',
        'layout',
      ]),
    );
    for (final user in [
      {'role': 'admin'},
      {'role': 'faculty', 'is_pit_lead': true, 'pit_lead_year': '3rd Year'},
    ]) {
      expect(ReportCatalog.visible(user), contains(report));
    }
    expect(
      ReportCatalog.visible({'role': 'faculty', 'is_adviser': true}),
      isNot(contains(report)),
    );
    expect(ReportCatalog.visible({'role': 'student'}), isNot(contains(report)));
  });
}
