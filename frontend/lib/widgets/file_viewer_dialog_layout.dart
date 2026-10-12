import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared viewport limits for file previews and minutes review dialogs.
class FileViewerDialogLayout {
  const FileViewerDialogLayout._({
    required this.size,
    required this.insetPadding,
  });

  static const double maxWidth = 1100;
  static const double maxHeight = 1000;

  final Size size;
  final EdgeInsets insetPadding;

  factory FileViewerDialogLayout.of(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableWidth = math.max(
      0.0,
      media.size.width - media.padding.horizontal - media.viewInsets.horizontal,
    );
    final availableHeight = math.max(
      0.0,
      media.size.height - media.padding.vertical - media.viewInsets.vertical,
    );
    final insetPadding = EdgeInsets.all(availableWidth < 600 ? 8 : 24);

    return FileViewerDialogLayout._(
      insetPadding: insetPadding,
      size: Size(
        math.min(
          maxWidth,
          math.max(0.0, availableWidth - insetPadding.horizontal),
        ),
        math.min(
          maxHeight,
          math.min(
            availableHeight * .9,
            math.max(0.0, availableHeight - insetPadding.vertical),
          ),
        ),
      ),
    );
  }
}
