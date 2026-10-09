import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../services/documenter_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/universal_file_viewer.dart';
import '../e_signature_upload_dialog.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/minutes/minutes_review_dialog.dart';

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

class _MinutesFormScreenState extends ConsumerState<MinutesFormScreen>
    with WidgetsBindingObserver {
  final Map<int, TextEditingController> _controllers = {};
  bool _isSavingDraft = false;
  bool _isSubmitting = false;
  bool _isReviewing = false;
  int _editVersion = 0, _savedVersion = 0;
  bool _hydrating = false, _saveFailed = false;
  Future<bool>? _autoSavePending;
  DateTime? _lastSavedAt;

  void _queueAutoSave() {
    if (_hydrating) return;
    _editVersion++;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), _autoSave);
    if (mounted) setState(() {});
  }

  Future<void> _autoSave() async {
    if (_autoSavePending != null || _isSavingDraft || _isSubmitting) return;
    final minutes = ref.read(documenterProvider).activeMinutes;
    final schedule = minutes?['schedule'] as Map?;
    if (minutes?['status'] != 'draft' ||
        schedule?['documenter'] != ref.read(authProvider).user?['id']) {
      return;
    }
    final scheduleId = widget.scheduleId;
    final version = _editVersion;
    final payload = _controllers.entries
        .map((e) => {'id': e.key, 'comments': e.value.text})
        .toList();
    final pending = ref
        .read(documenterProvider.notifier)
        .autoSaveComments(scheduleId, payload);
    _autoSavePending = pending;
    if (mounted) setState(() {});
    final saved = await pending;
    if (!mounted || scheduleId != widget.scheduleId) return;
    _autoSavePending = null;
    setState(() {
      _saveFailed = !saved;
      if (saved) {
        _savedVersion = version;
        _lastSavedAt = DateTime.now();
      }
    });
    if (saved && _editVersion > _savedVersion) {
      _autoSaveTimer = Timer(const Duration(seconds: 1), _autoSave);
    }
  }

  Future<void> _leaveForm() async {
    if (_editVersion > _savedVersion && !await _saveDraft(silent: true)) {
      if (mounted) {
        showErrorToast(
          context,
          'Save failed. Your unsaved notes are still here.',
        );
      }
      return;
    }
    if (mounted) widget.onBack();
  }

  Timer? _autoSaveTimer;
  Timer? _loadingTimeoutTimer;
  bool _showLoadingTimeout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      if (mounted) {
        _fetchDetail();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MinutesFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduleId != widget.scheduleId) {
      _cancelTimers();
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _editVersion = _savedVersion = 0;
      _lastSavedAt = null;
      _saveFailed = false;
      _autoSavePending = null;
      _isSavingDraft = _isSubmitting = _isReviewing = false;
      Future.microtask(() {
        if (mounted) {
          _fetchDetail();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _editVersion > _savedVersion) {
      unawaited(_autoSave());
    }
  }

  void _cancelTimers() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  Future<void> _fetchDetail() async {
    final scheduleId = widget.scheduleId;
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _showLoadingTimeout = true);
      }
    });

    try {
      await ref
          .read(documenterProvider.notifier)
          .fetchMinutesDetail(scheduleId);
    } catch (_) {
      // Error is caught and stored in provider state
    } finally {
      if (mounted && widget.scheduleId == scheduleId) {
        _loadingTimeoutTimer?.cancel();
        setState(() {
          _showLoadingTimeout = false;
        });
        _initializeControllers();
      }
    }
  }

  void _initializeControllers() {
    final minutes = ref.read(documenterProvider).activeMinutes;
    if (minutes == null) return;

    final comments = minutes['panelist_comments'] as List?;
    if (comments == null) return;

    _hydrating = true;
    for (final comment in comments) {
      final id = comment['id'] as int;
      final text = comment['comments']?.toString() ?? '';
      if (!_controllers.containsKey(id)) {
        _controllers[id] = TextEditingController(text: text)
          ..addListener(_queueAutoSave);
      } else {
        _controllers[id]!.text = text;
      }
    }
    _hydrating = false;
  }

  Future<bool> _saveDraft({bool silent = false}) async {
    if (_isSavingDraft) return false;
    final scheduleId = widget.scheduleId;
    _autoSaveTimer?.cancel();
    if (_autoSavePending != null) await _autoSavePending;
    if (!mounted || widget.scheduleId != scheduleId) return false;
    final version = _editVersion;

    setState(() {
      _isSavingDraft = true;
    });

    final commentsPayload = _controllers.entries.map((e) {
      return {'id': e.key, 'comments': e.value.text};
    }).toList();

    final ok = await ref
        .read(documenterProvider.notifier)
        .saveComments(scheduleId, commentsPayload);
    if (!mounted || widget.scheduleId != scheduleId) return false;

    if (mounted) {
      setState(() {
        _isSavingDraft = false;
        _saveFailed = !ok;
        if (ok) {
          _savedVersion = version;
          _lastSavedAt = DateTime.now();
        }
      });
      if (!silent) {
        if (ok) {
          showSuccessToast(context, 'Draft comments saved successfully.');
        } else {
          showErrorToast(context, 'Failed to save draft.');
        }
      }
    }
    return ok;
  }

  Future<void> _reviewAndSign() async {
    if (_isReviewing) return;
    final scheduleId = widget.scheduleId;
    setState(() => _isReviewing = true);
    try {
      if (!await _saveDraft(silent: true) ||
          !mounted ||
          scheduleId != widget.scheduleId) {
        if (mounted) {
          showErrorToast(
            context,
            'Save your notes successfully before reviewing.',
          );
        }
        return;
      }
      final bytes = await ref
          .read(documenterProvider.notifier)
          .previewPdf(scheduleId);
      if (!mounted || scheduleId != widget.scheduleId) return;
      if (bytes == null) {
        showErrorToast(
          context,
          'Unable to load the preview. Your saved notes are still available.',
        );
        return;
      }
      final comments =
          ref.read(documenterProvider).activeMinutes?['panelist_comments']
              as List? ??
          [];
      final user = ref.read(authProvider).user;
      final sign = await showDialog<bool>(
        context: context,
        builder: (_) => MinutesReviewDialog(
          pdfBytes: bytes,
          panelists: {
            for (final comment in comments)
              '${comment['panelist_role_snapshot']}: ${comment['panelist_name_snapshot']}':
                  _controllers[comment['id']]?.text.trim().isNotEmpty == true,
          },
          hasSignature: user?['e_signature']?.toString().isNotEmpty == true,
        ),
      );
      if (sign == true && mounted && scheduleId == widget.scheduleId) {
        await _submitAndSign();
      }
    } finally {
      if (mounted && scheduleId == widget.scheduleId) {
        setState(() => _isReviewing = false);
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
            content: const Text(
              'All panelist comments must be filled before submitting and signing the minutes.',
            ),
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
    final saved = await _saveDraft(silent: true);
    if (!saved || !mounted) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showErrorToast(
          context,
          'Save failed. Minutes have not been signed. Please try again.',
        );
      }
      return;
    }

    // 2. Submit minutes (signs as documenter)
    final ok = await ref
        .read(documenterProvider.notifier)
        .submitMinutes(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        showSuccessToast(context, 'Minutes submitted and signed successfully.');
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

    final ok = await ref
        .read(documenterProvider.notifier)
        .adviserSign(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        showSuccessToast(context, 'Signed as Project Adviser successfully.');
        _fetchDetail();
      }
    }
  }

  Future<void> _signAsChairman() async {
    setState(() {
      _isSubmitting = true;
    });

    final ok = await ref
        .read(documenterProvider.notifier)
        .chairmanSign(widget.scheduleId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (ok) {
        showSuccessToast(
          context,
          'Signed as Chairman successfully. PDF generated.',
        );
        _fetchDetail();
      }
    }
  }

  Future<void> _previewPdf() async {
    final minutes = ref.read(documenterProvider).activeMinutes;
    final schedule = minutes?['schedule'] as Map?;
    if (minutes?['status'] == 'draft' &&
        schedule?['documenter'] == ref.read(authProvider).user?['id']) {
      if (!await _saveDraft(silent: true) || !mounted) {
        if (mounted) {
          showErrorToast(
            context,
            'Save your changes successfully before previewing.',
          );
        }
        return;
      }
    }
    final bytes = await ref
        .read(documenterProvider.notifier)
        .previewPdf(widget.scheduleId);
    if (!mounted) return;
    if (bytes == null) {
      showErrorToast(context, 'Could not load the PDF preview.');
      return;
    }
    await viewPdfInDialog(
      context: context,
      pdfBytes: bytes,
      fileName: 'minutes_preview.pdf',
    );
  }

  Future<void> _viewPdf({int? revisionId}) async {
    final bytes = await ref
        .read(documenterProvider.notifier)
        .downloadPdf(widget.scheduleId, revisionId: revisionId);
    if (bytes != null && mounted) {
      final minutes = ref.read(documenterProvider).activeMinutes;
      final team = minutes?['team_name']?.toString() ?? 'team';
      final stage = minutes?['defense_stage_label']?.toString() ?? 'defense';
      await viewPdfInDialog(
        context: context,
        pdfBytes: bytes,
        fileName:
            'minutes_${team.replaceAll(' ', '_')}_${stage.replaceAll(' ', '_')}.pdf',
      );
    } else {
      if (mounted) {
        showErrorToast(context, 'Failed to load PDF.');
      }
    }
  }

  Widget _buildSkeletonBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSigningFlowStepper(null),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata Left Skeleton
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6E8EF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 140,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    for (int i = 0; i < 5; i++) ...[
                      Container(
                        width: double.infinity,
                        height: 14,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Comments Right Skeleton
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6E8EF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 200,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        if (_showLoadingTimeout)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry'),
                            onPressed: _fetchDetail,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DefensysTokens.maroon,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    for (int i = 0; i < 3; i++) ...[
                      Container(
                        width: double.infinity,
                        height: 80,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE6E8EF)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documenterProvider);
    final user = ref.watch(authProvider).user;
    final userHasSignature =
        user?['e_signature'] != null && user?['e_signature'] != '';

    final minutes = state.activeMinutes;

    Widget body;

    if (state.isLoading && minutes == null) {
      body = _buildSkeletonBody();
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
            ElevatedButton(onPressed: _fetchDetail, child: const Text('Retry')),
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

      final isAdviser =
          schedule?['team_adviser_id'] == user?['id'] ||
          (user?['is_adviser'] == true &&
              minutes['adviser_name'] == user?['name']);

      final isAdmin = user?['role']?.toString() == 'admin';
      final isCancelled = schedule?['status']?.toString() == 'cancelled';

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // E-Signature Alert Banner
          if (!userHasSignature &&
              _userNeedsToSign(status, isDocumenter, isAdviser, isAdmin))
            _buildNoSignatureBanner(),

          // Horizontal Progress Step Header
          _buildSigningFlowStepper(status),
          const SizedBox(height: 24),
          if ((minutes['revisions'] as List? ?? []).isNotEmpty) ...[
            DefensysShadcnScope(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Retained minutes versions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...(minutes['revisions'] as List).whereType<Map>().map(
                    (revision) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${revision['created_at']} · ${revision['reason']}',
                            ),
                          ),
                          if (revision['pdf_url'] != null)
                            ShadButton.outline(
                              onPressed: () => _viewPdf(
                                revisionId: (revision['id'] as num).toInt(),
                              ),
                              child: const Text('View signed version'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          LayoutBuilder(
            builder: (context, constraints) {
              final details = _buildDetailsCard(
                minutes,
                collapsed: constraints.maxWidth < 800,
              );
              final editor = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCommentsSection(
                    minutes,
                    status,
                    isDocumenter,
                    isCancelled,
                  ),
                  const SizedBox(height: 24),
                  _buildActionButtons(
                    status,
                    isDocumenter,
                    isAdviser,
                    isAdmin,
                    userHasSignature,
                    isCancelled,
                  ),
                ],
              );
              return constraints.maxWidth < 800
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [details, const SizedBox(height: 20), editor],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: details),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: editor),
                      ],
                    );
            },
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSavingDraft && !_isSubmitting && !_isReviewing) {
          _leaveForm();
        }
      },
      child: Scaffold(
        backgroundColor: DefensysTokens.backgroundOf(context),
        appBar: AppBar(
          backgroundColor: DefensysTokens.surfaceOf(context),
          elevation: 0,
          title: const Text(
            'Minutes of defense',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: DefensysTokens.maroon,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: DefensysTokens.maroon),
            onPressed: _isSavingDraft || _isSubmitting || _isReviewing
                ? null
                : _leaveForm,
          ),
          actions: [
            if (minutes != null)
              IconButton(
                tooltip: minutes['status'] == 'completed'
                    ? 'View signed PDF'
                    : 'Preview PDF',
                onPressed: _isSavingDraft || _isSubmitting || _isReviewing
                    ? null
                    : minutes['status'] == 'completed'
                    ? _viewPdf
                    : _previewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
          ),
          child: body,
        ),
      ),
    );
  }

  bool _userNeedsToSign(
    String? status,
    bool isDocumenter,
    bool isAdviser,
    bool isAdmin,
  ) {
    if (status == 'draft' && isDocumenter) return true;
    if (status == 'submitted' && isAdviser) return true;
    if (status == 'adviser_signed' && isAdmin) return true;
    return false;
  }

  Widget _buildNoSignatureBanner() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'E-signature required',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload your signature before signing these minutes. You can continue recording comments.',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const ESignatureUploadDialog(),
          ),
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Upload signature'),
        ),
      ],
    ),
  );

  Widget _buildSigningFlowStepper(String? status) {
    final activeStep = switch (status) {
      'submitted' => 1,
      'adviser_signed' => 2,
      'completed' => 3,
      _ => 0,
    };
    final labels = [
      'Editing',
      'Documenter signed',
      'Adviser signed',
      'Chairman signed',
    ];
    final message = switch (status) {
      'submitted' => 'Awaiting the project adviser’s signature.',
      'adviser_signed' => 'Awaiting the administrator’s signature as chairman.',
      'completed' => 'Finalized · All three signatures recorded.',
      _ => 'Record comments, review the PDF, then sign and submit.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (var index = 0; index < labels.length; index++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      index <= activeStep
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: index <= activeStep
                          ? DefensysTokens.maroonOf(context)
                          : DefensysTokens.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: index <= activeStep
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(
    Map<String, dynamic> minutes, {
    bool collapsed = false,
  }) {
    final schedule = minutes['schedule'] as Map?;
    final panelists = schedule?['panelists'] as List? ?? [];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailRow('Team', minutes['team_name']),
        _detailRow('Project', minutes['project_title']),
        _detailRow('Stage', minutes['defense_stage_label']),
        _detailRow(
          'Date & time',
          '${minutes['defense_date']} · ${_formatTime(minutes['defense_time'])}',
        ),
        _detailRow('Room', minutes['room']),
        _detailRow('Project adviser', minutes['adviser_name']),
        _detailRow('Documenter', minutes['documenter_name']),
        const Divider(),
        const Text(
          'Panel roster',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final panelist in panelists)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${panelist['name']} · ${panelist['is_chair'] == true ? 'Presiding panel chair' : 'Panel member'}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
    return Card(
      elevation: 0,
      color: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      child: collapsed
          ? ExpansionTile(
              title: const Text(
                'Defense details',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(minutes['team_name']?.toString() ?? 'Defense'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [content],
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Defense details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  content,
                ],
              ),
            ),
    );
  }

  Widget _detailRow(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
        const SizedBox(height: 3),
        Text(
          value?.toString() ?? '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _buildCommentsSection(
    Map<String, dynamic> minutes,
    String? status,
    bool isDocumenter,
    bool isCancelled,
  ) {
    final comments = minutes['panelist_comments'] as List? ?? [];
    final editable = status == 'draft' && isDocumenter && !isCancelled;
    final completed = _controllers.values
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    final saveLabel = _autoSavePending != null || _isSavingDraft
        ? 'Saving…'
        : _saveFailed
        ? 'Save failed · Your notes are still here. Retry Save draft.'
        : _editVersion > _savedVersion
        ? 'Unsaved changes'
        : _lastSavedAt != null
        ? 'Saved at ${TimeOfDay.fromDateTime(_lastSavedAt!).format(context)}'
        : 'Changes save automatically';
    return Card(
      elevation: 0,
      color: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Panelist comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (editable) ...[
              const SizedBox(height: 8),
              Text(
                saveLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: _saveFailed
                      ? Theme.of(context).colorScheme.error
                      : DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$completed of ${comments.length} panelist sections recorded',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
            const Divider(height: 28),
            for (final comment in comments) ...[
              Text(
                '${comment['panelist_role_snapshot'] == 'Chair' ? 'Presiding panel chair' : comment['panelist_role_snapshot']}: ${comment['panelist_name_snapshot']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (editable && _controllers[comment['id']] != null)
                TextField(
                  key: ValueKey('minutes-comment-${comment['id']}'),
                  controller: _controllers[comment['id']],
                  enabled: !_isSubmitting && !_isSavingDraft && !_isReviewing,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  decoration: const InputDecoration(
                    hintText:
                        'Record this panelist’s comments, questions and recommendations…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(14),
                  ),
                )
              else
                Text(
                  comment['comments']?.toString().isNotEmpty == true
                      ? comment['comments'].toString()
                      : 'No comments recorded.',
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              if (editable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _isSubmitting || _isSavingDraft
                        ? null
                        : () => _controllers[comment['id']]?.text =
                              'No comments or suggestions.',
                    child: const Text('No comments or suggestions'),
                  ),
                ),
              const SizedBox(height: 20),
            ],
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
      return const Text(
        'This defense is cancelled. Minutes are locked.',
        style: TextStyle(fontWeight: FontWeight.w600),
      );
    }
    if (_isSubmitting || _isSavingDraft || _isReviewing) {
      return const Center(child: CircularProgressIndicator());
    }
    final style = FilledButton.styleFrom(
      backgroundColor: DefensysTokens.maroon,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    );
    if (status == 'draft' && isDocumenter) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save draft'),
          ),
          FilledButton.icon(
            onPressed: _reviewAndSign,
            style: style,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review and sign'),
          ),
        ],
      );
    }
    if (status == 'submitted' && isAdviser) {
      return FilledButton.icon(
        onPressed: userHasSignature ? _signAsAdviser : null,
        style: style,
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Sign as project adviser'),
      );
    }
    if (status == 'adviser_signed' && isAdmin) {
      return FilledButton.icon(
        onPressed: userHasSignature ? _signAsChairman : null,
        style: style,
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Sign as chairman'),
      );
    }
    return Row(
      children: [
        const Icon(Icons.lock_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            status == 'completed'
                ? 'Finalized · Minutes are locked.'
                : 'Submitted · Waiting for the remaining signatures.',
          ),
        ),
      ],
    );
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
