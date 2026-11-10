import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

Future<void> showAdviserLimitsDialog({
  required BuildContext context,
  required Future<Map<String, dynamic>> Function() load,
  required Future<void> Function(Map<String, dynamic>, bool) save,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DefensysShadcnScope(
    maroonActions: true,
    child: AdviserLimitsDialog(load: load, save: save),
  ),
);

class AdviserLimitsDialog extends StatefulWidget {
  const AdviserLimitsDialog({
    super.key,
    required this.load,
    required this.save,
  });
  final Future<Map<String, dynamic>> Function() load;
  final Future<void> Function(Map<String, dynamic>, bool) save;

  @override
  State<AdviserLimitsDialog> createState() => _AdviserLimitsDialogState();
}

class _AdviserLimitsDialogState extends State<AdviserLimitsDialog> {
  final _limit = TextEditingController(text: '5');
  final _authorization = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  Map<String, dynamic>? _data;
  int? _adviserId;
  bool _loading = true, _saving = false;
  String? _error, _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_limit, _authorization, _reason, _reference]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map> get _advisers =>
      (_data?['advisers'] as List? ?? []).whereType<Map>().toList();
  Map? get _adviser =>
      _advisers.where((a) => a['id'] == _adviserId).firstOrNull;
  Map get _capacity => _adviser?['capacity'] as Map? ?? {};
  Map? get _exception => (_data?['exceptions'] as List? ?? [])
      .whereType<Map>()
      .where(
        (e) =>
            e['adviser_id'] == _adviserId &&
            e['semester_id'] == _data?['active_semester']?['id'],
      )
      .firstOrNull;

  void _select(int? value) {
    _adviserId = value;
    final exception = _exception;
    _limit.text = '${exception?['approved_limit'] ?? 5}';
    _authorization.text = exception?['authorization']?.toString() ?? '';
    _reference.text = exception?['reference']?.toString() ?? '';
    _reason.clear();
    _error = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _select(
          _advisers.any((a) => a['id'] == _adviserId)
              ? _adviserId
              : _advisers.firstOrNull?['id'] as int?,
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _errorText(error);
        });
      }
    }
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception: '), '');
  int? get _parsedLimit => int.tryParse(_limit.text.trim());
  bool get _validReason => _reason.text.trim().isNotEmpty;
  bool get _canSave =>
      !_loading &&
      !_saving &&
      _adviserId != null &&
      _data?['active_semester'] != null &&
      _validReason &&
      _authorization.text.trim().isNotEmpty &&
      _parsedLimit != null &&
      _parsedLimit! >= 5 &&
      _parsedLimit! <= 32767;

  Future<void> _save(bool revoke) async {
    if (_loading || _saving || (revoke ? !_validReason : !_canSave)) return;
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.save({
        'adviser_id': _adviserId,
        'semester_id': _data!['active_semester']['id'],
        'reason': _reason.text.trim(),
        if (!revoke) ...{
          'approved_limit': _parsedLimit,
          'authorization': _authorization.text.trim(),
          'reference': _reference.text.trim(),
        },
      }, revoke);
      if (!mounted) return;
      await _load();
      if (mounted) {
        setState(
          () => _message = revoke
              ? 'Exception revoked. Existing teams keep their adviser.'
              : 'Exception saved. You can now assign teams within this limit.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLength = 1000,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        ShadInput(
          key: ValueKey(label),
          controller: controller,
          enabled: !_saving,
          maxLength: maxLength,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final term = _data?['active_semester'] as Map?;
    final count = _capacity['active_count'] ?? 0;
    final limit = _capacity['effective_limit'] ?? 4;
    final hasException = _capacity['has_exception'] == true;
    final active = _exception;
    return PopScope(
      canPop: !_saving,
      child: ShadDialog(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        title: const Text('Adviser limits'),
        actionsAxis: Axis.vertical,
        expandActionsWhenTiny: false,
        closeIcon: const SizedBox.shrink(),
        actions: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (hasException)
                ShadButton.outline(
                  enabled: !_loading && !_saving && _validReason,
                  onPressed: () => _save(true),
                  child: const Text('Revoke exception'),
                ),
              ShadButton.outline(
                enabled: !_saving,
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ShadButton(
                enabled: _canSave,
                onPressed: () => _save(false),
                child: Text(_saving ? 'Saving…' : 'Save exception'),
              ),
            ],
          ),
        ],
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loading && _data == null)
                  ShadButton.outline(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                if (!_loading && _data != null) ...[
                  Text(
                    term == null
                        ? 'No active academic period.'
                        : '${term['display_name'] ?? term['label']}',
                    style: TextStyle(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  if (term != null) ...[
                    const SizedBox(height: 16),
                    const Text('Adviser'),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (_, constraints) => ShadSelect<int>(
                        key: ValueKey('adviser-$_adviserId'),
                        initialValue: _adviserId,
                        enabled: !_saving,
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth,
                        placeholder: const Text('Choose adviser'),
                        options: _advisers
                            .map(
                              (a) => ShadOption<int>(
                                value: a['id'] as int,
                                child: Text('${a['name']}'),
                              ),
                            )
                            .toList(),
                        selectedOptionBuilder: (_, value) => Text(
                          '${_advisers.where((a) => a['id'] == value).firstOrNull?['name'] ?? ''}',
                        ),
                        onChanged: (value) => setState(() {
                          _select(value);
                          _message = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '$count active teams · ${hasException ? 'Approved limit' : 'Limit'}: $limit',
                    ),
                    if (_capacity['is_overloaded'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Existing overload. New assignments are blocked; current teams keep their adviser.',
                        ),
                      ),
                    if (active != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${hasException ? 'Recorded' : 'Ended'} exception · ${active['reason']}',
                        ),
                      ),
                    _field(
                      'Approved limit',
                      _limit,
                      numeric: true,
                      maxLength: 5,
                    ),
                    if (_parsedLimit == null ||
                        _parsedLimit! < 5 ||
                        _parsedLimit! > 32767)
                      const Text('Enter a whole number from 5 to 32767.'),
                    _field(
                      'Department authorization',
                      _authorization,
                      maxLength: 500,
                    ),
                    _field('Reason for this change', _reason),
                    _field('Reference (optional)', _reference, maxLength: 255),
                    const SizedBox(height: 12),
                    Text(
                      'An exception records department approval for this semester. Each team counts once, including solo teams.',
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: ShadTheme.of(context).colorScheme.destructive,
                      ),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!),
                  ),
                if (_error != null && _data != null)
                  ShadButton.outline(
                    enabled: !_saving,
                    onPressed: _load,
                    child: const Text('Refresh'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
