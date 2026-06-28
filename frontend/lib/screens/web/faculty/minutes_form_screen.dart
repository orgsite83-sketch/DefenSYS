import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/documenter_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../utils/pdf_viewer.dart';
import 'e_signature_upload_dialog.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class MinutesFormScreen extends ConsumerStatefulWidget {
  final int scheduleId;
  final VoidCallback onBack;

  const MinutesFormScreen({
    super.key,
    required this.scheduleId,
    required this.onBack,
  });

  @override
  ConsumerState<MinutesFormScreen> createState() => _MinutesFormScreenState();
}

class _MinutesFormScreenState extends ConsumerState<MinutesFormScreen> {
  final Map<int, TextEditingController> _controllers = {};
  bool _isSavingDraft = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    await ref.read(documenterProvider.notifier).fetchMinutesDetail(widget.scheduleId);
    _initializeControllers();
  }

  void _initializeControllers() {
    final minutes = ref.read(documenterProvider).activeMinutes;
    if (minutes == null) return;

    final comments = minutes['panelist_comments'] as List?;
    if (comments == null) return;

    for (final comment in comments) {
      final id = comment['id'] as int;
      final text = comment['comments']?.toString() ?? '';
      if (!_controllers.containsKey(id)) {
        _controllers[id] = TextEditingController(text: text);
      } else {
        _controllers[id]!.text = text;
      }
    }
  }

  Future<void> _saveDraft({bool silent = false}) async {
    if (_isSavingDraft) return;

    setState(() {
      _isSavingDraft = true;
    });

    final commentsPayload = _controllers.entries.map((e) {
      return {
        'id': e.key,
        'comments': e.value.text,
      };
    }).toList();

    final ok = await ref
        .read(documenterProvider.notifier)
        .saveComments(widget.scheduleId, commentsPayload);

    if (mounted) {
      setState(() {
        _isSavingDraft = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Draft comments saved successfully.' : 'Failed to save draft.'),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitAndSign() async {
    // Validate comments are filled
    for (final controller in _controllers.values) {
      if (controller.text.trim().isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Incomplete Comments'),
            content: const Text('All panelist comments must be filled before submitting and signing the minutes.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    // 1. Save current comments first
    await _saveDraft(silent: true);

    // 2. Submit minutes (signs as documenter)
    final ok = await ref.read(documenterProvider.notifier).submitMinutes(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minutes submitted and signed successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchDetail();
      } else {
        final error = ref.read(documenterProvider).error ?? 'Submission failed';
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Submission Failed'),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _signAsAdviser() async {
    setState(() {
      _isSubmitting = true;
    });

    final ok = await ref.read(documenterProvider.notifier).adviserSign(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed as Project Adviser successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchDetail();
      }
    }
  }

  Future<void> _signAsChairman() async {
    setState(() {
      _isSubmitting = true;
    });

    final ok = await ref.read(documenterProvider.notifier).chairmanSign(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed as Chairman successfully. PDF generated.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchDetail();
      }
    }
  }

  Future<void> _viewPdf() async {
    final bytes = await ref.read(documenterProvider.notifier).downloadPdf(widget.scheduleId);
    if (bytes != null && mounted) {
      final minutes = ref.read(documenterProvider).activeMinutes;
      final team = minutes?['team_name']?.toString() ?? 'team';
      final stage = minutes?['defense_stage_label']?.toString() ?? 'defense';
      await viewPdfInDialog(
        context: context,
        pdfBytes: bytes,
        fileName: 'minutes_${team.replaceAll(' ', '_')}_${stage.replaceAll(' ', '_')}.pdf',
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load PDF.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documenterProvider);
    final user = ref.watch(authProvider).user;
    final userHasSignature = user?['e_signature'] != null && user?['e_signature'] != '';

    final minutes = state.activeMinutes;

    Widget body;

    if (state.isLoading && minutes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && minutes == null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              state.error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchDetail,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (minutes == null) {
      body = const Center(child: Text('No minutes found.'));
    } else {
      final status = minutes['status']?.toString();
      final schedule = minutes['schedule'] as Map<String, dynamic>?;
      final documenterId = schedule?['documenter'] as int?;
      final isDocumenter = user?['id'] == documenterId;

      final isAdviser = schedule?['team_adviser_id'] == user?['id'] || 
          (user?['is_adviser'] == true && minutes['adviser_name'] == user?['name']);
      
      final isAdmin = user?['role']?.toString() == 'admin';
      final isCancelled = schedule?['status']?.toString() == 'cancelled';

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // E-Signature Alert Banner
          if (!userHasSignature && _userNeedsToSign(status, isDocumenter, isAdviser, isAdmin))
            _buildNoSignatureBanner(),

          // Horizontal Progress Step Header
          _buildSigningFlowStepper(status),
          const SizedBox(height: 24),

          // Main Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Metadata Left Pane
              Expanded(
                flex: 4,
                child: _buildDetailsCard(minutes),
              ),
              const SizedBox(width: 24),

              // Comments / Form Right Pane
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCommentsSection(minutes, status, isDocumenter, isCancelled),
                    const SizedBox(height: 24),
                    _buildActionButtons(status, isDocumenter, isAdviser, isAdmin, userHasSignature, isCancelled),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Minutes of Defense Details',
          style: TextStyle(color: DefensysTokens.maroon, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DefensysTokens.maroon),
          onPressed: widget.onBack,
        ),
        actions: [
          if (minutes != null && minutes['status'] == 'completed')
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ElevatedButton.icon(
                onPressed: _viewPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('View Final PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroon,
                  foregroundColor: DefensysTokens.gold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: body,
      ),
    );
  }

  bool _userNeedsToSign(String? status, bool isDocumenter, bool isAdviser, bool isAdmin) {
    if (status == 'draft' && isDocumenter) return true;
    if (status == 'submitted' && isAdviser) return true;
    if (status == 'adviser_signed' && isAdmin) return true;
    return false;
  }

  Widget _buildNoSignatureBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'E-Signature Required',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'You have not uploaded your e-signature yet. You must upload a signature image to sign or submit these minutes.',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Color(0xFFB45309),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ESignatureUploadDialog(),
              );
            },
            icon: const Icon(Icons.draw_rounded, size: 16),
            label: const Text('Upload Signature'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSigningFlowStepper(String? status) {
    int activeStep = 0;
    if (status == 'submitted') activeStep = 1;
    if (status == 'adviser_signed') activeStep = 2;
    if (status == 'completed') activeStep = 3;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: Row(
        children: [
          _buildStep(0, 'Draft', 'Documenter Editing', activeStep >= 0),
          _buildArrow(activeStep >= 1),
          _buildStep(1, 'Submitted', 'Documenter Signed', activeStep >= 1),
          _buildArrow(activeStep >= 2),
          _buildStep(2, 'Adviser Signed', 'Adviser Approved', activeStep >= 2),
          _buildArrow(activeStep >= 3),
          _buildStep(3, 'Completed', 'Chairman Signed & PDF', activeStep >= 3),
        ],
      ),
    );
  }

  Widget _buildStep(int stepNum, String title, String subtitle, bool isCompleted) {
    final color = isCompleted ? DefensysTokens.maroon : Colors.grey.shade400;
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isCompleted ? DefensysTokens.maroon : Colors.white,
              border: Border.all(color: color, width: 2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                      (stepNum + 1).toString(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: isCompleted ? DefensysTokens.textDark : Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Colors.grey.shade400,
                    fontSize: 10.5,
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

  Widget _buildArrow(bool isCompleted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Icon(
        Icons.chevron_right,
        color: isCompleted ? DefensysTokens.maroon : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildDetailsCard(Map<String, dynamic> minutes) {
    final schedule = minutes['schedule'];
    final panelists = schedule?['panelists'] as List? ?? [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Defense Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textDark,
              ),
            ),
            const Divider(height: 24),
            _detailRow('Team Name', minutes['team_name']),
            _detailRow('Capstone Project', minutes['project_title']),
            _detailRow('Defense Stage', minutes['defense_stage_label']),
            _detailRow('Date & Time', '${minutes['defense_date']} @ ${_formatTime(minutes['defense_time'])}'),
            _detailRow('Room', minutes['room']),
            _detailRow('Project Adviser', minutes['adviser_name']),
            _detailRow('Documenter', minutes['documenter_name']),
            const SizedBox(height: 12),
            const Text(
              'Panel Assignments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: DefensysTokens.textDark),
            ),
            const SizedBox(height: 8),
            ...panelists.map((panelist) {
              final pMap = panelist as Map;
              final isChair = pMap['is_chair'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isChair ? const Color(0xFFFFFBEB) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      isChair ? Icons.star_rounded : Icons.person_outline_rounded,
                      color: isChair ? const Color(0xFFD97706) : Colors.grey.shade600,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pMap['name']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isChair ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isChair)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE68A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Chair',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF78350F)),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(
            value?.toString() ?? 'N/A',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: DefensysTokens.textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(Map<String, dynamic> minutes, String? status, bool isDocumenter, bool isCancelled) {
    final comments = minutes['panelist_comments'] as List? ?? [];
    final isDraft = status == 'draft' && !isCancelled;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6E8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Panelist Comments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textDark,
              ),
            ),
            const Divider(height: 24),
            ...comments.map((comment) {
              final cMap = comment as Map;
              final id = cMap['id'] as int;
              final controller = _controllers[id];

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.comment_bank_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '${cMap['panelist_role_snapshot']}: ${cMap['panelist_name_snapshot']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: DefensysTokens.textDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isDraft && isDocumenter && controller != null)
                      TextField(
                        controller: controller,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter comments/questions from this panelist...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          cMap['comments']?.toString() != ''
                              ? cMap['comments']?.toString() ?? ''
                              : 'No comments recorded.',
                          style: const TextStyle(fontSize: 13, height: 1.4, color: DefensysTokens.textDark),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    String? status,
    bool isDocumenter,
    bool isAdviser,
    bool isAdmin,
    bool userHasSignature,
    bool isCancelled,
  ) {
    if (isCancelled) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Defense schedule is cancelled. Minutes are locked.',
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_isSubmitting || _isSavingDraft) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> buttons = [];

    if (status == 'draft' && isDocumenter) {
      buttons.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save Draft'),
          onPressed: _saveDraft,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );
      buttons.add(const SizedBox(width: 16));
      buttons.add(
        Expanded(
          child: Tooltip(
            message: userHasSignature ? '' : 'Upload your e-signature first',
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Submit and Sign'),
              onPressed: userHasSignature ? _submitAndSign : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: DefensysTokens.gold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
      );
    } else if (status == 'submitted' && isAdviser) {
      buttons.add(
        Expanded(
          child: Tooltip(
            message: userHasSignature ? '' : 'Upload your e-signature first',
            child: ElevatedButton.icon(
              icon: const Icon(Icons.draw_rounded),
              label: const Text('Sign as Project Adviser'),
              onPressed: userHasSignature ? _signAsAdviser : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: DefensysTokens.gold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
      );
    } else if (status == 'adviser_signed' && isAdmin) {
      buttons.add(
        Expanded(
          child: Tooltip(
            message: userHasSignature ? '' : 'Upload your e-signature first',
            child: ElevatedButton.icon(
              icon: const Icon(Icons.draw_rounded),
              label: const Text('Sign as Chairman'),
              onPressed: userHasSignature ? _signAsChairman : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: DefensysTokens.gold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
      );
    } else {
      // Finished state or view-only state for this user
      buttons.add(
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  status == 'completed'
                      ? 'Minutes finalized & locked.'
                      : 'Minutes submitted. Pending signatures.',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: buttons);
  }

  String _formatTime(dynamic timeVal) {
    if (timeVal == null) return '';
    final timeStr = timeVal.toString();
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final dt = DateTime(2026, 1, 1, hour, minute);
        return DateFormat('h:mm a').format(dt);
      }
    } catch (_) {}
    return timeStr;
  }
}
