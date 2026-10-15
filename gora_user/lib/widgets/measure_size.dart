import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out size after each layout that changes it.
///
/// For overlays that must know how much of a map a card covers — so the camera
/// centres in the part still visible — without guessing a fixed height that is
/// wrong on half the screens and every large text setting.
class MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;
  const MeasureSize({super.key, required this.onChange, required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _last;
  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final s = child?.size ?? Size.zero;
    if (s == _last) return;
    _last = s;
    // Never setState during layout: report once the frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}
