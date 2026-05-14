import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/digital_vault_provider.dart';
import '../../../theme/app_theme.dart';

class DigitalVaultScreen extends ConsumerStatefulWidget {
  const DigitalVaultScreen({super.key});

  @override
  ConsumerState<DigitalVaultScreen> createState() => _DigitalVaultScreenState();
}

class _DigitalVaultScreenState extends ConsumerState<DigitalVaultScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(digitalVaultProvider.notifier).fetchEntries();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(digitalVaultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Vault'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(digitalVaultProvider.notifier).fetchEntries(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(digitalVaultProvider.notifier).fetchEntries(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildStats(state),
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    _notice(
                      Icons.error_outline,
                      state.error!,
                      AppColors.danger,
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildToolbar(state),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(36),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    _buildEntries(state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.maroon,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.maroon.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.security_outlined, color: Colors.white, size: 40),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read-Only Project Archive',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Browse public PIT files and approved Capstone vault submissions. Restricted source code and full manuscripts stay hidden.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(DigitalVaultState state) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _stat(
          'Visible Files',
          _count(state, 'total'),
          Icons.inventory_2,
          AppColors.maroon,
        ),
        _stat(
          'Filtered',
          _count(state, 'filtered'),
          Icons.filter_alt,
          Colors.blue,
        ),
        _stat(
          'Capstone',
          _count(state, 'capstone'),
          Icons.school_outlined,
          AppColors.gold,
        ),
        _stat(
          'PIT',
          _count(state, 'pit'),
          Icons.folder_copy_outlined,
          AppColors.success,
        ),
        _stat(
          'Restricted',
          _count(state, 'restricted'),
          Icons.lock_outline,
          AppColors.danger,
        ),
      ],
    );
  }

  Widget _stat(String label, int count, IconData icon, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _iconBox(icon, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(DigitalVaultState state) {
    final typeOptions = _mapList(state.options['type_options']);
    final yearLevels = _stringList(state.options['year_levels']);
    final stageOptions = _stringList(state.options['stage_options']);
    final academicYears = _stringList(state.options['academic_years']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search file, team, deliverable',
                ),
                onSubmitted: (value) => ref
                    .read(digitalVaultProvider.notifier)
                    .fetchEntries(search: value),
              ),
            ),
            _dropdownFromMaps(
              width: 180,
              label: 'Type',
              value: state.type,
              items: typeOptions,
              onChanged: (value) => ref
                  .read(digitalVaultProvider.notifier)
                  .fetchEntries(type: value ?? ''),
            ),
            _dropdownFromStrings(
              width: 190,
              label: 'Year Level',
              value: state.yearLevel,
              items: yearLevels,
              onChanged: (value) => ref
                  .read(digitalVaultProvider.notifier)
                  .fetchEntries(yearLevel: value ?? ''),
            ),
            _dropdownFromStrings(
              width: 220,
              label: 'Stage / Course',
              value: state.stage,
              items: stageOptions,
              onChanged: (value) => ref
                  .read(digitalVaultProvider.notifier)
                  .fetchEntries(stage: value ?? ''),
            ),
            _dropdownFromStrings(
              width: 180,
              label: 'Academic Year',
              value: state.academicYear,
              items: academicYears,
              onChanged: (value) => ref
                  .read(digitalVaultProvider.notifier)
                  .fetchEntries(academicYear: value ?? ''),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                ref
                    .read(digitalVaultProvider.notifier)
                    .fetchEntries(
                      search: '',
                      type: '',
                      yearLevel: '',
                      stage: '',
                      academicYear: '',
                    );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownFromMaps({
    required double width,
    required String label,
    required String value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty
        ? const [
            {'value': '', 'label': 'All Types'},
            {'value': 'capstone', 'label': 'Capstone'},
            {'value': 'pit', 'label': 'PIT'},
          ]
        : items;
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: options
            .map(
              (item) => DropdownMenuItem(
                value: item['value']?.toString() ?? '',
                child: Text(item['label']?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdownFromStrings({
    required double width,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = ['', ...items];
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: options
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(item.isEmpty ? 'All' : item),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEntries(DigitalVaultState state) {
    if (state.entries.isEmpty) {
      return Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(34),
          child: const Column(
            children: [
              Icon(
                Icons.vpn_key_off_outlined,
                size: 42,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 10),
              Text(
                'No vault files found',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Upload PIT archives or Capstone vault submissions first.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: state.entries.map(_entryCard).toList());
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final isCapstone = entry['type'] == 'capstone';
    final color = isCapstone ? AppColors.gold : Colors.blue;
    final title = isCapstone
        ? entry['deliverable_label']?.toString() ??
              entry['file_name']?.toString() ??
              ''
        : entry['file_name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBox(_fileIcon(entry['file_name']?.toString() ?? ''), color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry['file_name']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(isCapstone ? 'Capstone' : 'PIT', color),
                      _chip(
                        entry['year_level']?.toString() ?? 'No year',
                        AppColors.maroon,
                      ),
                      _chip(
                        entry['stage']?.toString() ?? 'No stage',
                        Colors.blueGrey,
                      ),
                      _chip(
                        entry['academic_year']?.toString() ?? 'No AY',
                        AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${entry['team_name'] ?? 'Unmatched'} - Uploaded by ${entry['uploaded_by'] ?? 'System'} - ${_date(entry['uploaded_at'])}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _showViewer(entry),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }

  void _showViewer(Map<String, dynamic> entry) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry['deliverable_label']?.toString() ?? 'Vault File'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _notice(
                Icons.lock_outline,
                entry['viewer_notice']?.toString() ??
                    'This vault item is available as a read-only preview.',
                AppColors.maroon,
              ),
              const SizedBox(height: 16),
              _metaRow('File', entry['file_name']),
              _metaRow('Type', entry['type']),
              _metaRow('Team', entry['team_name']),
              _metaRow('Year Level', entry['year_level']),
              _metaRow('Stage / Course', entry['stage']),
              _metaRow('Academic Year', entry['academic_year']),
              _metaRow('Status', entry['status']),
              _metaRow('Uploaded By', entry['uploaded_by']),
              _metaRow('Uploaded At', _date(entry['uploaded_at'])),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value?.toString() ?? '-')),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    );
  }

  IconData _fileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (ext == 'mp4' || ext == 'mov') return Icons.video_file_outlined;
    if (ext == 'png' || ext == 'jpg' || ext == 'jpeg') {
      return Icons.image_outlined;
    }
    if (ext == 'zip') return Icons.folder_zip_outlined;
    return Icons.description_outlined;
  }

  String _date(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '-';
    return text.split('T').first;
  }

  int _count(DigitalVaultState state, String key) {
    return _asInt(state.counts[key]);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }
}
