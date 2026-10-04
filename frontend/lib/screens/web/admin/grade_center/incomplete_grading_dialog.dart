import 'package:flutter/material.dart';

import '../../../../theme/defensys_tokens.dart';

/// Read-only grading blockers, with a fixed header and footer around the list.
class IncompleteGradingTeamsDialog extends StatefulWidget {
  const IncompleteGradingTeamsDialog({super.key, required this.teams});

  final List<Map<String, dynamic>> teams;

  @override
  State<IncompleteGradingTeamsDialog> createState() =>
      _IncompleteGradingTeamsDialogState();
}

class _IncompleteGradingTeamsDialogState
    extends State<IncompleteGradingTeamsDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';

  static const _components = {
    'panel': 'Panel',
    'adviser': 'Adviser',
    'peer': 'Peer',
  };

  String _teamName(Map<String, dynamic> team) =>
      team['team_name']?.toString() ?? 'Team';

  Set<String> _missing(Map<String, dynamic> team) {
    final components = team['missing_components'];
    if (components is List) {
      return components.map((value) => value.toString()).toSet();
    }
    final missing = {
      for (final component in _components.keys)
        if (team['${component}_complete'] == false) component,
    };
    return missing.isEmpty ? {'grading'} : missing;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    final availableHeight =
        size.height - MediaQuery.viewInsetsOf(context).vertical;
    final short = availableHeight < 540;
    final padding = short ? 16.0 : (compact ? 20.0 : 24.0);
    final visibleTeams = widget.teams
        .where((team) => _teamName(team).toLowerCase().contains(_query))
        .toList();
    final warningColor = DefensysTokens.goldOf(context);
    final borderColor = DefensysTokens.borderOf(context);
    final textColor = DefensysTokens.textPrimaryOf(context);
    final mutedColor = DefensysTokens.textSecondaryOf(context);

    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.all(compact ? 16 : 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (availableHeight - (compact ? 32 : 48))
                .clamp(0.0, 720.0)
                .toDouble(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  short ? 12 : padding,
                  padding,
                  short ? 8 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: warningColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.fact_check_outlined,
                            color: warningColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Grading not ready',
                            style: DefensysTokens.dialogTitle.copyWith(
                              color: textColor,
                              fontSize: compact ? 18 : 20,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                    if (!short) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Complete the missing evaluations below before marking '
                        'the stage or event officially complete.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: mutedColor,
                        ),
                      ),
                    ],
                    SizedBox(height: short ? 8 : 16),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: short ? 8 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(context),
                        borderRadius: BorderRadius.circular(
                          DefensysTokens.radiusMd,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.teams.length} '
                            '${widget.teams.length == 1 ? 'team needs' : 'teams need'} attention',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 20,
                            runSpacing: 6,
                            children: [
                              for (final entry in _components.entries)
                                if (widget.teams.any(
                                  (team) => _missing(team).contains(entry.key),
                                ))
                                  Text(
                                    '${entry.value}: ${widget.teams.where((team) => _missing(team).contains(entry.key)).length} missing',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: mutedColor,
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: short ? 8 : 16),
                    TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Search teams',
                        hintStyle: TextStyle(fontSize: 13, color: mutedColor),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: mutedColor,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                          borderSide: BorderSide(
                            color: DefensysTokens.maroonOf(context),
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _query = value.trim().toLowerCase());
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (!compact)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
                    ),
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('Team')),
                        Expanded(flex: 2, child: Text('Panel')),
                        Expanded(flex: 2, child: Text('Adviser')),
                        Expanded(flex: 3, child: Text('Peer evaluation')),
                      ],
                    ),
                  ),
                ),
              Flexible(
                child: SizedBox(
                  height: (visibleTeams.length * (compact ? 134.0 : 68.0))
                      .clamp(100.0, 360.0)
                      .toDouble(),
                  child: visibleTeams.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _query.isEmpty
                                  ? 'No incomplete teams to display.'
                                  : 'No teams match your search.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: mutedColor),
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            key: const ValueKey(
                              'incomplete-grading-teams-list',
                            ),
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            itemCount: visibleTeams.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: borderColor),
                            itemBuilder: (_, index) =>
                                _teamRow(visibleTeams[index], compact),
                          ),
                        ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: short ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Showing ${visibleTeams.length} of ${widget.teams.length} '
                        '${widget.teams.length == 1 ? 'team' : 'teams'}',
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamRow(Map<String, dynamic> team, bool compact) {
    final missing = _missing(team);
    final extra = missing.difference(_components.keys.toSet());
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _teamName(team),
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        if (extra.isNotEmpty)
          Text(
            extra.map((value) => value.replaceAll('_', ' ')).join(', '),
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.goldOf(context),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 10,
                  children: [
                    for (final component in _components.keys)
                      _componentStatus(team, component, compact: true),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: name,
                  ),
                ),
                for (final component in _components.keys)
                  Expanded(
                    flex: component == 'peer' ? 3 : 2,
                    child: _componentStatus(team, component),
                  ),
              ],
            ),
    );
  }

  Widget _componentStatus(
    Map<String, dynamic> team,
    String component, {
    bool compact = false,
  }) {
    final missing = _missing(team);
    final isMissing = missing.contains(component);
    final unknown =
        missing.contains('grading') && team['${component}_complete'] != true;
    final color = isMissing
        ? DefensysTokens.goldOf(context)
        : DefensysTokens.textSecondaryOf(context);
    final label = isMissing
        ? (component == 'peer'
              ? '${team['evaluators_done'] ?? 0}/${team['evaluators_total'] ?? 0} evaluators'
              : 'Missing')
        : (unknown ? 'Check grading' : 'Ready');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          Text(
            _components[component]!,
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMissing
                  ? Icons.schedule_rounded
                  : (unknown
                        ? Icons.help_outline_rounded
                        : Icons.check_rounded),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (component == 'peer' && isMissing) ...[
          const SizedBox(height: 3),
          Text(
            '${team['submitted'] ?? 0}/${team['required'] ?? 0} submissions',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}
