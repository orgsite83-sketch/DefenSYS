import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/api_config.dart';
import '../../services/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/operation_request_id.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'documenter_decision_fields.dart';

class DocumenterOutcomeCorrection extends ConsumerStatefulWidget {
  const DocumenterOutcomeCorrection({
    super.key,
    required this.scheduleId,
    required this.decision,
    required this.contextData,
  });
  final int scheduleId;
  final Map<String, dynamic> decision, contextData;
  @override
  ConsumerState<DocumenterOutcomeCorrection> createState() =>
      _DocumenterOutcomeCorrectionState();
}

class _DocumenterOutcomeCorrectionState
    extends ConsumerState<DocumenterOutcomeCorrection> {
  final _reason = TextEditingController();
  late Map<String, dynamic> _draft;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final source = widget.decision;
    _draft = {
      'request_id': newOperationRequestId(),
      'review_token':
          (widget.contextData['outcome_rule'] as Map?)?['review_token'],
      'verdict': source['verdict'],
      'selected_key': source['selected_key'] ?? '',
      'reason': source['reason'] ?? '',
      'instructions': source['instructions'] ?? '',
      'revision_entries': [
        for (final row
            in (source['revision_entries'] as List? ?? []).whereType<Map>())
          {
            'area_id': row['area_id'],
            'label': row['label'],
            'severity': row['severity'],
          },
      ],
      're_demo_required': source['re_demo_required'] == true,
      'demo_requirements': [
        for (final row
            in (source['demo_requirements'] as List? ?? []).whereType<Map>())
          {'text': row['text']},
      ],
    };
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_reason.text.trim().length < 5) {
      setState(() => _error = 'Describe the correction reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse(
              '${ApiConfig.defenseMinutesUrl}/${widget.scheduleId}/decision-correction/',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reason': _reason.text.trim(),
              'expected_updated_at': widget.contextData['grade_updated_at'],
              'changes': {
                'panel_decision': {
                  ...(Map<String, dynamic>.from(_draft)..remove('request_id')),
                  'source_revision': widget.decision['revision'],
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      final body = jsonDecode(response.body);
      setState(
        () => _error = body is Map
            ? '${body['detail'] ?? body}'
            : 'Unable to request correction.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to request correction. Your changes are still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      title: const Text('Correct the recorded outcome'),
      constraints: const BoxConstraints(maxWidth: 660, maxHeight: 780),
      actions: [
        ShadButton.outline(
          enabled: !_busy,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ShadButton(
          enabled: !_busy,
          onPressed: _request,
          backgroundColor: DefensysTokens.maroonOf(context),
          foregroundColor: Colors.white,
          child: Text(_busy ? 'Requesting…' : 'Request correction'),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The current outcome stays official until the administrator approves this correction.',
            ),
            const SizedBox(height: 16),
            const Text('Correction reason'),
            const SizedBox(height: 7),
            ShadInput(
              controller: _reason,
              enabled: !_busy,
              maxLines: 2,
              maxLength: 2000,
            ),
            const SizedBox(height: 20),
            DocumenterDecisionFields(
              value: _draft,
              contextData: widget.contextData,
              enabled: !_busy,
              onChanged: (value) => _draft = value,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ],
        ),
      ),
    ),
  );
}
