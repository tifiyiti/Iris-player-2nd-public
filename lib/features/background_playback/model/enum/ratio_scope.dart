/// Edit scope of the foreground/background volume ratio (sub_media §5.5).
///
/// The ratio has two layers: a GLOBAL pair (defaults 30 / 100) and a
/// per-foreground-media override keyed by the foreground media key. [global]
/// edits the shared pair; [current] edits the override row for the file that
/// is playing right now (empty override falls back to the global pair).
enum RatioScope {
  global,
  current,
}
