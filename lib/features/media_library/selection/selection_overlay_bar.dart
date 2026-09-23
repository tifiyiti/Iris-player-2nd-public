import 'package:flutter/material.dart';
import 'package:iris/features/media_library/selection/selection_action.dart';
import 'package:iris/features/media_library/selection/selection_controller.dart';

class SelectionOverlayBar<T> extends StatelessWidget {
  const SelectionOverlayBar({
    super.key,
    required this.controller,
    required this.allItems,
    required this.actions,
    this.maxVisibleActions = 3,
  });

  final SelectionController<T> controller;
  final List<T> allItems;
  final List<SelectionAction<T>> actions;
  final int maxVisibleActions;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        if (!controller.isSelecting) {
          return const SizedBox.shrink();
        }

        final visibleActions = actions.length <= maxVisibleActions
            ? actions
            : actions.take(maxVisibleActions).toList();

        final overflowActions = actions.length > maxVisibleActions
            ? actions.skip(maxVisibleActions).toList()
            : <SelectionAction<T>>[];

        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surface,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 520, // prevents full-width stretching
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // LEFT ACTIONS (fixed group)
                          _Group(
                            children: [
                              _Icon(
                                icon: Icon(Icons.select_all),
                                onPressed: () => controller.selectAll(allItems),
                              ),
                              _Icon(
                                icon: Icon(Icons.deselect),
                                onPressed: controller.clear,
                              ),
                              _Icon(
                                icon: Icon(Icons.flip),
                                onPressed: () => controller.invertAll(allItems),
                              ),
                            ],
                          ),

                          const SizedBox(width: 12),

                          // CENTER: COUNT (fixed size)
                          _CountBadge(count: controller.state.count),

                          // FLEXIBLE SPACE (THIS FIXES LAYOUT PROPERLY)
                          const Spacer(),

                          // RIGHT ACTIONS
                          ...visibleActions.map(
                            (a) => _Icon(
                              icon: a.icon,
                              onPressed: () => a.onPressed(context, controller),
                            ),
                          ),

                          // OVERFLOW MENU
                          if (overflowActions.isNotEmpty)
                            _MoreMenu<T>(actions: overflowActions, controller: controller),

                          const SizedBox(width: 4),

                          // CLOSE
                          _Icon(
                            icon: Icon(Icons.close),
                            onPressed: controller.exit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoreMenu<T> extends StatelessWidget {
  const _MoreMenu({
    required this.actions,
    required this.controller,
  });

  final List<SelectionAction<T>> actions;
  final SelectionController<T> controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz),
      itemBuilder: (context) {
        return List.generate(actions.length, (i) {
          final action = actions[i];

          return PopupMenuItem(
            value: i,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(child: action.icon),
                ),
                const SizedBox(width: 8),
                const Text("Action"),
              ],
            ),
          );
        });
      },
      onSelected: (i) {
        actions[i].onPressed(context, controller);
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(width: 4),
        ]
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({
    required this.icon,
    required this.onPressed,
  });

  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }
}
