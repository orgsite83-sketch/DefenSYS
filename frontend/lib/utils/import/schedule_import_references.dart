import 'defense_schedule_import_parser.dart';

String scheduleReferenceId(ParsedScheduleImportRow row, String duty) =>
    '${row.importRowId.isEmpty ? '${row.sourceFileId}:${row.sourceSheetName}:${row.sheetRow}' : row.importRowId}:$duty';

Map<String, String> scheduleFacultyFields(
  ParsedScheduleImportRow row, {
  required bool isPit,
}) => {
  'chair': row.chair,
  for (var i = 0; i < row.panelMembers.length; i++)
    'panel_$i': row.panelMembers[i],
  if (!isPit && row.documenter.isNotEmpty) 'documenter': row.documenter,
  if (!isPit && row.adviser.isNotEmpty) 'adviser': row.adviser,
};

List<Map<String, dynamic>> scheduleReferenceRequests(
  List<ParsedScheduleImportRow> rows, {
  required bool isPit,
}) => [
  for (final row in rows)
    for (final entry in scheduleFacultyFields(row, isPit: isPit).entries)
      if (entry.value.trim().isNotEmpty)
        {
          'reference_id': scheduleReferenceId(row, entry.key),
          'duty': entry.key,
          'text': entry.value,
          if (row.selectedAccountIds[entry.key] != null)
            'selected_account_id': row.selectedAccountIds[entry.key],
        },
];

/// A deliberate selection is confined to its duty and the current validated batch.
List<ParsedScheduleImportRow> selectScheduleAccount({
  required List<ParsedScheduleImportRow> rows,
  required String referenceId,
  required String duty,
  required int accountId,
  required Map<String, Map<String, dynamic>> resolutions,
  bool applyEquivalent = false,
}) {
  final source = resolutions[referenceId];
  return [
    for (final row in rows)
      (() {
        final id = scheduleReferenceId(row, duty),
            match = resolutions[scheduleReferenceId(row, duty)];
        final same =
            id == referenceId ||
            applyEquivalent &&
                source != null &&
                match != null &&
                source['duty'] == duty &&
                match['duty'] == duty &&
                source['reference_key'] == match['reference_key'] &&
                !row.selectedAccountIds.containsKey(duty);
        return same
            ? row.copyWith(
                selectedAccountIds: {
                  ...row.selectedAccountIds,
                  duty: accountId,
                },
              )
            : row;
      })(),
  ];
}
