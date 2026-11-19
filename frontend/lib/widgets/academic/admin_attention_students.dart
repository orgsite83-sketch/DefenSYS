import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../navigation/admin_attention_context.dart';
import '../../navigation/admin_route_paths.dart';
import '../../services/admin_attention_provider.dart';
import '../../services/academic_period_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// The affected records stay in the existing enrollment/formation workspace.
class AdminAttentionStudents extends ConsumerStatefulWidget {
  const AdminAttentionStudents({
    super.key,
    required this.context,
    this.onReview,
  });
  final AdminAttentionContext context;
  final Future<void> Function(List<Map<String, dynamic>>)? onReview;
  @override
  ConsumerState<AdminAttentionStudents> createState() =>
      _AdminAttentionStudentsState();
}

class _AdminAttentionStudentsState
    extends ConsumerState<AdminAttentionStudents> {
  int page = 1;
  bool busy = false;
  String? reviewError;

  @override
  void didUpdateWidget(covariant AdminAttentionStudents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.identity != widget.context.identity) {
      page = 1;
      reviewError = null;
    }
  }

  Widget text(String value, {bool muted = false, bool strong = false}) => Text(
    value,
    style: DefensysTokens.body.copyWith(
      color: muted
          ? DefensysTokens.textSecondaryOf(context)
          : DefensysTokens.textPrimaryOf(context),
      fontSize: muted ? 12 : 14,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final task = widget.context;
    final active = ref.watch(academicPeriodProvider);
    final mismatch = active.activeSemester != null
        ? active.activeSemester!['id'] != task.semesterId
        : active.schoolYears.isNotEmpty;
    final query = Uri(queryParameters: {...task.query, 'page': '$page'}).query;
    final value = task.valid && !mismatch
        ? ref.watch(adminAttentionStudentsProvider(query))
        : null;
    return DefensysShadcnScope(
      maroonActions: true,
      child: ShadCard(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        backgroundColor: DefensysTokens.surfaceOf(context),
        shadows: const [],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                text(
                  '${task.year == 'unclassified' ? 'Year needs review' : task.year} · ${task.kind == 'enrollment' ? 'Pending enrollment' : 'Students without a team'}',
                  strong: true,
                ),
                if (task.fromOverview)
                  ShadButton.link(
                    onPressed: () =>
                        GoRouter.maybeOf(context)?.go(AdminRoutes.overview),
                    child: const Text('Back to Overview'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (value == null)
              text(
                'This task context is unavailable. Return to Overview and refresh.',
                muted: true,
              )
            else
              value.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text(
                      error is AdminAttentionLoadException
                          ? error.message
                          : 'Could not load students. Please retry.',
                      muted: true,
                    ),
                    ShadButton.outline(
                      onPressed: () =>
                          ref.invalidate(adminAttentionStudentsProvider(query)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
                data: (data) {
                  final rows = (data['students'] as List? ?? [])
                      .whereType<Map>()
                      .map((row) => Map<String, dynamic>.from(row))
                      .toList();
                  final count = (data['count'] as num?)?.toInt() ?? 0;
                  final currentPage = (data['page'] as num?)?.toInt() ?? page;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text(
                        data['state'] == 'not_applicable'
                            ? 'Team formation is not open for this semester.'
                            : count == 0
                            ? 'No students remain in this task.'
                            : '$count ${count == 1 ? 'student' : 'students'}',
                        muted: true,
                      ),
                      for (final row in rows) ...[
                        const SizedBox(height: 12),
                        text(
                          row['name']?.toString() ?? row['username'].toString(),
                          strong: true,
                        ),
                        text(
                          [row['username'], row['section']]
                              .where(
                                (v) => v != null && v.toString().isNotEmpty,
                              )
                              .join(' · '),
                          muted: true,
                        ),
                      ],
                      if (reviewError != null) ...[
                        const SizedBox(height: 12),
                        text(reviewError!, muted: true),
                      ],
                      if (rows.isNotEmpty && widget.onReview != null) ...[
                        const SizedBox(height: 16),
                        if (task.year == 'unclassified')
                          text(
                            'Use the official class list below to confirm the target year before enrollment.',
                            muted: true,
                          )
                        else
                          ShadButton(
                            height: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            onPressed: busy
                                ? null
                                : () async {
                                    setState(() {
                                      busy = true;
                                      reviewError = null;
                                    });
                                    try {
                                      await widget.onReview!(rows);
                                    } catch (error) {
                                      if (mounted) {
                                        setState(
                                          () =>
                                              reviewError = error is StateError
                                              ? error.message.toString()
                                              : 'Could not prepare enrollment. Refresh and review again.',
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                            child: Flexible(
                              child: Text(
                                busy
                                    ? 'Preparing…'
                                    : 'Add this page to enrollment review',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                      if (count > 25) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ShadButton.outline(
                              onPressed: currentPage > 1
                                  ? () => setState(() => page = currentPage - 1)
                                  : null,
                              child: const Text('Previous'),
                            ),
                            text(
                              'Page $currentPage of ${(count / 25).ceil()}',
                              muted: true,
                            ),
                            ShadButton.outline(
                              onPressed: currentPage * 25 < count
                                  ? () => setState(() => page = currentPage + 1)
                                  : null,
                              child: const Text('Next'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
