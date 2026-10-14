import 'package:flutter/material.dart';
import 'stage_deliverable_presets.dart';

class StageDeliverablePresetsBar extends StatefulWidget {
  final List<Map<String, dynamic>> existingStages;
  final List<Map<String, dynamic>> currentDeliverables;
  final ValueChanged<List<Map<String, dynamic>>> onApplyDeliverables;
  final bool enabled;
  final DeliverablePresetScope scope;
  final String? yearLevel;
  final Object? currentSourceId;

  const StageDeliverablePresetsBar({
    super.key,
    required this.existingStages,
    required this.currentDeliverables,
    required this.onApplyDeliverables,
    this.enabled = true,
    this.scope = DeliverablePresetScope.capstone,
    this.yearLevel,
    this.currentSourceId,
  });

  @override
  State<StageDeliverablePresetsBar> createState() => _StageDeliverablePresetsBarState();
}

class _StageDeliverablePresetsBarState extends State<StageDeliverablePresetsBar> {
  List<StageDeliverablePreset> _customPresets = [];
  bool _loadingCustom = false;

  @override
  void initState() {
    super.initState();
    _loadCustomPresets();
  }

  @override
  void didUpdateWidget(covariant StageDeliverablePresetsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.yearLevel != widget.yearLevel) {
      _loadCustomPresets();
    }
  }

  bool get _isPit => widget.scope == DeliverablePresetScope.pit;
  bool get _hasPresetScope => !_isPit || widget.yearLevel?.trim().isNotEmpty == true;
  String get _sourceLabel => _isPit ? 'Event' : 'Stage';

  List<Map<String, dynamic>> get _scopedSources => widget.existingStages.where((s) {
    if (_isPit) {
      return s['scope'] == 'pit' &&
          StageDeliverablePresetManager.pitEventMatchesYearLevel(
            s['label']?.toString() ?? '',
            widget.yearLevel ?? '',
          );
    }
    return s['scope'] != 'pit';
  }).toList();

  Future<void> _loadCustomPresets() async {
    setState(() => _loadingCustom = true);
    final scope = widget.scope;
    final yearLevel = widget.yearLevel;
    if (scope == DeliverablePresetScope.pit && yearLevel != null) {
      await StageDeliverablePresetManager.adoptMatchingLegacyPitPresets(
        yearLevel,
        _scopedSources,
      );
    }
    final list = await StageDeliverablePresetManager.loadCustomPresets(
      scope: scope,
      yearLevel: yearLevel,
    );
    if (mounted && widget.scope == scope && widget.yearLevel == yearLevel) {
      setState(() {
        _customPresets = list;
        _loadingCustom = false;
      });
    }
  }

  Future<void> _handlePresetSelected(List<Map<String, dynamic>> presetDeliverables, String title) async {
    if (!widget.enabled) return;

    if (widget.currentDeliverables.isEmpty) {
      widget.onApplyDeliverables(StageDeliverablePresetManager.cloneDeliverables(presetDeliverables));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded "$title" (${presetDeliverables.length} deliverables).'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Prompt replace or append
    final action = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF334155), size: 22),
            SizedBox(width: 8),
            Text('Apply preset?'),
          ],
        ),
        content: Text(
          'You already have ${widget.currentDeliverables.length} deliverables configured. '
          'Would you like to replace them or append the preset items to your existing checklist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogCtx, 'append'),
            child: const Text('Append to List'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, 'replace'),
            child: const Text('Replace All'),
          ),
        ],
      ),
    );

    if (action == 'replace') {
      widget.onApplyDeliverables(StageDeliverablePresetManager.cloneDeliverables(presetDeliverables));
    } else if (action == 'append') {
      final combined = [
        ...widget.currentDeliverables,
        ...presetDeliverables,
      ];
      widget.onApplyDeliverables(StageDeliverablePresetManager.cloneDeliverables(combined));
    }
  }

  Future<void> _handleSaveAsPreset() async {
    if (widget.currentDeliverables.isEmpty) return;

    final nameController = TextEditingController(
      text: _isPit ? 'My Event Checklist' : 'My Stage Checklist',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined, color: Color(0xFF334155), size: 22),
            SizedBox(width: 8),
            Text('Save as Custom Preset'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save your ${widget.currentDeliverables.length} configured deliverables as a reusable preset for future ${_isPit ? '${widget.yearLevel ?? 'this year'} PIT events' : 'stages'}:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Preset Name',
                hintText: _isPit
                    ? 'e.g. PIT Showcase Checklist'
                    : 'e.g. BSIT Capstone 1 Checklist',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Save Preset'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      await StageDeliverablePresetManager.saveCustomPreset(
        nameController.text.trim(),
        widget.currentDeliverables,
        scope: widget.scope,
        yearLevel: widget.yearLevel,
      );
      await _loadCustomPresets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved custom preset "${nameController.text.trim()}".'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesWithDeliverables = _scopedSources.where((s) {
      final d = s['deliverables'];
      return d is List &&
          d.isNotEmpty &&
          (widget.currentSourceId == null ||
              s['id']?.toString() != widget.currentSourceId.toString());
    }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.flash_on_rounded, color: Color(0xFF475569), size: 15),
              ),
              const SizedBox(width: 8),
              const Text(
                'Quick Presets:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                _isPit
                    ? 'PIT · ${_hasPresetScope ? widget.yearLevel : 'Unassigned year'}'
                    : 'Capstone',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),

          // 1. Load Preset Menu (Clean Shadcn White)
          Theme(
            data: Theme.of(context).copyWith(
              hoverColor: const Color(0xFFF4F4F5),
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
            ),
            child: PopupMenuButton<StageDeliverablePreset>(
              enabled: widget.enabled && _hasPresetScope,
              tooltip: _isPit
                  ? 'Load saved PIT event checklist preset'
                  : 'Load standard or saved checklist preset',
              offset: const Offset(0, 38),
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              itemBuilder: (context) {
                final items = <PopupMenuEntry<StageDeliverablePreset>>[];

                // Capstone templates are not valid for PIT event checklists.
                if (!_isPit) {
                  items.add(const PopupMenuItem<StageDeliverablePreset>(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'RECOMMENDED TEMPLATES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ));
                }

                for (final preset in _isPit
                    ? <StageDeliverablePreset>[]
                    : StageDeliverablePresetManager.builtInPresets) {
                  items.add(
                    PopupMenuItem<StageDeliverablePreset>(
                      value: preset,
                      child: Row(
                        children: [
                          Icon(preset.icon, size: 16, color: const Color(0xFF334155)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  preset.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${preset.deliverables.length} files • ${preset.description}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Custom user-saved presets
                if (_customPresets.isNotEmpty) {
                  if (!_isPit) {
                    items.add(const PopupMenuDivider(height: 1));
                  }
                  items.add(
                    PopupMenuItem<StageDeliverablePreset>(
                      enabled: false,
                      height: 28,
                      child: Text(
                        _isPit ? 'SAVED ${widget.yearLevel?.toUpperCase() ?? 'PIT'} PIT PRESETS' : 'SAVED CUSTOM PRESETS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );

                  for (final custom in _customPresets) {
                    items.add(
                      PopupMenuItem<StageDeliverablePreset>(
                        value: custom,
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_added_rounded, size: 16, color: Color(0xFF475569)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${custom.name} (${custom.deliverables.length} files)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }

                if (_isPit && _customPresets.isEmpty) {
                  items.add(PopupMenuItem<StageDeliverablePreset>(
                    enabled: false,
                    child: Text(
                      _loadingCustom
                          ? 'Loading saved presets...'
                          : 'No saved presets for ${widget.yearLevel ?? 'this PIT year'} yet',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ));
                }

                return items;
              },
              onSelected: (preset) => _handlePresetSelected(preset.deliverables, preset.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFF334155)),
                    SizedBox(width: 5),
                    Text(
                      'Load Preset',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                  ],
                ),
              ),
            ),
          ),

          // 2. Copy from an existing source in the same scope.
          if (sourcesWithDeliverables.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(
                hoverColor: const Color(0xFFF4F4F5),
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
              ),
              child: PopupMenuButton<Map<String, dynamic>>(
                enabled: widget.enabled,
                tooltip: 'Copy checklist from another ${_sourceLabel.toLowerCase()}',
                offset: const Offset(0, 38),
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
                itemBuilder: (context) {
                  return [
                    PopupMenuItem<Map<String, dynamic>>(
                      enabled: false,
                      height: 28,
                      child: Text(
                        _isPit ? 'EXISTING PIT EVENTS' : 'EXISTING STAGES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    for (final stage in sourcesWithDeliverables)
                      PopupMenuItem<Map<String, dynamic>>(
                        value: stage,
                        child: Row(
                          children: [
                            const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF475569)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${stage['label']} (${(stage['deliverables'] as List).length} files)',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ];
                },
                onSelected: (stage) {
                  final delivs = StageDeliverablePresetManager.copyFromSource(stage);
                  _handlePresetSelected(delivs, stage['label']?.toString() ?? _sourceLabel);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x06000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.content_copy_rounded, size: 14, color: Color(0xFF334155)),
                      const SizedBox(width: 5),
                      Text(
                        'Copy from $_sourceLabel',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Save as Preset Button (Clean Shadcn White)
          if (widget.currentDeliverables.isNotEmpty && _hasPresetScope)
            InkWell(
              onTap: widget.enabled ? _handleSaveAsPreset : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_add_outlined, size: 14, color: Color(0xFF334155)),
                    SizedBox(width: 5),
                    Text(
                      'Save as Preset',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
