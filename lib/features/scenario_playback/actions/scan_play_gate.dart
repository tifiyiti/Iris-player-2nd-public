import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iris/features/media_library/scan/model/scan_rescan_reminder.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart'
    show ScanPhase;
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/scenario_playback/actions/pending_play_intent.dart';
import 'package:iris/features/media_library/scan/view/scan_options_dialog.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';

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
    final status = await _statusOf(dir, now, reminder);
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
  final row = await DbModule.mediaNodesDao
      .dirScanStatus(dir.storageId, dir.path);
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
        await _startScanFor(context, dir);
        // Recording the pending intent happens here — after the background
        // scan actually started — so the resume path only exists when a scan
        // genuinely took over and the original playback was interrupted.
        onScanNow?.call();
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

Future<void> _startScanFor(BuildContext context, ScenarioSourceSpec dir) async {
  final storage = useStorageStore().findById(dir.storageId);
  if (storage == null) return; // cannot scan without a storage → play aborted
  // Same options dialog as manual scans, probe default ON (see dialog).
  final probe =
      await showScanOptionsDialog(context, storageType: storage.type);
  if (probe == null || !context.mounted) return; // cancelled → abort play

  final scanStore = useRecursiveScanStore();
  final service = RecursiveScanService(
    storage: storage,
    scanStore: scanStore,
    nodesDao: DbModule.mediaNodesDao,
    sourcesDao: DbModule.mediaLibSourcesDao,
    probeService: probe ? createMediaProbeService() : null,
  );
  final rootPath = dir.path.isEmpty
      ? storage.basePath.join('/')
      : dir.path;
  unawaited(service.scanRecursively(
    rootPaths: [rootPath],
    context: context,
  ));
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

/// Watches the shared scan store for the completion of the scan that took over
/// this playback, then offers to resume the pending intent.
///
/// Listens for the transition `scanning → done/stopped/error`. Because the
/// listener is global to the scan store (single scan at a time in the app),
/// it re-checks [PendingPlayIntentHolder.pending] on each terminal transition
/// instead of relying on a captured intent — so a pending intent created for a
/// different root still gets its chance, and repeated completions don't double
/// resume. A separate [armed] flag in [ensureDirsScannedWithPendingPlay] keeps
/// this from stacking for one user action.
void _watchScanCompletionForResume({
  required PendingPlayIntentHolder holder,
  required BuildContext captureContext,
}) {
  // A debounce lets completeScan() (which fires the stream) finish applying
  // its persisted state before we re-check; lookup is cheap and idempotent.
  void offer() {
    final intent = holder.pending;
    if (intent == null) return;
    if (!captureContext.mounted) {
      // Caller already left the screen — drop the intent silently.
      holder.clear();
      return;
    }
    showDialog<void>(
      context: captureContext,
      builder: (dialogCtx) {
        final t = getLocalizations(dialogCtx);
        return AlertDialog(
          title: Text(t.gate_resume_title),
          content: Text(t.gate_resume_body),
          actions: [
            TextButton(
              onPressed: () {
                holder.clear();
                Navigator.of(dialogCtx).pop();
              },
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final pendingIntent = holder.pending;
                holder.clear();
                Navigator.of(dialogCtx).pop();
                if (pendingIntent != null) {
                  // Resume with the ORIGINAL captured parameters. The directory
                  // is now scanned, so the gate passes and playback proceeds.
                  await pendingIntent.resume();
                }
              },
              child: Text(t.gate_resume_continue),
            ),
          ],
        );
      },
    );
  }

  final scanStore = useRecursiveScanStore();
  ScanPhase? prevPhase = scanStore.state.phase;
  scanStore.stream.listen((state) {
    final wasScanning = prevPhase == ScanPhase.scanning;
    prevPhase = state.phase;
    if (wasScanning &&
        (state.phase == ScanPhase.done ||
            state.phase == ScanPhase.stopped ||
            state.phase == ScanPhase.error)) {
      offer();
    }
  });
}
