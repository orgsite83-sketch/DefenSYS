import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/api_config.dart';
import '../../../services/repository_audit_provider.dart';
import '../../../theme/app_theme.dart';

class RepositoryAuditScreen extends ConsumerStatefulWidget {
  const RepositoryAuditScreen({super.key});

  @override
  ConsumerState<RepositoryAuditScreen> createState() =>
      _RepositoryAuditScreenState();
}

class _RepositoryAuditScreenState extends ConsumerState<RepositoryAuditScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryAuditProvider.notifier).fetchEntries();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryAuditProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(state),
          const SizedBox(height: 26),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(
              Icons.error_outline_rounded,
              state.error!,
              AppColors.danger,
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(
              Icons.check_circle_outline_rounded,
              state.message!,
              AppColors.success,
            ),
          ],
          const SizedBox(height: 22),
          _repositoryTableCard(state),
        ],
      ),
    );
  }

  Widget _buildHeader(RepositoryAuditState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Digital Vault Manager',
                style: TextStyle(
                  color: AppColors.maroon,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Global view of all uploaded deliverables across all year levels and Capstone.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_can(state, 'can_upload_pit')) ...[
              _secondaryButton(
                icon: Icons.cloud_upload_outlined,
                label: 'Upload PIT',
                onTap: state.isSaving ? null : () => _showUploadDialog(state),
              ),
              const SizedBox(width: 12),
            ],
            _primaryButton(
              icon: Icons.file_download_rounded,
              label: 'Export Audit Log',
              onTap: state.isSaving ? null : _exportCsv,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStats(RepositoryAuditState state) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'Total Managed Files',
            value: _count(state, 'total'),
            valueColor: const Color(0xFF0F2743),
            icon: Icons.folder_copy_outlined,
            iconTint: const Color(0xFFCBD5E1),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Pending AI Classification',
            value: _count(state, 'pending'),
            valueColor: const Color(0xFFD97706),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFFDE68A),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Approved Vault Entries',
            value: _count(state, 'approved'),
            valueColor: const Color(0xFF059669),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFA7F3D0),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required int value,
    required Color valueColor,
    required IconData icon,
    required Color iconTint,
  }) {
    return Container(
      height: 107,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -26,
            child: Icon(
              icon,
              size: 76,
              color: iconTint.withValues(alpha: 0.34),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repositoryTableCard(RepositoryAuditState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _clearFiltersButton(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _filterFromMaps(
                  value: state.type,
                  label: 'All Types',
                  items: _mapList(state.options['type_options']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(type: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromMaps(
                  value: '',
                  label: 'All Teams',
                  items: _mapList(state.options['team_options']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(teamId: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromStrings(
                  value: state.stage,
                  label: 'All Stages',
                  items: _stringList(state.options['stage_options']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(stage: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromStrings(
                  value: state.yearLevel,
                  label: 'All Year Levels',
                  items: _stringList(state.options['year_levels']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(yearLevel: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromStrings(
                  value: state.academicYear,
                  label: 'All Academic Years',
                  items: _stringList(state.options['academic_years']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(academicYear: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromMaps(
                  value: state.status,
                  label: 'All Statuses',
                  items: _mapList(state.options['status_options']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(status: value ?? ''),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _filterFromStrings(
                  value: state.semester,
                  label: 'All Semesters',
                  items: _stringList(state.options['semesters']),
                  onChanged: (value) => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(semester: value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (state.isLoading)
            const SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.maroon),
              ),
            )
          else if (state.entries.isEmpty)
            _emptyRepositoryTable()
          else
            _repositoryTable(state),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${state.entries.length} files',
              style: const TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(RepositoryAuditState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 19,
          ),
          hintText: 'Search by file name, course, or semester...',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.maroon),
          ),
        ),
        onSubmitted: (value) {
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(search: value);
        },
      ),
    );
  }

  Widget _clearFiltersButton() {
    return SizedBox(
      height: 43,
      child: OutlinedButton.icon(
        onPressed: () {
          _searchController.clear();
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(
                search: '',
                type: '',
                yearLevel: '',
                academicYear: '',
                status: '',
                semester: '',
                teamId: '',
                stage: '',
              );
        },
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Clear Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _filterFromMaps({
    required String value,
    required String label,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty
        ? [
            {'value': '', 'label': label},
          ]
        : [
            {'value': '', 'label': label},
            ...items.where(
              (item) => (item['value']?.toString() ?? '').isNotEmpty,
            ),
          ];

    final values = options
        .map((item) => item['value']?.toString() ?? '')
        .toSet();
    final selected = values.contains(value) ? value : '';

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item['value']?.toString() ?? '',
                  child: Text(
                    item['label']?.toString() ?? label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterFromStrings({
    required String value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = ['', ...items];
    final selected = options.contains(value) ? value : '';

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.isEmpty ? label : item,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterShell({required Widget child}) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: child,
    );
  }

  Widget _repositoryTable(RepositoryAuditState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1515,
        child: Column(
          children: [
            _repositoryHeader(),
            ...state.entries.map((entry) => _repositoryRow(entry)),
          ],
        ),
      ),
    );
  }

  Widget _repositoryHeader() {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          _tableHeaderCell('File Name', flex: 3.45),
          _tableHeaderCell('Year Level', flex: 0.74),
          _tableHeaderCell('Academic Year', flex: 0.94),
          _tableHeaderCell('Course', flex: 0.62),
          _tableHeaderCell('Semester', flex: 0.78),
          _tableHeaderCell('Status', flex: 0.95),
          _tableHeaderCell('Uploaded', flex: 0.74),
          _tableHeaderCell('Action', flex: 0.64),
        ],
      ),
    );
  }

  Widget _emptyRepositoryTable() {
    return Column(
      children: [
        _repositoryHeader(),
        Container(
          height: 96,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: const Text(
            'No digital vault files found.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _repositoryRow(Map<String, dynamic> entry) {
    final isPit = entry['type'] == 'pit';
    final title = isPit
        ? entry['file_name']?.toString() ?? ''
        : entry['deliverable_label']?.toString() ??
              entry['file_name']?.toString() ??
              '';
    final uploadedBy = entry['uploaded_by']?.toString() ?? 'System';

    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '-' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'By $uploadedBy',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flex: 3.45,
          ),
          _tableCell(
            _yearBadge(entry['year_level']?.toString() ?? ''),
            flex: 0.74,
          ),
          _tableCell(
            _bodyText(entry['academic_year']?.toString() ?? ''),
            flex: 0.94,
          ),
          _tableCell(_bodyText(entry['course']?.toString() ?? ''), flex: 0.62),
          _tableCell(
            _bodyText(entry['semester']?.toString() ?? ''),
            flex: 0.78,
          ),
          _tableCell(
            _statusBadge(entry['status']?.toString() ?? ''),
            flex: 0.95,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.74),
          _tableCell(_rowActions(entry), flex: 0.64),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String label, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _yearBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    final icon = switch (status) {
      'Approved' || 'Vault Submission' => Icons.check_circle_rounded,
      'Needs Revision' => Icons.warning_rounded,
      'Pre-Defense' => Icons.school_rounded,
      _ => Icons.hourglass_empty_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.isEmpty ? 'Pending AI' : status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> entry) {
    final fileUrl = entry['file_url']?.toString() ?? '';
    final fileName = entry['file_name']?.toString() ?? '';
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // View button
        _actionIcon(
          tooltip: 'View PDF',
          icon: Icons.visibility_outlined,
          color: const Color(0xFF2563EB),
          onTap: () => _viewPdf(fileUrl, fileName),
        ),
        const SizedBox(width: 3),
        // Download button
        _actionIcon(
          tooltip: 'Download',
          icon: Icons.download_rounded,
          color: const Color(0xFF059669),
          onTap: () => _downloadFile(fileUrl, fileName),
        ),
        const SizedBox(width: 3),
        _actionIcon(
          tooltip: 'Audit trail',
          icon: Icons.history_rounded,
          color: AppColors.textSecondary,
          onTap: () => _showDetails(entry),
        ),
        if (entry['can_classify'] == true) ...[
          const SizedBox(width: 3),
          _actionIcon(
            tooltip: 'Classify',
            icon: Icons.psychology_alt_rounded,
            color: AppColors.warning,
            onTap: () => ref
                .read(repositoryAuditProvider.notifier)
                .classify(entry['id'].toString()),
          ),
        ],
        if (entry['can_override'] == true) ...[
          const SizedBox(width: 3),
          _actionIcon(
            tooltip: 'Override status',
            icon: Icons.lock_rounded,
            color: AppColors.textSecondary,
            onTap: () => _showOverrideDialog(entry),
          ),
        ],
      ],
    );
  }

  Widget _actionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.maroon,
          foregroundColor: AppColors.gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _prettyDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return _date(value);
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Future<void> _showUploadDialog(RepositoryAuditState state) async {
    final fileNames = TextEditingController(
      text: '${_yearPrefix(state)}.PIT301.CloudFileSyncSystem.1stSemester.pdf',
    );
    String yearLevel =
        state.scope['pit_year_level']?.toString().isNotEmpty == true
        ? state.scope['pit_year_level'].toString()
        : '3rd Year';
    String academicYear = state.academicYear;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upload PIT Repository Files'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((state.scope['pit_year_level']?.toString() ?? '').isEmpty)
                  _dialogDropdown(
                    label: 'PIT Year Level',
                    value: yearLevel,
                    items: const ['1st Year', '2nd Year', '3rd Year'],
                    onChanged: (value) => setDialogState(() {
                      yearLevel = value ?? yearLevel;
                      fileNames.text =
                          '${_prefixForYear(yearLevel)}.PIT301.CloudFileSyncSystem.1stSemester.pdf';
                    }),
                  )
                else
                  Text('Scoped to ${state.scope['pit_year_level']}'),
                const SizedBox(height: 12),
                _dialogDropdown(
                  label: 'Academic Year',
                  value: academicYear,
                  items: _stringList(state.options['academic_years']),
                  onChanged: (value) =>
                      setDialogState(() => academicYear = value ?? ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fileNames,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'PDF filenames, one per line',
                    hintText: '3rdYear.PIT301.ProjectTitle.1stSemester.pdf',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );

    final names = fileNames.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    fileNames.dispose();
    if (!mounted || saved != true) {
      return;
    }

    await ref
        .read(repositoryAuditProvider.notifier)
        .uploadPit(
          fileNames: names,
          yearLevel: yearLevel,
          academicYear: academicYear,
        );
  }

  Future<void> _showOverrideDialog(Map<String, dynamic> entry) async {
    String status = entry['status']?.toString() ?? 'Approved';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Override PIT Status'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => _dialogDropdown(
            label: 'Status',
            value: status,
            items: const [
              'Pending AI Classification',
              'Approved',
              'Needs Revision',
            ],
            onChanged: (value) =>
                setDialogState(() => status = value ?? status),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || saved != true) {
      return;
    }
    await ref
        .read(repositoryAuditProvider.notifier)
        .overrideStatus(entry['id'].toString(), status);
  }

  void _showDetails(Map<String, dynamic> entry) {
    final logs = _mapList(entry['audit_trail']);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Audit Trail - ${entry['file_name'] ?? ''}'),
        content: SizedBox(
          width: 560,
          child: logs.isEmpty
              ? const Text('No audit trail entries yet.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: logs
                      .map(
                        (log) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history),
                          title: Text(log['message']?.toString() ?? ''),
                          subtitle: Text(
                            '${log['action'] ?? ''} - ${log['previous_status'] ?? ''} -> ${log['new_status'] ?? ''}\n${log['actor'] ?? 'System'} - ${_date(log['created_at'])}',
                          ),
                        ),
                      )
                      .toList(),
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

  void _viewPdf(String fileUrl, String fileName) {
    if (fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File URL not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Construct full URL
    final fullUrl = fileUrl.startsWith('http')
        ? fileUrl
        : '${ApiConfig.mediaUrl}$fileUrl';

    // Open in new tab using url_launcher
    launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
  }

  void _downloadFile(String fileUrl, String fileName) {
    if (fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File URL not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Construct full URL
    final fullUrl = fileUrl.startsWith('http')
        ? fileUrl
        : '${ApiConfig.mediaUrl}$fileUrl';

    // For web, use url_launcher to trigger download
    // The browser will handle the download
    launchUrl(
      Uri.parse(fullUrl),
      mode: LaunchMode.externalApplication,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $fileName...'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final csv = await ref.read(repositoryAuditProvider.notifier).exportCsv();
    if (!mounted || csv == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repository Audit CSV'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(csv)),
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

  Widget _dialogDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty ? [value] : items;
    final selected = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: options
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
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

  Color _statusColor(String status) {
    if (status == 'Approved' || status == 'Vault Submission') {
      return AppColors.success;
    }
    if (status == 'Needs Revision') {
      return AppColors.danger;
    }
    if (status == 'Pre-Defense') {
      return Colors.blue;
    }
    return AppColors.warning;
  }

  bool _can(RepositoryAuditState state, String key) {
    return state.scope[key] == true;
  }

  String _date(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '-';
    return text.split('T').first;
  }

  int _count(RepositoryAuditState state, String key) {
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

  String _yearPrefix(RepositoryAuditState state) {
    return _prefixForYear(
      state.scope['pit_year_level']?.toString().isNotEmpty == true
          ? state.scope['pit_year_level'].toString()
          : '3rd Year',
    );
  }

  String _prefixForYear(String yearLevel) {
    if (yearLevel == '1st Year') return '1stYear';
    if (yearLevel == '2nd Year') return '2ndYear';
    return '3rdYear';
  }
}
