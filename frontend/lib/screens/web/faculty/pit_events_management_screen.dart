import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/defense_scheduler_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../services/dashboard_provider.dart';
import '../../../utils/unsaved_changes.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitEventsManagementScreen extends ConsumerStatefulWidget {
  const PitEventsManagementScreen({super.key});

  @override
  ConsumerState<PitEventsManagementScreen> createState() => _PitEventsManagementScreenState();
}

class _PitEventsManagementScreenState extends ConsumerState<PitEventsManagementScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _isLoadingConfigs = true;
  bool _isMatrixView = false;
  final Set<int> _expandedConfigIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingConfigs = true);
    await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
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
    if (config['is_locked'] == true) {
      showErrorToast(context, config['lock_reason']?.toString() ?? 'Cannot delete a secured PIT event with active defenses or grades.');
      return;
    }
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
      showSuccessToast(context, 'Configuration deleted successfully.');
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

  Color _getTierColor(int index, String? name, String? code) {
    final search = '${name ?? ''} ${code ?? ''}'.toLowerCase();
    if (search.contains('1st') || search.contains('101')) {
      return const Color(0xFFF59E0B); // Amber
    } else if (search.contains('2nd') || search.contains('201')) {
      return AppColors.maroon; // Crimson Maroon
    } else if (search.contains('3rd') || search.contains('301')) {
      return const Color(0xFF6366F1); // Indigo
    } else if (search.contains('4th') || search.contains('401')) {
      return const Color(0xFF10B981); // Emerald
    }
    final palette = [
      const Color(0xFFF59E0B),
      AppColors.maroon,
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
      const Color(0xFFEC4899),
    ];
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final isLoading = state.isLoading || _isLoadingConfigs;

    ref.listen<DefenseSchedulerState>(
      defenseSchedulerProvider,
      (previous, next) {
        if (next.error != null && next.error != previous?.error) {
          showErrorToast(context, next.error!);
        }
        if (next.message != null && next.message != previous?.message) {
          showSuccessToast(context, next.message!);
        }
      },
    );

    final activeSem = state.activeSemester;
    final activeSemLabel = activeSem != null ? (activeSem['display_name']?.toString() ?? '') : 'No active semester';

    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(64.0),
          child: CircularProgressIndicator(color: AppColors.maroon),
        ),
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
            _buildExecutiveHeader(activeSemLabel, state.isSaving),
            const SizedBox(height: 24),
            _buildExecutiveStatCards(),
            const SizedBox(height: 20),
            _buildLifecycleLegend(),
            const SizedBox(height: 24),
            _buildSectionHeader(),
            const SizedBox(height: 16),
            if (_configs.isEmpty)
              _buildEmptyState()
            else if (!_isMatrixView)
              _buildShowcaseCardsView()
            else
              _buildEventMatrixView(),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveHeader(String activeSemLabel, bool isSaving) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.confirmation_number_rounded, color: AppColors.maroon, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'PIT Event Operations & Setup',
                    style: TextStyle(
                      color: AppColors.maroon,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.3,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Configure discrete academic exhibition events, evaluation weight ratios (Panel vs Peer), rubrics, and deliverable checklists for $activeSemLabel.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.35,
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: isSaving ? null : _loadData,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('Refresh Events'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : () => _showEventDialog(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add Event'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExecutiveStatCards() {
    final total = _configs.length;
    final rubricsLinked = _configs.where((c) => c['panel_rubric_id'] != null && c['peer_rubric_id'] != null).length;
    final totalDeliverables = _configs.fold<int>(
      0,
      (sum, c) => sum + ((c['deliverables'] as List? ?? []).length),
    );

    // Calculate average panel vs peer weight ratio
    double avgPanelWeight = 80;
    if (_configs.isNotEmpty) {
      final sumPanel = _configs.fold<double>(0, (sum, c) => sum + (int.tryParse(c['panel_weight']?.toString() ?? '') ?? 80));
      avgPanelWeight = sumPanel / _configs.length;
    }
    final avgPeerWeight = 100 - avgPanelWeight.round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;

        final cards = [
          _statTile(
            title: 'Configured Events',
            value: '$total',
            subtitle: 'Exhibition event showcases',
            icon: Icons.event_available_rounded,
            accentColor: AppColors.maroon,
          ),
          _statTile(
            title: 'Grading Weight Ratios',
            value: '${avgPanelWeight.round()}% / $avgPeerWeight%',
            subtitle: 'Avg Panel vs Peer split ratio',
            icon: Icons.donut_large_rounded,
            accentColor: const Color(0xFFF59E0B),
            badgeText: 'Grading Model',
            badgeColor: const Color(0xFFFEF3C7),
            badgeTextColor: const Color(0xFF92400E),
          ),
          _statTile(
            title: 'Active Rubric Links',
            value: '$rubricsLinked / $total',
            subtitle: 'Panel & Peer rubrics configured',
            icon: Icons.assignment_turned_in_outlined,
            accentColor: const Color(0xFF10B981),
            badgeText: rubricsLinked == total ? 'Rubrics Complete' : 'Pending Setup',
            badgeColor: const Color(0xFFECFDF5),
            badgeTextColor: const Color(0xFF047857),
          ),
          _statTile(
            title: 'Vault & Archive Templates',
            value: '$totalDeliverables',
            subtitle: 'Deliverable checklist templates',
            icon: Icons.folder_copy_outlined,
            accentColor: const Color(0xFF6366F1),
            badgeText: 'Templates Active',
            badgeColor: const Color(0xFFEEF2FF),
            badgeTextColor: const Color(0xFF4338CA),
          ),
        ];

        if (isCompact) {
          return Column(
            children: cards.map((card) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card,
            )).toList(),
          );
        }

        return Row(
          children: cards
              .map((card) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _statTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    String? badgeText,
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor ?? const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeTextColor ?? const Color(0xFF475569),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: DefensysTokens.fontFamily,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
              fontFamily: DefensysTokens.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: DefensysTokens.fontFamily,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              fontFamily: DefensysTokens.fontFamily,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleLegend() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: AppColors.maroon),
              SizedBox(width: 8),
              Text(
                'PIT Event Lifecycle & Audit Safeguards',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 750;

              final steps = [
                _buildLegendStep(
                  stepNum: '01',
                  title: 'Event & Weights',
                  desc: 'Set event badge, tier code & panel vs peer weight split',
                  color: const Color(0xFFFEF3C7),
                  textColor: const Color(0xFF92400E),
                  numColor: const Color(0xFFF59E0B),
                ),
                _buildLegendStep(
                  stepNum: '02',
                  title: 'Rubrics & Checklists',
                  desc: 'Attach evaluation rubrics & archive filename templates',
                  color: const Color(0xFFECFDF5),
                  textColor: const Color(0xFF047857),
                  numColor: const Color(0xFF10B981),
                ),
                _buildLegendStep(
                  stepNum: '03',
                  title: 'Audit Lock Protection',
                  desc: 'Enforces read-only status once defenses or grades exist',
                  color: const Color(0xFFF1F5F9),
                  textColor: const Color(0xFF334155),
                  numColor: const Color(0xFF64748B),
                ),
              ];

              if (isCompact) {
                return Column(
                  children: steps.map((step) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: step,
                  )).toList(),
                );
              }

              return Row(
                children: [
                  Expanded(child: steps[0]),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8)),
                  ),
                  Expanded(child: steps[1]),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8)),
                  ),
                  Expanded(child: steps[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendStep({
    required String stepNum,
    required String title,
    required String desc,
    required Color color,
    required Color textColor,
    required Color numColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: numColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stepNum,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                fontFamily: DefensysTokens.fontFamily,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: textColor.withValues(alpha: 0.8),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PIT Event Showcase Hub',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                fontFamily: DefensysTokens.fontFamily,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Independent event cards with grading models and deliverable checklists',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                fontFamily: DefensysTokens.fontFamily,
              ),
            ),
          ],
        ),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _viewToggleButton(
                icon: Icons.style_rounded,
                label: 'Showcase Cards',
                isSelected: !_isMatrixView,
                onTap: () => setState(() => _isMatrixView = false),
              ),
              _viewToggleButton(
                icon: Icons.table_chart_rounded,
                label: 'Event Matrix',
                isSelected: _isMatrixView,
                onTap: () => setState(() => _isMatrixView = true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
                fontFamily: DefensysTokens.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF2F2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_busy_outlined, size: 36, color: AppColors.maroon),
          ),
          const SizedBox(height: 16),
          const Text(
            'No PIT Events Configured',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.textPrimary,
              fontFamily: DefensysTokens.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Configure evaluation weight splits, rubrics, and deliverable checklists for this academic semester.',
            style: TextStyle(
              color: DefensysTokens.textSecondary,
              fontSize: 13,
              fontFamily: DefensysTokens.fontFamily,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showEventDialog(),
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              label: const Text('Add Event Configuration'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.maroon,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowcaseCardsView() {
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
        final isDesktop = constraints.maxWidth > 900;
        final crossCount = isDesktop ? 2 : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: isDesktop ? 360 : 390,
          ),
          itemCount: _configs.length,
          itemBuilder: (context, index) {
            final config = _configs[index];
            final configId = int.tryParse(config['id']?.toString() ?? '') ?? index;
            final isExpanded = _expandedConfigIds.contains(configId);
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final postCount = delivs.where((d) => d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault').length;
            final isLocked = config['is_locked'] == true;
            final lockReason = config['lock_reason']?.toString() ?? 'Event is secured & locked';
            final panelWeight = int.tryParse(config['panel_weight']?.toString() ?? '') ?? 80;
            final peerWeight = int.tryParse(config['peer_weight']?.toString() ?? '') ?? 20;

            final eventName = config['event_name']?.toString() ?? '';
            final eventCode = config['event_code']?.toString() ?? '';
            final tierColor = _getTierColor(index, eventName, eventCode);

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Event Tier Accent Banner
                    Container(
                      height: 6,
                      color: tierColor,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card Header Row: Title, Code, Status & Actions
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: tierColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.confirmation_number_outlined, size: 20, color: tierColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            eventName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.textPrimary,
                                              fontFamily: DefensysTokens.fontFamily,
                                              letterSpacing: -0.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (eventCode.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Text(
                                              eventCode,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                fontFamily: DefensysTokens.fontFamily,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (isLocked)
                                      Tooltip(
                                        message: lockReason,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFFB45309)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Audit Locked & Secured',
                                              style: TextStyle(
                                                color: const Color(0xFF92400E),
                                                fontSize: 11.5,
                                                fontFamily: DefensysTokens.fontFamily,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.check_circle_outline_rounded, size: 12, color: Color(0xFF047857)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Active Event Showcase',
                                            style: TextStyle(
                                              color: const Color(0xFF047857),
                                              fontSize: 11.5,
                                              fontFamily: DefensysTokens.fontFamily,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 32,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showEventDialog(config),
                                      icon: Icon(
                                        isLocked ? Icons.visibility_outlined : Icons.edit_outlined,
                                        size: 13,
                                      ),
                                      label: Text(isLocked ? 'View' : 'Edit'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textPrimary,
                                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        textStyle: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: isLocked ? lockReason : 'Delete Event',
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: InkWell(
                                        onTap: () => _deleteConfig(config),
                                        borderRadius: BorderRadius.circular(7),
                                        hoverColor: isLocked ? Colors.grey.shade100 : DefensysTokens.dangerBg,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: isLocked ? const Color(0xFFE2E8F0) : const Color(0xFFFCA5A5),
                                            ),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 15,
                                              color: isLocked ? Colors.grey : DefensysTokens.danger,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Dual Evaluation Weight Gauge Bar
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.maroon, shape: BoxShape.circle)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Panel: $panelWeight%',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.maroon,
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Peer: $peerWeight%',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB45309),
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  height: 8,
                                  child: Row(
                                    children: [
                                      if (panelWeight > 0)
                                        Expanded(
                                          flex: panelWeight,
                                          child: Container(color: AppColors.maroon),
                                        ),
                                      if (peerWeight > 0)
                                        Expanded(
                                          flex: peerWeight,
                                          child: Container(color: const Color(0xFFF59E0B)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Rubric Micro-cards Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildMicroRubricCard(
                                  icon: Icons.assignment_outlined,
                                  label: 'Panel Rubric',
                                  value: rubricName(config['panel_rubric_id']),
                                  color: const Color(0xFFFEF2F2),
                                  iconColor: AppColors.maroon,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMicroRubricCard(
                                  icon: Icons.groups_outlined,
                                  label: 'Peer Rubric',
                                  value: peerRubricName(config['peer_rubric_id']),
                                  color: const Color(0xFFFFFBEB),
                                  iconColor: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Expandable Deliverable Checklist Drawer
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedConfigIds.remove(configId);
                                } else {
                                  _expandedConfigIds.add(configId);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.folder_outlined, size: 16, color: Color(0xFF6366F1)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Deliverable Checklist ($preCount Pre, $postCount Post)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                          fontFamily: DefensysTokens.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 120),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: delivs.isEmpty
                                  ? const Text(
                                      'No deliverable templates configured for this event.',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: DefensysTokens.fontFamily),
                                    )
                                  : SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: delivs.map<Widget>((d) {
                                          final isPost = d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault';
                                          final isReq = d['required'] == true;

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isPost ? Icons.archive_outlined : Icons.description_outlined,
                                                  size: 13,
                                                  color: isPost ? const Color(0xFF6366F1) : AppColors.maroon,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    d['label']?.toString() ?? 'Deliverable',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.textPrimary,
                                                      fontFamily: DefensysTokens.fontFamily,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isReq)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 4),
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFEE2E2),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      'Req',
                                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.maroon),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
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

  Widget _buildMicroRubricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventMatrixView() {
    final state = ref.watch(defenseSchedulerProvider);
    final rubricList = state.rubrics;
    final peerRubricList = state.peerRubrics;

    String rubricName(dynamic id) {
      if (id == null) return 'None (No Rubric)';
      final r = rubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Rubric';
    }

    String peerRubricName(dynamic id) {
      if (id == null) return 'None (No Rubric)';
      final r = peerRubricList.firstWhere(
        (item) => item['id']?.toString() == id.toString(),
        orElse: () => const {},
      );
      return r['name']?.toString() ?? 'Unknown Peer Rubric';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          dataRowMinHeight: 60,
          dataRowMaxHeight: 60,
          columns: const [
            DataColumn(label: Text('Event & Code', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Weight Split', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Panel Rubric', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Peer Rubric', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Deliverables', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily))),
          ],
          rows: _configs.map((config) {
            final delivs = config['deliverables'] as List? ?? [];
            final preCount = delivs.where((d) => d['deliverable_type'] == 'pre').length;
            final postCount = delivs.where((d) => d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault').length;
            final isLocked = config['is_locked'] == true;
            final lockReason = config['lock_reason']?.toString() ?? 'Secured & locked';

            return DataRow(
              cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        config['event_name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary, fontFamily: DefensysTokens.fontFamily),
                      ),
                      if (config['event_code']?.toString().isNotEmpty == true)
                        Text(
                          config['event_code']?.toString() ?? '',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: DefensysTokens.fontFamily),
                        ),
                    ],
                  ),
                ),
                DataCell(
                  isLocked
                      ? Tooltip(
                          message: lockReason,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDE68A))),
                            child: const Text('Locked', style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA7F3D0))),
                          child: const Text('Active', style: TextStyle(color: Color(0xFF047857), fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: DefensysTokens.maroon.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text('${config['panel_weight']}% Panel / ${config['peer_weight']}% Peer', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: DefensysTokens.maroon)),
                  ),
                ),
                DataCell(Text(rubricName(config['panel_rubric_id']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataCell(Text(peerRubricName(config['peer_rubric_id']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataCell(Text('$preCount Pre, $postCount Post', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showEventDialog(config),
                        icon: Icon(isLocked ? Icons.visibility_outlined : Icons.edit_outlined, size: 16, color: AppColors.textPrimary),
                      ),
                      IconButton(
                        onPressed: () => _deleteConfig(config),
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: isLocked ? Colors.grey : DefensysTokens.danger),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
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
  final _eventCodeController = TextEditingController();
  final _archiveFileTemplateController = TextEditingController();
  late final TextEditingController _panelWeightController;
  late final TextEditingController _peerWeightController;

  int? _panelRubricId;
  int? _peerRubricId;
  int _panelWeight = 80;
  int _peerWeight = 20;

  List<Map<String, dynamic>> _deliverables = [];
  final List<TextEditingController> _labelControllers = [];
  final List<TextEditingController> _templateControllers = [];

  bool _isDirty = false;
  bool _allowPop = false;

  bool _checkIfDirty() {
    final initialEventName = widget.config?['event_name']?.toString() ?? '';
    final initialTemplate = (widget.config?['archive_file_template'] ?? widget.config?['vault_file_template'])?.toString() ?? '';
    final initialPanelRubric = int.tryParse(widget.config?['panel_rubric_id']?.toString() ?? '');
    final initialPeerRubric = int.tryParse(widget.config?['peer_rubric_id']?.toString() ?? '');
    final initialPanelWeight = int.tryParse(widget.config?['panel_weight']?.toString() ?? '') ?? 80;
    final initialPeerWeight = int.tryParse(widget.config?['peer_weight']?.toString() ?? '') ?? 20;

    final initialDelList = widget.config?['deliverables'] as List? ?? [];

    if (_eventNameController.text != initialEventName) return true;
    if (_eventCodeController.text != (widget.config?['event_code']?.toString() ?? '')) return true;
    if (_archiveFileTemplateController.text != initialTemplate) return true;
    if (_panelRubricId != initialPanelRubric) return true;
    if (_peerRubricId != initialPeerRubric) return true;
    if (_panelWeight != initialPanelWeight) return true;
    if (_peerWeight != initialPeerWeight) return true;

    if (_deliverables.length != initialDelList.length) return true;

    for (int i = 0; i < _deliverables.length; i++) {
      final current = _deliverables[i];
      final initial = Map<String, dynamic>.from(initialDelList[i] as Map);

      if (current['label']?.toString() != initial['label']?.toString()) return true;

      final currentType = current['deliverable_type']?.toString();
      final initialType = initial['deliverable_type']?.toString();
      final normCurrentType = currentType == 'vault' ? 'post' : currentType;
      final normInitialType = initialType == 'vault' ? 'post' : initialType;
      if (normCurrentType != normInitialType) return true;

      if ((current['required'] == true) != (initial['required'] == true)) return true;
      if ((current['is_restricted'] == true) != (initial['is_restricted'] == true)) return true;

      final currentTpl = current['archive_file_template'] ?? current['vault_file_template'];
      final initialTpl = initial['archive_file_template'] ?? initial['vault_file_template'];
      if (currentTpl?.toString() != initialTpl?.toString()) return true;
    }

    return false;
  }

  void _markDirty() {
    final isDirty = _checkIfDirty();
    if (_isDirty == isDirty) return;
    setState(() {
      _isDirty = isDirty;
    });
  }

  Future<void> _handleClose() async {
    if (_isDirty) {
      final discard = await confirmDiscardUnsavedChanges(context);
      if (discard && mounted) {
        setState(() {
          _allowPop = true;
        });
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _allowPop = true;
      });
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      _eventNameController.text = widget.config!['event_name']?.toString() ?? '';
      _eventCodeController.text = widget.config!['event_code']?.toString() ?? '';
      _archiveFileTemplateController.text = (widget.config!['archive_file_template'] ?? widget.config!['vault_file_template'])?.toString() ?? '';
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
      _templateControllers.add(TextEditingController(
          text: (d['archive_file_template'] ?? d['vault_file_template'])?.toString() ?? ''));
    }
    _eventNameController.addListener(_markDirty);
    _eventCodeController.addListener(_markDirty);
    _archiveFileTemplateController.addListener(_markDirty);
    _panelWeightController.addListener(_markDirty);
    _peerWeightController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _eventNameController.removeListener(_markDirty);
    _eventCodeController.removeListener(_markDirty);
    _archiveFileTemplateController.removeListener(_markDirty);
    _panelWeightController.removeListener(_markDirty);
    _peerWeightController.removeListener(_markDirty);

    _eventNameController.dispose();
    _eventCodeController.dispose();
    _archiveFileTemplateController.dispose();
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
    final clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _panelWeight = 0;
        _peerWeight = 100;
        _peerWeightController.text = '100';
      });
      _markDirty();
      return;
    }
    final parsed = int.tryParse(clean);
    if (parsed != null) {
      final clamped = parsed.clamp(0, 100);
      setState(() {
        _panelWeight = clamped;
        _peerWeight = 100 - clamped;
        _peerWeightController.text = (100 - clamped).toString();
        if (parsed != clamped) {
          _panelWeightController.text = clamped.toString();
        }
      });
    }
    _markDirty();
  }

  void _onPeerWeightChanged(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _peerWeight = 0;
        _panelWeight = 100;
        _panelWeightController.text = '100';
      });
      _markDirty();
      return;
    }
    final parsed = int.tryParse(clean);
    if (parsed != null) {
      final clamped = parsed.clamp(0, 100);
      setState(() {
        _peerWeight = clamped;
        _panelWeight = 100 - clamped;
        _panelWeightController.text = (100 - clamped).toString();
        if (parsed != clamped) {
          _peerWeightController.text = clamped.toString();
        }
      });
    }
    _markDirty();
  }

  void _addDeliverable() {
    setState(() {
      _deliverables.add({
        'deliverable_id': '',
        'label': '',
        'deliverable_type': 'pre',
        'required': true,
        'display_order': _deliverables.length + 1,
        'archive_note': '',
        'archive_file_template': '',
        'is_restricted': false,
      });
      _labelControllers.add(TextEditingController(text: ''));
      _templateControllers.add(TextEditingController(text: ''));
    });
    _markDirty();
  }

  void _removeDeliverable(int index) {
    setState(() {
      _deliverables.removeAt(index);
      final lCtrl = _labelControllers.removeAt(index);
      final tCtrl = _templateControllers.removeAt(index);
      lCtrl.dispose();
      tCtrl.dispose();
    });
    _markDirty();
  }

  String _resolveFilenamePreview(String template, String label, String pitYear) {
    var result = template.trim();
    if (result.isEmpty) {
      result = '{project}';
    }
    final cleanedYear = pitYear.replaceAll(' ', '');
    String courseCode = 'PIT201';
    if (pitYear == '1st Year') {
      courseCode = 'PIT101';
    } else if (pitYear == '2nd Year') {
      courseCode = 'PIT201';
    } else if (pitYear == '3rd Year') {
      courseCode = 'PIT301';
    } else if (pitYear == '4th Year') {
      courseCode = 'PIT401';
    }

    result = result.replaceAll('{year}', cleanedYear);
    result = result.replaceAll('{course}', courseCode);
    result = result.replaceAll('{project}', 'IoTMonitor');
    result = result.replaceAll('{event}', '${cleanedYear}PITExpo');
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
    if (_panelWeight + _peerWeight != 100) {
      showValidationToast(context, 'Weights must total exactly 100%.');
      return;
    }

    final state = ref.read(defenseSchedulerProvider);
    final activeSem = state.activeSemester;
    final semesterId = activeSem != null ? int.tryParse(activeSem['id']?.toString() ?? '') : null;

    final payload = {
      'semester_id': semesterId,
      'event_name': _eventNameController.text.trim(),
      'event_code': _eventCodeController.text.trim(),
      'panel_rubric_id': _panelRubricId,
      'peer_rubric_id': _peerRubricId,
      'panel_weight': _panelWeight,
      'peer_weight': _peerWeight,
      'archive_file_template': _archiveFileTemplateController.text.trim(),
      'deliverables': _deliverables,
    };

    final success = await ref.read(defenseSchedulerProvider.notifier).savePitEventConfig(payload);
    if (success) {
      setState(() {
        _isDirty = false;
        _allowPop = true;
      });
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
    final bool isLocked = widget.config?['is_locked'] == true;
    final String lockReason = widget.config?['lock_reason']?.toString() ??
        'This PIT Event is secured because active defenses or evaluation grades exist.';

    final state = ref.watch(defenseSchedulerProvider);
    final dashboard = ref.watch(dashboardProvider('faculty')).data;
    final pitYear = dashboard?['pit_lead_year']?.toString() ?? '2nd Year';

    final otherConfigs = state.pitEvents.where((c) {
      if (widget.config == null) return true;
      return c['id']?.toString() != widget.config!['id']?.toString();
    });

    final Map<int, String> assignedPanelEventMap = {};
    final Map<int, String> assignedPeerEventMap = {};

    for (final c in otherConfigs) {
      final pId = int.tryParse(c['panel_rubric_id']?.toString() ?? '');
      final prId = int.tryParse(c['peer_rubric_id']?.toString() ?? '');
      final eventName = c['event_name']?.toString() ?? 'Another Event';
      if (pId != null) assignedPanelEventMap[pId] = eventName;
      if (prId != null) assignedPeerEventMap[prId] = eventName;
    }

    final panelRubrics = state.rubrics.where((r) {
      return r['scope'] == 'pit' && r['evaluation_type'] == 'panel';
    }).toList();

    final peerRubrics = state.peerRubrics.where((r) {
      return r['scope'] == 'pit' && r['evaluation_type'] == 'peer';
    }).toList();

    return PopScope(
      canPop: !_isDirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _handleClose();
      },
      child: Dialog(
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
                          widget.config != null ? (isLocked ? 'View PIT Event (Secured)' : 'Edit PIT Event') : 'Add PIT Event',
                          style: const TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: _handleClose,
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
                      if (isLocked) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline_rounded, color: Color(0xFFB45309), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PIT Event Locked (Read-Only)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF92400E),
                                        fontFamily: DefensysTokens.fontFamily,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      lockReason,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFB45309),
                                        fontFamily: DefensysTokens.fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Group 1: General configuration
                      _buildFormGroup(
                        title: 'General Details',
                        subtitle: '• Required event details and rubrics',
                        icon: Icons.event_note_outlined,
                        children: [
                          TextFormField(
                            controller: _eventNameController,
                            readOnly: isLocked,
                            decoration: _dialogInputDecoration(
                              labelText: 'Event Name',
                              hintText: 'e.g. $pitYear PIT Expo',
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
                          TextFormField(
                            controller: _eventCodeController,
                            readOnly: isLocked,
                            decoration: _dialogInputDecoration(
                              labelText: 'Stage code',
                            ),
                            style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Note: Assigning rubrics now is optional. You can leave them as "None" and attach published rubrics later before scheduling defenses.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF0369A1),
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                      fontFamily: DefensysTokens.fontFamily,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int?>(
                                  initialValue: _panelRubricId,
                                  decoration: _dialogInputDecoration(labelText: 'Panel Rubric'),
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14, color: DefensysTokens.textPrimary),
                                  items: () {
                                    final list = <DropdownMenuItem<int?>>[
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('None (No Rubric)'),
                                      ),
                                    ];
                                    list.addAll(panelRubrics.map((r) {
                                      return DropdownMenuItem<int?>(
                                        value: int.tryParse(r['id']?.toString() ?? ''),
                                        child: Text(r['name']?.toString() ?? ''),
                                      );
                                    }));
                                    if (_panelRubricId != null && !panelRubrics.any((r) => int.tryParse(r['id']?.toString() ?? '') == _panelRubricId)) {
                                      final currentRubric = state.rubrics.firstWhere(
                                        (r) => int.tryParse(r['id']?.toString() ?? '') == _panelRubricId,
                                        orElse: () => const {},
                                      );
                                      list.add(DropdownMenuItem<int?>(
                                        value: _panelRubricId,
                                        child: Text(currentRubric['name']?.toString() ?? 'Selected Rubric'),
                                      ));
                                    }
                                    return list;
                                  }(),
                                  onChanged: isLocked ? null : (value) {
                                    setState(() => _panelRubricId = value);
                                    _markDirty();
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<int?>(
                                  initialValue: _peerRubricId,
                                  decoration: _dialogInputDecoration(labelText: 'Peer Rubric'),
                                  style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14, color: DefensysTokens.textPrimary),
                                  items: () {
                                    final list = <DropdownMenuItem<int?>>[
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('None (No Rubric)'),
                                      ),
                                    ];
                                    list.addAll(peerRubrics.map((r) {
                                      return DropdownMenuItem<int?>(
                                        value: int.tryParse(r['id']?.toString() ?? ''),
                                        child: Text(r['name']?.toString() ?? ''),
                                      );
                                    }));
                                    if (_peerRubricId != null && !peerRubrics.any((r) => int.tryParse(r['id']?.toString() ?? '') == _peerRubricId)) {
                                      final currentRubric = state.peerRubrics.firstWhere(
                                        (r) => int.tryParse(r['id']?.toString() ?? '') == _peerRubricId,
                                        orElse: () => const {},
                                      );
                                      list.add(DropdownMenuItem<int?>(
                                        value: _peerRubricId,
                                        child: Text(currentRubric['name']?.toString() ?? 'Selected Rubric'),
                                      ));
                                    }
                                    return list;
                                  }(),
                                  onChanged: isLocked ? null : (value) {
                                    setState(() => _peerRubricId = value);
                                    _markDirty();
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
                                  readOnly: isLocked,
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
                                  readOnly: isLocked,
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
                              onChanged: isLocked ? null : (val) {
                                final panelVal = val.toInt();
                                final peerVal = 100 - panelVal;
                                setState(() {
                                  _panelWeight = panelVal;
                                  _peerWeight = peerVal;
                                  _panelWeightController.text = panelVal.toString();
                                  _peerWeightController.text = peerVal.toString();
                                });
                                _markDirty();
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
                                onPressed: isLocked ? null : () {
                                  setState(() {
                                    _panelWeight = 80;
                                    _peerWeight = 20;
                                    _panelWeightController.text = '80';
                                    _peerWeightController.text = '20';
                                  });
                                  _markDirty();
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
                              onPressed: isLocked ? null : _addDeliverable,
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
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pre-Defense items gate endorsement. Post-Defense items unlock after defense is officially complete.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF0369A1),
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                  fontFamily: DefensysTokens.fontFamily,
                                ),
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
                          final isPost = d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault';

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
                                        readOnly: isLocked,
                                        decoration: _dialogInputDecoration(
                                          labelText: 'Name / Label',
                                          hintText: 'e.g. System Demo URL',
                                        ),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 14),
                                        onChanged: (val) {
                                          d['label'] = val.trim();
                                          // Re-evaluate template preview
                                          if (isPost) {
                                            setState(() {});
                                          }
                                          _markDirty();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: d['deliverable_type']?.toString() == 'vault' ? 'post' : d['deliverable_type']?.toString(),
                                        decoration: _dialogInputDecoration(labelText: 'Type'),
                                        style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13, color: DefensysTokens.textPrimary),
                                        items: const [
                                          DropdownMenuItem(value: 'pre', child: Text('Pre-Defense', style: TextStyle(fontSize: 13, fontFamily: DefensysTokens.fontFamily))),
                                          DropdownMenuItem(value: 'post', child: Text('Post-Defense', style: TextStyle(fontSize: 13, fontFamily: DefensysTokens.fontFamily))),
                                        ],
                                        onChanged: isLocked ? null : (val) {
                                          if (val != null) {
                                            setState(() {
                                              d['deliverable_type'] = val;
                                            });
                                            _markDirty();
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
                                            onChanged: isLocked ? null : (val) {
                                              setState(() {
                                                d['required'] = val == true;
                                              });
                                              _markDirty();
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
                                      onPressed: isLocked ? null : () => _removeDeliverable(idx),
                                      icon: Icon(Icons.delete_outline_rounded, color: isLocked ? Colors.grey : DefensysTokens.danger),
                                      style: IconButton.styleFrom(
                                        hoverColor: isLocked ? Colors.grey.shade100 : DefensysTokens.dangerBg,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isPost) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: d['is_restricted'] == true,
                                        activeColor: DefensysTokens.maroon,
                                        onChanged: isLocked ? null : (val) {
                                          setState(() {
                                            d['is_restricted'] = val == true;
                                          });
                                          _markDirty();
                                        },
                                      ),
                                      const Text(
                                        'Restricted (Private in Archive)',
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
                                              readOnly: isLocked,
                                              decoration: _dialogInputDecoration(
                                                labelText: 'Archive Naming Template',
                                                hintText: 'e.g. {year}.{course}.{project}.{semester}',
                                              ),
                                              style: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 13),
                                              onChanged: (val) {
                                                setState(() {
                                                  d['archive_file_template'] = val.trim();
                                                });
                                                _markDirty();
                                              },
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Note: If left blank, the project title will be used as default.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: DefensysTokens.textSecondary,
                                                fontStyle: FontStyle.italic,
                                                fontFamily: DefensysTokens.fontFamily,
                                              ),
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
                                                        labelStyle: TextStyle(color: isLocked ? Colors.grey : DefensysTokens.maroon),
                                                        backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.05),
                                                        side: BorderSide(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
                                                        padding: EdgeInsets.zero,
                                                        onPressed: isLocked ? null : () {
                                                          final current = templateCtrl.text;
                                                          final next = current + varName;
                                                          templateCtrl.text = next;
                                                          setState(() {
                                                            d['archive_file_template'] = next;
                                                          });
                                                          _markDirty();
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
                                                _resolveFilenamePreview((d['archive_file_template'] ?? d['vault_file_template'])?.toString() ?? '', d['label'] ?? '', pitYear),
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
                    icon: Icon(isLocked ? Icons.check : Icons.close, size: 18),
                    label: isLocked ? 'Close' : 'Cancel',
                    onTap: _handleClose,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: (state.isSaving || isLocked) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLocked ? Colors.grey : DefensysTokens.maroon,
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
                      icon: isLocked
                          ? const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.white)
                          : (state.isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline, size: 18, color: Colors.white)),
                      label: Text(isLocked ? 'Secured (Read-Only)' : 'Save Configuration'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
