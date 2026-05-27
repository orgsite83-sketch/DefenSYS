import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/system_audit_provider.dart';
import 'widgets/defensys_admin_shell.dart';

class AuditComplianceScreen extends ConsumerStatefulWidget {
  const AuditComplianceScreen({super.key});

  @override
  ConsumerState<AuditComplianceScreen> createState() =>
      _AuditComplianceScreenState();
}

class _AuditComplianceScreenState extends ConsumerState<AuditComplianceScreen> {
  final _searchController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(systemAuditProvider.notifier).fetch();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(systemAuditProvider);
    final selectedLog =
        state.selectedLog ?? (state.logs.isNotEmpty ? state.logs.first : null);
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.verified_user_outlined,
            title: 'Audit Trail & Evidence Review',
            subtitle:
                'Evidence trail for official academic actions and access changes.',
            actions: _AuditReadinessBadge(state: state),
          ),
          const SizedBox(height: 14),
          _EvidenceStatusCards(state: state),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: DefensysCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audit Filters', style: DefensysUi.sectionTitle),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _FilterDropdown(
                        label: 'Category',
                        value: state.category,
                        options: _categoryOptions,
                        onChanged: ref
                            .read(systemAuditProvider.notifier)
                            .setCategory,
                      ),
                      _FilterDropdown(
                        label: 'Review Status',
                        value: state.reviewStatus,
                        options: state.options['review_statuses'],
                        onChanged: ref
                            .read(systemAuditProvider.notifier)
                            .setReviewStatus,
                      ),
                      _FilterDropdown(
                        label: 'Action',
                        value: state.action,
                        options: (state.options['actions'] as List?)
                            ?.map(
                              (item) => {'value': '$item', 'label': '$item'},
                            )
                            .toList(),
                        onChanged: ref
                            .read(systemAuditProvider.notifier)
                            .setAction,
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search evidence',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: ref
                              .read(systemAuditProvider.notifier)
                              .setSearch,
                          onSubmitted: (_) =>
                              ref.read(systemAuditProvider.notifier).fetch(),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _startDateController,
                          decoration: const InputDecoration(
                            labelText: 'Start date',
                            hintText: 'YYYY-MM-DD',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: ref
                              .read(systemAuditProvider.notifier)
                              .setStartDate,
                          onSubmitted: (_) =>
                              ref.read(systemAuditProvider.notifier).fetch(),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _endDateController,
                          decoration: const InputDecoration(
                            labelText: 'End date',
                            hintText: 'YYYY-MM-DD',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: ref
                              .read(systemAuditProvider.notifier)
                              .setEndDate,
                          onSubmitted: (_) =>
                              ref.read(systemAuditProvider.notifier).fetch(),
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () =>
                              ref.read(systemAuditProvider.notifier).fetch(),
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              final table = _AuditTrailTable(state: state, auditRow: _auditRow);
              final details = _EvidenceDetailsPanel(log: selectedLog);

              if (!wide) {
                return Column(
                  children: [table, const SizedBox(height: 14), details],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: table),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  DataRow _auditRow(Map<String, dynamic> log) {
    final selected = ref.watch(systemAuditProvider).selectedLog;
    final isSelected = selected?['id']?.toString() == log['id']?.toString();
    return DataRow(
      selected: isSelected,
      onSelectChanged: (_) =>
          ref.read(systemAuditProvider.notifier).selectLog(log),
      cells: [
        DataCell(Text(_dateTime(log['created_at']))),
        DataCell(Text(log['category_label']?.toString() ?? '')),
        DataCell(Text(log['action']?.toString() ?? '')),
        DataCell(Text(log['actor_name']?.toString() ?? 'System')),
        DataCell(Text(_evidenceStatus(log))),
        DataCell(Text(_reviewStatus(log))),
      ],
    );
  }
}

const _categoryOptions = [
  {'value': 'academic_period', 'label': 'Academic Period Changes'},
  {'value': 'grade_center', 'label': 'Grade & Result Decisions'},
  {'value': 'scheduling', 'label': 'Schedule Changes'},
  {'value': 'repository', 'label': 'Repository Vault Evidence'},
  {'value': 'guest_access', 'label': 'Guest Access Activity'},
];

class _AuditReadinessBadge extends StatelessWidget {
  final SystemAuditState state;

  const _AuditReadinessBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = _count(state.counts['filtered'], fallback: state.logs.length);
    final needsReview = _count(state.counts['needs_review']);
    final reviewed = _count(state.counts['reviewed']);
    final readiness = total == 0
        ? 0
        : (((total - needsReview).clamp(0, total) / total) * 100).round();
    final label = needsReview == 0 ? 'Ready for Review' : 'Pending Review';

    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            color: DefensysUi.accentGold,
            size: 32,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ISO 9001:2015 Audit Readiness', style: DefensysUi.subtitle),
              const SizedBox(height: 2),
              Text(
                '$readiness%',
                style: const TextStyle(
                  color: DefensysUi.primaryMaroon,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 22),
          _StatusPill(label: label, value: '$reviewed/$total'),
        ],
      ),
    );
  }
}

class _EvidenceStatusCards extends StatelessWidget {
  final SystemAuditState state;

  const _EvidenceStatusCards({required this.state});

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _SummaryCard(
              width: cardWidth,
              label: 'Audit Readiness',
              value:
                  '${_readinessPercent(state.counts, fallback: state.logs.length)}%',
              status: _readinessStatus(state),
              icon: Icons.fact_check_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Open Findings',
              value: '${_count(state.counts['needs_review'])}',
              status: 'Requires Attention',
              icon: Icons.rate_review_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Verified Evidence',
              value: '${_count(state.counts['captured'])}',
              status: 'Verified',
              icon: Icons.task_alt_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Pending Review',
              value: '${_count(state.counts['needs_review'])}',
              status: 'Awaiting Review',
              icon: Icons.schedule_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String status;
  final IconData icon;

  const _SummaryCard({
    required this.width,
    required this.label,
    required this.value,
    required this.status,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DefensysCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: DefensysUi.accentGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: DefensysUi.primaryMaroon, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: DefensysUi.primaryMaroon,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DefensysUi.accentGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTrailTable extends StatelessWidget {
  final SystemAuditState state;
  final DataRow Function(Map<String, dynamic>) auditRow;

  const _AuditTrailTable({required this.state, required this.auditRow});

  @override
  Widget build(BuildContext context) {
    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: DefensysUi.primaryMaroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('Audit Trail Register', style: DefensysUi.sectionTitle),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (state.error != null)
            _AuditMessage(
              icon: Icons.error_outline_rounded,
              title: 'Audit records could not be loaded',
              message: _auditErrorMessage(state.error!),
            )
          else if (state.logs.isEmpty)
            _AuditMessage(
              icon: Icons.info_outline_rounded,
              title: _hasAuditFilters(state)
                  ? 'No matching audit records'
                  : 'No audit records yet',
              message: _hasAuditFilters(state)
                  ? 'Try clearing a category, status, action, search, or date filter to widen the audit register.'
                  : 'New official academic actions and repository changes will appear here after they are logged.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Date / Time')),
                  DataColumn(label: Text('Process Area')),
                  DataColumn(label: Text('Control Activity')),
                  DataColumn(label: Text('Responsible User')),
                  DataColumn(label: Text('Evidence Status')),
                  DataColumn(label: Text('Review Status')),
                ],
                rows: state.logs.map(auditRow).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _EvidenceDetailsPanel extends StatelessWidget {
  final Map<String, dynamic>? log;

  const _EvidenceDetailsPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    final item = log;
    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: DefensysUi.primaryMaroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence Packet Preview',
                  style: DefensysUi.sectionTitle,
                ),
              ),
              if (item != null)
                _StatusPill(label: 'ID', value: '${item['id'] ?? '-'}'),
            ],
          ),
          const SizedBox(height: 14),
          if (item == null)
            const Text('Select an audit record to review its evidence details.')
          else ...[
            _DetailLine('Responsible User', item['actor_name'] ?? 'System'),
            _DetailLine('Timestamp', _dateTime(item['created_at'])),
            _DetailLine('Category', item['category_label']),
            _DetailLine('Action', item['action']),
            _DetailLine(
              'Target',
              '${item['target_type'] ?? ''} #${item['target_id'] ?? ''}',
            ),
            _DetailLine('Review Status', item['review_status_label']),
            _DetailLine('Reason', item['reason']),
            const SizedBox(height: 12),
            _MetadataBlock(
              title: 'Previous Evidence',
              value: item['old_values'],
            ),
            const SizedBox(height: 12),
            _MetadataBlock(title: 'New Evidence', value: item['new_values']),
          ],
        ],
      ),
    );
  }
}

class _AuditMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AuditMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysUi.neutralBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysUi.neutralBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DefensysUi.primaryMaroon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DefensysUi.sectionTitle),
                const SizedBox(height: 4),
                Text(message, style: DefensysUi.subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final dynamic value;

  const _DetailLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 128, child: Text(label, style: DefensysUi.subtitle)),
          Expanded(child: Text(text.isEmpty ? '-' : text)),
        ],
      ),
    );
  }
}

class _MetadataBlock extends StatelessWidget {
  final String title;
  final dynamic value;

  const _MetadataBlock({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final rows = _metadataRows(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DefensysUi.subtitle),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: rows.isEmpty
              ? const Text(
                  'No evidence captured',
                  style: TextStyle(color: DefensysUi.steelGrey),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows
                      .map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(
                                  row.label,
                                  style: const TextStyle(
                                    color: DefensysUi.steelGrey,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: SelectableText(row.value)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _MetadataRow {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});
}

class _StatusPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatusPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysUi.primaryMaroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: DefensysUi.primaryMaroon,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final dynamic options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      {'value': '', 'label': 'All $label'},
      ...List<Map<String, dynamic>>.from(options ?? const []),
    ];
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item['value']?.toString() ?? '',
                child: Text(
                  item['label']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        selectedItemBuilder: (context) => items
            .map(
              (item) => Text(
                item['label']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
              ),
            )
            .toList(),
        onChanged: (next) => onChanged(next ?? ''),
      ),
    );
  }
}

int _count(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _readinessPercent(Map<String, dynamic> counts, {int fallback = 0}) {
  final total = _count(counts['filtered'], fallback: fallback);
  final needsReview = _count(counts['needs_review']);
  if (total == 0) return 0;
  return (((total - needsReview).clamp(0, total) / total) * 100).round();
}

String _readinessStatus(SystemAuditState state) {
  final total = _count(state.counts['filtered'], fallback: state.logs.length);
  final needsReview = _count(state.counts['needs_review']);
  if (total == 0) return 'No Records';
  return needsReview == 0 ? 'Excellent' : 'Needs Review';
}

bool _hasAuditFilters(SystemAuditState state) {
  return state.category.isNotEmpty ||
      state.reviewStatus.isNotEmpty ||
      state.action.isNotEmpty ||
      state.search.isNotEmpty ||
      state.startDate.isNotEmpty ||
      state.endDate.isNotEmpty;
}

String _auditErrorMessage(String error) {
  final lower = error.toLowerCase();
  if (lower.contains('signed out') ||
      lower.contains('session') ||
      lower.contains('token')) {
    return 'Your sign-in session expired. Sign in again, then reopen Audit Trail to reload the records.';
  }
  return error;
}

String _evidenceStatus(Map<String, dynamic> log) {
  final status = log['review_status']?.toString() ?? '';
  if (status == 'needs_review' || status == 'requires_reason') {
    return 'Needs Review';
  }
  return 'Evidence Captured';
}

String _reviewStatus(Map<String, dynamic> log) {
  final status = log['review_status']?.toString() ?? '';
  if (status == 'reviewed') return 'Reviewed';
  return 'Pending Review';
}

String _dateTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '';
  final date =
      '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  final time =
      '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

List<_MetadataRow> _metadataRows(dynamic value) {
  if (value == null) return const [];
  if (value is Map && value.isEmpty) return const [];
  if (value is List && value.isEmpty) return const [];
  if (value is Map) {
    return value.entries
        .map(
          (entry) => _MetadataRow(
            label: _metadataLabel(entry.key),
            value: _metadataValue(entry.value),
          ),
        )
        .toList();
  }

  final text = _metadataText(value);
  if (text == '-' || text.trim().isEmpty) return const [];
  return [_MetadataRow(label: 'Evidence', value: text)];
}

String _metadataLabel(dynamic key) {
  final raw = key?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Evidence';

  const labels = {
    'active_semester': 'Active Semester',
    'active_semester_id': 'Active Semester ID',
    'forced': 'Forced Switch',
  };
  final known = labels[raw];
  if (known != null) return known;

  final spaced = raw
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      );
  return spaced
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.toUpperCase() == part && part.length <= 3) return part;
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String _metadataValue(dynamic value) {
  if (value == null) return 'Not set';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value.toString();
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? 'Not set' : text;
  }
  if (value is Map) {
    if (value.isEmpty) return 'Not set';
    return value.entries
        .map((entry) => '${_metadataLabel(entry.key)}: ${_metadataValue(entry.value)}')
        .join(', ');
  }
  if (value is List) {
    if (value.isEmpty) return 'Not set';
    return value.map(_metadataValue).join(', ');
  }

  final text = value.toString().trim();
  return text.isEmpty ? 'Not set' : text;
}

String _metadataText(dynamic value) {
  if (value == null) return '-';
  if (value is Map && value.isEmpty) return '-';
  if (value is List && value.isEmpty) return '-';
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }
}
