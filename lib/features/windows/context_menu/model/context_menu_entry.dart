import 'package:flutter/material.dart';
import 'package:iris/features/windows/desktop_keyboard/model/potplayer_action.dart';

/// Declarative model for the PotPlayer-style Windows context menu.
///
/// Sealed hierarchy keeps the builder pure and testable; view maps entries
/// to MenuAnchor widgets (SubmenuButton / MenuItemButton).
sealed class ContextMenuEntry {
  const ContextMenuEntry();
}

class ContextMenuItem extends ContextMenuEntry {
  const ContextMenuItem({
    required this.label,
    required this.icon,
    required this.action,
    this.hint,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final PotPlayerAction action;
  final String? hint;
  final bool enabled;
}

class ContextMenuSubmenu extends ContextMenuEntry {
  const ContextMenuSubmenu({
    required this.label,
    required this.icon,
    required this.children,
  });

  final String label;
  final IconData icon;
  final List<ContextMenuEntry> children;
}

class ContextMenuDivider extends ContextMenuEntry {
  const ContextMenuDivider();
}
