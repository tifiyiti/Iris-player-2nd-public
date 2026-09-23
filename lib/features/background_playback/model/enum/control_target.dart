/// Which playback engine the shared control surface currently targets.
///
/// The whole point of the foreground/background split: while 副音播放 is on,
/// the user flips this to route the main slider, play/pause, gestures and
/// shortcuts to the secondary engine — the shared controls never grow a
/// second copy, they just re-target.
enum ControlTarget {
  foreground,
  background,
}
