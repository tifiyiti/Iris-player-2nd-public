/// Pure Z-key speed-reset semantics (PotPlayer parity).
///
/// Z parks any custom rate at 1.0 while remembering it; pressing Z again
/// restores the remembered rate. The remembered value tracks ANY non-1.0
/// rate change (X/C keys, menus, gestures all funnel through
/// [AppStore.updateRate]), so "restore" always means "the last custom
/// speed the user had", never a stale snapshot.
({double rate, double memory}) resolveSpeedResetToggle(
    double current, double memory) {
  if (current != 1.0) return (rate: 1.0, memory: current);
  if (memory != 1.0) return (rate: memory, memory: memory);
  return (rate: 1.0, memory: memory);
}
