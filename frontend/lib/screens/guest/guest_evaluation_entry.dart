import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../navigation/admin_route_paths.dart';
import '../../services/auth_provider.dart';

class GuestEvaluationEntry extends ConsumerStatefulWidget {
  const GuestEvaluationEntry({super.key, this.initialCode});
  final String? initialCode;
  @override
  ConsumerState<GuestEvaluationEntry> createState() =>
      _GuestEvaluationEntryState();
}

class _GuestEvaluationEntryState extends ConsumerState<GuestEvaluationEntry> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _code;
  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void didUpdateWidget(covariant GuestEvaluationEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCode != oldWidget.initialCode) {
      _code.text = widget.initialCode ?? '';
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (!_form.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).loginGuest(_code.text);
    if (ok && mounted) context.go(AppRoutes.guestDefenses);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.school_rounded,
                          color: colors.primary,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'DefenSYS',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Guest evaluation',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Enter the access code from your defense coordinator to see your assigned teams and evaluation forms.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _code,
                      enabled: !auth.isLoading,
                      autofocus: widget.initialCode == null,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => auth.isLoading ? null : _enter(),
                      decoration: const InputDecoration(
                        labelText: 'Invitation code',
                        hintText: 'DEF-…',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key_rounded),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your invitation code.'
                          : null,
                    ),
                    if (auth.error != null ||
                        auth.sessionExpiredMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        auth.error ?? auth.sessionExpiredMessage!,
                        style: TextStyle(color: colors.error),
                        semanticsLabel:
                            auth.error ?? auth.sessionExpiredMessage,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.isLoading || auth.isRestoring
                          ? null
                          : _enter,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Open my assigned defenses'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Works in your browser on a phone or laptop. No app download or institutional account needed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'If the invitation link fails, open this page directly and enter the same code. For expired access, contact your coordinator.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
