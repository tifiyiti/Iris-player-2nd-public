import 'package:flutter/widgets.dart';
import 'package:iris/features/media_library/selection/selection_controller.dart';

class SelectionAction<T> {
  final Widget icon;
  final Future<void> Function(
    BuildContext context,
    // SelectionStore<T> store,
    SelectionController<T> controller,
  ) onPressed;

  const SelectionAction({
    required this.icon,
    required this.onPressed,
  });
}
