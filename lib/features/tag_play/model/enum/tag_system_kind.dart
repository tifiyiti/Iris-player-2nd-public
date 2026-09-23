/// System-reserved tag roles.
///
/// A row whose `video_tags.system_kind` is non-null is owned by the system:
/// it can never be deleted and its name is fixed (the role, not the name, is
/// the identity — callers must never match reserved tags by their display
/// name). Reserved tags otherwise behave exactly like user tags: members can
/// be freely added/removed and (except name/kind) fields like `description`
/// remain editable.
///
/// The canonical names/descriptions below are CONTENT stored in the DB (the
/// existing tag seed ships Chinese display names the same way) — they are not
/// ARB keys; UI chrome around reserved tags is localized via ARB.
enum TagSystemKind {
  /// 「临时标记」 — jump-back within a 30-minute window, members expire after
  /// 6 hours. Pre-existing behavior of the v2 built-in seed.
  tempMarker(
    canonicalName: '临时标记',
    canonicalDescription: '30 分钟回切 · 6 小时过期删除',
    retention: Duration(hours: 6),
    resumeWindow: Duration(minutes: 30),
  ),

  /// 「永久收藏」 — permanent retention and permanent jump-back. Pre-existing
  /// behavior of the v2 built-in seed.
  favorite(
    canonicalName: '永久收藏',
    canonicalDescription: '永久收藏 · 回切永久',
    retention: null,
    resumeWindow: null,
  ),

  /// 「副音备选」 — the default candidate source of 副音播放 (background
  /// playback). Permanent retention (a reserved tag must never expire its own
  /// members).
  backgroundVoiceCandidate(
    canonicalName: '副音备选',
    canonicalDescription: '副音播放候选源',
    retention: null,
    resumeWindow: null,
  );

  final String canonicalName;
  final String canonicalDescription;

  /// Member auto-expiry policy applied when the role row is created/adopted.
  final Duration? retention;

  /// Jump-back window applied when the role row is created/adopted.
  final Duration? resumeWindow;

  const TagSystemKind({
    required this.canonicalName,
    required this.canonicalDescription,
    required this.retention,
    required this.resumeWindow,
  });
}
