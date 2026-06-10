import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/defense_scheduler_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';

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

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.event_note, color: AppColors.maroon, size: 24),
            const SizedBox(width: 8),
            const Text(
              'PIT Events Configuration',
              style: TextStyle(
                color: AppColors.maroon,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (state.activeSemester != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.maroon.withOpacity(0.1)),
                  ),
                  child: Text(
                    state.activeSemester!['display_name']?.toString() ?? '',
                    style: const TextStyle(
                      color: AppColors.maroon,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.maroon),
            )
          : RefreshIndicator(
              color: AppColors.maroon,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBanner(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Event Configurations',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showEventDialog(),
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Add Event', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.maroon,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
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
            ),
    );
  }

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.maroon, size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event setup precedes scheduling',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Configure events, grading weights, rubrics, and deliverable guidelines. Pre-Defense deliverables will block defense scheduler assignments until student teams upload them and instructors endorse the team.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
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
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No PIT Events Configured',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure grading rules and deliverable checklists for this semester.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showEventDialog(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.maroon,
              elevation: 0,
            ),
            child: const Text('Add Event', style: TextStyle(color: Colors.white)),
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
        final crossCount = constraints.maxWidth > 900 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 220,
          ),
          itemCount: _configs.length,
          itemBuilder: (context, index) {
            final config = _configs[index];
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final vaultCount = delivs.where((d) => d['deliverable_type'] == 'vault').length;

            return Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
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
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroon.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${config['panel_weight']}% Panel / ${config['peer_weight']}% Peer',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildConfigRow(
                            icon: Icons.assignment_outlined,
                            label: 'Panel Rubric: ',
                            value: rubricName(config['panel_rubric_id']),
                          ),
                          const SizedBox(height: 6),
                          _buildConfigRow(
                            icon: Icons.groups_outlined,
                            label: 'Peer Rubric: ',
                            value: peerRubricName(config['peer_rubric_id']),
                          ),
                          const SizedBox(height: 6),
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
                        OutlinedButton.icon(
                          onPressed: () => _showEventDialog(config),
                          icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.textPrimary),
                          label: const Text('Edit', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _deleteConfig(config),
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
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
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
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

  int? _panelRubricId;
  int? _peerRubricId;
  int _panelWeight = 80;
  int _peerWeight = 20;

  List<Map<String, dynamic>> _deliverables = [];

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
      });
    });
  }

  void _removeDeliverable(int index) {
    setState(() {
      _deliverables.removeAt(index);
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
                  Text(
                    widget.config == null ? 'Configure New PIT Event' : 'Edit Event Configuration',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.maroon,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Name
                      TextFormField(
                        controller: _eventNameController,
                        decoration: const InputDecoration(
                          labelText: 'Event Name',
                          hintText: 'e.g. 2nd Year PIT Expo',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Event Name is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Rubrics Selection
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _panelRubricId,
                              decoration: const InputDecoration(
                                labelText: 'Panel Rubric',
                                border: OutlineInputBorder(),
                              ),
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
                              value: _peerRubricId,
                              decoration: const InputDecoration(
                                labelText: 'Peer Rubric',
                                border: OutlineInputBorder(),
                              ),
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
                      const SizedBox(height: 16),
                      // Weights
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _panelWeight.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Panel Weight (%)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final parsed = int.tryParse(value) ?? 0;
                                setState(() {
                                  _panelWeight = parsed;
                                  _peerWeight = (100 - parsed).clamp(0, 100);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('peerWeight_$_peerWeight'),
                              initialValue: _peerWeight.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Peer Weight (%)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final parsed = int.tryParse(value) ?? 0;
                                setState(() {
                                  _peerWeight = parsed;
                                  _panelWeight = (100 - parsed).clamp(0, 100);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Deliverables Checklist',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addDeliverable,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Deliverable'),
                            style: TextButton.styleFrom(foregroundColor: AppColors.maroon),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _deliverables.length,
                        itemBuilder: (context, idx) {
                          final d = _deliverables[idx];
                          final isVault = d['deliverable_type'] == 'vault';

                          // Controllers for each item
                          final labelCtrl = TextEditingController(text: d['label']);
                          final templateCtrl = TextEditingController(text: d['vault_file_template']);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: labelCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Name / Label',
                                            hintText: 'e.g. System Demo URL',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (val) {
                                            d['label'] = val.trim();
                                            // Re-evaluate template preview
                                            if (isVault) {
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 125,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: d['deliverable_type']?.toString(),
                                          decoration: const InputDecoration(
                                            labelText: 'Type',
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'pre', child: Text('Pre-Defense', style: TextStyle(fontSize: 13))),
                                            DropdownMenuItem(value: 'vault', child: Text('Vault', style: TextStyle(fontSize: 13))),
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
                                      const SizedBox(width: 4),
                                      Checkbox(
                                        value: d['required'] == true,
                                        onChanged: (val) {
                                          setState(() {
                                            d['required'] = val == true;
                                          });
                                        },
                                      ),
                                      const Text('Required', style: TextStyle(fontSize: 13)),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        onPressed: () => _removeDeliverable(idx),
                                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                  if (isVault) ...[
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: templateCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Vault Naming Template',
                                        hintText: 'e.g. {year}.{course}.{project}.{semester}',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          d['vault_file_template'] = val.trim();
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      children: ['{year}', '{course}', '{project}', '{event}', '{semester}', '{deliverable}']
                                          .map((varName) => ActionChip(
                                                label: Text(varName, style: const TextStyle(fontSize: 11)),
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
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Text(
                                            'Preview: ',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                                          ),
                                          Expanded(
                                            child: Text(
                                              _resolveFilenamePreview(d['vault_file_template'] ?? '', d['label'] ?? ''),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.maroon,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
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
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: state.isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.maroon,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: state.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save Configuration', style: TextStyle(color: Colors.white)),
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
