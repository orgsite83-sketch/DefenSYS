import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/team_workflow_status.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'deliverable_file_widgets.dart';
import 'requirement_summary.dart';
import 'deliverable_popup_navigation.dart';

/// The checklist shows progress; the existing file widgets live in its popup.
class DeliverableRequirementCard extends StatelessWidget {
  const DeliverableRequirementCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.enabled = true,
    this.compact = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final summary = RequirementSummary(item);
    final weekly = item['source'] == 'weekly_reports';
    final optional = item['required'] == false;
    final waived = item['is_waived'] == true;
    final template = item['template'] is Map;
    final format = compact && '${item['file_format'] ?? ''}'.isNotEmpty
        ? DeliverableFormatInfo.fromFormat('${item['file_format']}')
        : null;
    final metadata = [
      if (format != null)
        format.extensions.length == 1
            ? format.extensions.single.toUpperCase()
            : format.label,
      if (waived)
        'Waived requirement'
      else if (optional)
        'Optional ${weekly ? 'reports' : 'files'}'
      else
        '${summary.required} required ${weekly ? 'report' : 'file'}${summary.required == 1 ? '' : 's'}',
      if (template) 'Template available',
    ].join(' · ');
    final completed =
        summary.status == 'Accepted' || summary.status == 'Archived';
    final details = [
      if (waived)
        'Waived'
      else if (completed)
        summary.status
      else ...[
        if (summary.corrections > 0)
          '${summary.corrections} ${summary.corrections == 1 ? 'correction' : 'corrections'}',
        if (summary.overdue > 0) '${summary.overdue} overdue',
        if (!optional && summary.missing > 0) '${summary.missing} missing',
        if (summary.pending > 0) '${summary.pending} awaiting review',
        if ((optional || summary.missing == 0) &&
            summary.pending == 0 &&
            summary.corrections == 0)
          optional ? 'Optional' : summary.status,
      ],
      if (summary.late > 0) '${summary.late} late',
    ].join(' · ');
    final tone = waived
        ? WorkflowStatusTone.neutral
        : completed
        ? WorkflowStatusTone.success
        : summary.corrections > 0 || summary.overdue > 0
        ? WorkflowStatusTone.attention
        : WorkflowStatusTone.neutral;
    final style = DefensysTokens.caption.copyWith(
      fontFamily: DefensysTokens.fontFamilyInter,
      color: DefensysTokens.textSecondaryOf(context),
    );
    if (compact) {
      return DefensysShadcnScope(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onOpen : null,
            borderRadius: BorderRadius.circular(8),
            hoverColor: DefensysTokens.surfaceHigherOf(context),
            focusColor: DefensysTokens.surfaceHigherOf(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: DefensysTokens.maroonOf(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['label'] ?? 'Document'}',
                          style: DefensysTokens.body.copyWith(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(metadata, style: style),
                        const SizedBox(height: 6),
                        DeliverableStatusBadge(label: details, tone: tone),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: DefensysTokens.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: DefensysTokens.borderOf(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onOpen : null,
            hoverColor: DefensysTokens.surfaceHigherOf(context),
            focusColor: DefensysTokens.surfaceHigherOf(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final icon = Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: DefensysTokens.surfaceHigherOf(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: DefensysTokens.borderOf(context),
                          ),
                        ),
                        child: Icon(
                          weekly
                              ? Icons.assignment_outlined
                              : summary.required > 1
                              ? Icons.file_copy_outlined
                              : Icons.description_outlined,
                          size: 20,
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                      );
                      final description = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['label'] ?? item['name'] ?? 'Deliverable'}',
                            style: DefensysTokens.body.copyWith(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(metadata, style: style),
                        ],
                      );
                      final status = DeliverableStatusBadge(
                        label: details,
                        tone: tone,
                        maxLines: 3,
                      );
                      if (constraints.maxWidth < 360 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.15) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                icon,
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: status,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            description,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(child: description),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: status,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceOf(context),
                    border: Border(
                      top: BorderSide(color: DefensysTokens.borderOf(context)),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final progress = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DeliverableStatusBadge(
                            label:
                                summary.required == 0 ||
                                    summary.uploaded > summary.required
                                ? summary.progress
                                : '${summary.progress} Uploaded',
                            tone: WorkflowStatusTone.neutral,
                          ),
                          if (summary.acceptedFiles > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${summary.acceptedFiles} accepted',
                              style: style,
                            ),
                          ],
                        ],
                      );
                      final action = ShadButton.outline(
                        size: ShadButtonSize.sm,
                        height: 40,
                        enabled: enabled,
                        onPressed: enabled ? onOpen : null,
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        child: const Text('Manage files'),
                      );
                      if (constraints.maxWidth < 320 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.15) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            progress,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: action,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: progress,
                            ),
                          ),
                          const SizedBox(width: 10),
                          action,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets direct API actions protect the popup while a write is in progress.
class DeliverablePopupActivity extends InheritedWidget {
  const DeliverablePopupActivity({
    super.key,
    required this.busy,
    required super.child,
  });
  final ValueNotifier<bool> busy;

  static ValueNotifier<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DeliverablePopupActivity>()?.busy;

  @override
  bool updateShouldNotify(DeliverablePopupActivity oldWidget) =>
      busy != oldWidget.busy;
}

Future<void> showDeliverableRequirementDialog(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DeliverablePopupHost(builder: builder),
);

class _DeliverablePopupHost extends ConsumerStatefulWidget {
  const _DeliverablePopupHost({required this.builder});
  final WidgetBuilder builder;
  @override
  ConsumerState<_DeliverablePopupHost> createState() =>
      _DeliverablePopupHostState();
}

class _DeliverablePopupHostState extends ConsumerState<_DeliverablePopupHost> {
  final busy = ValueNotifier(false);
  final navigator = GlobalKey<NavigatorState>();
  @override
  void dispose() {
    busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(
      capstoneDeliverablesProvider.select((state) => state.isSaving),
    );
    return DefensysShadcnScope(
      child: DeliverablePopupActivity(
        busy: busy,
        child: ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (context, writing, _) => PopScope(
            canPop: !saving && !writing,
            child: DeliverablePopupNavigation(
              navigator: navigator,
              child: NavigatorPopHandler<Object?>(
                enabled: !saving && !writing,
                onPopWithResult: (result) {
                  if (!saving &&
                      !writing &&
                      navigator.currentState?.canPop() == true) {
                    navigator.currentState?.pop(result);
                  }
                },
                child: Navigator(
                  key: navigator,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        Material(
                          type: MaterialType.transparency,
                          child: Builder(builder: widget.builder),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content-sized shadcn shell with a pinned header/footer and one body scroll.
class DeliverableRequirementDialog extends ConsumerWidget {
  const DeliverableRequirementDialog({
    super.key,
    required this.item,
    required this.child,
  });
  final Map<String, dynamic> item;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = RequirementSummary(item);
    final saving = ref.watch(
      capstoneDeliverablesProvider.select((state) => state.isSaving),
    );
    final activity = DeliverablePopupActivity.maybeOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: activity ?? const AlwaysStoppedAnimation(false),
      builder: (context, writing, _) {
        final enabled = !saving && !writing;
        void close() {
          if (enabled) Navigator.of(context, rootNavigator: true).maybePop();
        }

        final available = MediaQuery.sizeOf(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: ShadDialog(
            key: const ValueKey('deliverable-requirement-dialog'),
            constraints: BoxConstraints(
              maxWidth: 960,
              maxHeight: available.height - 24,
            ),
            removeBorderRadiusWhenTiny: false,
            padding: const EdgeInsets.all(16),
            scrollable: true,
            titleTextAlign: TextAlign.left,
            descriptionTextAlign: TextAlign.left,
            descriptionStyle: DefensysTokens.body.copyWith(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: DefensysTokens.textPrimaryOf(context),
            ),
            titlePinned: true,
            actionsPinned: true,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            title: LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  '${item['label'] ?? 'Deliverable'}',
                  style: DefensysTokens.body.copyWith(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                );
                final metadata = Text(
                  '${summary.required} required ${item['source'] == 'weekly_reports' ? 'report' : 'file'}${summary.required == 1 ? '' : 's'}',
                  style: DefensysTokens.caption.copyWith(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                );
                final progress = ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .55,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      DeliverableStatusBadge(
                        label:
                            '${summary.progress}${summary.required > 0 && summary.uploaded <= summary.required ? ' Uploaded' : ''}',
                        tone: WorkflowStatusTone.neutral,
                      ),
                      if (summary.acceptedFiles > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${summary.acceptedFiles} accepted',
                          style: DefensysTokens.caption.copyWith(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
                final closeButton = ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  width: 40,
                  height: 40,
                  padding: EdgeInsets.zero,
                  enabled: enabled,
                  onPressed: enabled ? close : null,
                  child: const Tooltip(
                    message: 'Close deliverable',
                    child: Icon(Icons.close, size: 20),
                  ),
                );
                final narrow =
                    constraints.maxWidth < 440 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.15;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 8),
                          closeButton,
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: metadata),
                          const SizedBox(width: 8),
                          progress,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 6), metadata],
                      ),
                    ),
                    const SizedBox(width: 12),
                    progress,
                    const SizedBox(width: 8),
                    closeButton,
                  ],
                );
              },
            ),
            closeIcon: const SizedBox.shrink(),
            actions: [
              ShadButton.outline(
                enabled: enabled,
                onPressed: enabled ? close : null,
                child: const Text('Done'),
              ),
            ],
            child: child,
          ),
        );
      },
    );
  }
}
