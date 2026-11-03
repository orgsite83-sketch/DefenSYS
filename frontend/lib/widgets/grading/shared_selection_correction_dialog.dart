import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../services/academic/section_concept_service.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../shadcn/defensys_action_menu.dart';
import '../shadcn/defensys_shadcn_scope.dart';

Future<bool> showSharedSelectionCorrection(
  BuildContext context,
  Map<String, dynamic> review,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SharedSelectionCorrectionDialog(review: review),
    ) ??
    false;

class SharedSelectionCorrectionMenu extends StatelessWidget {
  const SharedSelectionCorrectionMenu({
    super.key,
    required this.review,
    required this.onCorrect,
    this.enabled = true,
  });

  final Map<String, dynamic> review;
  final VoidCallback onCorrect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final correction = review['selection_correction'] as Map? ?? {};
    if (correction['is_chair'] != true ||
        '${review['selected_key'] ?? ''}'.isEmpty) {
      return const SizedBox.shrink();
    }
    return DefensysActionMenu(
      key: const ValueKey('shared-selection-actions'),
      label: 'More actions',
      enabled: enabled,
      items: [
        DefensysMenuItem(
          label: 'Correct shared selection',
          icon: LucideIcons.pencil,
          onPressed: enabled && correction['can_correct'] == true
              ? onCorrect
              : null,
          hint: '${correction['unavailable_reason'] ?? ''}',
        ),
      ],
    );
  }
}

class _SharedSelectionCorrectionDialog extends ConsumerStatefulWidget {
  const _SharedSelectionCorrectionDialog({required this.review});
  final Map<String, dynamic> review;
  @override
  ConsumerState<_SharedSelectionCorrectionDialog> createState() =>
      _SharedSelectionCorrectionState();
}

class SharedSelectionCorrectionHistory extends StatelessWidget {
  const SharedSelectionCorrectionHistory({super.key, required this.review});
  final Map<String, dynamic> review;
  @override
  Widget build(BuildContext context) {
    final history =
        ((review['selection_correction'] as Map?)?['history'] as List? ?? [])
            .whereType<Map>()
            .toList();
    if (history.isEmpty) return const SizedBox.shrink();
    final systems = (review['systems'] as List? ?? []).whereType<Map>();
    String title(dynamic key) =>
        '${systems.where((s) => s['key'] == key).firstOrNull?['title'] ?? key}';
    return ShadAccordion<String>(
      children: [
        ShadAccordionItem(
          value: 'selection-corrections',
          title: const Text('Selection history'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final change in history.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${title(change['from_key'])} → ${title(change['to_key'])}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${change['by_name']} · ${change['reason']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SharedSelectionCorrectionState
    extends ConsumerState<_SharedSelectionCorrectionDialog> {
  final _reason = TextEditingController();
  String? _target;
  bool _reviewing = false, _busy = false;
  Map get _correction => widget.review['selection_correction'] as Map? ?? {};
  List<Map> _rows(dynamic value) =>
      (value as List? ?? []).whereType<Map>().toList();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy ||
        _target == null ||
        _reason.text.trim().isEmpty ||
        _correction['can_correct'] != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      // This is the token reviewed when the dialog opened, including all teams.
      await ref
          .read(sectionConceptServiceProvider)
          .action(widget.review, 'correct_selection', {
            'concept_key': _target,
            'remarks': _reason.text.trim(),
            'review_token': _correction['review_token'],
          });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showErrorToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final systems = _rows(widget.review['systems']);
    final from =
        '${_correction['from_key'] ?? widget.review['selected_key'] ?? ''}';
    String title(String? key) =>
        '${systems.where((s) => s['key'] == key).firstOrNull?['title'] ?? key ?? ''}';
    final muted = DefensysTokens.textSecondaryOf(context);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: DefensysTokens.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        ),
        child: DefensysShadcnScope(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height - 64,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _reviewing
                        ? 'Review shared-system correction'
                        : 'Correct shared-system selection',
                    style: DefensysTokens.dialogTitle.copyWith(
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Current system',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title(from),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  if (!_reviewing) ...[
                    const Text(
                      'Correct system',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) => ShadRadioGroup<String>(
                        initialValue: _target,
                        enabled: !_busy,
                        spacing: 14,
                        items: [
                          for (final system in systems.where(
                            (s) => s['key'] != from,
                          ))
                            SizedBox(
                              width: constraints.maxWidth,
                              child: ShadRadio<String>(
                                value: '${system['key']}',
                                color: DefensysTokens.maroonTextOf(context),
                                label: Text('${system['title']}'),
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _target = value),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Reason',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ShadInput(
                      controller: _reason,
                      placeholder: const Text('Explain the correction'),
                      maxLines: 3,
                      maxLength: 5000,
                      onChanged: (_) => setState(() {}),
                    ),
                  ] else ...[
                    Text(
                      'Correct system',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title(_target),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Divider(
                      height: 28,
                      color: DefensysTokens.borderOf(context),
                    ),
                    Text(
                      'Affects all ${_rows(_correction['teams']).length} participating teams',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final team in _rows(_correction['teams'])) ...[
                      const SizedBox(height: 16),
                      Text(
                        '${team['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'From: ${(team['module_titles'] as Map?)?[from] ?? ''}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'To: ${(team['module_titles'] as Map?)?[_target] ?? ''}',
                      ),
                    ],
                    Divider(
                      height: 28,
                      color: DefensysTokens.borderOf(context),
                    ),
                    Text(_reason.text.trim()),
                    const SizedBox(height: 12),
                    Text(
                      'Existing assessments for the corrected module will be used. Missing evaluations stay pending. Earlier scores and drafts remain attached to their original modules.',
                      style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      ShadButton.ghost(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      if (_reviewing)
                        ShadButton.outline(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _reviewing = false),
                          child: const Text('Back'),
                        ),
                      ShadButton(
                        backgroundColor: DefensysTokens.maroonOf(context),
                        foregroundColor: Colors.white,
                        onPressed:
                            _busy ||
                                _target == null ||
                                _reason.text.trim().isEmpty
                            ? null
                            : _reviewing
                            ? _confirm
                            : () => setState(() => _reviewing = true),
                        child: Text(
                          _busy
                              ? 'Confirming...'
                              : _reviewing
                              ? 'Confirm correction'
                              : 'Review correction',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
