import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/defense_scheduler_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitEventsManagementScreen extends ConsumerStatefulWidget {
  const PitEventsManagementScreen({super.key});

  @override
  ConsumerState<PitEventsManagementScreen> createState() => _PitEventsManagementScreenState();
}

class _PitEventsManagementScreenState extends ConsumerState<PitEventsManagementScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _isLoadingConfigs = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingConfigs = true);
    // Fetch rubrics, active semester, and schedules options
    await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    // Fetch PIT configurations
    final notifier = ref.read(defenseSchedulerProvider.notifier);
    final activeSem = ref.read(defenseSchedulerProvider).activeSemester;
    final semesterId = activeSem != null ? int.tryParse(activeSem['id']?.toString() ?? '') : null;
    final configsList = await notifier.fetchPitEventConfigs(semesterId: semesterId);
    if (mounted) {
      setState(() {
        _configs = configsList;
        _isLoadingConfigs = false;
      });
    }
  }

  Future<void> _deleteConfig(Map<String, dynamic> config) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Event Configuration',
      message: 'Are you sure you want to delete "${config['event_name']}"? This will also delete all associated deliverables.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    final configId = int.tryParse(config['id']?.toString() ?? '');
    if (configId == null) return;

    final success = await ref.read(defenseSchedulerProvider.notifier).deletePitEventConfig(configId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration deleted successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadData();
    }
  }

  void _showEventDialog([Map<String, dynamic>? config]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EventConfigEditDialog(
        config: config,
        onSaveSuccess: () {
          Navigator.of(context).pop();
          _loadData();
        },
      ),
    );
  }

  Widget _primaryButton({
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysTokens.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
      ),
    );
  }


  Widget _cardButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required Color borderColor,
  }) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
      ),
    );
  }

  Widget _cardIconButton({
    required Widget icon,
    required VoidCallback onTap,
    required Color color,
    required Color hoverColor,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: hoverColor,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: color),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final isLoading = state.isLoading || _isLoadingConfigs;

    ref.listen<DefenseSchedulerState>(
      defenseSchedulerProvider,
      (previous, next) {
        if (next.error != null && next.error != previous?.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error!),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        if (next.message != null && next.message != previous?.message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.message!),
              backgroundColor: AppColors.success,
            ),
          );
        }
      },
    );

    final activeSem = state.activeSemester;
    final activeSemLabel = activeSem != null ? (activeSem['display_name']?.toString() ?? '') : 'No active semester';

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      );
    }

    return RefreshIndicator(
      color: AppColors.maroon,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefensysPageHeader(
              icon: Icons.event_note_outlined,
              title: 'PIT Events Configuration',
              subtitle: activeSemLabel,
              actions: _primaryButton(
                icon: const Icon(Icons.add, size: 18, color: Colors.white),
                label: 'Add Event',
                onTap: () => _showEventDialog(),
              ),
            ),
            const SizedBox(height: 28),
            _buildTopBanner(),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Event Configurations',
                  style: DefensysUi.sectionTitle,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_configs.isEmpty)
              _buildEmptyState()
            else
              _buildGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysTokens.infoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: DefensysTokens.infoText, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event setup precedes scheduling',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.infoText,
                    fontSize: 14,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure events, grading weights, rubrics, and deliverable guidelines. Pre-Defense deliverables will block defense scheduler assignments until student teams upload them and instructors endorse the team.',
                  style: TextStyle(
                    color: DefensysTokens.infoText.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontFamily: DefensysTokens.fontFamily,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return DefensysCard(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No PIT Events Configured',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.textPrimary,
              fontFamily: DefensysTokens.fontFamily,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure grading rules and deliverable checklists for this semester.',
            style: TextStyle(
              color: DefensysTokens.textSecondary,
              fontSize: 13,
              fontFamily: DefensysTokens.fontFamily,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _primaryButton(
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: 'Add Event',
            onTap: () => _showEventDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final state = ref.watch(defenseSchedulerProvider);
    final rubricList = state.rubrics;
    final peerRubricList = state.peerRubrics;

    String rubricName(dynamic id) {
      if (id == null) return 'Not Selected';
      final r = rubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Rubric';
    }

    String peerRubricName(dynamic id) {
      if (id == null) return 'Not Selected';
      final r = peerRubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Peer Rubric';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 950;

        if (isDesktop) {
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _configs.length,
            itemBuilder: (context, index) {
              final config = _configs[index];
              final delivs = config['deliverables'] as List? ?? [];
              final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
              final vaultCount = delivs.where((d) => d['deliverable_type'] == 'vault').length;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DefensysCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              config['event_name']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textPrimary,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
                              ),
                              child: Text(
                                '${config['panel_weight']}% Panel / ${config['peer_weight']}% Peer',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: DefensysTokens.maroon,
                                  fontFamily: DefensysTokens.fontFamily,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildConfigRow(
                          icon: Icons.assignment_outlined,
                          label: 'Panel Rubric: ',
                          value: rubricName(config['panel_rubric_id']),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildConfigRow(
                          icon: Icons.groups_outlined,
                          label: 'Peer Rubric: ',
                          value: peerRubricName(config['peer_rubric_id']),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildConfigRow(
                          icon: Icons.folder_outlined,
                          label: 'Deliverables: ',
                          value: '$preCount Pre-Defense, $vaultCount Vault',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _cardButton(
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            label: 'Edit',
                            onTap: () => _showEventDialog(config),
                            color: DefensysTokens.textDark,
                            borderColor: const Color(0xFFD1D5DB),
                          ),
                          const SizedBox(width: 8),
                          _cardIconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            onTap: () => _deleteConfig(config),
                            color: DefensysTokens.danger,
                            hoverColor: DefensysTokens.dangerBg,
                            tooltip: 'Delete Event',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        // Mobile / Tablet View (Card layout)
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth > 600 ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 250,
          ),
          itemCount: _configs.length,
          itemBuilder: (context, index) {
            final config = _configs[index];
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final vaultCount = delivs.where((d) => d['deliverable_type'] == 'vault').length;

            return DefensysCard(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          config['event_name']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textPrimary,
                            fontFamily: DefensysTokens.fontFamily,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
                        ),
                        child: Text(
                          '${config['panel_weight']}% Panel / ${config['peer_weight']}% Peer',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.maroon,
                            fontFamily: DefensysTokens.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildConfigRow(
                          icon: Icons.assignment_outlined,
                          label: 'Panel Rubric: ',
                          value: rubricName(config['panel_rubric_id']),
                        ),
                        const SizedBox(height: 10),
                        _buildConfigRow(
                          icon: Icons.groups_outlined,
                          label: 'Peer Rubric: ',
                          value: peerRubricName(config['peer_rubric_id']),
                        ),
                        const SizedBox(height: 10),
                        _buildConfigRow(
                          icon: Icons.folder_outlined,
                          label: 'Deliverables: ',
                          value: '$preCount Pre-Defense, $vaultCount Vault Template',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _cardButton(
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: 'Edit',
                        onTap: () => _showEventDialog(config),
                        color: DefensysTokens.textDark,
                        borderColor: const Color(0xFFD1D5DB),
                      ),
                      const SizedBox(width: 8),
                      _cardIconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        onTap: () => _deleteConfig(config),
                        color: DefensysTokens.danger,
                        hoverColor: DefensysTokens.dangerBg,
                        tooltip: 'Delete Event',
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildConfigRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: DefensysTokens.textSecondary),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: DefensysTokens.textSecondary,
            fontWeight: FontWeight.w500,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              color: DefensysTokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontFamily: DefensysTokens.fontFamily,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _EventConfigEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? config;
  final VoidCallback onSaveSuccess;

  const _EventConfigEditDialog({
    this.config,
    required this.onSaveSuccess,
  });

  @override
  ConsumerState<_EventConfigEditDialog> createState() => _EventConfigEditDialogState();
}

class _EventConfigEditDialogState extends ConsumerState<_EventConfigEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _vaultFileTemplateController = TextEditingController();
  late final TextEditingController _panelWeightController;
  late final TextEditingController _peerWeightController;

  int? _panelRubricId;
  int? _peerRubricId;
  int _panelWeight = 80;
  int _peerWeight = 20;

  List<Map<String, dynamic>> _deliverables = [];
  final List<TextEditingController> _labelControllers = [];
  final List<TextEditingController> _templateControllers = [];

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      _eventNameController.text = widget.config!['event_name']?.toString() ?? '';
      _vaultFileTemplateController.text = widget.config!['vault_file_template']?.toString() ?? '';
      _panelRubricId = int.tryParse(widget.config!['panel_rubric_id']?.toString() ?? '');
      _peerRubricId = int.tryParse(widget.config!['peer_rubric_id']?.toString() ?? '');
      _panelWeight = int.tryParse(widget.config!['panel_weight']?.toString() ?? '') ?? 80;
      _peerWeight = int.tryParse(widget.config!['peer_weight']?.toString() ?? '') ?? 20;

      final delList = widget.config!['deliverables'] as List? ?? [];
      _deliverables = delList.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    _panelWeightController = TextEditingController(text: _panelWeight.toString());
    _peerWeightController = TextEditingController(text: _peerWeight.toString());

    for (final d in _deliverables) {
      _labelControllers.add(TextEditingController(text: d['label']?.toString() ?? ''));
      _templateControllers.add(TextEditingController(text: d['vault_file_template']?.toString() ?? ''));
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _vaultFileTemplateController.dispose();
    _panelWeightController.dispose();
    _peerWeightController.dispose();
    for (final ctrl in _labelControllers) {
      ctrl.dispose();
    }
    for (final ctrl in _templateControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onPanelWeightChanged(String value) {
    setState(() {
      _panelWeight = int.tryParse(value.trim()) ?? 0;
    });
  }

  void _onPeerWeightChanged(String value) {
    setState(() {
      _peerWeight = int.tryParse(value.trim()) ?? 0;
    });
  }

  void _addDeliverable() {
    setState(() {
      _deliverables.add({
        'deliverable_id': '',
        'label': '',
        'deliverable_type': 'pre',
        'required': true,
        'display_order': _deliverables.length + 1,
        'vault_note': '',
        'vault_file_template': '',
        'is_restricted': false,
      });
      _labelControllers.add(TextEditingController(text: ''));
      _templateControllers.add(TextEditingController(text: ''));
    });
  }

  void _removeDeliverable(int index) {
    setState(() {
      _deliverables.removeAt(index);
      final lCtrl = _labelControllers.removeAt(index);
      final tCtrl = _templateControllers.removeAt(index);
      lCtrl.dispose();
      tCtrl.dispose();
    });
  }

  String _resolveFilenamePreview(String template, String label) {
    var result = template.trim();
    if (result.isEmpty) {
      result = '{year}.{course}.{project}.{semester}';
    }
    result = result.replaceAll('{year}', '2ndYear');
    result = result.replaceAll('{course}', 'PIT201');
    result = result.replaceAll('{project}', 'IoTMonitor');
    result = result.replaceAll('{event}', '2ndYearPITExpo');
    result = result.replaceAll('{semester}', '1stSemester');

    // Deliverable slug: title-cased no special characters
    final slug = label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    result = result.replaceAll('{deliverable}', slug.isNotEmpty ? slug : 'ProposalPDF');

    if (!result.toLowerCase().endsWith('.pdf')) {
      result += '.pdf';
    }
    return result;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_panelRubricId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Panel Rubric.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_peerRubricId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Peer Rubric.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_panelWeight + _peerWeight != 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weights must total exactly 100%.'), backgroundColor: Colors.red),
      );
      return;
    }

    final state = ref.read(defenseSchedulerProvider);
    final activeSem = state.activeSemester;
    final semesterId = activeSem != null ? int.tryParse(activeSem['id']?.toString() ?? '') : null;

    final payload = {
      'semester_id': semesterId,
      'event_name': _eventNameController.text.trim(),
      'panel_rubric_id': _panelRubricId,
      'peer_rubric_id': _peerRubricId,
      'panel_weight': _panelWeight,
      'peer_weight': _peerWeight,
      'vault_file_template': _vaultFileTemplateController.text.trim(),
      'deliverables': _deliverables,
    };

    final success = await ref.read(defenseSchedulerProvider.notifier).savePitEventConfig(payload);
    if (success) {
      widget.onSaveSuccess();
    }
  }

  InputDecoration _dialogInputDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(
        fontFamily: DefensysTokens.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: DefensysTokens.textSecondary,
      ),
      hintStyle: const TextStyle(
        fontFamily: DefensysTokens.fontFamily,
        fontSize: 13,
        color: Colors.grey,
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DefensysTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
      ),
    );
  }

  Widget _buildWeightSplitBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 10,
            color: Colors.grey.shade200,
            child: Row(
              children: [
                if (_panelWeight > 0)
                  Expanded(
                    flex: _panelWeight,
                    child: Container(
                      color: DefensysTokens.maroon,
                    ),
                  ),
                if (_peerWeight > 0)
                  Expanded(
                    flex: _peerWeight,
                    child: Container(
                      color: DefensysTokens.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: DefensysTokens.maroon, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Panel Evaluation: $_panelWeight%', style: const TextStyle(fontSize: 12, color: DefensysTokens.textSecondary, fontFamily: DefensysTokens.fontFamily, fontWeight: FontWeight.w600)),
              ],
            ),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: DefensysTokens.gold, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Peer Evaluation: $_peerWeight%', style: const TextStyle(fontSize: 12, color: DefensysTokens.textSecondary, fontFamily: DefensysTokens.fontFamily, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormGroup({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: DefensysTokens.maroon, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textPrimary,
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: DefensysTokens.textDark,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontFamily: DefensysTokens.fontFamily,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final panelRubrics = state.rubrics.where((r) => r['scope'] == 'pit' && r['evaluation_type'] == 'panel').toList();
    final peerRubrics = state.peerRubrics.where((r) => r['scope'] == 'pit' && r['evaluation_type'] == 'peer').toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings_suggest_outlined, color: DefensysTokens.maroon, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        widget.config == null ? 'Configure New PIT Event' : 'Edit Event Configuration',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.maroon,
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      hoverColor: Colors.grey.shade100,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group 1: General configuration
                      _buildFormGroup(
                        title: 'General Details',
                        subtitle: '• Required event details and rubrics',
                        icon: Icons.event_note_outlined,
                        children: [
                          TextFormField(
                            controller: _eventNameController,
                            decoration: _dialogInputDecoration(
                              labelText: 'Event Name',
                              hintText: 'e.g. 2nd Year PIT Expo',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Event Name is required.';
                              }
                              return null;
                            },
                            style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _panelRubricId,
                                  decoration: _dialogInputDecoration(labelText: 'Panel Rubric (Required)'),
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14, color: DefensysTokens.textPrimary),
                                  items: panelRubrics.map((r) {
                                    return DropdownMenuItem<int>(
                                      value: int.tryParse(r['id']?.toString() ?? ''),
                                      child: Text(r['name']?.toString() ?? ''),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() => _panelRubricId = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _peerRubricId,
                                  decoration: _dialogInputDecoration(labelText: 'Peer Rubric (Required)'),
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14, color: DefensysTokens.textPrimary),
                                  items: peerRubrics.map((r) {
                                    return DropdownMenuItem<int>(
                                      value: int.tryParse(r['id']?.toString() ?? ''),
                                      child: Text(r['name']?.toString() ?? ''),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() => _peerRubricId = value);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Group 2: Weight distribution
                      _buildFormGroup(
                        title: 'Grading Weight Split',
                        subtitle: '• Adjust the ratio between Panel and Peer evaluation (Must total 100%)',
                        icon: Icons.percent_outlined,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _panelWeightController,
                                  decoration: _dialogInputDecoration(
                                    labelText: 'Panel Weight (%)',
                                    hintText: 'e.g. 80',
                                  ),
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                  onChanged: _onPanelWeightChanged,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final parsed = int.tryParse(value);
                                    if (parsed == null) {
                                      return 'Invalid number';
                                    }
                                    if (parsed < 0) {
                                      return 'Must be >= 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _peerWeightController,
                                  decoration: _dialogInputDecoration(
                                    labelText: 'Peer Weight (%)',
                                    hintText: 'e.g. 20',
                                  ),
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                  onChanged: _onPeerWeightChanged,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final parsed = int.tryParse(value);
                                    if (parsed == null) {
                                      return 'Invalid number';
                                    }
                                    if (parsed < 0) {
                                      return 'Must be >= 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Slide or type to adjust weights:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                  fontFamily: DefensysTokens.fontFamily,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: DefensysTokens.maroon,
                              inactiveTrackColor: DefensysTokens.gold,
                              thumbColor: DefensysTokens.maroon,
                              overlayColor: DefensysTokens.maroon.withValues(alpha: 0.12),
                              valueIndicatorColor: DefensysTokens.maroon,
                              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                              trackHeight: 6,
                            ),
                            child: Slider(
                              value: _panelWeight.clamp(0, 100).toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20, // step of 5%
                              label: 'Panel: $_panelWeight% / Peer: $_peerWeight%',
                              onChanged: (val) {
                                final panelVal = val.toInt();
                                final peerVal = 100 - panelVal;
                                setState(() {
                                  _panelWeight = panelVal;
                                  _peerWeight = peerVal;
                                  _panelWeightController.text = panelVal.toString();
                                  _peerWeightController.text = peerVal.toString();
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildWeightSplitBar(),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total: ${_panelWeight + _peerWeight}%${(_panelWeight + _peerWeight) == 100 ? '' : ' — must equal 100%'}',
                                style: TextStyle(
                                  color: (_panelWeight + _peerWeight) == 100
                                      ? DefensysTokens.success
                                      : DefensysTokens.danger,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  fontFamily: DefensysTokens.fontFamily,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _panelWeight = 80;
                                    _peerWeight = 20;
                                    _panelWeightController.text = '80';
                                    _peerWeightController.text = '20';
                                  });
                                },
                                icon: const Icon(Icons.restore, size: 14, color: DefensysTokens.maroon),
                                label: const Text('Reset to 80 / 20'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: DefensysTokens.maroon,
                                  side: const BorderSide(color: DefensysTokens.maroon, width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: DefensysTokens.fontFamily,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Deliverables Header Section
                      Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.checklist_outlined, color: DefensysTokens.maroon, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Deliverables Checklist',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: DefensysTokens.textPrimary,
                                        fontFamily: DefensysTokens.fontFamily,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• Add student deliverables for this event',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                        fontFamily: DefensysTokens.fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _addDeliverable,
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Deliverable'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: DefensysTokens.maroon,
                                    textStyle: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _deliverables.length,
                        itemBuilder: (context, idx) {
                          final d = _deliverables[idx];
                          final isVault = d['deliverable_type'] == 'vault';

                          // Controllers for each item
                          final labelCtrl = _labelControllers[idx];
                          final templateCtrl = _templateControllers[idx];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: TextFormField(
                                        controller: labelCtrl,
                                        decoration: _dialogInputDecoration(
                                          labelText: 'Name / Label',
                                          hintText: 'e.g. System Demo URL',
                                        ),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                        onChanged: (val) {
                                          d['label'] = val.trim();
                                          // Re-evaluate template preview
                                          if (isVault) {
                                            setState(() {});
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: d['deliverable_type']?.toString(),
                                        decoration: _dialogInputDecoration(labelText: 'Type'),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13, color: DefensysTokens.textPrimary),
                                        items: const [
                                          DropdownMenuItem(value: 'pre', child: Text('Pre-Defense', style: TextStyle(fontSize: 13, fontFamily: DefensysTokens.fontFamily))),
                                          DropdownMenuItem(value: 'vault', child: Text('Vault', style: TextStyle(fontSize: 13, fontFamily: DefensysTokens.fontFamily))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              d['deliverable_type'] = val;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      height: 48,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        border: Border.all(color: const Color(0xFFE5E7EB)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: d['required'] == true,
                                            activeColor: DefensysTokens.maroon,
                                            onChanged: (val) {
                                              setState(() {
                                                d['required'] = val == true;
                                              });
                                            },
                                          ),
                                          const Text(
                                            'Required',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: DefensysTokens.fontFamily,
                                              color: DefensysTokens.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      onPressed: () => _removeDeliverable(idx),
                                      icon: const Icon(Icons.delete_outline_rounded, color: DefensysTokens.danger),
                                      style: IconButton.styleFrom(
                                        hoverColor: DefensysTokens.dangerBg,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isVault) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: d['is_restricted'] == true,
                                        activeColor: DefensysTokens.maroon,
                                        onChanged: (val) {
                                          setState(() {
                                            d['is_restricted'] = val == true;
                                          });
                                        },
                                      ),
                                      const Text(
                                        'Restricted (Private in Vault)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: DefensysTokens.fontFamily,
                                          color: DefensysTokens.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            TextFormField(
                                              controller: templateCtrl,
                                              decoration: _dialogInputDecoration(
                                                labelText: 'Vault Naming Template',
                                                hintText: 'e.g. {year}.{course}.{project}.{semester}',
                                              ),
                                              style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13),
                                              onChanged: (val) {
                                                setState(() {
                                                  d['vault_file_template'] = val.trim();
                                                });
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: ['{year}', '{course}', '{project}', '{event}', '{semester}', '{deliverable}']
                                                  .map((varName) => ActionChip(
                                                        label: Text(
                                                          varName,
                                                          style: const TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            fontFamily: DefensysTokens.fontFamily,
                                                          ),
                                                        ),
                                                        labelStyle: const TextStyle(color: DefensysTokens.maroon),
                                                        backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.05),
                                                        side: BorderSide(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
                                                        padding: EdgeInsets.zero,
                                                        onPressed: () {
                                                          final current = templateCtrl.text;
                                                          final next = current + varName;
                                                          templateCtrl.text = next;
                                                          setState(() {
                                                            d['vault_file_template'] = next;
                                                          });
                                                        },
                                                      ))
                                                  .toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: DefensysTokens.maroon.withValues(alpha: 0.03),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.1)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.remove_red_eye_outlined, size: 14, color: DefensysTokens.maroon),
                                                  const SizedBox(width: 6),
                                                  const Text(
                                                    'Filename Preview',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      color: DefensysTokens.maroon,
                                                      fontFamily: DefensysTokens.fontFamily,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              SelectableText(
                                                _resolveFilenamePreview(d['vault_file_template'] ?? '', d['label'] ?? ''),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.w700,
                                                  color: DefensysTokens.maroon,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _secondaryButton(
                    icon: const Icon(Icons.close, size: 18),
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: state.isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                      icon: state.isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                      label: const Text('Save Configuration'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
