import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/curriculum_analytics_provider.dart';
import '../../../theme/app_theme.dart';
import 'widgets/defensys_admin_shell.dart';

class CurriculumAnalyticsScreen extends ConsumerStatefulWidget {
  const CurriculumAnalyticsScreen({super.key});

  @override
  ConsumerState<CurriculumAnalyticsScreen> createState() =>
      _CurriculumAnalyticsScreenState();
}

class _CurriculumAnalyticsScreenState
    extends ConsumerState<CurriculumAnalyticsScreen> {
  final _classifierController = TextEditingController(
    text:
        'This project develops a Flutter mobile application with cloud file storage, responsive UI, and REST API integration.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
    });
  }

  @override
  void dispose() {
    _classifierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumAnalyticsProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(state),
          const SizedBox(height: 26),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(
              Icons.error_outline_rounded,
              state.error!,
              AppColors.danger,
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(
              Icons.check_circle_outline_rounded,
              state.message!,
              AppColors.success,
            ),
          ],
          const SizedBox(height: 22),
          if (state.isLoading)
            const SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.maroon),
              ),
            )
          else ...[
            _buildMainAnalyticsGrid(state),
            const SizedBox(height: 22),
            _buildLowerAnalyticsGrid(state),
            const SizedBox(height: 22),
            _buildClassifier(state),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(CurriculumAnalyticsState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.maroon,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.analytics_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DSS: Curriculum Analytics',
                style: TextStyle(
                  color: AppColors.maroon,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Analyze technology adoption trends to guide evidence-based curriculum improvements.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _primaryButton(
          icon: Icons.description_rounded,
          label: 'Generate Curriculum Proposal',
          onTap: state.isSaving ? null : _generateProposal,
        ),
      ],
    );
  }

  Widget _buildStats(CurriculumAnalyticsState state) {
    final trends = _map(state.data['trend_cards']);
    final topTech = trends['top_tech']?.toString();
    final leastTech = trends['least_tech']?.toString();
    final topYearLevel = trends['top_year_level']?.toString();

    return Row(
      children: [
        Expanded(
          child: _insightStatCard(
            label: 'MOST UPLOADED COURSE',
            value: topTech == null || topTech.isEmpty ? 'No data' : topTech,
            subtitle: '${_asInt(state.data['entries_count'])} total files',
            icon: Icons.trending_up_rounded,
            accentColor: AppColors.success,
            topBorderColor: AppColors.success,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _insightStatCard(
            label: 'MOST ACTIVE YEAR LEVEL',
            value: topYearLevel == null || topYearLevel.isEmpty
                ? 'No data'
                : topYearLevel,
            subtitle: 'Highest upload volume',
            icon: Icons.layers_rounded,
            accentColor: Colors.blue,
            topBorderColor: Colors.blue,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _insightStatCard(
            label: 'LEAST UPLOADED COURSE',
            value: leastTech == null || leastTech.isEmpty
                ? 'No data'
                : leastTech,
            subtitle: 'Lowest upload volume',
            icon: Icons.trending_down_rounded,
            accentColor: AppColors.danger,
            topBorderColor: AppColors.danger,
          ),
        ),
      ],
    );
  }

  Widget _insightStatCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color topBorderColor,
  }) {
    return Container(
      height: 122,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(top: BorderSide(color: topBorderColor, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5D6678),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainAnalyticsGrid(CurriculumAnalyticsState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildDistributionPanel(state)),
        const SizedBox(width: 22),
        Expanded(child: _buildSystemSuggestionsPanel(state)),
      ],
    );
  }

  Widget _buildLowerAnalyticsGrid(CurriculumAnalyticsState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildTrendSeries(state)),
        const SizedBox(width: 22),
        Expanded(child: _buildCurriculumInsightsPanel(state)),
      ],
    );
  }

  Widget _buildDistributionPanel(CurriculumAnalyticsState state) {
    final distribution = _mapList(state.data['distribution']);
    final years = _stringList(state.data['academic_years']);
    final selectedYear = state.selectedAcademicYear;

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capstone Tech Stack Distribution',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Percentage of teams using each technology stack',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (years.isNotEmpty) _academicYearDropdown(years, selectedYear),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 18),
          if (distribution.isEmpty)
            const SizedBox(
              height: 115,
              child: Center(
                child: Text(
                  'No repository data for this period.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...distribution.map(_distributionBarRow),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 18),
          _yearOverYearSnapshot(state),
        ],
      ),
    );
  }

  Widget _academicYearDropdown(List<String> years, String selectedYear) {
    final selected = years.contains(selectedYear) ? selectedYear : years.first;

    return Container(
      width: 120,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: years
              .map((year) => DropdownMenuItem(value: year, child: Text(year)))
              .toList(),
          onChanged: (value) => ref
              .read(curriculumAnalyticsProvider.notifier)
              .fetchAnalytics(academicYear: value ?? ''),
        ),
      ),
    );
  }

  Widget _distributionBarRow(Map<String, dynamic> item) {
    final pct = _asInt(item['percentage']).clamp(0, 100);
    final color = _color(item['color']);
    final tech = item['tech']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 145,
            child: Text(
              tech.isEmpty ? 'Unclassified' : tech,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 11,
                color: color,
                backgroundColor: const Color(0xFFF1F2F4),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 42,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearOverYearSnapshot(CurriculumAnalyticsState state) {
    final yoy = _mapList(state.data['year_over_year']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Year-over-Year Snapshot',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        if (yoy.isEmpty)
          const Text(
            'No year-over-year data yet.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: yoy.map((row) {
              return Container(
                width: 255,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['academic_year']?.toString() ?? '',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      row['top_tech']?.toString() ?? 'No data',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${row['top_percentage'] ?? 0}% of uploads',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSystemSuggestionsPanel(CurriculumAnalyticsState state) {
    final suggestions = _mapList(state.data['suggestions']);
    final distribution = _mapList(state.data['distribution']);

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'System Suggestions',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'DSS',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          if (suggestions.isEmpty)
            _suggestionBox(
              title: 'No Repository Data Yet',
              body:
                  'Upload PIT or Capstone files through Repository Audit to generate curriculum insights.',
              type: 'info',
            )
          else
            _suggestionBox(
              title:
                  suggestions.first['title']?.toString() ?? 'Repository Signal',
              body: suggestions.first['body']?.toString() ?? '',
              type: suggestions.first['type']?.toString() ?? 'info',
            ),
          const SizedBox(height: 22),
          const Text(
            'ADOPTION BREAKDOWN',
            style: TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          if (distribution.isEmpty)
            const Text(
              'No adoption breakdown available.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            ...distribution.map(_adoptionBreakdownRow),
        ],
      ),
    );
  }

  Widget _adoptionBreakdownRow(Map<String, dynamic> item) {
    final pct = _asInt(item['percentage']).clamp(0, 100);
    final color = _color(item['color']);
    final tech = item['tech']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tech.isEmpty ? 'Unclassified' : tech,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 5,
                color: color,
                backgroundColor: const Color(0xFFF1F2F4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSeries(CurriculumAnalyticsState state) {
    final series = _mapList(state.data['trend_series']);
    final distribution = _mapList(state.data['distribution']);

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tech Stack Adoption — 3-Year Trend',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Capstone project technology usage across academic years',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 120,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bar Chart',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 18),
          if (series.isEmpty && distribution.isEmpty)
            const SizedBox(
              height: 250,
              child: Center(
                child: Text(
                  'No adoption trend data yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            _simpleTrendChart(series, distribution),
        ],
      ),
    );
  }

  Widget _simpleTrendChart(
    List<Map<String, dynamic>> series,
    List<Map<String, dynamic>> distribution,
  ) {
    final bars = series.isNotEmpty
        ? series.map((item) {
            final points = _mapList(item['points']);
            final last = points.isNotEmpty ? points.last : const {};
            return {
              'label': item['tech']?.toString() ?? '',
              'percentage': _asInt(last['percentage']),
              'color': item['color'],
            };
          }).toList()
        : distribution;

    return SizedBox(
      height: 350,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: List.generate(
                    6,
                    (index) => Expanded(
                      child: Container(
                        alignment: Alignment.topLeft,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: Text(
                          '${100 - (index * 20)}%',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 42, right: 22, top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: bars.map((bar) {
                      final pct = _asInt(bar['percentage']).clamp(0, 100);
                      final color = _color(bar['color']);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: pct == 0 ? 0.03 : pct / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.80),
                                  border: Border.all(color: color),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 8,
            children: bars.map((bar) {
              final color = _color(bar['color']);
              final label = bar['label']?.toString() ?? '';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 32, height: 10, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label.isEmpty ? 'Unclassified' : label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurriculumInsightsPanel(CurriculumAnalyticsState state) {
    final suggestions = _mapList(state.data['suggestions']);

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Curriculum Insights',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'AI-generated recommendations based on trend analysis',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          if (suggestions.isEmpty)
            _suggestionBox(
              title: 'No Curriculum Insights Yet',
              body:
                  'Repository uploads are required before DSS insights can be generated.',
              type: 'info',
            )
          else
            ...suggestions.map(
              (suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _suggestionBox(
                  title: suggestion['title']?.toString() ?? '',
                  body: suggestion['body']?.toString() ?? '',
                  type: suggestion['type']?.toString() ?? 'info',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _suggestionBox({
    required String title,
    required String body,
    required String type,
  }) {
    final color = switch (type) {
      'success' => AppColors.success,
      'critical' => AppColors.warning,
      'danger' => AppColors.danger,
      _ => Colors.blue,
    };

    final icon = switch (type) {
      'success' => Icons.check_circle_rounded,
      'critical' => Icons.trending_up_rounded,
      'danger' => Icons.warning_rounded,
      _ => Icons.info_outline_rounded,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Curriculum Signal' : title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassifier(CurriculumAnalyticsState state) {
    final classifier = state.classifier;

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ML Document Classifier',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Naive Bayes-style keyword classification with repository similarity search.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _classifierController,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Paste project abstract or document text',
            ),
          ),
          const SizedBox(height: 12),
          _primaryButton(
            icon: Icons.bolt_rounded,
            label: 'Run Classification',
            onTap: state.isSaving
                ? null
                : () => ref
                      .read(curriculumAnalyticsProvider.notifier)
                      .classify(_classifierController.text.trim()),
          ),
          if (classifier != null) ...[
            const SizedBox(height: 18),
            _classifierResult(classifier),
          ],
        ],
      ),
    );
  }

  Widget _classifierResult(Map<String, dynamic> classifier) {
    final similar = _mapList(classifier['similar_projects']);
    final keywords = _stringList(classifier['matched_keywords']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _chip(
                'Domain: ${classifier['domain'] ?? 'Unclassified'}',
                Colors.blue,
              ),
              _chip(
                'Confidence: ${classifier['confidence'] ?? 0}%',
                AppColors.success,
              ),
              if (keywords.isNotEmpty)
                _chip('Keywords: ${keywords.join(', ')}', AppColors.maroon),
            ],
          ),
          if (similar.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Similar Projects In Vault',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...similar.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_copy_outlined),
                title: Text(item['team_name']?.toString() ?? ''),
                subtitle: Text(
                  '${item['file_name'] ?? ''} - ${item['academic_year'] ?? ''} - ${item['tech_stack'] ?? ''}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contentCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.maroon,
          foregroundColor: AppColors.gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Future<void> _generateProposal() async {
    await ref.read(curriculumAnalyticsProvider.notifier).generateProposal();
    if (!mounted) {
      return;
    }
    final proposal = ref.read(curriculumAnalyticsProvider).proposal;
    if (proposal == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(proposal['title']?.toString() ?? 'Curriculum Proposal'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(proposal['summary']?.toString() ?? ''),
                const SizedBox(height: 16),
                _proposalSection(
                  'Recommendations',
                  proposal['recommendations'],
                ),
                const SizedBox(height: 12),
                _proposalSection('Next Steps', proposal['next_steps']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _proposalSection(String title, dynamic value) {
    final items = _stringList(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('- '),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Color _color(dynamic value) {
    final hex = value?.toString() ?? '';
    if (hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return AppColors.maroon;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
