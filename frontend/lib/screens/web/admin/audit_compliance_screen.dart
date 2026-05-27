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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(systemAuditProvider);
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DefensysPageHeader(
            icon: Icons.verified_user_outlined,
            title: 'Audit Trail & Evidence Review',
            subtitle:
                'Evidence trail for official academic actions and access changes.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SummaryCard(
                label: 'Audit Records',
                value: '${state.counts['filtered'] ?? state.logs.length}',
                icon: Icons.fact_check_outlined,
              ),
              const SizedBox(width: 14),
              _SummaryCard(
                label: 'Needs Review',
                value: '${state.counts['needs_review'] ?? 0}',
                icon: Icons.rate_review_outlined,
              ),
              const SizedBox(width: 14),
              _SummaryCard(
                label: 'Reviewed',
                value: '${state.counts['reviewed'] ?? 0}',
                icon: Icons.verified_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          DefensysCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit Filters', style: DefensysUi.sectionTitle),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _FilterDropdown(
                      label: 'Category',
                      value: state.category,
                      options: state.options['categories'],
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
                          ?.map((item) => {'value': '$item', 'label': '$item'})
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
                        onChanged:
                            ref.read(systemAuditProvider.notifier).setSearch,
                        onSubmitted: (_) =>
                            ref.read(systemAuditProvider.notifier).fetch(),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(systemAuditProvider.notifier).fetch(),
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          DefensysCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit Trail Register', style: DefensysUi.sectionTitle),
                const SizedBox(height: 12),
                if (state.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (state.error != null)
                  Text(state.error!, style: const TextStyle(color: Colors.red))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Action')),
                        DataColumn(label: Text('Responsible User')),
                        DataColumn(label: Text('Evidence Status')),
                        DataColumn(label: Text('Target')),
                      ],
                      rows: state.logs.map(_auditRow).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _auditRow(Map<String, dynamic> log) {
    return DataRow(
      cells: [
        DataCell(Text(_date(log['created_at']))),
        DataCell(Text(log['category_label']?.toString() ?? '')),
        DataCell(Text(log['action']?.toString() ?? '')),
        DataCell(Text(log['actor_name']?.toString() ?? 'System')),
        DataCell(Text(log['review_status_label']?.toString() ?? '')),
        DataCell(Text('${log['target_type'] ?? ''} #${log['target_id'] ?? ''}')),
      ],
    );
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DefensysCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: DefensysUi.primaryMaroon),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DefensysUi.subtitle),
                Text(
                  value,
                  style: const TextStyle(
                    color: DefensysUi.primaryMaroon,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
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
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item['value']?.toString() ?? '',
                child: Text(item['label']?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged: (next) => onChanged(next ?? ''),
      ),
    );
  }
}
