import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/pit_repository_assistant_provider.dart';
import '../../../theme/app_theme.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitRepositoryAssistantCard extends ConsumerStatefulWidget {
  const PitRepositoryAssistantCard({super.key});

  @override
  ConsumerState<PitRepositoryAssistantCard> createState() =>
      _PitRepositoryAssistantCardState();
}

class _PitRepositoryAssistantCardState
    extends ConsumerState<PitRepositoryAssistantCard> {
  int? _selectedFacultyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pitRepositoryAssistantProvider.notifier).fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pitRepositoryAssistantProvider);

    return Container(
      decoration: DefensysUi.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                color: DefensysUi.primaryMaroon,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Repository Assistant Assignment',
                      style: TextStyle(
                        color: DefensysUi.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Assign a faculty member to handle document uploads for your year level (${state.yearLevel.isNotEmpty ? state.yearLevel : '—'}).',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(
              state.message!,
              style: TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ],
          if (state.assigned != null) ...[
            const SizedBox(height: 14),
            Text(
              'Current: ${state.assigned!['name']}',
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'ASSIGN TO',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedFacultyId,
                  decoration: InputDecoration(
                    hintText: state.isLoading
                        ? 'Loading faculty...'
                        : '— Select a faculty member —',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: state.candidates
                      .map(
                        (candidate) => DropdownMenuItem<int>(
                          value: candidate['id'] as int,
                          child: Text(
                            candidate['name']?.toString() ?? 'Faculty',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: state.isSaving
                      ? null
                      : (value) => setState(() => _selectedFacultyId = value),
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                onPressed: state.isSaving || _selectedFacultyId == null
                    ? null
                    : () async {
                        final ok = await ref
                            .read(pitRepositoryAssistantProvider.notifier)
                            .assign(_selectedFacultyId!);
                        if (ok && mounted) {
                          setState(() => _selectedFacultyId = null);
                        }
                      },
                icon: state.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outline, size: 18),
                label: const Text('Save Assignment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysUi.primaryMaroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only one faculty member can hold the Repository Assistant role at a time for your year level. Assigning a new one will revoke the previous assignment.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
