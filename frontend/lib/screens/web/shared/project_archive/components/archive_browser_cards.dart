import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';

/// The folder/file presentation shared by Project Archive and team file browsing.
class ArchiveCardGrid extends StatelessWidget {
  const ArchiveCardGrid({
    super.key,
    required this.children,
    this.folders = false,
  });
  final List<Widget> children;
  final bool folders;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = folders
          ? (constraints.maxWidth >= 1080
                ? 4
                : constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth >= 470
                ? 2
                : 1)
          : (constraints.maxWidth >= 1200
                ? 4
                : constraints.maxWidth >= 840
                ? 3
                : constraints.maxWidth >= 540
                ? 2
                : 1);
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ArchiveFolderCard extends StatelessWidget {
  const ArchiveFolderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.onOpen,
    this.list = false,
    this.tapKey,
  });
  final String title, subtitle, countLabel;
  final VoidCallback onOpen;
  final bool list;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            color: ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: muted,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
    final count = Text(
      countLabel,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontSize: 11,
        color: muted,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: list ? 8 : 0),
      child: Material(
        color: DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: tapKey,
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          hoverColor: DefensysTokens.surfaceHigherOf(context),
          focusColor: DefensysTokens.surfaceHigherOf(context),
          splashColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: list ? 72 : 148),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: list
                ? Row(
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        color: Color(0xFFE8AA12),
                        size: 30,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [labels, const SizedBox(height: 4), count],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, size: 18, color: muted),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        color: Color(0xFFE8AA12),
                        size: 34,
                      ),
                      const SizedBox(height: 18),
                      labels,
                      const SizedBox(height: 6),
                      count,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class ArchiveFileCard extends StatelessWidget {
  const ArchiveFileCard({
    super.key,
    required this.title,
    required this.fileName,
    required this.metadata,
    required this.status,
    required this.onOpen,
    this.actions,
    this.missing = false,
    this.list = false,
    this.tapKey,
  });
  final String title, fileName, metadata;
  final Widget status;
  final Widget? actions;
  final VoidCallback? onOpen;
  final bool missing, list;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final format = DeliverableFormatInfo.fromFileName(fileName);
    final dark = DefensysTokens.isDark(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final icon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: missing
            ? DefensysTokens.surfaceHigherOf(context)
            : format.color.withValues(alpha: dark ? .25 : .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? DefensysTokens.borderOf(context)
              : format.color.withValues(alpha: dark ? .45 : .22),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        missing ? Icons.description_outlined : format.icon,
        color: missing ? muted : format.color,
        size: 26,
      ),
    );
    final label = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: list ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        color: ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
    final meta = Text(
      metadata,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
    return Material(
      color: DefensysTokens.panelOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: tapKey,
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        hoverColor: DefensysTokens.surfaceHigherOf(context),
        focusColor: DefensysTokens.surfaceHigherOf(context),
        splashColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: list ? 84 : 180),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: DefensysTokens.borderOf(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: list
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label,
                          const SizedBox(height: 4),
                          meta,
                          const SizedBox(height: 6),
                          status,
                        ],
                      ),
                    ),
                    if (actions != null) ...[
                      const SizedBox(width: 10),
                      actions!,
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerRight, child: status),
                    const SizedBox(height: 6),
                    Center(child: icon),
                    const SizedBox(height: 10),
                    label,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: meta),
                        if (actions != null) ...[
                          const SizedBox(width: 8),
                          actions!,
                        ],
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
