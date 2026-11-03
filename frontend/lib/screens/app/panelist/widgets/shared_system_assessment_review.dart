import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/academic/section_concept_service.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../../../../widgets/grading/shared_selection_correction_dialog.dart';
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
  String _decision = 'approved';
  bool _busy = false;

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
      _decision = 'approved';
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
    super.dispose();
  }

  List<Map<String, dynamic>> rows(dynamic value) => (value as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  Future<void> _correctSelection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await showSharedSelectionCorrection(
        context,
        Map<String, dynamic>.from(_review),
      );
      if (changed && mounted) {
        await widget.onUpdated();
        if (mounted) showSuccessToast(context, 'Shared selection corrected.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        _review['can_decide'] != true ||
        (_review['verdict'] ?? '').toString().isNotEmpty) {
      return;
    }
    final verdict = _decision;
    final selection = _selection;
    final notes = _notes.text.trim();
    final review = Map<String, dynamic>.from(_review);
    final retry = verdict == 'for_redefense';
    if (!retry && selection == null) return;
    if (verdict != 'approved' && notes.isEmpty) return;
    final systems = rows(_review['systems']);
    final selected = systems
        .where((row) => row['key'] == selection)
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
    if (_review['id'] != review['id'] ||
        _review['round_id'] != review['round_id']) {
      showErrorToast(
        context,
        'The hearing changed. Review the current decision again.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await ref.read(sectionConceptServiceProvider).action(
        review,
        'decide',
        {
          'verdict': verdict,
          'remarks': notes,
          'concepts': [
            for (final system in systems)
              {
                'key': system['key'],
                'decision': retry
                    ? 'rejected'
                    : system['key'] == selection
                    ? verdict
                    : 'not_selected',
                'remarks': retry || system['key'] == selection ? notes : '',
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
    final teamCount = rows(_review['teams']).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                    'Shared systems',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                      color: ink,
                    ),
                  ),
                  ShadBadge.outline(
                    child: Text(
                      _review['verdict'] == 'for_redefense'
                          ? 'Another hearing required'
                          : recorded
                          ? 'System selected'
                          : canDecide
                          ? 'Chair decision needed'
                          : 'Shared decision pending',
                    ),
                  ),
                ],
              ),
            ),
            SharedSelectionCorrectionMenu(
              review: _review,
              enabled: !_busy,
              onCorrect: _correctSelection,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$teamCount ${teamCount == 1 ? 'team' : 'teams'} · ${systems.length} ${systems.length == 1 ? 'proposal' : 'proposals'}',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        SharedSelectionCorrectionHistory(review: _review),
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
          Text(
            'Decision',
            style: TextStyle(color: ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ShadRadioGroup<String>(
            initialValue: _decision,
            enabled: canDecide,
            spacing: 14,
            items: [
              for (final choice in const {
                'approved': 'Select the shared system',
                'approved_with_revisions': 'Select with shared revisions',
                'for_redefense': 'Request another shared hearing',
              }.entries)
                ShadRadio<String>(
                  value: choice.key,
                  color: DefensysTokens.maroonTextOf(context),
                  label: Text(choice.value),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _decision = value);
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Panel recommendations',
            style: TextStyle(color: ink, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
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
          if (_decision != 'approved') ...[
            const SizedBox(height: 6),
            Text(
              'Describe the required changes before confirming.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
          const SizedBox(height: 12),
          ShadButton(
            key: const ValueKey('confirm-inline-shared-system'),
            height: 0,
            expands: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabled:
                canDecide &&
                (_decision == 'for_redefense' || _selection != null) &&
                (_decision == 'approved' || _notes.text.trim().isNotEmpty),
            onPressed: _submit,
            child: Text(
              _busy ? 'Recording decision...' : 'Confirm shared decision',
              textAlign: TextAlign.center,
            ),
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
