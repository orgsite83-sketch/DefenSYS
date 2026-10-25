import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../theme/defensys_tokens.dart';

Map<String, dynamic>? teamImportPreviewFor(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> previews,
  int index,
) {
  final key = rows[index]['group_key'];
  final keyed = previews.any((p) => '${p['group_key'] ?? ''}'.isNotEmpty);
  return previews
      .where(
        (p) => keyed && key != null && '$key'.isNotEmpty
            ? p['group_key'] == key
            : p['row'] == index + 1,
      )
      .firstOrNull;
}

List<Map<String, dynamic>> teamImportSummaries(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> validated, {
  String? assignedSection,
}) {
  final summaries = <String, Map<String, dynamic>>{
    for (final summary in validated) '${summary['section']}': summary,
  };
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final section = '${row['section'] ?? assignedSection ?? ''}';
    grouped.putIfAbsent(section, () => []).add(row);
  }
  for (final group in grouped.entries) {
    if (summaries.containsKey(group.key)) continue;
    final systems = group.value
        .map((r) => '${r['system_name'] ?? ''}'.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    final managers = group.value
        .map((r) => '${r['project_manager'] ?? ''}'.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    if (systems.isEmpty &&
        managers.isEmpty &&
        !group.value.any((r) => r['project_kind'] == 'module')) {
      continue;
    }
    summaries[group.key] = {
      'section': group.key,
      'system_name': systems.join(' / '),
      'project_manager_name': managers.join(' / '),
      'team_count': group.value.length,
      'year_level': group.value.first['year_level'],
      'issues': <String>[
        if (systems.length > 1) 'Use one System Name for this section.',
        if (managers.length > 1) 'Use one Project Manager for this section.',
      ],
    };
  }
  return summaries.values.toList();
}

class TeamImportSharedDetails extends StatelessWidget {
  const TeamImportSharedDetails({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final issues = (summary['issues'] as List? ?? const [])
        .map((v) => '$v')
        .toList();
    final warnings = (summary['warnings'] as List? ?? const [])
        .map((v) => '$v')
        .toList();
    final ready = summary['ready'] == true && issues.isEmpty;
    final color = issues.isNotEmpty
        ? (DefensysTokens.isDark(context)
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFB91C1C))
        : warnings.isNotEmpty
        ? (DefensysTokens.isDark(context)
              ? const Color(0xFFFCD34D)
              : const Color(0xFFB45309))
        : ready
        ? (DefensysTokens.isDark(context)
              ? const Color(0xFF86EFAC)
              : const Color(0xFF15803D))
        : colors.mutedForeground;
    final name = '${summary['project_manager_name'] ?? ''}'.trim();
    final id = '${summary['project_manager_username'] ?? ''}'.trim();
    final manager = id.isEmpty || name == id ? name : '$name ($id)';
    final system = '${summary['system_name'] ?? ''}'.trim();
    final previousSystem = '${summary['previous_system_name'] ?? ''}'.trim();
    final previousManager = '${summary['previous_project_manager_name'] ?? ''}'
        .trim();
    final previousId = '${summary['previous_project_manager_username'] ?? ''}'
        .trim();
    Widget detail(
      String label,
      String value, {
      String? previous,
      String? reference,
      bool retained = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.mutedForeground),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value.isEmpty ? 'Not supplied' : value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        if (reference?.isNotEmpty == true && reference != value) ...[
          const SizedBox(height: 4),
          Text(
            'Uploaded reference: $reference',
            style: TextStyle(fontSize: 11, color: colors.mutedForeground),
          ),
        ],
        if (retained ||
            (previous?.isNotEmpty == true && previous != value)) ...[
          const SizedBox(height: 4),
          Text(
            retained ? 'Existing assignment retained' : 'Previously: $previous',
            style: TextStyle(fontSize: 11, color: colors.mutedForeground),
          ),
        ],
      ],
    );
    return Container(
      key: ValueKey('shared-system-${summary['section']}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: color.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.hub_outlined, size: 17),
              Text(
                'Shared system · ${summary['section']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${summary['team_count']} teams/modules',
                style: TextStyle(fontSize: 11, color: colors.mutedForeground),
              ),
              if ('${summary['year_level'] ?? ''}'.isNotEmpty)
                Text(
                  '${summary['year_level']}',
                  style: TextStyle(fontSize: 11, color: colors.mutedForeground),
                ),
              Text(
                issues.isNotEmpty
                    ? 'Needs correction'
                    : ready
                    ? 'Details validated'
                    : 'Not checked',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final details = [
                detail(
                  'System Name',
                  system,
                  previous: previousSystem,
                  retained: summary['retains_system_name'] == true,
                ),
                detail(
                  'Project Manager',
                  manager,
                  reference: '${summary['project_manager_reference'] ?? ''}',
                  previous: previousId.isEmpty || previousId == previousManager
                      ? previousManager
                      : '$previousManager ($previousId)',
                  retained: summary['retains_project_manager'] == true,
                ),
              ];
              return constraints.maxWidth >= 560
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details[0]),
                        const SizedBox(width: 20),
                        Expanded(child: details[1]),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        details[0],
                        const SizedBox(height: 12),
                        details[1],
                      ],
                    );
            },
          ),
          for (final issue in [...issues, ...warnings])
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  issue,
                  style: TextStyle(fontSize: 12, color: color, height: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TeamImportValidationToolbar extends StatelessWidget {
  const TeamImportValidationToolbar({
    super.key,
    required this.rows,
    required this.previewRows,
    required this.filter,
    required this.onFilter,
    required this.onFirstIssue,
    required this.action,
    this.checking = false,
    this.error,
    this.onRetry,
  });
  final List<Map<String, dynamic>> rows, previewRows;
  final String filter;
  final ValueChanged<String> onFilter;
  final VoidCallback onFirstIssue;
  final Widget action;
  final bool checking;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    var ready = 0, warnings = 0, issues = 0, pending = 0;
    for (var index = 0; index < rows.length; index++) {
      final result = teamImportPreviewFor(rows, previewRows, index);
      if (checking || result == null) {
        pending++;
      } else if (result['ready'] != true) {
        issues++;
      } else if ((result['warnings'] as List? ?? []).isNotEmpty) {
        warnings++;
      } else {
        ready++;
      }
    }
    final dark = DefensysTokens.isDark(context);
    Widget count(String label, int value, Color color) => Text(
      '$label $value',
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    );
    return Material(
      color: colors.background,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  'Batch: ${rows.length} teams',
                  style: const TextStyle(fontSize: 12),
                ),
                count(
                  'Ready',
                  ready,
                  dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                ),
                count(
                  'With warnings',
                  warnings,
                  dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                ),
                count(
                  'Needs correction',
                  issues,
                  dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                ),
                count(
                  checking ? 'Checking' : 'Not checked',
                  pending,
                  colors.mutedForeground,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final entry in const {
                      'all': 'All',
                      'issues': 'Issues',
                      'warnings': 'Warnings',
                    }.entries)
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        backgroundColor: filter == entry.key
                            ? colors.muted
                            : null,
                        onPressed: () => onFilter(entry.key),
                        child: Text(entry.value),
                      ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      enabled: !checking && (issues > 0 || warnings > 0),
                      onPressed: onFirstIssue,
                      child: const Text('Go to first issue'),
                    ),
                  ],
                ),
                action,
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(fontSize: 12, color: colors.destructive),
                ),
              ),
              if (onRetry != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: onRetry,
                    child: const Text('Retry validation'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pins the review controls within the real page viewport after their anchor
/// scrolls out of view; does not introduce a second scrolling region.
class TeamImportStickyReview extends StatefulWidget {
  const TeamImportStickyReview({
    super.key,
    required this.anchor,
    required this.toolbar,
    required this.child,
    required this.enabled,
  });
  final GlobalKey anchor;
  final Widget toolbar, child;
  final bool enabled;
  @override
  State<TeamImportStickyReview> createState() => _TeamImportStickyReviewState();
}

class _TeamImportStickyReviewState extends State<TeamImportStickyReview> {
  bool pinned = false, scheduled = false;
  void update() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      final anchor = widget.anchor.currentContext?.findRenderObject();
      final host = context.findRenderObject();
      final next =
          widget.enabled &&
          anchor is RenderBox &&
          host is RenderBox &&
          anchor.attached &&
          anchor.localToGlobal(Offset.zero).dy <
              host.localToGlobal(Offset.zero).dy;
      if (next != pinned) setState(() => pinned = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    update();
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        update();
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          if (pinned && widget.enabled)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: widget.toolbar,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
