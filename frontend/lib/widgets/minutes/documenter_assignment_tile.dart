import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/documenter_assignment.dart';
import '../../theme/defensys_tokens.dart';

/// A compact session on phones and a scannable assignment row on desktop.
class DocumenterAssignmentTile extends StatelessWidget {
  const DocumenterAssignmentTile({
    super.key,
    required this.assignment,
    required this.wide,
    required this.onOpen,
    required this.onPreview,
  });
  final DocumenterAssignment assignment;
  final bool wide;
  final VoidCallback onOpen, onPreview;

  @override
  Widget build(BuildContext context) {
    final data = assignment.data;
    final secondary = DefensysTokens.textSecondaryOf(context);
    final time = _time(data['start_time']);
    final project = data['project_title']?.toString() ?? '';
    final room = data['room']?.toString() ?? '';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data['defense_stage_label']?.toString() ?? 'Capstone defense',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          assignment.team,
          style: TextStyle(
            fontSize: wide ? 16 : 17,
            height: 1.3,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        if (project.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            project,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            if (!wide && time.isNotEmpty)
              _meta(context, Icons.schedule_rounded, time),
            if (room.isNotEmpty)
              _meta(
                context,
                Icons.location_on_outlined,
                room.toLowerCase().startsWith('room') ? room : 'Room $room',
              ),
            _meta(
              context,
              assignment.locked
                  ? Icons.block_outlined
                  : Icons.event_available_outlined,
              assignment.sessionLabel,
            ),
          ],
        ),
      ],
    );
    final status = _status(context);
    final action = _actions(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShadCard(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        backgroundColor: DefensysTokens.surfaceOf(context),
        rowMainAxisSize: MainAxisSize.max,
        columnCrossAxisAlignment: CrossAxisAlignment.stretch,
        child: wide
            ? Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          time.isEmpty ? 'Time TBC' : time,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Defense session',
                          style: TextStyle(fontSize: 11, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 64,
                    color: DefensysTokens.borderOf(context),
                  ),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: details),
                  const SizedBox(width: 24),
                  Expanded(flex: 3, child: status),
                  const SizedBox(width: 16),
                  SizedBox(width: 210, child: action),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 14),
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
                  const SizedBox(height: 12),
                  status,
                  const SizedBox(height: 12),
                  action,
                ],
              ),
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: DefensysTokens.textSecondaryOf(context)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ),
    ],
  );

  Widget _status(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final finalized = assignment.minutesStatus == 'completed';
    final waiting = assignment.signed && !finalized;
    final color = assignment.locked
        ? DefensysTokens.textSecondaryOf(context)
        : finalized
        ? (dark ? const Color(0xFF6EE7B7) : DefensysTokens.successText)
        : waiting
        ? (dark ? const Color(0xFFFCD34D) : DefensysTokens.warningText)
        : assignment.hasComments
        ? DefensysTokens.maroonTextOf(context)
        : DefensysTokens.textSecondaryOf(context);
    final icon = finalized
        ? Icons.verified_outlined
        : waiting
        ? Icons.pending_outlined
        : assignment.hasComments
        ? Icons.edit_note_rounded
        : Icons.note_add_outlined;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            assignment.statusLabel,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final hasAction = !(assignment.locked && assignment.minutesStatus == null);
    final preview =
        assignment.minutesStatus != null &&
        assignment.minutesStatus != 'completed';
    final primary = !assignment.locked && !assignment.signed;
    final label = Text(
      assignment.actionLabel,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    final button = primary
        ? ShadButton(
            onPressed: onOpen,
            expands: true,
            height: 44 * MediaQuery.textScalerOf(context).scale(1),
            backgroundColor: DefensysTokens.maroonOf(context),
            hoverBackgroundColor: DefensysTokens.isDark(context)
                ? DefensysTokens.maroonLight
                : DefensysTokens.maroonDark,
            foregroundColor: Colors.white,
            hoverForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: label,
          )
        : ShadButton.outline(
            onPressed: onOpen,
            expands: true,
            height: 44 * MediaQuery.textScalerOf(context).scale(1),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: label,
          );
    return Row(
      children: [
        if (hasAction) Expanded(child: button),
        if (preview) ...[
          if (hasAction) const SizedBox(width: 6),
          Tooltip(
            message: 'Preview saved minutes PDF',
            child: ShadButton.ghost(
              width: 40,
              height: 44,
              padding: EdgeInsets.zero,
              onPressed: onPreview,
              child: const Icon(LucideIcons.fileText, size: 18),
            ),
          ),
        ],
      ],
    );
  }

  String _time(dynamic value) {
    final parts = value?.toString().split(':') ?? [];
    if (parts.length < 2) return '';
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    return hour == null || minute == null
        ? ''
        : DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
  }
}
