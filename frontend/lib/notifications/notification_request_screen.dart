import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../config/api_config.dart';
import '../services/authenticated_client.dart';
import '../services/defense_scheduler_provider.dart';
import '../services/admin/external_evaluator_provider.dart';
import '../services/admin/panelist_requests_provider.dart';
import '../services/user_management_provider.dart';
import '../theme/defensys_tokens.dart';
import '../widgets/shadcn/defensys_shadcn_scope.dart';
import 'notifications_provider.dart';

/// A durable URL for one request, including its decision after review.
class NotificationRequestScreen extends ConsumerStatefulWidget {
  const NotificationRequestScreen({
    super.key,
    required this.kind,
    required this.requestId,
    required this.onBack,
    this.embedded = false,
    this.onOpenRoles,
  });
  final String kind;
  final int requestId;
  final VoidCallback onBack;
  final bool embedded;
  final ValueChanged<int>? onOpenRoles;

  @override
  ConsumerState<NotificationRequestScreen> createState() =>
      _NotificationRequestScreenState();
}

class _NotificationRequestScreenState
    extends ConsumerState<NotificationRequestScreen> {
  Map<String, dynamic>? _item;
  bool _loading = true, _saving = false, _canReview = false;
  String? _error;
  int _generation = 0;
  bool get _panelist => widget.kind == 'panelist';
  Uri get _uri => Uri.parse(
    '${ApiConfig.usersUrl}/${_panelist ? 'panelist-requests' : 'external-evaluators'}/${widget.requestId}/',
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant NotificationRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.kind != widget.kind) {
      _item = null;
      Future.microtask(_load);
    }
  }

  Future<void> _load({bool preserveError = false}) async {
    final generation = ++_generation;
    if (!mounted) return;
    setState(() {
      _loading = true;
      if (!preserveError) _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(_uri);
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200) {
        throw Exception(
          response.statusCode == 404 || response.statusCode == 403
              ? 'This request is no longer available or you do not have access.'
              : 'Could not load the request. Please try again.',
        );
      }
      final data = jsonDecode(response.body) as Map;
      setState(() {
        _item = Map<String, dynamic>.from(data['request']);
        _canReview = data['can_review'] == true;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _item = null;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _review(bool approve) async {
    if (_saving || _loading || !_canReview || _item?['status'] != 'pending') {
      return;
    }
    var note = '';
    if (!approve) {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => DefensysShadcnScope(
          child: ShadDialog(
            title: const Text('Decline request'),
            description: const Text(
              'Include a reason for the person who requested approval.',
            ),
            constraints: const BoxConstraints(maxWidth: 460),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(dialogContext, note.trim()),
                child: const Text('Decline request'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ShadInput(
                placeholder: const Text('Reason (optional)'),
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                onChanged: (value) => note = value,
              ),
            ),
          ),
        ),
      );
      if (result == null || !mounted) return;
      note = result;
    }
    final generation = _generation;
    final uri = _uri;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .patch(
            uri,
            body: jsonEncode({
              _panelist ? 'decision' : 'status': approve
                  ? 'approved'
                  : 'declined',
              'review_note': note,
            }),
          );
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200) {
        setState(
          () => _error =
              'The request could not be reviewed. Its latest status is shown below.',
        );
      } else {
        ref.invalidate(notificationsProvider('admin'));
        ref.invalidate(defenseSchedulerProvider);
        if (widget.embedded)
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        if (_panelist) {
          ref.invalidate(panelistRequestsProvider);
          ref.read(userManagementProvider.notifier).fetchUsers();
        }
        if (!_panelist) ref.invalidate(externalEvaluatorProvider);
      }
      await _load(preserveError: true);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not save the decision. Refresh to check the current status.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
      ],
    ),
  );

  Widget _requestContainer({required Widget child}) =>
      widget.embedded ? child : ShadCard(child: child);

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '' : DateFormat('MMM d, y · h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final status = item?['status']?.toString() ?? '';
    final pending = status == 'pending';
    final active = _panelist || item?['is_active'] != false;
    final label = !active
        ? 'Inactive'
        : pending
        ? 'Awaiting approval'
        : status == 'approved'
        ? 'Approved'
        : 'Declined';
    return DefensysShadcnScope(
      child: ColoredBox(
        color: widget.embedded
            ? DefensysTokens.surfaceOf(context)
            : DefensysTokens.backgroundOf(context),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(widget.embedded ? 0 : 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.embedded)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ShadButton.ghost(
                        onPressed: widget.onBack,
                        leading: const Icon(LucideIcons.arrowLeft, size: 16),
                        child: const Text('Defense Operations'),
                      ),
                    ),
                  if (!widget.embedded) const SizedBox(height: 20),
                  _requestContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _panelist
                              ? 'Panelist eligibility request'
                              : 'External evaluator request',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Request #${widget.requestId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(color: DefensysTokens.danger),
                          ),
                        ],
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (item != null) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ShadBadge.outline(child: Text(label)),
                          ),
                          _detail(
                            _panelist ? 'Faculty member' : 'Evaluator',
                            (item[_panelist ? 'faculty_name' : 'name'] ?? '')
                                .toString(),
                          ),
                          _detail(
                            'Requested by',
                            (item['requested_by_name'] ?? '').toString(),
                          ),
                          if ((item['pit_year'] ?? '').toString().isNotEmpty)
                            _detail('PIT year', item['pit_year'].toString()),
                          if (!_panelist &&
                              (item['institution'] ?? '').toString().isNotEmpty)
                            _detail(
                              'Institution',
                              item['institution'].toString(),
                            ),
                          if (!_panelist &&
                              (item['email'] ?? '').toString().isNotEmpty)
                            _detail('Email', item['email'].toString()),
                          if ((item['reason'] ?? '').toString().isNotEmpty)
                            _detail('Reason', item['reason'].toString()),
                          _detail('Requested', _date(item['created_at'])),
                          if (!pending) ...[
                            _detail(
                              'Reviewed by',
                              (item['reviewed_by_name'] ?? 'Administrator')
                                  .toString(),
                            ),
                            _detail('Reviewed', _date(item['reviewed_at'])),
                            if ((item['review_note'] ?? '')
                                .toString()
                                .isNotEmpty)
                              _detail(
                                'Decision note',
                                item['review_note'].toString(),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              'This request has already been reviewed.',
                              style: TextStyle(
                                fontSize: 13,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                          if (pending && _canReview && active) ...[
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ShadButton(
                                  enabled: !_saving,
                                  onPressed: _saving
                                      ? null
                                      : () => _review(true),
                                  leading: const Icon(
                                    LucideIcons.check,
                                    size: 16,
                                  ),
                                  child: Text(
                                    _saving ? 'Saving…' : 'Approve request',
                                  ),
                                ),
                                ShadButton.outline(
                                  enabled: !_saving,
                                  onPressed: _saving
                                      ? null
                                      : () => _review(false),
                                  child: const Text('Decline'),
                                ),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        if (widget.onOpenRoles != null &&
                            item?['faculty_id'] is num)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ShadButton.outline(
                              enabled: !_loading && !_saving,
                              onPressed: _loading || _saving
                                  ? null
                                  : () => widget.onOpenRoles!(
                                      (item!['faculty_id'] as num).toInt(),
                                    ),
                              leading: const Icon(
                                LucideIcons.shieldCheck,
                                size: 14,
                              ),
                              child: const Text('Open role editor'),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton.ghost(
                            enabled: !_loading && !_saving,
                            onPressed: _loading || _saving ? null : _load,
                            leading: const Icon(
                              LucideIcons.refreshCw,
                              size: 14,
                            ),
                            child: const Text('Refresh status'),
                          ),
                        ),
                      ],
                    ),
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
