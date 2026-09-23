import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/gesture_guide/controller/gesture_guide_presenter.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/hooks/use_gesture_mode.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_controller.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_models.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_entry.dart'
    show openGestureRegionSettings, openGestureRegionEditorDirectly;
import 'package:iris/widgets/dialogs/show_reset_gesture_layout_dialog.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';

// KEEP: Early inline line-drag editing rendered directly on the guide's first
// screen was more visually polished than the legacy full-screen editor, but it
// violated the requirement that all region edits go through the mature
// region↔lines↔blocks editor (m*n grid, reset/cancel/confirm, per-profile
// persistence). The inline implementation is retained here for reference and
// comparison only; [_kInlineEditEnabled] is permanently false so the code is
// dead and never executes.
const bool _kInlineEditEnabled = false;

const List<Color> _kRegionPalette = [
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.deepOrange,
  Colors.indigo,
];

/// Live gesture guide: renders the CURRENTLY EFFECTIVE layout
/// ([AppStore.useActiveGestureLayouts] — profile selection, orientation and
/// tag-play auto-follow all apply) as one full-screen page per intent.
/// Pages are switched by horizontal swipe; the bottom chip row (full text,
/// always readable, clickable) jumps to a page and doubles as a legend, so
/// no extra "current profile" header is needed.
///
/// Right-side actions:
///  - pencil: directly edits the CURRENT page's intent+active profile, skipping
///    the selection dialog (same mature Editor, m*n grid, reset/cancel/confirm);
///  - settings: shows the legacy selection dialog (orientation-filtered) then
///    pushes the same Editor;
///  - close: returns to player (no warning dialog).
/// Legacy (classic mode) shows the guide read-only.
class GestureGuideOverlay extends HookWidget {
  const GestureGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Reactive inputs only: the show/hide flag, the effective layouts and the
    // auto-follow tag id are select()-subscribed, so the guide is LIVE — any
    // settings/layout change (including in-guide line edits) re-renders it
    // immediately.
    final isShowGestureTips =
        usePlayerUiStore().select(context, (state) => state.isShowGestureTips);
    final layouts = useAppStore().useActiveGestureLayouts(context);
    // Recomputed every build on purpose: the resolved maps are shared final
    // instances, so identity-based memoization would cache stale sections
    // across layout swaps.
    final t = getLocalizations(context);
    final sections = buildGuideSections(layouts, t);

    // The guide mirrors the real dispatch mode: classic (legacy / desktop)
    // stays read-only, meta region modes allow inline line editing.
    final canEdit = useGestureMode(
          orientation: MediaQuery.of(context).orientation,
          isPhone: isMobilePlatform,
        ) !=
        GestureMode.classic;

    // All hooks run unconditionally: returning early BEFORE them would shrink
    // the hook list on hidden builds and destroy page/edit state, so a
    // settings/editor round-trip could never restore the same page.
    final currentIndex = useState(0);
    // Retained dead state for the inline editor (see _kInlineEditEnabled).
    final isEditing = useState(false);
    final editLines = useState<List<EditableLine>?>(null);

    // Page index survives hide/show cycles (settings/editor round-trip).
    final storedPage =
        usePlayerUiStore().select(context, (s) => s.gestureGuidePage);
    // Re-keyed on section count so a rotation/profile swap that shrinks the
    // page list also resets the controller instead of asserting out of range.
    final pageController = usePageController(
      initialPage: sections.isEmpty
          ? 0
          : storedPage.clamp(0, sections.length - 1),
      keys: [sections.length],
    );

    // Restore: when the guide is (re)revealed — e.g. after the settings/editor
    // flow hid it — jump back to the page the user left, map included.
    useEffect(() {
      if (!isShowGestureTips || sections.isEmpty) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = storedPage.clamp(0, sections.length - 1);
        if (pageController.hasClients &&
            pageController.page?.round() != target) {
          pageController.jumpToPage(target);
        }
        currentIndex.value = target;
      });
      return null;
    }, [isShowGestureTips, storedPage, sections.length]);

    final activeViewTagId =
        useTagPlayStore().select(context, (s) => s.activeViewTagId);
    final tagViewDrives =
        TagPlayGate.viewSwitchingEnabled && activeViewTagId != null;

    if (!isShowGestureTips || sections.isEmpty) return const SizedBox.shrink();

    // Defensive clamp while the controller catches up after a shrink.
    final int current =
        currentIndex.value < sections.length ? currentIndex.value : 0;

    // ── Retained inline-edit helpers (dead when _kInlineEditEnabled==false) ──
    // KEEP: More polished than the legacy full-screen grid editor, but it
    // bypasses reset/cancel/confirm and per-profile persistence. Guarded by
    // _kInlineEditEnabled so it never executes; kept for visual reference.
    void updateEditLine(int index, double newValue) {
      if (!_kInlineEditEnabled) return;
      final lines = editLines.value;
      if (lines == null || index < 0 || index >= lines.length) return;
      final copy = [...lines];
      copy[index].value = GestureEditorController().clampLineValue(
        line: copy[index],
        all: copy,
        newValue: newValue,
      );
      editLines.value = copy;
    }

    Future<void> commitEditLines() async {
      if (!_kInlineEditEnabled) return;
      final lines = editLines.value;
      if (lines == null || sections.isEmpty) return;
      final section = sections[current];
      final source = layouts[section.intent];
      if (source == null) return;
      try {
        await useAppStore().updateGestureIntentLayout(
          profileKey: useAppStore().resolveActiveGestureProfileKey(
            useAppStore().state,
            MediaQuery.of(context).orientation,
          ),
          intent: section.intent,
          layout: LayoutTopology(lines: lines)
              .rebuildLayoutFrom(source, section.intent),
        );
      } catch (e) {
        areaKeyLog.e('Failed to save guide-edited gesture layout: $e');
      }
    }

    Future<void> toggleEdit() async {
      if (!_kInlineEditEnabled) return;
      if (isEditing.value) {
        // Edits are already committed per drag end — exiting is purely visual.
        isEditing.value = false;
        editLines.value = null;
        return;
      }
      final layout = layouts[sections[current].intent];
      editLines.value =
          layout == null ? null : LayoutTopology.computeEditableLines(layout);
      isEditing.value = true;
    }

    // ── New: direct edit skips selection dialog ──
    Future<void> openDirectEdit() async {
      if (sections.isEmpty) return;
      final section = sections[current];
      final profileKey = useAppStore().resolveActiveGestureProfileKey(
        useAppStore().state,
        MediaQuery.of(context).orientation,
      );
      // Hide-then-restore: editor pushes on top, guide reappears on pop.
      usePlayerUiStore().updateIsShowGestureTips(false);
      await openGestureRegionEditorDirectly(
        context,
        profileKey: profileKey,
        intent: section.intent,
      );
      if (context.mounted) {
        usePlayerUiStore().updateIsShowGestureTips(true);
      }
    }

    return Stack(
      children: [
        // Full-screen barrier — no bottom carve-out: normalized rects map
        // 1:1 onto the whole player surface, matching the real gesture layer.
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
            child: PageView.builder(
              key: ValueKey(sections.length),
              controller: pageController,
              // Inline edit was horizontal-dragging — page swipe yielded.
              // Now always scrollable; dead inline path guarded.
              physics: _kInlineEditEnabled && isEditing.value
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              onPageChanged: (i) {
                currentIndex.value = i;
                usePlayerUiStore().updateGestureGuidePage(i);
                if (_kInlineEditEnabled && isEditing.value) {
                  final layout = layouts[sections[i].intent];
                  editLines.value = layout == null
                      ? null
                      : LayoutTopology.computeEditableLines(layout);
                }
              },
              itemCount: sections.length,
              itemBuilder: (context, i) => _guidePage(
                sections[i],
                editLines: _kInlineEditEnabled && isEditing.value && i == current
                    ? editLines.value
                    : null,
                sourceLayout: layouts[sections[i].intent],
                onLineDrag: updateEditLine,
                onLineDragEnd: commitEditLines,
              ),
            ),
          ),
        ),
        if (tagViewDrives)
          Positioned(
            top: 32,
            left: 0,
            right: 0,
            child: Center(child: _autoFollowBadge(context)),
          ),
        if (!canEdit)
          Positioned(
            top: 40,
            left: 24,
            child: _legacyCaption(context),
          ),
        _topRightActions(
          context,
          canEdit: canEdit,
          isEditing: _kInlineEditEnabled && isEditing.value,
          onToggleEdit: toggleEdit,
          onDirectEdit: openDirectEdit,
        ),
        _bottomSwitcher(context, sections, current, (i) {
          currentIndex.value = i;
          pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 250),
            curve: Curves.ease,
          );
        }),
      ],
    );
  }

  /// One full-screen page: all regions of a single intent, label always on.
  /// While editing, regions are rebuilt from the dragged lines so the map
  /// follows the finger; actions re-match by max intersection.
  Widget _guidePage(
    GuideSection section, {
    required List<EditableLine>? editLines,
    required GestureLayout? sourceLayout,
    required void Function(int index, double newValue) onLineDrag,
    required VoidCallback onLineDragEnd,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final editing = editLines != null && sourceLayout != null;
      final entries = editing
          ? [
              for (final region in LayoutTopology(lines: editLines)
                  .rebuildLayoutFrom(sourceLayout, section.intent)
                  .regions)
                GuideRegionEntry(
                  normalizedRect: region.normalizedRect,
                  action: region.action,
                ),
            ]
          : section.regions;
      return Stack(
        children: [
          // Bottom layer: partition boxes and functional icons
          for (var i = 0; i < entries.length; i++)
            _regionBoxBase(
              context,
              entry: entries[i],
              color: _kRegionPalette[i % _kRegionPalette.length],
              size: size,
            ),
          // Top layer: text labels rendered independently above partitions/icons without squeezing
          for (var i = 0; i < entries.length; i++)
            _regionBoxText(
              context,
              entry: entries[i],
              color: _kRegionPalette[i % _kRegionPalette.length],
              size: size,
            ),
          if (editing)
            for (var i = 0; i < editLines.length; i++)
              _GuideLineHandle(
                line: editLines[i],
                index: i,
                size: size,
                onDrag: (value) => onLineDrag(i, value),
                onDragEnd: onLineDragEnd,
              ),
        ],
      );
    });
  }

  /// Bottom layer: partition boundary background/border + icon only.
  Widget _regionBoxBase(
    BuildContext context, {
    required GuideRegionEntry entry,
    required Color color,
    required Size size,
  }) {
    final d = describeAction(entry.action, getLocalizations(context));
    final effectiveColor = d.active ? color : Colors.white24;
    return Positioned.fromRect(
      rect: Rect.fromLTWH(
        entry.normalizedRect.left * size.width,
        entry.normalizedRect.top * size.height,
        entry.normalizedRect.width * size.width,
        entry.normalizedRect.height * size.height,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: d.active ? effectiveColor.withValues(alpha: 0.12) : null,
          border: Border.all(color: effectiveColor.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Icon(d.icon, size: 36, color: effectiveColor),
        ),
      ),
    );
  }

  /// Top layer: text label positioned cleanly below the icon when space permits,
  /// or above the icon if vertical height is too small, never directly colliding over the icon.
  Widget _regionBoxText(
    BuildContext context, {
    required GuideRegionEntry entry,
    required Color color,
    required Size size,
  }) {
    final d = describeAction(entry.action, getLocalizations(context));
    final rectHeight = entry.normalizedRect.height * size.height;
    // If region height is tight (< 70px), place text slightly above or rely on non-overlapping alignment.
    // We position text using alignment: when height is ample, place it below icon (Alignment.bottomCenter);
    // when compact, place it above or centered with vertical offset.
    final bool isCompact = rectHeight < 75;

    return Positioned.fromRect(
      rect: Rect.fromLTWH(
        entry.normalizedRect.left * size.width,
        entry.normalizedRect.top * size.height,
        entry.normalizedRect.width * size.width,
        entry.normalizedRect.height * size.height,
      ),
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Align(
            alignment: isCompact ? Alignment.topCenter : Alignment.bottomCenter,
            child: Text(
              d.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: d.active ? Colors.white : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(
                    blurRadius: 4,
                    color: Colors.black87,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _autoFollowBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: Colors.amberAccent),
          const SizedBox(width: 6),
          Text(getLocalizations(context).guide_auto_follow_badge,
              style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _legacyCaption(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        getLocalizations(context).guide_legacy_caption,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  Widget _topRightActions(
    BuildContext context, {
    required bool canEdit,
    required bool isEditing,
    required Future<void> Function() onToggleEdit,
    required Future<void> Function() onDirectEdit,
  }) {
    final t = getLocalizations(context);
    Future<void> openSettings() async {
      // Hide-then-restore: the guide reopens at the exact page (and action
      // map) the user left once the settings/editor flow closes.
      usePlayerUiStore().updateIsShowGestureTips(false);
      await openGestureRegionSettings(context);
      if (context.mounted) {
        usePlayerUiStore().updateIsShowGestureTips(true);
      }
    }

    return Positioned(
      top: 32,
      right: 32,
      child: Column(
        children: [
          if (canEdit)
            IconButton(
              key: const Key('gesture_guide_edit'),
              // When inline edit is disabled, pencil always means direct edit.
              tooltip: _kInlineEditEnabled && isEditing
                  ? t.guide_tip_finish_edit
                  : t.guide_tip_direct_edit,
              icon: Icon(
                _kInlineEditEnabled && isEditing
                    ? Icons.check_rounded
                    : Icons.edit_outlined,
                color: Colors.white,
              ),
              onPressed: _kInlineEditEnabled ? onToggleEdit : onDirectEdit,
            ),
          IconButton(
            key: const Key('gesture_guide_settings'),
            tooltip: t.guide_tip_settings,
            icon:
                const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: openSettings,
          ),
          IconButton(
            key: const Key('gesture_guide_reset'),
            tooltip: t.guide_tip_reset,
            icon: const Icon(Icons.restore_rounded, color: Colors.white),
            onPressed: () async {
              usePlayerUiStore().updateIsShowGestureTips(false);
              showResetGestureLayoutDialog(context);
              if (context.mounted) {
                usePlayerUiStore().updateIsShowGestureTips(true);
              }
            },
          ),
          IconButton(
            key: const Key('gesture_guide_close'),
            tooltip: t.guide_tip_close,
            // Only the guide has a close action and it returns directly to the
            // player without a warning dialog; the editor's cancel/reset/confirm
            // each have their own suppressible warnings.
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () =>
                usePlayerUiStore().updateIsShowGestureTips(false),
          ),
        ],
      ),
    );
  }

  /// Bottom legend: page dots + full-text chips. Chips are ALWAYS readable
  /// (opaque dark background + white label when unselected, themed container
  /// when selected) and clickable to jump between intent pages, replacing the
  /// old "current profile" header.
  Widget _bottomSwitcher(
    BuildContext context,
    List<GuideSection> sections,
    int current,
    ValueChanged<int> onJump,
  ) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sections.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < sections.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == current ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == current ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < sections.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(sections[i].title),
                        selected: i == current,
                        showCheckmark: false,
                        onSelected: (_) => onJump(i),
                        labelStyle: TextStyle(
                          color: i == current
                              ? Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                              : Colors.white,
                          fontWeight: i == current
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        backgroundColor: Colors.black54,
                        selectedColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color:
                                i == current ? Colors.white : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim draggable split line (RETAINED DEAD CODE).
/// KEEP: Polished inline handle that commits per drag end. Retained for
/// reference only — [_kInlineEditEnabled] is false so it never renders or
/// commits; all edits now go through the full-screen grid editor.
class _GuideLineHandle extends StatelessWidget {
  const _GuideLineHandle({
    required this.line,
    required this.index,
    required this.size,
    required this.onDrag,
    required this.onDragEnd,
  });

  final EditableLine line;
  final int index;
  final Size size;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final isVertical = line.axis == LineAxis.vertical;
    return Positioned(
      left: isVertical ? size.width * line.value - 16 : 0,
      top: isVertical ? 0 : size.height * line.value - 16,
      width: isVertical ? 32 : size.width,
      height: isVertical ? size.height : 32,
      child: GestureDetector(
        key: Key('gesture_guide_line_${line.axis.name}_$index'),
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) {
          final delta = isVertical
              ? d.delta.dx / size.width
              : d.delta.dy / size.height;
          onDrag(line.value + delta);
        },
        onPanEnd: (_) => onDragEnd(),
        child: Center(
          child: Container(
            width: isVertical ? 22 : 48,
            height: isVertical ? 48 : 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white54),
            ),
            child: Text(
              '${(line.value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
