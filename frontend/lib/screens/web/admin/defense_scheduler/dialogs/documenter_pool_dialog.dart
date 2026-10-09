import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../config/api_config.dart';
import '../../../../../services/auth_provider.dart';
import '../../../../../services/authenticated_client.dart';
import '../../../../../services/authz_errors.dart';
import '../../../../../services/defense_scheduler_provider.dart';
import '../../../../../theme/defensys_tokens.dart';

class DocumenterPoolButton extends ConsumerWidget {
  const DocumenterPoolButton({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(authProvider).user?['role'] == 'admin';
    return TextButton(
      onPressed: !admin
          ? null
          : () async {
              final saved = await showDialog<bool>(
                context: context,
                builder: (_) => const DocumenterPoolDialog(),
              );
              if (saved == true && context.mounted) {
                await ref
                    .read(defenseSchedulerProvider.notifier)
                    .fetchSchedules();
                onChanged?.call();
              }
            },
      child: const Text('Manage pool'),
    );
  }
}

class DocumenterPoolDialog extends ConsumerStatefulWidget {
  const DocumenterPoolDialog({super.key});
  @override
  ConsumerState<DocumenterPoolDialog> createState() =>
      _DocumenterPoolDialogState();
}

class _DocumenterPoolDialogState extends ConsumerState<DocumenterPoolDialog> {
  List<Map<String, dynamic>> _people = [];
  final Map<int, bool> _changes = {};
  bool _loading = true, _saving = false, _eligibleOnly = false;
  String _search = '';
  String? _error;
  String get _url => '${ApiConfig.defenseMinutesUrl}/documenter-pool/';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = friendlyHttpErrorMessage(response.statusCode, response.body);
        });
        return;
      }
      final payload = jsonDecode(response.body) as Map;
      setState(() {
        _people = (payload['people'] as List)
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load documenters. Please try again.';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .patch(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'changes': [
                for (final change in _changes.entries)
                  {'id': change.key, 'is_documenter': change.value},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _saving = false;
        _error = friendlyHttpErrorMessage(response.statusCode, response.body);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to save the pool. Your changes are still here.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people
        .where(
          (p) =>
              (!_eligibleOnly ||
                  (_changes[(p['id'] as num).toInt()] ??
                      p['is_documenter'] == true)) &&
              p['name'].toString().toLowerCase().contains(_search),
        )
        .toList();
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: DefensysTokens.surfaceOf(context),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(context).height * .82,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Documenter pool',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      tooltip: 'Close pool',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Choose who can be assigned to prepare minutes. Save changes before assigning a defense.',
                ),
                const SizedBox(height: 16),
                TextField(
                  enabled: !_saving,
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search faculty or administrators',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All faculty & administrators'),
                      selected: !_eligibleOnly,
                      onSelected: (_) => setState(() => _eligibleOnly = false),
                    ),
                    ChoiceChip(
                      label: const Text('Eligible documenters'),
                      selected: _eligibleOnly,
                      onSelected: (_) => setState(() => _eligibleOnly = true),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _people.isEmpty && _error != null
                      ? Center(
                          child: OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        )
                      : people.isEmpty
                      ? const Center(child: Text('No matching people.'))
                      : ListView.separated(
                          itemCount: people.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final person = people[index],
                                id = (person['id'] as num).toInt();
                            final eligible =
                                _changes[id] ?? person['is_documenter'] == true;
                            final pending =
                                person['pending_assignments'] as List? ?? [];
                            final blocked = eligible && pending.isNotEmpty;
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(person['name'].toString()),
                              value: eligible,
                              subtitle: Text(
                                pending.isEmpty
                                    ? '${person['role']} · No outstanding minutes'
                                    : '${pending.length} outstanding assignment(s): ${pending.map((p) => p['team_name']).join(', ')}. Reassign or finalize before removing.',
                              ),
                              onChanged: _saving || blocked
                                  ? null
                                  : (value) => setState(() {
                                      if (value ==
                                          (person['is_documenter'] == true)) {
                                        _changes.remove(id);
                                      } else {
                                        _changes[id] = value!;
                                      }
                                    }),
                            );
                          },
                        ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text('${_changes.length} pending change(s)'),
                    ),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading || _saving || _changes.isEmpty
                          ? null
                          : _save,
                      child: Text(_saving ? 'Saving…' : 'Save changes'),
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
