import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_stream/media_stream.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/service/vm_duration_scan.dart'
    show VmScanOutcome, VmWriteBack, defaultVmWriteBack;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/models/storages/ftp.dart' show getFTPAuth;
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart' show getWebDAVAuth;
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/features/media_library/services/media_uri.dart';
import 'package:iris/utils/path_conv.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// One harvested file's media info (null = unobtainable).
typedef HarvestedMedia = ({int durationMs, int? width, int? height});

/// Opens [seg] in a background player and resolves its media info.
///
/// Returns null when unobtainable. Never throws (failures degrade to null):
/// the harvest loop additionally guards with a per-file timeout, so a
/// hanging opener can only cost its budget, never the run.
typedef VmHarvestOpener = Future<HarvestedMedia?> Function(VirtualSegment seg);

/// Background duration harvest over EXACTLY [segments].
///
/// Scope-strict: the caller passes only the failed virtual group's segments
/// (never the library) — the last resort of the efficiency cascade, after
/// the Shell scan, for files whose property handler returns nothing usable
/// (A/B-pinned: VT_EMPTY duration, garbage height) and for FTP, which has
/// no scan-time probing at all.
///
/// - Write-back is incremental (same drift seam as the Shell scan), so
///   cancellation/timeout keeps partial results.
/// - Never touches the play queue or any player-facing store — only the
///   media_nodes columns. The main player is undisturbed (separate Player
///   instance owned by the opener).
/// - Never throws: opener errors degrade to per-segment failures.
Future<VmScanOutcome> harvestVmDurations(
  List<VirtualSegment> segments, {
  required VmHarvestOpener opener,
  VmWriteBack? writeBack,
  bool Function()? shouldCancel,
  void Function(int done, int total, String name)? onProgress,
  Duration perFileTimeout = const Duration(seconds: 20),
  Duration totalBudget = const Duration(minutes: 1),
  AppLocalizations? l10n,
}) async {
  final stopwatch = Stopwatch()..start();
  final persist = writeBack ?? defaultVmWriteBack;

  final failedKeys = <String>[];
  final succeededKeys = <String>[];
  var scanned = 0;
  var done = 0;

  VmScanOutcome finish({bool cancelled = false, bool timedOut = false}) {
    stopwatch.stop();
    final outcome = VmScanOutcome(
      ok: failedKeys.isEmpty && !cancelled && !timedOut,
      scanned: scanned,
      skipped: 0,
      succeededKeys: List.unmodifiable(succeededKeys),
      failedKeys: List.unmodifiable(failedKeys),
      elapsed: stopwatch.elapsed,
      cancelled: cancelled,
      timedOut: timedOut,
    );
    _log.i('[vm-harvest] done ${outcome.summary(l10n ?? AppLocalizationsEn())} total=${segments.length}');
    if (failedKeys.isNotEmpty) {
      _log.w('[vm-harvest] failed sample: ${failedKeys.take(3).join(',')}');
    }
    return outcome;
  }

  // Global ceiling mirrors the preflight budget: 100 files x 20s would
  // otherwise block for ~33min. Cancellation is honored BETWEEN files only.
  // Budget expiry reports timedOut (partial results kept) — distinct from a
  // user cancel, which aborts the whole playback.
  for (final s in segments) {
    if (shouldCancel?.call() == true) {
      return finish(cancelled: true);
    }
    if (stopwatch.elapsed > totalBudget) {
      return finish(timedOut: true);
    }
    HarvestedMedia? got;
    try {
      got = await opener(s).timeout(perFileTimeout);
    } on TimeoutException {
      got = null;
    } catch (_) {
      got = null;
    }
    if (got != null) {
      // Sanitize every opener's output (not just production): malformed
      // w/h would otherwise pollute resolution sorting downstream.
      final sane = sanitizeProbeResult(ProbeResult(
        durationMs: got.durationMs,
        width: got.width,
        height: got.height,
      ));
      if (sane.durationMs == null || sane.durationMs! <= 0) {
        got = null;
      } else {
        got = (
          durationMs: sane.durationMs!,
          width: sane.width,
          height: sane.height
        );
      }
    }
    if (got != null && got.durationMs > 0) {
      try {
        final written = await persist(
          storageId: s.storageId,
          path: canonicalDbPath(s.path.join('/')),
          durationMs: got.durationMs,
          width: got.width,
          height: got.height,
        );
        if (written) {
          scanned++;
          succeededKeys.add(s.mediaKey);
        } else {
          _log.w('[vm-harvest] write-back no-op (no media_nodes row) ${s.mediaKey}');
          failedKeys.add(s.mediaKey);
        }
      } catch (e) {
        _log.w('[vm-harvest] write-back failed ${s.mediaKey}: $e');
        failedKeys.add(s.mediaKey);
      }
    } else {
      failedKeys.add(s.mediaKey);
    }
    done++;
    onProgress?.call(done, segments.length, s.name);
    if (shouldCancel?.call() == true) {
      return finish(cancelled: true);
    }
  }
  return finish();
}

/// Production opener: one background media_kit [Player] PER FILE (no video
/// controller, no rendering surface) that opens the segment with
/// `play: false` purely to read `duration` (+ video dims when available).
///
/// Per-file instances (scheme A): a timed-out file's late `duration` event
/// can never satisfy the NEXT file's `firstWhere` — each open subscribes to
/// its own player's stream, and the stray player disposes itself when its own
/// internal budgets fire. Sharing one Player across files caused exactly
/// that cross-attribution (wrong duration persisted for the wrong file).
///
/// URI/header construction mirrors the player hooks exactly
/// (`use_media_kit_player` open block): FTP goes through the local
/// `MediaStream` proxy with FTP auth, WebDAV uses its direct URL with WebDAV
/// auth, local files use the sanitized playable path. Volume is forced to 0
/// as a belt-and-braces measure (nothing should audible-play with
/// `play: false` regardless).
class MediaKitHarvestOpener {
  MediaKitHarvestOpener({Duration perFileTimeout = const Duration(seconds: 20)})
      : _perFileTimeout = perFileTimeout;

  final Duration _perFileTimeout;

  Future<HarvestedMedia?> call(VirtualSegment seg) async {
    final player = Player();
    try {
      final target = _openTarget(seg);
      if (target == null) return null;
      try {
        await player.setVolume(0);
      } catch (_) {}
      await player.open(
        Media(target.uri, httpHeaders: target.headers),
        play: false,
      );
      // Duration arrives via demux on open (proven by durationArrived on
      // ordinary opens); dims are best-effort with a short budget.
      final dur = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(_durationBudget());
      int? w;
      int? h;
      try {
        final vp = await player.stream.videoParams
            .firstWhere((v) => (v.w ?? 0) > 0 && (v.h ?? 0) > 0)
            .timeout(const Duration(seconds: 2));
        w = vp.w;
        h = vp.h;
      } on TimeoutException {
        // Dims optional; duration is the must-have.
      }
      final sane = sanitizeProbeResult(ProbeResult(
          durationMs: dur.inMilliseconds, width: w, height: h));
      if (sane.durationMs == null || sane.durationMs! <= 0) return null;
      return (
        durationMs: sane.durationMs!,
        width: sane.width,
        height: sane.height
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await player.stop();
      } catch (_) {}
      try {
        player.dispose();
      } catch (_) {}
    }
  }

  Duration _durationBudget() {
    final budget = _perFileTimeout - const Duration(seconds: 3);
    return budget < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : budget;
  }

  /// No-op retained for call-site compatibility: players are now owned and
  /// disposed per file inside [call].
  Future<void> dispose() async {}


  /// Builds the exact open target the player hooks would use for [seg].
  /// Null when unresolvable (FTP proxy down). The storage lookup is
  /// defensive: without a store entry the segment is treated as local
  /// (same graceful-degradation posture as the player hooks' fallbacks).
  ({String uri, Map<String, String> headers})? _openTarget(
      VirtualSegment seg) {
    Storage? storage;
    try {
      storage = useStorageStore().findById(seg.storageId);
    } catch (_) {
      storage = null;
    }
    final type = storage?.type ?? StorageType.none;
    if (type == StorageType.ftp && storage is FTPStorage) {
      // This is a direct Media() consumer, so it prepends the proxy itself;
      // the relative part is shared with every other producer.
      final proxy = MediaStream().url;
      if (proxy == null || proxy.isEmpty) return null;
      return (
        uri: '$proxy/${ftpPlayableUri(storage, seg.path)}',
        headers: {'authorization': getFTPAuth(storage)}
      );
    }
    if (type == StorageType.webdav && storage is WebDAVStorage) {
      // Derived from the storage record (scheme/port + the CURRENT host), the
      // same way every MediaNode→FileItem producer builds it — a wildcard entry
      // must never be dialled as `192.168.*.*`.
      return (
        uri: webdavPlayableUri(storage, seg.path),
        headers: {'authorization': getWebDAVAuth(storage)}
      );
    }
    return (
      // SAF rows carry their real content:// document uri; plain rows fall
      // back to the rebuilt playable path.
      uri: sanitizePlayableUri(nodePlayableUri(seg.path, uri: seg.uri)),
      headers: const <String, String>{}
    );
  }
}
