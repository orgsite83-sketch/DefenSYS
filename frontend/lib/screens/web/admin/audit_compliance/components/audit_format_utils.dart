import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditDiffEntry {
  final String field;
  final String before;
  final String after;
  final bool isChanged;

  const AuditDiffEntry({
    required this.field,
    required this.before,
    required this.after,
    this.isChanged = true,
  });
}

class AuditFormatUtils {
  AuditFormatUtils._();

  static String formatAction(String? rawAction, [Map<String, dynamic>? log]) {
    final action = (rawAction ?? '').trim().toLowerCase();
    if (action.isEmpty) return 'System event';

    if (action == 'rubric.create') return 'Rubric created';
    if (action == 'rubric.update') return 'Rubric updated';
    if (action == 'rubric.delete' || action == 'rubric.deleted') return 'Rubric deleted';
    if (action == 'rubric.fields_modified' || action == 'rubric.field_modified') return 'Rubric fields modified';
    if (action == 'rubric.settings_updated' || action == 'rubric.settings_update') return 'Rubric settings updated';
    if (action == 'rubric.finalized' || action == 'rubric.finalized_archive') return 'Rubric finalized for archive';

    if (action == 'grade.finalized' || action == 'grade.finalize') return 'Grade finalized for archive';
    if (action == 'grade.deleted' || action == 'grade.delete') return 'Grade deleted for archive';
    if (action == 'evaluation.settings_updated') return 'Evaluation settings updated';

    if (action == 'user.create' || action == 'user.created') return 'User created';
    if (action == 'user.update' || action == 'user.updated') return 'User updated';
    if (action == 'user.delete' || action == 'user.deleted') return 'User deleted';

    if (action == 'defense_stage.update' || action == 'stage.update') return 'Defense stage modified';
    if (action == 'project.archive' || action == 'project.archived') return 'Project archived';
    if (action == 'project.restore' || action == 'project.restored') return 'Project archive restored';

    if (action.startsWith('repository.')) {
      if (action.contains('upload')) return 'Deliverable uploaded';
      if (action.contains('status')) return 'Deliverable status updated';
      if (action.contains('delete')) return 'Deliverable removed';
    }

    if (action.contains('create')) return '${_capitalizeFirst(action.split('.').first)} created';
    if (action.contains('update') || action.contains('edit')) return '${_capitalizeFirst(action.split('.').first)} updated';
    if (action.contains('delete')) return '${_capitalizeFirst(action.split('.').first)} deleted';

    // Default: convert dot or underscore notation to Title Case
    return action
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map(_capitalizeFirst)
        .join(' ');
  }

  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  static IconData actionIcon(String? rawAction) {
    final action = (rawAction ?? '').trim().toLowerCase();
    if (action.contains('delete') || action.contains('remove')) {
      return Icons.delete_outline_rounded;
    }
    if (action.contains('create') || action.contains('add')) {
      return Icons.add_box_outlined;
    }
    if (action.contains('update') || action.contains('edit') || action.contains('field')) {
      return Icons.edit_outlined;
    }
    if (action.contains('setting')) {
      return Icons.settings_outlined;
    }
    if (action.contains('grade') || action.contains('eval')) {
      return Icons.fact_check_outlined;
    }
    if (action.contains('archive') || action.contains('restore')) {
      return Icons.inventory_2_outlined;
    }
    if (action.contains('user')) {
      return Icons.person_outline_rounded;
    }
    return Icons.description_outlined;
  }

  static Color actionIconColor(BuildContext context, String? rawAction) {
    final action = (rawAction ?? '').trim().toLowerCase();
    if (action.contains('delete') || action.contains('remove')) {
      return const Color(0xFFDC2626); // Red
    }
    return DefensysTokens.textPrimaryOf(context);
  }

  static String extractResourceSubtitle(Map<String, dynamic> log) {
    final newVals = log['new_values'] is Map ? Map<String, dynamic>.from(log['new_values']) : {};
    final oldVals = log['old_values'] is Map ? Map<String, dynamic>.from(log['old_values']) : {};

    // 1. Specific rubric title/name
    final name = newVals['name'] ?? oldVals['name'] ?? newVals['title'] ?? oldVals['title'];
    final evalType = newVals['evaluation_type'] ?? oldVals['evaluation_type'] ?? newVals['target_role'] ?? oldVals['target_role'];
    if (name != null && name.toString().trim().isNotEmpty) {
      final nameStr = name.toString().trim();
      if (evalType != null && evalType.toString().trim().isNotEmpty) {
        final evalStr = evalType.toString().trim();
        if (!nameStr.toLowerCase().contains(evalStr.toLowerCase())) {
          return '$nameStr – ${_capitalizeFirst(evalStr)}';
        }
      }
      return nameStr;
    }

    // 2. User name
    final fullName = newVals['full_name'] ?? oldVals['full_name'];
    if (fullName != null && fullName.toString().trim().isNotEmpty) {
      return fullName.toString().trim();
    }
    final username = newVals['username'] ?? oldVals['username'];
    if (username != null && username.toString().trim().isNotEmpty) {
      return username.toString().trim();
    }

    // 3. Team name / project
    final team = newVals['team_name'] ?? oldVals['team_name'] ?? newVals['team'] ?? oldVals['team'];
    if (team != null && team.toString().trim().isNotEmpty) {
      return team.toString().trim();
    }

    // 4. Fallback to target type / id
    final targetType = log['target_type']?.toString();
    final targetId = log['target_id']?.toString();
    if (targetType != null && targetType.isNotEmpty) {
      return targetId != null ? '$targetType #$targetId' : targetType;
    }

    return 'System Resource';
  }

  static String formatProcessArea(Map<String, dynamic> log) {
    final category = log['category']?.toString() ?? '';
    final categoryLabel = log['category_label']?.toString() ?? '';
    final action = (log['action']?.toString() ?? '').toLowerCase();

    if (action.startsWith('rubric.') || action.contains('grade') || category == 'grade_center' || category == 'rubrics') {
      return 'Evaluation & Grades';
    }
    if (category == 'user_management' || action.startsWith('user.')) {
      return 'User Management';
    }
    if (category == 'defense' || action.contains('stage') || action.contains('schedule')) {
      return 'Defense Operations';
    }
    if (category == 'repository' || action.contains('archive')) {
      return 'Project Archive';
    }
    if (categoryLabel.isNotEmpty) {
      return categoryLabel;
    }
    return _capitalizeFirst(category.replaceAll('_', ' '));
  }

  static String formatTimestamp(String? isoString, {bool multiLine = false}) {
    if (isoString == null || isoString.isEmpty) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[dt.month - 1];
      final day = dt.day;
      final year = dt.year;

      final hour24 = dt.hour;
      final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour24 >= 12 ? 'PM' : 'AM';

      if (multiLine) {
        return '$month $day, $year\n$hour12:$minute $period';
      }
      return '$month $day, $year · $hour12:$minute $period';
    } catch (_) {
      return isoString;
    }
  }

  static List<AuditDiffEntry> computeDiff(
    Map<String, dynamic>? oldVals,
    Map<String, dynamic>? newVals,
  ) {
    final oldMap = oldVals ?? {};
    final newMap = newVals ?? {};
    final allKeys = {...oldMap.keys, ...newMap.keys}.toList();

    // Skip technical internal keys
    const ignoredKeys = {
      'id', 'created_at', 'updated_at', 'password', 'token',
      'ip_address', 'user_agent'
    };

    final result = <AuditDiffEntry>[];
    for (final key in allKeys) {
      if (ignoredKeys.contains(key.toLowerCase())) continue;
      final beforeVal = oldMap[key]?.toString() ?? '—';
      final afterVal = newMap[key]?.toString() ?? '—';
      final isChanged = beforeVal != afterVal;

      if (isChanged) {
        result.add(AuditDiffEntry(
          field: formatFieldLabel(key),
          before: beforeVal.isEmpty ? '—' : beforeVal,
          after: afterVal.isEmpty ? '—' : afterVal,
          isChanged: true,
        ));
      }
    }
    return result;
  }

  static List<MapEntry<String, String>> extractAttributes(
    Map<String, dynamic>? values,
  ) {
    if (values == null || values.isEmpty) return [];
    const ignoredKeys = {
      'id', 'created_at', 'updated_at', 'password', 'token',
      'ip_address', 'user_agent'
    };

    final list = <MapEntry<String, String>>[];
    values.forEach((k, v) {
      if (ignoredKeys.contains(k.toLowerCase())) return;
      final label = formatFieldLabel(k);
      final valStr = v?.toString() ?? '—';
      list.add(MapEntry(label, valStr.isEmpty ? '—' : valStr));
    });
    return list;
  }

  static String formatFieldLabel(String key) {
    final lower = key.toLowerCase();
    if (lower == 'name') return 'Name';
    if (lower == 'scope') return 'Scope';
    if (lower == 'semester' || lower == 'semester_id') return 'Semester';
    if (lower == 'evaluation_type') return 'Evaluation Type';
    if (lower == 'passing_score') return 'Passing Score';
    if (lower == 'description') return 'Description';
    if (lower == 'target_role') return 'Target Role';
    if (lower == 'username') return 'Username';
    if (lower == 'email') return 'Email';
    if (lower == 'role') return 'Role';
    if (lower == 'status') return 'Status';
    if (lower == 'is_active') return 'Active Status';

    return key
        .replaceAll('_', ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map(_capitalizeFirst)
        .join(' ');
  }

  static bool isDeleteAction(String? action) {
    final a = (action ?? '').toLowerCase();
    return a.contains('delete') || a.contains('remove');
  }

  static bool isCreateAction(String? action, Map<String, dynamic>? oldVals) {
    final a = (action ?? '').toLowerCase();
    if (a.contains('create') || a.contains('add')) return true;
    return oldVals == null || oldVals.isEmpty;
  }

  static bool isUpdateAction(String? action, Map<String, dynamic>? oldVals, Map<String, dynamic>? newVals) {
    if (isDeleteAction(action)) return false;
    final a = (action ?? '').toLowerCase();
    if (a.contains('update') || a.contains('edit') || a.contains('modify')) return true;
    return (oldVals != null && oldVals.isNotEmpty) && (newVals != null && newVals.isNotEmpty);
  }
}
