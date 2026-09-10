import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';

/// Interactive modal allowing users to toggle and customize signatories on exports.
class DefensysSignatoryCustomizerDialog extends StatefulWidget {
  final List<DefensysSignatory> initialSignatories;
  final bool initialIncludeSignatures;
  final List<DefensysSignatory>? defaultSignatories;
  final void Function(List<DefensysSignatory> signatories, bool includeSignatures) onApply;

  const DefensysSignatoryCustomizerDialog({
    super.key,
    required this.initialSignatories,
    required this.initialIncludeSignatures,
    this.defaultSignatories,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required List<DefensysSignatory> currentSignatories,
    required bool currentIncludeSignatures,
    List<DefensysSignatory>? defaultSignatories,
    required void Function(List<DefensysSignatory> signatories, bool includeSignatures) onApply,
  }) {
    return showDialog(
      context: context,
      builder: (dialogCtx) => DefensysSignatoryCustomizerDialog(
        initialSignatories: currentSignatories,
        initialIncludeSignatures: currentIncludeSignatures,
        defaultSignatories: defaultSignatories,
        onApply: onApply,
      ),
    );
  }

  @override
  State<DefensysSignatoryCustomizerDialog> createState() => _DefensysSignatoryCustomizerDialogState();
}

class _DefensysSignatoryCustomizerDialogState extends State<DefensysSignatoryCustomizerDialog> {
  late bool _includeSignatures;
  late List<Map<String, String>> _signatories;
  late List<String> _availableLabels;
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _roleControllers;

  @override
  void initState() {
    super.initState();
    _includeSignatures = widget.initialIncludeSignatures;
    _signatories = widget.initialSignatories
        .map((s) => {'label': s.label, 'name': s.name, 'role': s.role})
        .toList();

    if (_signatories.isEmpty) {
      _signatories = [
        {'label': 'Prepared by:', 'name': '', 'role': 'Academic Documenter / Evaluator'},
        {'label': 'Noted by:', 'name': '', 'role': 'Project Adviser / Panel Chair'},
        {'label': 'Approved by:', 'name': 'IT Program Chairperson', 'role': 'IT Program Chairperson'},
      ];
    }

    _nameControllers = _signatories.map((s) => TextEditingController(text: s['name'] ?? '')).toList();
    _roleControllers = _signatories.map((s) => TextEditingController(text: s['role'] ?? '')).toList();

    _availableLabels = [
      'Prepared by:',
      'Noted by:',
      'Approved by:',
      'Verified by:',
      'Attested by:',
      'Certified Correct by:',
    ];

    for (final s in _signatories) {
      final lbl = s['label'] ?? '';
      if (lbl.isNotEmpty && !_availableLabels.contains(lbl)) {
        _availableLabels.add(lbl);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _roleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _promptCustomLabel(int signerIndex) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (promptCtx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.label_outline_rounded, color: DefensysTokens.maroon, size: 20),
              SizedBox(width: 8),
              Text('Add Custom Signatory Label', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter header label for this signatory (e.g. Verified by:, Attested by:, Dean:)',
                style: TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                autofocus: true,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'e.g. Verified by:',
                  hintStyle: const TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    borderSide: const BorderSide(color: DefensysTokens.border),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(promptCtx).pop(),
              child: const Text('Cancel', style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusSm)),
              ),
              onPressed: () {
                final entered = textController.text.trim();
                if (entered.isNotEmpty) {
                  final formatted = entered.endsWith(':') ? entered : '$entered:';
                  setState(() {
                    if (!_availableLabels.contains(formatted)) {
                      _availableLabels.add(formatted);
                    }
                    _signatories[signerIndex]['label'] = formatted;
                  });
                }
                Navigator.of(promptCtx).pop();
              },
              child: const Text('Add & Apply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSignatoryEditorRow(int idx) {
    final s = _signatories[idx];
    final currentLabel = s['label'] ?? 'Prepared by:';
    if (!_availableLabels.contains(currentLabel)) {
      _availableLabels.add(currentLabel);
    }

    final menuItems = <DropdownMenuItem<String>>[
      ..._availableLabels.map((lbl) => DropdownMenuItem(
            value: lbl,
            child: Text(lbl, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          )),
      const DropdownMenuItem(
        value: '__ADD_CUSTOM__',
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 14, color: DefensysTokens.maroon),
            SizedBox(width: 4),
            Text('Custom Label...', style: TextStyle(fontSize: 11.5, color: DefensysTokens.maroon, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.maroon,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Label Dropdown
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: DropdownButtonFormField<String>(
                    initialValue: currentLabel,
                    isDense: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                    ),
                    items: menuItems,
                    onChanged: (val) {
                      if (val == '__ADD_CUSTOM__') {
                        _promptCustomLabel(idx);
                      } else if (val != null) {
                        setState(() => _signatories[idx]['label'] = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_signatories.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                  tooltip: 'Remove Signatory',
                  onPressed: () {
                    setState(() {
                      _signatories.removeAt(idx);
                      _nameControllers.removeAt(idx).dispose();
                      _roleControllers.removeAt(idx).dispose();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Signatory Name TextField
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _nameControllers[idx],
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Signatory Name',
                    labelStyle: const TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                    hintText: 'e.g. John Doe, MSIT',
                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Signatory Role / Title TextField
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _roleControllers[idx],
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Designation / Institutional Role',
                    labelStyle: const TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                    hintText: 'e.g. Capstone Project Adviser',
                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(bottom: BorderSide(color: DefensysTokens.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    ),
                    child: const Icon(Icons.history_edu_rounded, size: 20, color: DefensysTokens.maroon),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure PDF Report Signatories',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Customize certification statement, signatory count, names, roles, or toggle signatures off.',
                          style: TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Toggle Switch Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _includeSignatures ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        border: Border.all(
                          color: _includeSignatures ? const Color(0xFFFDE68A) : DefensysTokens.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _includeSignatures ? Icons.verified_outlined : Icons.do_not_disturb_on_outlined,
                            color: _includeSignatures ? const Color(0xFFD97706) : DefensysTokens.steelGrey,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Include Signatory & Certification Block',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _includeSignatures ? const Color(0xFF92400E) : DefensysTokens.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _includeSignatures
                                      ? 'Institutional certification disclaimer and signature lines will be rendered on the PDF.'
                                      : 'Signatures and certification disclaimer will be completely omitted from the export.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _includeSignatures ? const Color(0xFFB45309) : DefensysTokens.steelGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _includeSignatures,
                            activeThumbColor: DefensysTokens.maroon,
                            onChanged: (val) {
                              setState(() => _includeSignatures = val);
                            },
                          ),
                        ],
                      ),
                    ),

                    if (_includeSignatures) ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text(
                            'CONFIGURED SIGNATORIES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.steelGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroon.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                            ),
                            child: Text(
                              '${_signatories.length} ${_signatories.length == 1 ? "Signer" : "Signers"}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: DefensysTokens.maroon,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Signatory', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () {
                              setState(() {
                                _signatories.add({
                                  'label': 'Approved by:',
                                  'name': '',
                                  'role': 'Academic Reviewer',
                                });
                                _nameControllers.add(TextEditingController(text: ''));
                                _roleControllers.add(TextEditingController(text: 'Academic Reviewer'));
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Signatories List
                      ...List.generate(_signatories.length, (idx) => _buildSignatoryEditorRow(idx)),
                    ],
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                border: Border(top: BorderSide(color: DefensysTokens.border)),
              ),
              child: Row(
                children: [
                  if (widget.defaultSignatories != null && widget.defaultSignatories!.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: DefensysTokens.steelGrey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () {
                        setState(() {
                          for (final c in _nameControllers) {
                            c.dispose();
                          }
                          for (final c in _roleControllers) {
                            c.dispose();
                          }
                          _signatories = widget.defaultSignatories!
                              .map((s) => {'label': s.label, 'name': s.name, 'role': s.role})
                              .toList();
                          _nameControllers = _signatories.map((s) => TextEditingController(text: s['name'] ?? '')).toList();
                          _roleControllers = _signatories.map((s) => TextEditingController(text: s['role'] ?? '')).toList();
                        });
                      },
                      child: const Text('Reset Defaults', style: TextStyle(fontSize: 12)),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DefensysTokens.textDark,
                      side: const BorderSide(color: DefensysTokens.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
                    ),
                    onPressed: () {
                      final updatedList = <DefensysSignatory>[];
                      for (int i = 0; i < _signatories.length; i++) {
                        updatedList.add(DefensysSignatory(
                          label: _signatories[i]['label'] ?? 'Prepared by:',
                          name: _nameControllers[i].text.trim(),
                          role: _roleControllers[i].text.trim(),
                        ));
                      }

                      widget.onApply(updatedList, _includeSignatures);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply Signatories', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
