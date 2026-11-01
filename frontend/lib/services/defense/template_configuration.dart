import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../network/authenticated_client.dart';

const templateMaxBytes = 20 * 1024 * 1024;
const templateExtensions = [
  'docx',
  'pdf',
  'pptx',
  'xlsx',
  'csv',
  'tsv',
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'svg',
  'bmp',
  'ico',
  'mp4',
  'webm',
  'mov',
  'm4v',
  'avi',
  'mkv',
  'ogv',
  'mp3',
  'wav',
  'aac',
  'ogg',
  'm4a',
  'flac',
  'wma',
  'txt',
  'md',
  'markdown',
  'zip',
];

/// Browser drafts retain selection names, but not the selected file's bytes.
/// Keep this a form validation error, separate from HTTP/connection failures.
class TemplateSelectionException implements Exception {
  const TemplateSelectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? templateSelectionError(Map<String, dynamic> row) {
  if (row['template_action'] != 'replace') return null;
  final file = row['_templateFile'] as PlatformFile?;
  if (file?.bytes?.isNotEmpty == true) return null;
  final label = '${row['label'] ?? 'this deliverable'}'.trim();
  return 'Select the template for "$label" again, or remove it to continue.';
}

/// Keep selected bytes only in memory, outside configuration JSON/browser drafts.
List<Map<String, dynamic>> templateDrafts(
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) => [
  for (final row in teams)
    {'scope': 'team', 'deliverable_id': row['deliverable_id'], 'row': row},
  for (final row in shared)
    if (row['team_deliverable_id'] == null)
      {'scope': 'shared', 'deliverable_id': row['deliverable_id'], 'row': row},
];

dynamic _configurationValue(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!entry.key.toString().startsWith('_') &&
            !const [
              'template',
              'template_action',
              'template_selection_name',
              'template_selection_size',
            ].contains(entry.key))
          entry.key.toString(): _configurationValue(entry.value),
    };
  }
  if (value is List) return value.map(_configurationValue).toList();
  return value;
}

/// A single request saves setup and template changes. Older JSON callers work too.
Future<http.Response> saveTemplateConfiguration(
  AuthenticatedHttpClient client,
  String method,
  Uri uri,
  Map<String, dynamic> payload,
) async {
  final configuration = Map<String, dynamic>.from(
    _configurationValue(payload) as Map,
  );
  final files = <String, PlatformFile>{};
  final changes = <Map<String, dynamic>>[];
  for (final draft
      in (payload['_templateDrafts'] as List? ?? []).whereType<Map>()) {
    final row = draft['row'] as Map;
    final source = (row['template'] as Map?)?['id'];
    final action = row['template_action'] ?? 'keep';
    if (action == 'keep' && source == null) continue;
    final change = <String, dynamic>{
      'scope': draft['scope'],
      'deliverable_id': draft['deliverable_id'],
      'action': action,
      if (source != null) 'source_id': source,
    };
    if (action == 'replace') {
      final selectionError = templateSelectionError(Map<String, dynamic>.from(row));
      if (selectionError != null) {
        throw TemplateSelectionException(selectionError);
      }
      final file = row['_templateFile'] as PlatformFile?;
      final key = 'template_${files.length}';
      files[key] = file!;
      change['upload_key'] = key;
    }
    changes.add(change);
  }
  if (changes.isNotEmpty) configuration['template_changes'] = changes;
  if (files.isEmpty) {
    return method == 'PATCH'
        ? client.patch(uri, body: jsonEncode(configuration))
        : client.post(uri, body: jsonEncode(configuration));
  }
  final request = http.MultipartRequest(method, uri)
    ..fields['configuration'] = jsonEncode(configuration);
  for (final entry in files.entries) {
    request.files.add(
      http.MultipartFile.fromBytes(
        entry.key,
        entry.value.bytes!,
        filename: entry.value.name,
      ),
    );
  }
  // Multipart bodies cannot be sent twice; keep a failed write for deliberate retry.
  return http.Response.fromStream(
    await client.sendAuthenticated(request, retryOn401: false),
  );
}
