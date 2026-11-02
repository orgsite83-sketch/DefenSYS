import 'package:flutter/material.dart';

/// File forms and previews replace the popup's content instead of stacking it.
class DeliverablePopupNavigation extends InheritedWidget {
  const DeliverablePopupNavigation({
    super.key,
    required this.navigator,
    required super.child,
  });
  final GlobalKey<NavigatorState> navigator;

  static DeliverablePopupNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DeliverablePopupNavigation>();

  @override
  bool updateShouldNotify(DeliverablePopupNavigation oldWidget) =>
      navigator != oldWidget.navigator;
}

Future<T?> showDeliverablePopupStep<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  final popup = DeliverablePopupNavigation.maybeOf(context);
  if (popup == null) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }
  return popup.navigator.currentState!.push<T>(
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          Material(type: MaterialType.transparency, child: builder(context)),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}
