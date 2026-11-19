import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

/// Read-only cohort cards. Details never expose lead-owned edits.
class AdminPitOverview extends StatefulWidget {
  const AdminPitOverview({super.key, required this.cohorts});

  final List? cohorts;

  @override
  State<AdminPitOverview> createState() => _AdminPitOverviewState();
}

class _AdminPitOverviewState extends State<AdminPitOverview> {
  final Set<String> expanded = {};

  Widget text(String value, {bool muted = false, bool strong = false}) => Text(
    value,
    style: DefensysTokens.body.copyWith(
      fontSize: 13,
      height: 1.5,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
      color: muted
          ? DefensysTokens.textSecondaryOf(context)
          : DefensysTokens.textPrimaryOf(context),
    ),
  );

  Widget divider() =>
      Divider(height: 1, color: DefensysTokens.borderOf(context));

  String nextDefense(Map cohort) {
    final raw = cohort['next_defense']?.toString();
    if (raw == null || raw.isEmpty) return 'No upcoming defense';
    final date = DateTime.tryParse(raw);
    return date == null
        ? 'Unavailable'
        : DateFormat('MMM d, yyyy').format(date);
  }

  Widget metric(String label, Object? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 39 * MediaQuery.textScalerOf(context).scale(1),
        ),
        child: Text(
          value?.toString() ?? 'Unavailable',
          style: DefensysTokens.pageTitle.copyWith(
            fontSize: value == null ? 13 : 26,
            fontWeight: value == null ? FontWeight.w400 : FontWeight.w700,
            height: 1.5,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: value == null
                ? DefensysTokens.textSecondaryOf(context)
                : DefensysTokens.textPrimaryOf(context),
          ),
        ),
      ),
      text(label, muted: true),
    ],
  );

  Widget eventDetails(List<Map> events, Object? count) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      divider(),
      const SizedBox(height: 16),
      text('Events', strong: true),
      const SizedBox(height: 8),
      if (events.isEmpty)
        text(
          count == 0 ? 'No events configured.' : 'Event details unavailable.',
          muted: true,
        )
      else ...[
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            divider(),
            const SizedBox(height: 12),
          ],
          text(events[i]['event_name']?.toString() ?? 'Unnamed event'),
          const SizedBox(height: 2),
          text(
            events[i]['is_officially_complete'] == true
                ? 'Officially complete'
                : 'Open',
            muted: true,
          ),
        ],
        if ((int.tryParse('$count') ?? 0) > events.length) ...[
          const SizedBox(height: 12),
          text('Showing ${events.length} of $count events', muted: true),
        ],
      ],
    ],
  );

  Widget cohortCard(Map cohort) {
    final year = cohort['year']?.toString() ?? 'Year unavailable';
    final leads = (cohort['leads'] as List? ?? [])
        .map((lead) => lead.toString().trim())
        .where((lead) => lead.isNotEmpty)
        .toList();
    final events = (cohort['events'] as List? ?? []).whereType<Map>().toList();
    final count =
        cohort['event_count'] ??
        (cohort['events'] is List ? events.length : null);
    final isExpanded = expanded.contains(year);
    return ShadCard(
      key: ValueKey('pit-cohort-$year'),
      padding: const EdgeInsets.all(20),
      backgroundColor: DefensysTokens.surfaceOf(context),
      border: ShadBorder.all(color: DefensysTokens.borderOf(context), width: 1),
      radius: BorderRadius.circular(DefensysTokens.radiusLg),
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '$year PIT',
              style: DefensysTokens.sectionTitle.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
          text('PIT lead', muted: true),
          const SizedBox(height: 4),
          text(
            leads.isEmpty ? 'Unassigned' : leads.join(', '),
            muted: leads.isEmpty,
            strong: leads.isNotEmpty,
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: metric('Teams', cohort['teams'])),
              const SizedBox(width: 16),
              Expanded(child: metric('Events', count)),
            ],
          ),
          const SizedBox(height: 20),
          divider(),
          const SizedBox(height: 16),
          text('Next defense', muted: true),
          const SizedBox(height: 4),
          text(
            nextDefense(cohort),
            muted: cohort['next_defense'] == null,
            strong: cohort['next_defense'] != null,
          ),
          const SizedBox(height: 16),
          Semantics(
            expanded: isExpanded,
            label: '$year PIT',
            child: ShadButton.ghost(
              key: ValueKey('pit-details-$year'),
              width: double.infinity,
              height: 40 * MediaQuery.textScalerOf(context).scale(1),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: DefensysTokens.maroonTextOf(context),
              hoverForegroundColor: DefensysTokens.maroonTextOf(context),
              onPressed: () => setState(() {
                isExpanded ? expanded.remove(year) : expanded.add(year);
              }),
              trailing: Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              child: Flexible(
                child: Text(isExpanded ? 'Hide details' : 'View details'),
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            eventDetails(events, count),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cohorts = widget.cohorts?.whereType<Map>().toList();
    return Column(
      key: const ValueKey('overview-pit-cohorts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PIT overview',
          style: DefensysTokens.sectionTitle.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        text('Read-only oversight · Managed by PIT Leads', muted: true),
        const SizedBox(height: 16),
        if (cohorts == null || cohorts.isEmpty)
          ShadCard(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            backgroundColor: DefensysTokens.surfaceOf(context),
            border: ShadBorder.all(
              color: DefensysTokens.borderOf(context),
              width: 1,
            ),
            radius: BorderRadius.circular(DefensysTokens.radiusLg),
            shadows: const [],
            child: text(
              cohorts == null
                  ? 'PIT cohort information unavailable.'
                  : 'No PIT cohorts in this semester.',
              muted: true,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final effectiveWidth =
                  constraints.maxWidth /
                  MediaQuery.textScalerOf(context).scale(1);
              final columns = effectiveWidth >= 1000
                  ? 3
                  : effectiveWidth >= 650
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final cohort in cohorts)
                    SizedBox(width: width, child: cohortCard(cohort)),
                ],
              );
            },
          ),
      ],
    );
  }
}
