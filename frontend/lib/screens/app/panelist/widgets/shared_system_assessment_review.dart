import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/academic/section_concept_service.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../panelist_models.dart';
import 'defense_materials_card.dart';

/// One section hearing, shared by every participating team's grading workspace.
class SharedSystemAssessmentReview extends ConsumerStatefulWidget {
  const SharedSystemAssessmentReview({
    super.key,
    required this.team,
    required this.onView,
    required this.onUpdated,
  });
  final TeamData team;
  final ValueChanged<Map<String, dynamic>> onView;
  final Future<void> Function() onUpdated;
  @override
  ConsumerState<SharedSystemAssessmentReview> createState() =>
      _SharedSystemAssessmentReviewState();
}

class _SharedSystemAssessmentReviewState
    extends ConsumerState<SharedSystemAssessmentReview> {
  late Map<String, dynamic> _review;
  late final TextEditingController _notes;
  late String _sourceSignature;
  String? _selection;
  bool _busy = false;
  final _instructions = ShadAccordionController<String>();

  @override
  void initState() {
    super.initState();
    _review = widget.team.sharedReview ?? {};
    _sourceSignature = jsonEncode(_review);
    _notes = TextEditingController(text: (_review['remarks'] ?? '').toString());
  }

  @override
  void didUpdateWidget(covariant SharedSystemAssessmentReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.team.sharedReview ?? {};
    final signature = jsonEncode(next);
    if (signature == _sourceSignature) return;
    _sourceSignature = signature;
    final changed =
        next['round_id'] != _review['round_id'] || next['id'] != _review['id'];
    if (changed) {
      _selection = null;
      _instructions.value = [];
      _notes.text = (next['remarks'] ?? '').toString();
    } else if ((_review['verdict'] ?? '').toString().isNotEmpty &&
        (next['verdict'] ?? '').toString().isEmpty) {
      // A late assignment refresh cannot undo a successful decision response.
      return;
    }
    _review = next;
  }

  @override
  void dispose() {
    _notes.dispose();
    _instructions.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> rows(dynamic value) => (value as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  Future<void> _submit(String verdict) async {
    if (_busy ||
        _review['can_decide'] != true ||
        (_review['verdict'] ?? '').toString().isNotEmpty) {
      return;
    }
    final retry = verdict == 'for_redefense';
    if (!retry && _selection == null) return;
    if (verdict != 'approved' && _notes.text.trim().isEmpty) return;
    final systems = rows(_review['systems']);
    final selected = systems
        .where((row) => row['key'] == _selection)
        .firstOrNull;
    final teams = rows(_review['teams']);
    final confirmed = await showConfirmDialog(
      context,
      title: retry
          ? 'Request another shared hearing?'
          : 'Confirm shared system?',
      message:
          '${retry ? 'The shared proposals will require another hearing.' : (selected?['title'] ?? '').toString()}\nApplies to ${_review['section'] ?? ''} and ${teams.length} participating teams.',
      confirmLabel: retry
          ? 'Request shared hearing'
          : 'Confirm shared direction',
      confirmColor: DefensysTokens.saveActionBg,
      contentPrefix: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                team['name'].toString(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(sectionConceptServiceProvider).action(
        _review,
        'decide',
        {
          'verdict': verdict,
          'remarks': _notes.text.trim(),
          'concepts': [
            for (final system in systems)
              {
                'key': system['key'],
                'decision': retry
                    ? 'rejected'
                    : system['key'] == _selection
                    ? verdict
                    : 'not_selected',
                'remarks': retry || system['key'] == _selection
                    ? _notes.text.trim()
                    : '',
              },
          ],
        },
      );
      if (!mounted) return;
      setState(() => _review = {..._review, ...updated, 'can_decide': false});
      try {
        await widget.onUpdated();
        if (mounted) {
          showSuccessToast(context, 'Shared system decision recorded.');
        }
      } catch (_) {
        if (mounted) {
          showErrorToast(
            context,
            'Decision recorded. Refresh to load the updated team results.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        showErrorToast(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _emptyFiles =>
      widget.team.gradingWorkspace['shared_materials_configured'] == false
      ? 'No shared defense materials configured.'
      : widget.team.gradingWorkspace.containsKey('shared_materials_configured')
      ? 'No shared files uploaded yet.'
      : 'Shared materials are unavailable.';

  Widget _files(String key) {
    final files = widget.team.sharedMaterials
        .where((file) => file['candidate_key'] == key)
        .toList();
    final group = DefenseMaterialsCard(
      materials: files,
      onView: widget.onView,
      title: 'Shared system files',
      flat: true,
      emptyLabel: _emptyFiles,
    );
    if (files.length <= 3) return group;
    return ShadAccordion<String>(
      children: [
        ShadAccordionItem(
          value: 'files-$key',
          title: Text(
            'Shared system files · ${files.where((f) => f['missing'] != true).length}',
            style: const TextStyle(fontSize: 12),
          ),
          child: DefenseMaterialsCard(
            materials: files,
            onView: widget.onView,
            embedded: true,
          ),
        ),
      ],
    );
  }

  Widget _proposal(
    Map<String, dynamic> system, {
    required bool canDecide,
    required bool recorded,
  }) {
    final key = system['key'].toString();
    final selected = recorded
        ? key == _review['selected_key']
        : key == _selection;
    return Container(
      key: ValueKey('shared-system-option-$key'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? DefensysTokens.maroonTextOf(context).withValues(alpha: .45)
              : DefensysTokens.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recorded && selected) ...[
            Text(
              'Selected shared system',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.maroonTextOf(context),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!recorded && _review['can_decide'] == true)
                Radio<String>(value: key, enabled: canDecide),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: !recorded && _review['can_decide'] == true ? 10 : 0,
                  ),
                  child: Text(
                    system['title'].toString(),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _files(key),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final systems = rows(_review['systems']);
    final recorded = (_review['verdict'] ?? '').toString().isNotEmpty;
    final canDecide = _review['can_decide'] == true && !_busy && !recorded;
    final selectedKey = (_review['selected_key'] ?? '').toString();
    final shown = selectedKey.isNotEmpty
        ? systems.where((s) => s['key'] == selectedKey).toList()
        : systems;
    final alternatives = systems.where((s) => s['key'] != selectedKey).toList();
    final common = widget.team.sharedMaterials
        .where((f) => (f['candidate_key'] ?? '').toString().isEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Shared systems',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
            color: ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${_review['section'] ?? ''} · ${rows(_review['teams']).length} participating teams',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        Text(
          _review['verdict'] == 'for_redefense'
              ? 'Another shared hearing required'
              : recorded
              ? 'Shared decision recorded'
              : 'One shared system is selected for this section.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: recorded ? FontWeight.w600 : FontWeight.w400,
            color: ink,
          ),
        ),
        if (!recorded) ...[
          const SizedBox(height: 5),
          Text(
            'Decision pending',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
        if (!recorded &&
            !canDecide &&
            (_review['decision_unavailable_reason'] ?? '')
                .toString()
                .isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _review['decision_unavailable_reason'].toString(),
            style: TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
        ],
        if (common.isNotEmpty) ...[
          const SizedBox(height: 22),
          DefenseMaterialsCard(
            materials: common,
            onView: widget.onView,
            title: 'Section common files',
            flat: true,
          ),
        ],
        RadioGroup<String>(
          groupValue: _selection,
          onChanged: (value) {
            if (canDecide) setState(() => _selection = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final system in shown)
                _proposal(system, canDecide: canDecide, recorded: recorded),
              if (selectedKey.isNotEmpty && alternatives.isNotEmpty)
                ShadAccordion<String>(
                  children: [
                    ShadAccordionItem(
                      value: 'other-proposals',
                      title: const Text(
                        'Other proposals',
                        style: TextStyle(fontSize: 12),
                      ),
                      child: Column(
                        children: [
                          for (final system in alternatives)
                            _proposal(system, canDecide: false, recorded: true),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (systems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No shared proposals are available for this hearing.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
        if (!recorded && _review['can_decide'] == true) ...[
          const SizedBox(height: 24),
          ShadButton(
            key: const ValueKey('confirm-inline-shared-system'),
            height: 0,
            expands: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabled: canDecide && _selection != null,
            onPressed: () => _submit('approved'),
            child: Text(
              _busy ? 'Recording decision...' : 'Confirm shared system',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          ShadAccordion<String>(
            key: const ValueKey('shared-section-instructions'),
            controller: _instructions,
            maintainState: true,
            children: [
              ShadAccordionItem(
                value: 'instructions',
                title: const Text(
                  'Section instructions',
                  style: TextStyle(fontSize: 12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShadInput(
                      key: const ValueKey('shared-section-notes'),
                      controller: _notes,
                      enabled: canDecide,
                      maxLines: 3,
                      maxLength: 5000,
                      placeholder: const Text(
                        'Shared recommendations or required changes',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShadButton.outline(
                          height: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          enabled:
                              canDecide &&
                              _selection != null &&
                              _notes.text.trim().isNotEmpty,
                          onPressed: () => _submit('approved_with_revisions'),
                          child: const Flexible(
                            child: Text('Confirm with shared revisions'),
                          ),
                        ),
                        ShadButton.outline(
                          height: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          enabled: canDecide && _notes.text.trim().isNotEmpty,
                          onPressed: () => _submit('for_redefense'),
                          child: const Flexible(
                            child: Text('Request another shared hearing'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else if ((_review['remarks'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'Section instructions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _review['remarks'].toString(),
            style: TextStyle(fontSize: 13, height: 1.5, color: muted),
          ),
        ],
      ],
    );
  }
}
