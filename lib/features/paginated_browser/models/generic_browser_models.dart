import 'package:flutter/material.dart';

class SortOption {
  final String label;
  final dynamic value;

  const SortOption({required this.label, this.value});
}

class CustomSelectionAction<T> {
  final Widget icon;
  final String label;

  /// Offline-grey: false renders the action disabled (null onPressed /
  /// PopupMenuItem disabled) with no reaction on tap. Defaults true so
  /// existing call sites are unaffected.
  final bool enabled;

  /// Per-selection availability, evaluated by the bar on every selection
  /// change (e.g. disable play actions while any selected item sits on a
  /// disconnected storage). Null keeps the static [enabled].
  final bool Function(Set<T> selectedItems)? enabledFor;
  final Future<bool> Function(BuildContext context, Set<T> selectedItems) onPressed; // Returns true to exit selection

  const CustomSelectionAction({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.enabledFor,
    required this.onPressed,
  });
}

class GenericItemAction<T> {
  final String label;
  final Widget? icon;

  /// Offline-grey: false renders the trailing menu entry disabled.
  final bool enabled;
  final void Function(BuildContext context, dynamic item) onPressed;

  const GenericItemAction({
    required this.label,
    this.icon,
    this.enabled = true,
    required this.onPressed,
  });
}

class PageAction {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final List<PageAction>? subActions;

  const PageAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.subActions,
  });

  /// Offline-grey: both null renders the action disabled (IconButton with
  /// null onPressed greys natively; submenu entries follow
  /// `onPressed != null`). Tap has no reaction.
}
