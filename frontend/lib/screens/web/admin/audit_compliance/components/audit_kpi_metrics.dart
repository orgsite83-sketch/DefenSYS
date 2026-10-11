import 'package:flutter/material.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditKpiMetrics extends StatelessWidget {
  final SystemAuditState state;
  final bool isAdmin;
  final void Function(String track, String yearLevel)? onSelectScope;
  final VoidCallback onRefresh;

  const AuditKpiMetrics({
    super.key,
    required this.state,
    required this.isAdmin,
    required this.onSelectScope,
    required this.onRefresh,
  });

  int _count(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scopes =
        <
          ({
            String title,
            String track,
            String year,
            Map<String, dynamic> data,
            String owner,
          })
        >[];
    if (isAdmin) {
      scopes.add((
        title: 'Capstone',
        track: 'capstone',
        year: '',
        data: state.capstoneProgress,
        owner: 'Admin oversight',
      ));
    }
    for (final row in state.pitProgress) {
      final year = row['year_level']?.toString() ?? '';
      if (year.isEmpty) continue;
      if (!isAdmin && year != state.yearLevel) continue;
      final leads = (row['leads'] as List? ?? [])
          .whereType<Map>()
          .map((lead) => lead['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .join(', ');
      scopes.add((
        title: 'PIT · $year',
        track: 'pit',
        year: year,
        data: row,
        owner: leads.isEmpty ? 'No PIT Lead assigned' : leads,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review coverage',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isAdmin
                        ? 'Capstone and PIT by year · search, process, action, and date filters apply'
                        : 'Your assigned PIT year · search, process, action, and date filters apply',
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh audit data',
              onPressed: state.isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (scopes.isEmpty)
          Text(
            'Review coverage will appear when audit data is loaded.',
            style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1180
                  ? 4
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final scope in scopes)
                    SizedBox(
                      width: width,
                      child: _buildScopeCard(
                        context,
                        title: scope.title,
                        data: scope.data,
                        owner: scope.owner,
                        isCapstone: scope.track == 'capstone',
                        selected:
                            state.track == scope.track &&
                            state.yearLevel == scope.year,
                        onTap: onSelectScope == null
                            ? null
                            : () => onSelectScope!(scope.track, scope.year),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildScopeCard(
    BuildContext context, {
    required String title,
    required Map<String, dynamic> data,
    required String owner,
    required bool isCapstone,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final total = _count(data['total']);
    final reviewed = _count(data['reviewed']);
    final pending = _count(data['pending']);
    final leadReviews = _count(data['reviewed_by_lead']);
    final adminReviews = _count(data['reviewed_by_admin']);
    final progress = total == 0 ? 0.0 : (reviewed / total).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final secondary = DefensysTokens.textSecondaryOf(context);
    final isDark = DefensysTokens.isDark(context);
    final selectedBorder = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$title, $reviewed of $total reviewed, $pending pending',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        child: Container(
          height: 178,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            border: Border.all(
              color: selected
                  ? selectedBorder
                  : DefensysTokens.borderOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 17,
                      color: secondary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    total == 0 ? '—' : '$percent%',
                    style: TextStyle(
                      fontSize: 27,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        total == 0
                            ? 'no events'
                            : '$reviewed of $total reviewed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: DefensysTokens.borderOf(context),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF059669),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                total == 0
                    ? 'No events in this range'
                    : '$pending awaiting review',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                total == 0
                    ? owner
                    : isCapstone
                    ? '$adminReviews admin reviews'
                    : '$owner · $leadReviews lead reviews',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
