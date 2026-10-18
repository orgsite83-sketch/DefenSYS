/// Match the browser download's type to its actual format.
String downloadMimeType(String filename) => switch (filename
    .toLowerCase()
    .split('.')
    .last) {
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'csv' => 'text/csv;charset=utf-8',
  'pdf' => 'application/pdf',
  'zip' => 'application/zip',
  'json' => 'application/json',
  'txt' => 'text/plain;charset=utf-8',
  _ => 'application/octet-stream',
};
