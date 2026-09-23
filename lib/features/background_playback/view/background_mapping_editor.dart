import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/active_mapping_resolver.dart';
import 'package:iris/features/background_playback/resolver/mapping_timeline_math.dart';
import 'package:iris/features/background_playback/resolver/segment_entry_target.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/services/apb_edit_context.dart';
import 'package:iris/features/background_playback/services/current_bg_resolver.dart';
import 'package:iris/features/background_playback/store/use_apb_edit_session_store.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/virtual_media/interaction/controller/foreground_window_resolver.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/format_duration_hms.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';
import 'package:provider/provider.dart';

/// Enters the fb/bg align edit mode — the ONE self-contained window of the
/// mapping feature. It REPLACES the control bar (see `SegmentAlignEditPanel`)
/// rather than opening a floating card.
///
/// Opening it FREEZES the pair: playback is paused immediately (the user
/// restarts with the in-panel play/pause button), `SegmentEditGuard` blocks
/// prev/next and end-of-media advancing on both runtimes, and the panel never
/// auto-hides.
Future<void> showBackgroundMappingEditor(BuildContext context) async {
  final bg = useBackgroundPlaybackStore();
  if (bg.state.segmentEditMode) {
    bg.exitSegmentEdit();
    // The entry locked a transient single-fg context; release it so the
    // previous playback context resumes.
    await closeActiveApbEditSession();
    return;
  }
  if (!bg.state.enabled) {
    await showMessageDialog(
      Navigator.of(context, rootNavigator: true),
      message: getLocalizations(context).bg_segment_need_enabled,
      type: MessageDialogType.info,
    );
    return;
  }

  final fgPlayer = context.read<MediaPlayer>();
  final engine = context.read<BackgroundPlaybackEngine>();
  final t = getLocalizations(context);

  // Physical foreground window (VM merged timeline undone) and the live bg
  // file (mapped › engine › natural) — never a stale one-shot snapshot.
  final window = foregroundWindowNow(
    playerDurationMs: fgPlayer.duration.inMilliseconds,
    playerPositionMs: fgPlayer.position.inMilliseconds,
  );
  final FileItem? bgFile = resolveCurrentBgFile(
    mappedFile: bg.state.mappedFile,
    engineFile: engine.file,
    naturalFile: bg.currentFile,
  );

  // 播放什么就进什么 bg: an ACTIVE saved segment in use at the current position
  // IS the edit target (full stored values, id + activation order preserved, so
  // Save can offer overwrite-vs-new). With none in use we still open the
  // NEAREST saved segment — clicking APB must show the saved mapping, not
  // silently seed a brand-new one far from it. No saved segment at all → seed.
  final FileItem? fgFile = _currentForegroundFile();
  final BackgroundMappingTimeline? timeline = await _timelineFor(fgFile);
  final MappingSegment? effective = timeline == null
      ? null
      : ActiveMappingResolver.effectiveAt(
          timeline.sortedSegments,
          window.positionMs,
        );
  final MappingSegment? origin = effective ??
      (timeline == null
          ? null
          : nearestActiveSegment(timeline.sortedSegments, window.positionMs));

  // Position protection (副音 mismatch): the editor frames the edited segment,
  // so a playhead far outside its window would land on a segment it can only
  // show after a jump. Ask first; once suppressed (Settings → Warning dialogs)
  // it jumps silently. Cancelling opens nothing and leaves playback untouched.
  bool jumpToOrigin = false;
  if (effective == null && origin != null && window.durationMs > 0) {
    // Prefer the live bg duration; fall back to the segment's saved file total
    // so the check can run even while the 副音 engine is still opening.
    final int bgDurMs = engine.duration.inMilliseconds > 0
        ? engine.duration.inMilliseconds
        : (MappingTimelineMath.bgTotalMsFromNorms(origin) ?? 0);
    final bool outside = origin.isPlayMedia &&
        playheadOutsideSegmentWindow(
          fgDurMs: window.durationMs,
          bgDurMs: bgDurMs,
          zoom: bg.state.fgWindowZoom,
          pushBg: bg.state.fgWindowPushBg,
          fgPosMs: window.positionMs,
          segmentStartMs: origin.fgStartMs,
          segmentEndMs: origin.fgEndMs,
        );
    if (outside) {
      if (!context.mounted) return;
      final bool ok = await showConfirmSuppressibleDialog(
        context,
        warningId: kWarningBgAlignForceSeek,
        title: t.bg_align_force_seek_title,
        message: t.bg_align_force_seek_body(
            formatDurationHms(Duration(milliseconds: origin.fgStartMs))),
        confirmLabel: t.bg_align_force_seek_confirm,
      );
      if (!ok) return;
      jumpToOrigin = true;
    }
  }

  // Freeze the pair only once the user committed to the edit.
  fgPlayer.pause();

  // fg 都锁: bind the edited foreground into a transient single-item workspace
  // (same mechanism as the mapping-manager entry) so foreground transport can
  // never step away; the previous context is restored on exit. Global
  // per-file progress keeps the same media at the same position.
  if (fgFile != null) {
    final session = await ApbEditContext.enter(fg: fgFile);
    if (session != null) {
      useApbEditSessionStore().begin(session);
    }
  }

  // Land on A AFTER the context switch: switching reloads the foreground at its
  // saved progress, which would overwrite a seek made before it. This is what
  // the entry prompt promised, and it makes the first editor frame show the
  // segment instead of a collapsed ring at a far-away playhead.
  if (jumpToOrigin && origin != null) {
    await _seekToSegmentStart(
      fgPlayer: fgPlayer,
      engine: engine,
      window: window,
      segment: origin,
    );
  }

  final SegmentEditDraft? draft = draftForEntry(
    origin: origin,
    fgPosMs: window.positionMs,
    fgDurMs: window.durationMs,
    bgPosMs: engine.position.inMilliseconds,
    bgDurMs: engine.duration.inMilliseconds,
    bgFile: bgFile,
    minSpanMs: bg.state.minSegmentSpanMs,
  );

  if (draft != null) {
    bg.enterSegmentEdit(draft);
  }
}

/// The play queue's current foreground file (null when nothing is loaded).
FileItem? _currentForegroundFile() {
  final state = usePlayQueueStore().state;
  final queue = state.playQueue;
  final index = state.currentIndex;
  if (queue.isEmpty || index < 0) return null;
  final i = queue.indexWhere((e) => e.index == index);
  if (i < 0 || i >= queue.length) return null;
  return queue[i].file;
}

/// Loads the foreground's saved timeline (null when it has none / no identity).
Future<BackgroundMappingTimeline?> _timelineFor(FileItem? fgFile) async {
  if (fgFile == null) return null;
  final storageId = fgFile.storageId;
  final path = fgFile.path.join('/');
  if (storageId.isEmpty || path.isEmpty) return null;
  try {
    return await DbModule.bgMappingRepo.getTimelineForFg(
      storageId: storageId,
      path: path,
    );
  } catch (_) {
    return null;
  }
}

/// Seeks the pair to the segment's A: the foreground to the physical A (VM
/// undone) and the 副音 to the mapped bg frame, so the editor opens already on
/// the segment.
Future<void> _seekToSegmentStart({
  required MediaPlayer fgPlayer,
  required BackgroundPlaybackEngine engine,
  required ForegroundWindow window,
  required MappingSegment segment,
}) async {
  fgPlayer.seek(
      Duration(milliseconds: window.playerPositionFor(segment.fgStartMs)));
  final int? bgStart = segment.bgStartMs;
  if (segment.isPlayMedia && bgStart != null) {
    await engine.seek(Duration(milliseconds: bgStart));
  }
}

/// Builds the initial span as the WHOLE usable range for the current alignment:
/// A where bg 00:00 lands (capped at the video head) and B where bg runs out
/// (capped at the video end). Deliberately NOT "the current position + 1 min" —
/// A must sit on the real bg alignment point. Null when the foreground has no
/// usable duration yet.
SegmentEditDraft? seedSegmentDraft({
  required int fgPosMs,
  required int fgDurMs,
  required int bgPosMs,
  required int bgDurMs,
  String? bgStorageId,
  String? bgPath,
  int fgPercent = kDefaultSegmentFgPercent,
  int bgPercent = kDefaultSegmentBgPercent,
  int minSpanMs = kDefaultMinSegmentSpanMs,
  int? colorArgb,
}) {
  if (fgDurMs <= 0) return null;
  final raw = SegmentSpanMath.fullFeasibleSpan(
    fgDurMs: fgDurMs,
    bgDurMs: bgDurMs,
    bgOffsetMs: bgPosMs - fgPosMs.clamp(0, fgDurMs),
    minSpanMs: minSpanMs,
  );
  return SegmentEditDraft(
    action: MappingAction.playMedia,
    span: SegmentSpanMath.clamp(raw,
        fgDurMs: fgDurMs, bgDurMs: bgDurMs, minSpanMs: minSpanMs),
    bgStorageId: bgStorageId,
    bgPath: bgPath,
    fgPercent: fgPercent,
    bgPercent: bgPercent,
    colorArgb: colorArgb,
  );
}

/// Chooses the draft the APB editor opens with.
///
/// 播放什么就进什么 bg: an in-use saved segment ([origin]) IS the draft — its
/// full stored span/bg/ratio plus its id and activation order, so Save can ask
/// overwrite-vs-new. With no origin the editor seeds a brand-new segment from
/// the live alignment. Null only when the foreground has no usable duration.
SegmentEditDraft? draftForEntry({
  required MappingSegment? origin,
  required int fgPosMs,
  required int fgDurMs,
  required int bgPosMs,
  required int bgDurMs,
  required FileItem? bgFile,
  int minSpanMs = kDefaultMinSegmentSpanMs,
}) {
  if (origin != null) {
    final base = SegmentEditDraft.fromSegment(origin);
    return base.copyWith(
      span: SegmentSpanMath.clamp(
        base.span,
        fgDurMs: fgDurMs,
        bgDurMs: bgDurMs,
        minSpanMs: minSpanMs,
      ),
    );
  }
  return seedSegmentDraft(
    fgPosMs: fgPosMs,
    fgDurMs: fgDurMs,
    bgPosMs: bgPosMs,
    bgDurMs: bgDurMs,
    bgStorageId: bgFile?.storageId,
    bgPath: bgFile?.path.join('/'),
    minSpanMs: minSpanMs,
  );
}
