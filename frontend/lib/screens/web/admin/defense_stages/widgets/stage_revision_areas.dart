import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../utils/operation_request_id.dart';

class StageRevisionAreas extends StatefulWidget {
  const StageRevisionAreas({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<Map<String, dynamic>> value;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;

  @override
  State<StageRevisionAreas> createState() => _StageRevisionAreasState();
}

class _StageRevisionAreasState extends State<StageRevisionAreas> {
  final Map<String, TextEditingController> _labels = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StageRevisionAreas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final ids = widget.value.map((area) => '${area['id']}').toSet();
    for (final key in _labels.keys.toList()) {
      if (!ids.contains(key)) _labels.remove(key)!.dispose();
    }
    for (final area in widget.value) {
      _labels.putIfAbsent(
        '${area['id']}',
        () => TextEditingController(text: '${area['label'] ?? ''}'),
      );
    }
  }

  void _change(String id, Map<String, dynamic> fields) => widget.onChanged([
    for (final area in widget.value)
      area['id'] == id ? {...area, ...fields} : {...area},
  ]);

  @override
  void dispose() {
    for (final controller in _labels.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Revision areas',
        style: DefensysTokens.sectionTitle.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Configure the areas the chair decides on. New hearings capture these settings; existing hearings retain their policy.',
        style: DefensysTokens.caption.copyWith(
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      for (final area in widget.value)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(
                key: ValueKey('revision-area-${area['id']}'),
                controller: _labels['${area['id']}'],
                placeholder: const Text(
                  'For example: Concept, System, Manuscript',
                ),
                enabled: widget.enabled,
                maxLength: 80,
                onChanged: (value) =>
                    _change('${area['id']}', {'label': value}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ShadCheckbox(
                    value: area['allows_demo'] == true,
                    enabled: widget.enabled,
                    label: const Text('Allow re-demo for this area'),
                    onChanged: (value) =>
                        _change('${area['id']}', {'allows_demo': value}),
                  ),
                  ShadButton.ghost(
                    enabled: widget.enabled,
                    onPressed: () => widget.onChanged([
                      for (final row in widget.value)
                        if (row['id'] != area['id']) {...row},
                    ]),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      ShadButton.outline(
        enabled: widget.enabled && widget.value.length < 12,
        onPressed: () => widget.onChanged([
          ...widget.value,
          {'id': newOperationRequestId(), 'label': '', 'allows_demo': false},
        ]),
        child: const Text('Add revision area'),
      ),
    ],
  );
}
