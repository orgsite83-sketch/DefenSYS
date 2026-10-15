import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeliverablePresetScope { capstone, pit }

class StageDeliverablePreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<Map<String, dynamic>> deliverables;
  final bool isCustom;

  const StageDeliverablePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.deliverables,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'deliverables': deliverables,
    'is_custom': isCustom,
  };

  factory StageDeliverablePreset.fromJson(Map<String, dynamic> json) =>
      StageDeliverablePreset(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Untitled Preset',
        description: json['description']?.toString() ?? '',
        icon: Icons.bookmark_border_rounded,
        deliverables: (json['deliverables'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((d) => Map<String, dynamic>.from(d))
                .toList() ??
            [],
        isCustom: true,
      );
}

class StageDeliverablePresetManager {
  static const _prefKey = 'defensys_custom_stage_presets_v1';

  static bool pitEventMatchesYearLevel(String eventYearLevel, String yearLevel) {
    if (yearLevel.trim().isEmpty) return false;
    return eventYearLevel.trim().toLowerCase() == yearLevel.trim().toLowerCase();
  }

  static String? _storageKey(DeliverablePresetScope scope, String? yearLevel) {
    if (scope == DeliverablePresetScope.capstone) return _prefKey;
    final year = yearLevel?.trim().toLowerCase() ?? '';
    if (year.isEmpty) return null;
    return 'defensys_custom_pit_presets_v1_${year.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
  }

  static const conceptHearing = StageDeliverablePreset(
    id: 'concept_hearing',
    name: 'Concept Proposal / Title Hearing',
    description: 'Adviser acceptance, panel nomination, hearing form, and concept paper draft.',
    icon: Icons.lightbulb_outline_rounded,
    deliverables: [
      {
        'deliverable_id': 'D1',
        'label': 'Adviser Acceptance Form',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 1,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D2',
        'label': 'Nomination of Panel Members',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 2,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D3',
        'label': 'Approved Concept Hearing Form',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 3,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D4',
        'label': 'Concept Paper Manuscript Draft',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 4,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': true,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D5',
        'label': 'Approved Concept Paper',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 5,
        'archive_note': '',
        'archive_file_template': '{project}_{deliverable}',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
    ],
  );

  static const outlineProposal = StageDeliverablePreset(
    id: 'outline_proposal',
    name: 'Project Proposal / Outline Defense',
    description: 'Adviser endorsement, manuscript draft, slides, and revision compliance matrix.',
    icon: Icons.menu_book_rounded,
    deliverables: [
      {
        'deliverable_id': 'D1',
        'label': 'Adviser Endorsement Form',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 1,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D2',
        'label': 'Proposal Manuscript Draft',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 2,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': true,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D3',
        'label': 'Oral Defense Slide Deck',
        'deliverable_type': 'pre',
        'requirement_timing': 'defense',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 3,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': true,
        'verdict_condition': 'all_pass',
        'file_format': 'presentation',
      },
      {
        'deliverable_id': 'D4',
        'label': 'Approved Proposal Manuscript',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 4,
        'archive_note': '',
        'archive_file_template': '{project}_{deliverable}',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D5',
        'label': 'Revision Compliance Matrix',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 5,
        'archive_note': '',
        'archive_file_template': '{project}_{deliverable}',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'revisions_only',
        'file_format': 'pdf',
      },
    ],
  );

  static const finalDefense = StageDeliverablePreset(
    id: 'final_defense',
    name: 'Colloquium / Final Oral Defense & Archiving',
    description: 'Final manuscript, similarity clearance, defense deck, archive package, and revisions.',
    icon: Icons.school_rounded,
    deliverables: [
      {
        'deliverable_id': 'D1',
        'label': 'Adviser Endorsement Form',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 1,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D2',
        'label': 'Final Manuscript Draft',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 2,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': true,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D3',
        'label': 'Turnitin / Similarity Index Clearance',
        'deliverable_type': 'pre',
        'requirement_timing': 'scheduling',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 3,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D4',
        'label': 'Oral Defense Slide Deck',
        'deliverable_type': 'pre',
        'requirement_timing': 'defense',
        'deadline_hours_before': 24,
        'required': true,
        'display_order': 4,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
        'is_defense_material': true,
        'verdict_condition': 'all_pass',
        'file_format': 'presentation',
      },
      {
        'deliverable_id': 'D5',
        'label': 'Final Approved Hardbound Manuscript',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 5,
        'archive_note': '',
        'archive_file_template': '{project}',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D6',
        'label': 'Revision Compliance Matrix',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 6,
        'archive_note': '',
        'archive_file_template': '{project}_{deliverable}',
        'is_restricted': false,
        'is_defense_material': false,
        'verdict_condition': 'revisions_only',
        'file_format': 'pdf',
      },
      {
        'deliverable_id': 'D7',
        'label': 'Source Code & Project Deliverables Archive',
        'deliverable_type': 'post',
        'required': true,
        'display_order': 7,
        'archive_note': '',
        'archive_file_template': '{project}_source_code',
        'is_restricted': true,
        'is_defense_material': false,
        'verdict_condition': 'all_pass',
        'file_format': 'archive',
      },
    ],
  );

  static List<StageDeliverablePreset> get builtInPresets => [
        conceptHearing,
        outlineProposal,
        finalDefense,
      ];

  /// Deep clones a list of deliverable definitions, assigning clean order IDs.
  static List<Map<String, dynamic>> cloneDeliverables(List<dynamic> source) {
    final cloned = <Map<String, dynamic>>[];
    for (int i = 0; i < source.length; i++) {
      final raw = source[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      item['deliverable_id'] = 'D${i + 1}';
      item['display_order'] = i + 1;
      // Remove any attached UI controllers so fresh ones can attach
      item.remove('_labelController');
      item.remove('_templateController');
      cloned.add(item);
    }
    return cloned;
  }

  /// Copies deliverables from an existing stage or PIT event map.
  static List<Map<String, dynamic>> copyFromSource(Map<String, dynamic> source) {
    final delivs = source['deliverables'];
    if (delivs is List) {
      return cloneDeliverables(delivs);
    }
    return [];
  }

  /// Loads custom user-saved presets from SharedPreferences.
  static Future<List<StageDeliverablePreset>> loadCustomPresets({
    DeliverablePresetScope scope = DeliverablePresetScope.capstone,
    String? yearLevel,
  }) async {
    try {
      final key = _storageKey(scope, yearLevel);
      if (key == null) return [];
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => StageDeliverablePreset.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Saves a custom preset to SharedPreferences.
  static Future<void> saveCustomPreset(
    String name,
    List<Map<String, dynamic>> items, {
    DeliverablePresetScope scope = DeliverablePresetScope.capstone,
    String? yearLevel,
  }) async {
    try {
      final key = _storageKey(scope, yearLevel);
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadCustomPresets(scope: scope, yearLevel: yearLevel);
      final newPreset = StageDeliverablePreset(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}_${existing.length}',
        name: name.trim().isEmpty ? 'Custom Preset' : name.trim(),
        description: '${items.length} deliverables checklist',
        icon: Icons.bookmark_border_rounded,
        deliverables: cloneDeliverables(items),
        isCustom: true,
      );
      existing.add(newPreset);
      final jsonList = existing.map((p) => p.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (_) {}
  }

  /// Deletes a custom preset from SharedPreferences.
  static Future<void> deleteCustomPreset(
    String id, {
    DeliverablePresetScope scope = DeliverablePresetScope.capstone,
    String? yearLevel,
  }) async {
    try {
      final key = _storageKey(scope, yearLevel);
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadCustomPresets(scope: scope, yearLevel: yearLevel);
      existing.removeWhere((p) => p.id == id);
      final jsonList = existing.map((p) => p.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (_) {}
  }

  /// Move a legacy unscoped preset only when both its name and checklist match
  /// an existing PIT event. Ambiguous presets stay with the Capstone presets.
  static Future<void> adoptMatchingLegacyPitPresets(
    String yearLevel,
    List<Map<String, dynamic>> events,
  ) async {
    final key = _storageKey(DeliverablePresetScope.pit, yearLevel);
    if (key == null || events.isEmpty) return;
    try {
      final legacy = await loadCustomPresets();
      final pit = await loadCustomPresets(
        scope: DeliverablePresetScope.pit,
        yearLevel: yearLevel,
      );
      final matched = <StageDeliverablePreset>[];
      for (final preset in legacy) {
        final presetLabels = preset.deliverables
            .map((d) => d['label']?.toString().trim().toLowerCase())
            .toList();
        if (events.any((event) {
          final eventLabels = (event['deliverables'] as List? ?? [])
              .whereType<Map>()
              .map((d) => d['label']?.toString().trim().toLowerCase())
              .toList();
          return preset.name.trim().toLowerCase() ==
                  event['label']?.toString().trim().toLowerCase() &&
              presetLabels.isNotEmpty &&
              presetLabels.every((label) => label != null && label.isNotEmpty) &&
              presetLabels.length == eventLabels.length &&
              _sameLabels(presetLabels, eventLabels);
        })) {
          matched.add(preset);
        }
      }
      if (matched.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final pitIds = pit.map((p) => p.id).toSet();
      pit.addAll(matched.where((p) => !pitIds.contains(p.id)));
      final saved = await prefs.setString(
        key,
        jsonEncode(pit.map((p) => p.toJson()).toList()),
      );
      if (!saved) return;
      final matchedIds = matched.map((p) => p.id).toSet();
      legacy.removeWhere((p) => matchedIds.contains(p.id));
      await prefs.setString(
        _prefKey,
        jsonEncode(legacy.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }

  static bool _sameLabels(List<String?> a, List<String?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
