/// Display mode of the playback-speed picker (more menu / control-bar RATE).
///
/// `dualWheel` is the alarm-clock-style two-wheel picker (integer 0..10 +
/// tenths 0..9) and is the metadata-era default. `list` keeps the legacy flat
/// 0.1-step list, so users who prefer the old long menu can opt back into it.
enum SpeedRatePickerMode { dualWheel, list }
