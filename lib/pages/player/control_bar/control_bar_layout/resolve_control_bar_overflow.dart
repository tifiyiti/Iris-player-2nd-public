import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';

/// A control slot on a LINEAR control bar that can take part in overflow
/// handling.
///
/// A slot is the identity of a button, independent of which layout renders it
/// (desktop one-line / desktop stacked / tablet / phone). The overflow model
/// works on slots so every layout can share one collapse policy and one
/// More-menu payload.
enum ControlBarSlot {
  playPause,
  stop,
  prev,
  next,
  shuffle,
  repeat,
  fit,
  windowFitMode,
  rate,
  volume,
  subtitle,
  backgroundMenu,
  playQueue,
  storage,
  fullscreen,
  more,
}

/// Slots that are NEVER pushed into More — the primary transport plus the
/// affordances a user must always reach (audio, fullscreen, the More trigger
/// itself). Everything else degrades into the More menu when width runs out.
const Set<ControlBarSlot> kControlBarCoreSlots = <ControlBarSlot>{
  ControlBarSlot.playPause,
  ControlBarSlot.prev,
  ControlBarSlot.next,
  ControlBarSlot.volume,
  ControlBarSlot.fullscreen,
  ControlBarSlot.more,
};

/// Order in which OPTIONAL slots are pushed into More as the bar narrows
/// (index 0 = least important, collapsed first).
///
/// Rationale: appearance-only toggles (storage browser, shuffle, repeat) leave
/// first; navigation-adjacent ones (play queue, subtitle tracks, the 副音
/// menu) next; the transport-adjacent stop and the display toggles last; the
/// playback rate — already historically a More fallback — is the final one to
/// go.
const List<ControlBarSlot> kControlBarCollapseOrder = <ControlBarSlot>[
  ControlBarSlot.storage,
  ControlBarSlot.shuffle,
  ControlBarSlot.repeat,
  ControlBarSlot.playQueue,
  ControlBarSlot.subtitle,
  ControlBarSlot.backgroundMenu,
  ControlBarSlot.stop,
  ControlBarSlot.fit,
  ControlBarSlot.windowFitMode,
  ControlBarSlot.rate,
];

/// Nominal width of [slot] inside a row. The audio control is a fixed 160px
/// strip on wide bars and a plain 48px icon below the volume breakpoint (see
/// `AdaptiveVolumeControl`); the caller passes the effective width.
double controlBarSlotWidth(
  ControlBarSlot slot, {
  required double volumeWidth,
}) =>
    slot == ControlBarSlot.volume ? volumeWidth : kControlBarIconButtonWidth;

/// Resolves which optional [present] slots must be pushed into More so the
/// row fits inside [availableWidth].
///
/// Deterministic and side-effect free, so the policy is unit-testable without
/// pumping widgets. [sliderReserveWidth] is the width the seek axis keeps on
/// the SAME row (0 when the slider lives on its own row, as in the stacked /
/// tablet / phone arrangements). Collapsing stops as soon as the row fits; if
/// even the core slots do not fit (extreme widths) the optional set is
/// exhausted and the caller falls back to a wrapping/two-row arrangement.
Set<ControlBarSlot> resolveControlBarOverflow({
  required double availableWidth,
  required Set<ControlBarSlot> present,
  required double volumeWidth,
  double sliderReserveWidth = 0,
}) {
  double used = sliderReserveWidth;
  final List<ControlBarSlot> optionals = <ControlBarSlot>[];
  for (final ControlBarSlot slot in present) {
    used += controlBarSlotWidth(slot, volumeWidth: volumeWidth);
    if (!kControlBarCoreSlots.contains(slot)) {
      optionals.add(slot);
    }
  }
  // Least important first; ties (slots absent from the order) keep a stable
  // relative order via the original iteration.
  optionals.sort((a, b) {
    final int ia = kControlBarCollapseOrder.indexOf(a);
    final int ib = kControlBarCollapseOrder.indexOf(b);
    return ia.compareTo(ib);
  });

  final Set<ControlBarSlot> collapsed = <ControlBarSlot>{};
  int i = 0;
  while (used > availableWidth && i < optionals.length) {
    final ControlBarSlot slot = optionals[i++];
    collapsed.add(slot);
    used -= controlBarSlotWidth(slot, volumeWidth: volumeWidth);
  }
  return collapsed;
}

