import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shares the panels' natural height without asking the calendar's
/// LayoutBuilder for unsupported intrinsic dimensions or fixing its height.
class OverviewPanelRow extends MultiChildRenderObjectWidget {
  OverviewPanelRow({
    super.key,
    required Widget readiness,
    required Widget schedule,
  }) : super(children: [readiness, schedule]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _OverviewPanelRowRender();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    renderObject.markNeedsLayout();
  }
}

class _OverviewPanelParentData extends ContainerBoxParentData<RenderBox> {}

class _OverviewPanelRowRender extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _OverviewPanelParentData();
    }
  }

  @override
  void performLayout() {
    final left = firstChild!;
    final right = childAfter(left)!;
    final width = constraints.maxWidth;
    const gap = 16.0;
    final leftWidth = (width - gap) * 2 / 5;
    final rightWidth = width - gap - leftWidth;
    left.layout(
      BoxConstraints.tightFor(width: leftWidth),
      parentUsesSize: true,
    );
    right.layout(
      BoxConstraints.tightFor(width: rightWidth),
      parentUsesSize: true,
    );
    final height = math.max(left.size.height, right.size.height);
    size = constraints.constrain(Size(width, height));
    left.layout(
      BoxConstraints.tight(Size(leftWidth, height)),
      parentUsesSize: true,
    );
    right.layout(
      // Keep height unbounded so internal calendar changes (Month/Week or
      // selected-session details) propagate layout invalidation to this row.
      BoxConstraints(
        minWidth: rightWidth,
        maxWidth: rightWidth,
        minHeight: height,
      ),
      parentUsesSize: true,
    );
    (left.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    (right.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      leftWidth + gap,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
