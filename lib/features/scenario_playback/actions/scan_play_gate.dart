import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iris/features/media_library/scan/model/scan_rescan_reminder.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart'
    show ScanPhase;
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/scenario_playback/actions/media_revision_actions.dart';
import 'package:iris/features/scenario_playback/actions/pending_play_intent.dart';
import 'package:iris/features/media_library/scan/view/scan_options_dialog.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_error.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';

/// Per-directory scan gate status (decision output of [classifyDirScanStatus]).
enum DirScanGateStatus { unscanned, scanning, done, error, stale }

/// Classifies one directory's persisted scan status against the reminder
/// window. Pure — no IO — so it is unit-testable.
///
/// - `state == null` (row missing) or `'notScan'` → unscanned.
/// - `'scanning'` → scanning; `'error'` → error.
/// - `'scanDone'`: fresh (within [reminderMinutes]) → done; older → stale.
///   A `scanDone` row without `lastScanAt` is treated as done (corrupt rows
///   must not block playback). `reminderMinutes == 0` disables staleness.
DirScanGateStatus classifyDirScanStatus({
  required String? state,
  required DateTime? lastScanAt,
  required DateTime now,
  required int reminderMinutes,
}) {
  switch (state) {
    case null:
    case 'notScan':
      return DirScanGateStatus.unscanned;
    case 'scanning':
      return DirScanGateStatus.scanning;
    case 'error':
      return DirScanGateStatus.error;
    case 'scanDone':
      if (reminderMinutes <= 0 || lastScanAt == null) {
        return DirScanGateStatus.done;
      }
      final age = now.difference(lastScanAt);
      return age.inMinutes >= reminderMinutes
          ? DirScanGateStatus.stale
          : DirScanGateStatus.done;
    default:
      // Unknown persisted value → treat as unscanned (fail open to a dialog).
      return DirScanGateStatus.unscanned;
  }
}

/// Human-readable staleness, e.g. English `2h 05m` / `45m` / `30h`,
/// Chinese `2小时05分` / `45分` / `30小时`.
String formatStaleness(Duration age, AppLocalizations t) {
  final h = age.inHours;
  final m = age.inMinutes.remainder(60);
  final hs = '$h';
  final ms = m.toString().padLeft(2, '0');
  if (h > 0 && m > 0) return t.gate_stale_hm(hs, ms);
  if (h > 0) return t.gate_stale_h(hs);
  return t.gate_stale_m('$m');
}

/// Reclassifies a persisted `scanning` stamp that no live scan backs.
///
/// The stamp is cleared only when a scan completes successfully over that whole
/// subtree, so a failed child listing, a stopped run or a run superseded by a
/// newer one leaves it behind. Claiming "being scanned" for it is doubly wrong:
/// nothing is running, and that dialog hides the rescan button — the directory
/// then can never be repaired from the gate. Never-fully-scanned is the honest
/// reading, and it offers the full rescan.
DirScanGateStatus resolveLiveScanStatus(
  DirScanGateStatus status, {
  required bool scanLive,
}) {
  if (status != DirScanGateStatus.scanning || scanLive) return status;
  return DirScanGateStatus.unscanned;
}

/// True while the shared scan store is actually scanning [storageId].
bool _scanIsLiveFor(String storageId) {
  final store = useRecursiveScanStore();
  if (!store.isScanning) return false;
  final running = store.state.storageId;
  return running == null || running == storageId;
}

/// Playback gate: checks every recursive directory against its scan status.
///
/// Returns true when playback may proceed; false when it was aborted (user
/// chose to scan now / cancelled). Fresh (`done`) directories pass silently.
/// The first non-pass directory shows a status dialog offering scan-now
/// (via [showScanOptionsDialog] with probe default ON) or play-anyway.
///
/// When the user picks scan-now, [onScanNow] (if provided) is invoked right
/// after the background scan starts — the natural place for a caller to record
/// a [PendingPlayIntent] so the interrupted playback can be resumed when the
/// scan completes (plan: fix override-play lost after scan).
Future<bool> ensureDirsScanned(
  BuildContext context,
  List<ScenarioSourceSpec> dirs, {
  VoidCallback? onScanNow,
}) async {
  final reminder = await scanReminderMinutes();
  final now = DateTime.now();
  final gated = <ScenarioSourceSpec, DirScanGateStatus>{};

  for (final dir in dirs) {
    if (!dir.recursive) continue; // non-recursive scopes need no full scan
    final status = resolveLiveScanStatus(
      await _statusOf(dir, now, reminder),
      scanLive: _scanIsLiveFor(dir.storageId),
    );
    if (status == DirScanGateStatus.done) continue;
    gated[dir] = status;
  }
  if (gated.isEmpty) return true;
  if (!context.mounted) return false;

  // Gate the FIRST non-pass directory (one dialog at a time).
  final entry = gated.entries.first;
  final dir = entry.key;
  final status = entry.value;
  return _showGateDialog(context, dir, status, onScanNow: onScanNow);
}

Future<DirScanGateStatus> _statusOf(
  ScenarioSourceSpec dir,
  DateTime now,
  int reminderMinutes,
) async {
  final row =
      await DbModule.mediaNodesDao.dirScanStatus(dir.storageId, dir.path);
  return classifyDirScanStatus(
    state: row?.state,
    lastScanAt: row?.lastScanAt,
    now: now,
    reminderMinutes: reminderMinutes,
  );
}

Future<bool> _showGateDialog(
  BuildContext context,
  ScenarioSourceSpec dir,
  DirScanGateStatus status, {
  VoidCallback? onScanNow,
}) async {
  final t = getLocalizations(context);
  final label = _dirLabel(dir, t);
  final (title, body) = switch (status) {
    DirScanGateStatus.unscanned => (
        t.gate_unscanned_title,
        t.gate_unscanned_body(label),
      ),
    DirScanGateStatus.scanning => (
        t.gate_scanning_title,
        t.gate_scanning_body(label),
      ),
    DirScanGateStatus.error => (
        t.gate_error_title,
        t.gate_error_body(label),
      ),
    DirScanGateStatus.stale => (
        t.gate_stale_title,
        t.gate_stale_body(label, formatStaleness(await _stalenessOf(dir), t)),
      ),
    DirScanGateStatus.done => ('', ''),
  };
  if (!context.mounted) return false;

  final choice = await showDialog<DirScanGateChoice>(
    context: context,
    builder: (_) => buildScanGateDialog(
      title: title,
      body: body,
      status: status,
      playAnywayLabel: t.gate_play_anyway,
      cancelLabel: t.cancel,
      scanNowLabel: t.gate_scan_now,
      onChoice: (choice) => Navigator.of(context).pop(choice),
    ),
  );

  switch (choice) {
    case DirScanGateChoice.playAnyway:
      return true;
    case DirScanGateChoice.scanNow:
      if (context.mounted) {
        final started = await _startScanFor(context, dir);
        // Only record the pending intent when a scan ACTUALLY started. If the
        // user cancelled the options dialog (or the storage could not be
        // resolved), no scan took over, so arming a resume would silently drop
        // this play and later pop a spurious resume dialog after an unrelated
        // scan completes.
        if (started) onScanNow?.call();
      }
      return false; // scan overlay takes over; playback aborted
    case DirScanGateChoice.cancel:
    case null:
      return false;
  }
}

/// The scan-gate decision dialog for [status].
///
/// Extracted and visible so the widget test can pump every status directly
/// (no DB fixture): every status must offer 取消 — including `scanning`, where
/// the user must be able to back out instead of being forced to "play anyway".
/// "立即完整扫描" is meaningless while a scan is already running, so it stays
/// hidden for [DirScanGateStatus.scanning].
@visibleForTesting
Widget buildScanGateDialog({
  required String title,
  required String body,
  required DirScanGateStatus status,
  required String playAnywayLabel,
  required String cancelLabel,
  required String scanNowLabel,
  required ValueChanged<DirScanGateChoice> onChoice,
}) {
  return AlertDialog(
    title: Text(title),
    content: Text(body),
    actions: [
      TextButton(
        onPressed: () => onChoice(DirScanGateChoice.playAnyway),
        child: Text(playAnywayLabel),
      ),
      TextButton(
        onPressed: () => onChoice(DirScanGateChoice.cancel),
        child: Text(cancelLabel),
      ),
      if (status != DirScanGateStatus.scanning)
        FilledButton(
          onPressed: () => onChoice(DirScanGateChoice.scanNow),
          child: Text(scanNowLabel),
        ),
    ],
  );
}

Future<Duration> _stalenessOf(ScenarioSourceSpec dir) async {
  final row =
      await DbModule.mediaNodesDao.dirScanStatus(dir.storageId, dir.path);
  final last = row?.lastScanAt;
  if (last == null) return Duration.zero;
  return DateTime.now().difference(last);
}

/// Starts a background recursive scan for [dir] and returns whether it actually
/// started. False when the storage cannot be resolved or the user cancelled the
/// scan-options dialog — callers must then NOT record a pending play intent.
Future<bool> _startScanFor(BuildContext context, ScenarioSourceSpec dir) async {
  final storage = useStorageStore().findById(dir.storageId);
  if (storage == null) return false; // cannot scan without a storage
  // Same options dialog as manual scans, probe default ON (see dialog).
  final probe = await showScanOptionsDialog(context, storageType: storage.type);
  if (probe == null || !context.mounted) return false; // cancelled → no scan

  final scanStore = useRecursiveScanStore();
  final service = RecursiveScanService(
    storage: storage,
    scanStore: scanStore,
    nodesDao: DbModule.mediaNodesDao,
    sourcesDao: DbModule.mediaLibSourcesDao,
    probeService: probe ? createMediaProbeService() : null,
  );
  final rootPath = dir.path.isEmpty ? storage.basePath.join('/') : dir.path;
  // The scan mutates `media_nodes`; announce the storage when it finishes so
  // the derived queue index and any open queue view pick up the new content.
  unawaited(service
      .scanRecursively(rootPaths: [rootPath], context: context).then(
          (_) => MediaRevisionActions.mediaNodesChanged([storage.id])));
  return true;
}

String _dirLabel(ScenarioSourceSpec dir, AppLocalizations t) =>
    dir.path.isEmpty ? t.gate_storage_root : dir.path;

/// The user's answer in [buildScanGateDialog]: proceed with the play, start a
/// full scan first, or abort. Public so the dialog builder can be tested.
enum DirScanGateChoice { playAnyway, scanNow, cancel }

/// Runs the scan gate and, when the user picks scan-now, records a
/// [PendingPlayIntent] (i.e. [playOnScanNow]) that resumes the interrupted
/// playback once the scan finishes.
///
/// This is the fix for "override play is lost after an on-demand scan": a
/// playback action blocked by an unscanned directory must survive the scan —
/// otherwise the user's tap does nothing after scanning completes.
///
/// [dirs] are the recursive scopes that gate playback; they are passed to
/// [ensureDirsScanned], and [playOnScanNow] is the resume closure that repeats
/// the original action with the SAME captured parameters. Rerunning the action
/// after the scan completes naturally passes the gate (the directory is now in
/// `scanDone`), so no force flag is needed.
///
/// Returns true when playback may proceed immediately (fresh dirs, or the user
/// chose play-anyway); false when the scan took over (the intent is pending and
/// will be resumed on confirmation — caller should NOT play now).
Future<bool> ensureDirsScannedWithPendingPlay(
  BuildContext context,
  List<ScenarioSourceSpec> dirs, {
  required Future<void> Function() playOnScanNow,
}) async {
  final hold = usePendingPlayIntentHolder();
  // Single-use listener: only arm it the first time this window's scan is
  // triggered, so consecutive gate dialogs don't stack watchers.
  var armed = false;

  final proceed = await ensureDirsScanned(
    context,
    dirs,
    onScanNow: () {
      if (armed) return;
      armed = true;
      hold.set(PendingPlayIntent(resume: playOnScanNow));
      _watchScanCompletionForResume(
        holder: hold,
        captureContext: context,
      );
    },
  );
  return proceed;
}

/// Whether a scan-store phase change should offer the resume prompt.
///
/// Pure and `@visibleForTesting` so the once-only contract is unit-testable:
/// exactly one offer per armed intent, on the first `scanning → terminal`
/// transition. [offered] latches after the first terminal transition; further
/// transitions (a multi-storage batch completes once per storage) are ignored.
@visibleForTesting
bool shouldOfferScanResume({
  required ScanPhase? previousPhase,
  required ScanPhase nextPhase,
  required bool offered,
}) {
  if (offered) return false;
  if (previousPhase != ScanPhase.scanning) return false;
  return nextPhase == ScanPhase.done ||
      nextPhase == ScanPhase.stopped ||
      nextPhase == ScanPhase.error;
}

/// Watches the shared scan store for the completion of the scan that took over
/// this playback, then offers to resume the pending intent ONCE.
///
/// Listens for the transition `scanning → done/stopped/error`. The pending
/// intent is CONSUMED before the dialog is shown so a scan that reaches a
/// terminal phase more than once (a multi-storage batch completes once per
/// storage) can never stack duplicate dialogs. The subscription cancels itself
/// after offering, so repeated gated plays cannot accumulate listeners that all
/// fire on one completion. A separate [armed] flag in
/// [ensureDirsScannedWithPendingPlay] keeps this from stacking for one user
/// action.
void _watchScanCompletionForResume({
  required PendingPlayIntentHolder holder,
  required BuildContext captureContext,
}) {
  final scanStore = useRecursiveScanStore();
  ScanPhase? prevPhase = scanStore.state.phase;
  var offered = false;
  StreamSubscription<dynamic>? sub;
  sub = scanStore.stream.listen((state) {
    final shouldOffer = shouldOfferScanResume(
      previousPhase: prevPhase,
      nextPhase: state.phase,
      offered: offered,
    );
    prevPhase = state.phase;
    if (!shouldOffer) return;
    final intent = holder.pending;
    if (intent == null) return;
    offered = true;
    // Consume first: the dialog below must not be able to stack, and a
    // subsequent terminal transition has nothing left to offer.
    holder.clear();
    unawaited(sub?.cancel() ?? Future<void>.value());
    if (!captureContext.mounted) return;
    _offerPendingResume(captureContext, intent);
  });
}

/// Shows the single "scan finished — continue playing?" prompt for [intent].
///
/// The intent was already consumed by the watcher; a Cancel here simply drops
/// it (and never resumes).
void _offerPendingResume(BuildContext context, PendingPlayIntent intent) {
  if (!context.mounted) {
    return; // caller already left the screen — drop silently
  }
  showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final t = getLocalizations(dialogCtx);
      return AlertDialog(
        title: Text(t.gate_resume_title),
        content: Text(t.gate_resume_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              if (!context.mounted) return;
              await _resumePending(context, intent);
            },
            child: Text(t.gate_resume_continue),
          ),
        ],
      );
    },
  );
}

/// Runs a pending intent, surfacing a failure as the uniform copyable error
/// dialog instead of an unhandled async error.
///
/// A resume re-runs the ORIGINAL action with `force:false`, so it can
/// legitimately throw [PlaybackUnavailableException] when the completed scan
/// still leaves the scope empty (e.g. a folder with no in-scope media).
Future<void> _resumePending(
  BuildContext context,
  PendingPlayIntent intent,
) async {
  try {
    await intent.resume();
  } catch (e) {
    if (!context.mounted) return;
    final t = getLocalizations(context);
    final message = e is PlaybackUnavailableException
        ? e.displayMessage(t)
        : t.dlg_play_failed_prefix('$e');
    await showCopyableErrorDialog(
      context,
      title: t.dlg_copy_error_title,
      message: message,
    );
  }
}
