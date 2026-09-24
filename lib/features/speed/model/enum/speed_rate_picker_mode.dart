/// Display mode of the playback-speed picker (more menu / control-bar RATE).
///
/// `dualWheel` is the alarm-clock-style two-wheel picker (integer 0..10 +
/// tenths 0..9) and is the metadata-era default. `slider` is the single
/// segmented-linear track. `list` keeps the legacy flat 0.1-step menu, so
/// users who prefer the old long menu can opt back into it.
///
/// Every mode renders in the same draggable card, so a remembered position
/// applies to whichever picker is current.
enum SpeedRatePickerMode {
  dualWheel,
  slider,
  list,
}
