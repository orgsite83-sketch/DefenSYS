import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/api_config.dart';
import '../../../theme/app_theme.dart';
import 'widgets/defensys_admin_shell.dart';

// ---------------------------------------------------------------------------
// Lightweight provider – fetches only adviser rubrics, no global state bleed
// ---------------------------------------------------------------------------

class _AdviserCriteriaState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> rubrics;
  final List<Map<String, dynamic>> semesters;
  final List<Map<String, dynamic>> defenseStages;
  final List<String> scaleOptions;
  final Map<String, dynamic>? activeSemester;
  final String? error;
  final String? message;

  const _AdviserCriteriaState({
    this.isLoading = false,
    this.isSaving = false,
    this.rubrics = const [],
    this.semesters = const [],
    this.defenseStages = const [],
    this.scaleOptions = const ['10-Point Scale', '5-Point Scale', '100-Point Scale'],
    this.activeSemester,
    this.error,
    this.message,
  });

  _AdviserCriteriaState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? rubrics,
    List<Map<String, dynamic>>? semesters,
    List<Map<String, dynamic>>? defenseStages,
    List<String>? scaleOptions,
    Map<String, dynamic>? activeSemester,
    bool clearActiveSemester = false,
    String? error,
    bool clearError = false,
    String? message,
    bool clearMessage = false,
  }) {
    return _AdviserCriteriaState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      rubrics: rubrics ?? this.rubrics,
      semesters: semesters ?? this.semesters,
      defenseStages: defenseStages ?? this.defenseStages,
      scaleOptions: scaleOptions ?? this.scaleOptions,
      activeSemester: clearActiveSemester ? null : activeSemester ?? this.activeSemester,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class _AdviserCriteriaNotifier extends Notifier<_AdviserCriteriaState> {
  static String get _baseUrl => ApiConfig.rubricsUrl;

  @override
  _AdviserCriteriaState build() => const _AdviserCriteriaState();

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) throw Exception('No authentication token found.');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) return data['detail'].toString();
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) return firstValue.first.toString();
          return firstValue.toString();
        }
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }

  Future<void> fetchRubrics({String? successMessage}) async {
    state = state.copyWith(isLoading: state.rubrics.isEmpty, clearError: true, clearMessage: true);
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'evaluation_type': 'adviser',
      });
      final response = await http.get(uri, headers: await _headers());
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyPayload(payload, successMessage: successMessage);
        return;
      }
      state = state.copyWith(isLoading: false, error: _errorFromResponse(response));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    List<Map<String, dynamic>> readMapList(dynamic v) {
      if (v is! List) return [];
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      rubrics: readMapList(payload['rubrics']),
      semesters: readMapList(payload['semesters']),
      defenseStages: readMapList(payload['defense_stages']),
      scaleOptions: payload['scale_options'] is List
          ? (payload['scale_options'] as List).map((e) => e.toString()).toList()
          : state.scaleOptions,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      message: successMessage,
      clearError: true,
    );
  }

  Future<bool> createRubric(Map<String, dynamic> payload) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchRubrics(successMessage: 'Adviser rubric created.');
        return true;
      }
      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/$rubricId/'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric updated.');
        return true;
      }
      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> deleteRubric(int rubricId) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/$rubricId/'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric deleted.');
        return true;
      }
      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> publishRubric(int rubricId) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/$rubricId/publish/'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric published and locked.');
        return true;
      }
      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }
}

final _adviserCriteriaProvider =
    NotifierProvider<_AdviserCriteriaNotifier, _AdviserCriteriaState>(
      _AdviserCriteriaNotifier.new,
    );

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AdviserCriteriaScreen extends ConsumerStatefulWidget {
  const AdviserCriteriaScreen({super.key});

  @override
  ConsumerState<AdviserCriteriaScreen> createState() => _AdviserCriteriaScreenState();
}

class _AdviserCriteriaScreenState extends ConsumerState<AdviserCriteriaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_adviserCriteriaProvider.notifier).fetchRubrics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_adviserCriteriaProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.rate_review_rounded,
            title: 'Adviser Criteria',
            subtitle:
                'Create and manage rubrics with evaluation criteria that advisers use to grade their student groups.',
            actions: _primaryButton(
              icon: Icons.add_rounded,
              label: 'Create Adviser Rubric',
              onTap: state.isSaving ? null : () => _showCreateDialog(state),
            ),
          ),
          const SizedBox(height: 22),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(Icons.error_outline_rounded, state.error!, AppColors.danger),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(Icons.check_circle_outline_rounded, state.message!, AppColors.success),
          ],
          const SizedBox(height: 22),
          state.isLoading
              ? const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
              : _buildRubricList(state),
        ],
      ),
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────

  Widget _buildStats(_AdviserCriteriaState state) {
    final total = state.rubrics.length;
    final published = state.rubrics.where((r) => r['status'] == 'published').length;
    final draft = total - published;

    return Row(
      children: [
        Expanded(child: _statCard('Total Rubrics', '$total', Icons.checklist_rounded, DefensysUi.primaryMaroon)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('Published', '$published', Icons.lock_rounded, AppColors.success)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('Draft', '$draft', Icons.edit_note_rounded, AppColors.warning)),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: DefensysUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(title, style: DefensysUi.subtitle),
            ],
          ),
        ],
      ),
    );
  }

  // ── Rubric list ──────────────────────────────────────────────────────────

  Widget _buildRubricList(_AdviserCriteriaState state) {
    if (state.rubrics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: DefensysUi.cardDecoration(),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.rate_review_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('No adviser rubrics yet.', style: DefensysUi.sectionTitle),
              const SizedBox(height: 6),
              Text(
                'Create an adviser rubric above and add criteria so advisers can grade their teams.',
                style: DefensysUi.subtitle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: state.rubrics
          .map((rubric) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _RubricCard(
                  rubric: rubric,
                  isSaving: state.isSaving,
                  onPublish: state.isSaving
                      ? null
                      : () => ref.read(_adviserCriteriaProvider.notifier).publishRubric(rubric['id']),
                  onEdit: state.isSaving ? null : () => _showEditDialog(rubric, state),
                  onDelete: (rubric['status'] == 'published' || rubric['is_locked'] == true)
                      ? null
                      : () => _confirmDelete(rubric),
                ),
              ))
          .toList(),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showCreateDialog(_AdviserCriteriaState state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RubricDialog(
        title: 'Create Adviser Rubric',
        state: state,
        onSave: (payload) async {
          final ok = await ref.read(_adviserCriteriaProvider.notifier).createRubric(payload);
          return ok;
        },
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> rubric, _AdviserCriteriaState state) {
    final locked = rubric['is_locked'] == true;
    if (locked) {
      _showSnack('This rubric is locked and cannot be edited.');
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RubricDialog(
        title: 'Edit Adviser Rubric',
        rubric: rubric,
        state: state,
        onSave: (payload) async {
          final ok = await ref.read(_adviserCriteriaProvider.notifier).updateRubric(rubric['id'], payload);
          return ok;
        },
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> rubric) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Rubric?'),
        content: Text('This will permanently delete "${rubric['name']}" and all its criteria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(_adviserCriteriaProvider.notifier).deleteRubric(rubric['id']);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _primaryButton({required IconData icon, required String label, VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: DefensysUi.primaryMaroon,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontFamily: DefensysUi.fontFamily, fontWeight: FontWeight.w700, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rubric card (shows criteria inline)
// ---------------------------------------------------------------------------

class _RubricCard extends StatefulWidget {
  final Map<String, dynamic> rubric;
  final bool isSaving;
  final VoidCallback? onPublish;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _RubricCard({
    required this.rubric,
    required this.isSaving,
    this.onPublish,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_RubricCard> createState() => _RubricCardState();
}

class _RubricCardState extends State<_RubricCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rubric = widget.rubric;
    final isPublished = rubric['status'] == 'published';
    final isLocked = rubric['is_locked'] == true;
    final criteria = (rubric['criteria'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Container(
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─ Header ─────────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPublished
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPublished ? Icons.lock_rounded : Icons.edit_note_rounded,
                      color: isPublished ? AppColors.success : AppColors.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rubric['name'] ?? 'Unnamed Rubric',
                          style: DefensysUi.sectionTitle.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            _chip(rubric['scale'] ?? '10-Point Scale', Colors.blueGrey),
                            const SizedBox(width: 6),
                            _chip(rubric['context_label'] ?? 'All Stages', DefensysUi.primaryMaroon),
                            const SizedBox(width: 6),
                            _chip(
                              '${criteria.length} Criteri${criteria.length == 1 ? 'on' : 'a'}',
                              DefensysUi.steelGrey,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  DefensysStatusBadge(
                    label: isPublished ? 'Published' : 'Draft',
                    background: isPublished ? DefensysUi.successBg : DefensysUi.warningBg,
                    textColor: isPublished ? DefensysUi.successText : DefensysUi.warningText,
                    borderColor: isPublished ? DefensysUi.successBorder : DefensysUi.warningBorder,
                    showDot: isPublished,
                  ),
                  const SizedBox(width: 12),
                  // Action buttons
                  if (!isLocked && widget.onEdit != null)
                    _iconBtn(Icons.edit_outlined, 'Edit', widget.onEdit!),
                  if (!isPublished && widget.onPublish != null)
                    _iconBtn(Icons.publish_rounded, 'Publish', widget.onPublish!),
                  if (widget.onDelete != null)
                    _iconBtn(Icons.delete_outline_rounded, 'Delete', widget.onDelete!, color: AppColors.danger),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: DefensysUi.steelGrey,
                  ),
                ],
              ),
            ),
          ),
          // ─ Criteria list ───────────────────────────────────────────────────
          if (_expanded) ...[
            Container(height: 1, color: DefensysUi.neutralBorder),
            criteria.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No criteria added yet.', style: TextStyle(color: DefensysUi.steelGrey)),
                  )
                : _buildCriteriaTable(criteria),
          ],
        ],
      ),
    );
  }

  Widget _buildCriteriaTable(List<Map<String, dynamic>> criteria) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(4),
          2: IntrinsicColumnWidth(),
          3: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DefensysUi.neutralBorder)),
            ),
            children: [
              _th('Criterion'),
              _th('Description'),
              _th('Max Score'),
              _th('Order'),
            ],
          ),
          ...criteria.map(
            (c) => TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysUi.neutralBorder, width: 0.5)),
              ),
              children: [
                _td(c['name']?.toString() ?? ''),
                _td(c['description']?.toString() ?? '—'),
                _tdCenter('${c['max_score'] ?? 10}'),
                _tdCenter('${c['display_order'] ?? 0}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Text(label, style: DefensysUi.tableHeader),
      );

  Widget _td(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Text(value, style: DefensysUi.tableCell),
      );

  Widget _tdCenter(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Text(value, style: DefensysUi.tableCell, textAlign: TextAlign.center),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color ?? DefensysUi.steelGrey),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / Edit dialog
// ---------------------------------------------------------------------------

class _RubricDialog extends ConsumerStatefulWidget {
  final String title;
  final Map<String, dynamic>? rubric;
  final _AdviserCriteriaState state;
  final Future<bool> Function(Map<String, dynamic>) onSave;

  const _RubricDialog({
    required this.title,
    this.rubric,
    required this.state,
    required this.onSave,
  });

  @override
  ConsumerState<_RubricDialog> createState() => _RubricDialogState();
}

class _RubricDialogState extends ConsumerState<_RubricDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String? _semesterId;
  String? _stageId;
  String _scale = '10-Point Scale';
  bool _saving = false;

  // Criteria
  final List<Map<String, dynamic>> _criteria = [];
  final _criterionNameCtrl = TextEditingController();
  final _criterionDescCtrl = TextEditingController();
  int _criterionMaxScore = 10;

  @override
  void initState() {
    super.initState();
    final r = widget.rubric;
    if (r != null) {
      _nameCtrl.text = r['name'] ?? '';
      _semesterId = r['semester_id']?.toString();
      _stageId = r['defense_stage_id']?.toString();
      _scale = r['scale'] ?? '10-Point Scale';
      for (final c in (r['criteria'] as List? ?? [])) {
        _criteria.add(Map<String, dynamic>.from(c as Map));
      }
    }
    // Default to active semester
    final activeSem = widget.state.activeSemester;
    if (_semesterId == null && activeSem != null) {
      _semesterId = activeSem['id']?.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _criterionNameCtrl.dispose();
    _criterionDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semesters = widget.state.semesters;
    final stages = widget.state.defenseStages;
    final scales = widget.state.scaleOptions;

    return AlertDialog(
      title: Text(widget.title, style: DefensysUi.sectionTitle.copyWith(fontSize: 17)),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  'Rubric Name',
                  TextFormField(
                    controller: _nameCtrl,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    decoration: _inputDec('e.g. Capstone Adviser Evaluation'),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'Semester',
                        DropdownButtonFormField<String>(
                          value: _semesterId,
                          validator: (v) => v == null ? 'Required' : null,
                          items: semesters
                              .map((s) => DropdownMenuItem(
                                    value: s['id'].toString(),
                                    child: Text(s['display_name'] ?? s['label'] ?? '${s['id']}'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _semesterId = v),
                          decoration: _inputDec('Select semester'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'Defense Stage',
                        DropdownButtonFormField<String>(
                          value: _stageId,
                          validator: (v) => v == null ? 'Required' : null,
                          items: stages
                              .map((s) => DropdownMenuItem(
                                    value: s['id'].toString(),
                                    child: Text(s['label'] ?? '${s['id']}'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _stageId = v),
                          decoration: _inputDec('Select stage'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _field(
                  'Score Scale',
                  DropdownButtonFormField<String>(
                    value: _scale,
                    items: scales
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _scale = v;
                        _criterionMaxScore = v == '5-Point Scale'
                            ? 5
                            : v == '100-Point Scale'
                                ? 100
                                : 10;
                      });
                    },
                    decoration: _inputDec('Select scale'),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Criteria section ───────────────────────────────────────
                Row(
                  children: [
                    Text('Criteria', style: DefensysUi.sectionTitle),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addCriterion,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Criterion'),
                      style: TextButton.styleFrom(foregroundColor: DefensysUi.primaryMaroon),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCriteriaRows(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.primaryMaroon,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Rubric'),
        ),
      ],
    );
  }

  Widget _buildCriteriaRows() {
    if (_criteria.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysUi.neutralBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('No criteria yet. Click "Add Criterion" to add one.',
              style: TextStyle(color: DefensysUi.steelGrey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: DefensysUi.neutralBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: List.generate(_criteria.length, (i) {
          final c = _criteria[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: i < _criteria.length - 1
                  ? const Border(bottom: BorderSide(color: DefensysUi.neutralBorder, width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Icon(Icons.drag_indicator_rounded, color: Colors.grey.shade300, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(c['name'] ?? '', style: DefensysUi.tableCell.copyWith(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(c['description'] ?? '—',
                      style: DefensysUi.tableCell, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: DefensysUi.primaryMaroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Max: ${c['max_score']}',
                      style: const TextStyle(fontSize: 12, color: DefensysUi.primaryMaroon, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _criteria.removeAt(i)),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _addCriterion() {
    _criterionNameCtrl.clear();
    _criterionDescCtrl.clear();
    _criterionMaxScore = _scale == '5-Point Scale' ? 5 : _scale == '100-Point Scale' ? 100 : 10;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Add Criterion'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  'Criterion Name',
                  TextField(
                    controller: _criterionNameCtrl,
                    decoration: _inputDec('e.g. Research Quality'),
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  'Description (optional)',
                  TextField(
                    controller: _criterionDescCtrl,
                    decoration: _inputDec('Brief description…'),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  'Max Score',
                  DropdownButtonFormField<int>(
                    value: _criterionMaxScore,
                    items: [for (final v in [1, 2, 3, 5, 10, 20, 50, 100])
                      DropdownMenuItem(value: v, child: Text('$v'))],
                    onChanged: (v) => setInner(() => _criterionMaxScore = v ?? 10),
                    decoration: _inputDec('Max score'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysUi.primaryMaroon,
                  foregroundColor: Colors.white,
                  elevation: 0),
              onPressed: () {
                final name = _criterionNameCtrl.text.trim();
                if (name.isEmpty) return;
                setState(() {
                  _criteria.add({
                    'name': name,
                    'description': _criterionDescCtrl.text.trim(),
                    'scale': _scale,
                    'max_score': _criterionMaxScore,
                    'weight': 1,
                    'display_order': _criteria.length,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final payload = {
      'name': _nameCtrl.text.trim(),
      'scope': 'capstone',
      'semester_id': int.tryParse(_semesterId ?? '') ?? 0,
      'defense_stage_id': int.tryParse(_stageId ?? '') ?? 0,
      'evaluation_type': 'adviser',
      'scale': _scale,
      'criteria': _criteria.asMap().entries.map((e) => {
        ...e.value,
        'display_order': e.key,
      }).toList(),
    };

    final ok = await widget.onSave(payload);
    setState(() => _saving = false);
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _field(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DefensysUi.steelGrey)),
        const SizedBox(height: 5),
        child,
      ],
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
        filled: true,
        fillColor: DefensysUi.bgLight,
      );
}
