/// Which foreground media a 副音 activation applies to (the "作用范围" control
/// of the quick bar / 副音 menu).
///
/// - [currentOnly]: only the media the run was started on; leaving it pauses
///   副音 (the subsystem stays alive), returning resumes.
/// - [smart]: a newly opened media defaults to no 副音, EXCEPT a media that has
///   a saved 副音 pairing (`bg_mappings` timeline) — that one auto-starts 副音.
///   This is the "已保存副音 fg 自动播放" behavior.
/// - [all]: 副音 keeps playing its own queue across foreground media switches.
///
/// [BgApplyScope] is a persisted preference (the `bg.applyScope` AUX row) that
/// survives a restart only while the "跨重启保存" option is on.
enum BgApplyScope {
  currentOnly,
  smart,
  all,
}
