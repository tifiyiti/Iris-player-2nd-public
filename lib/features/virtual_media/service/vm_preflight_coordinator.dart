import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_preflight.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// Time budget for the blocking playback preflight. The source is the
/// database only (no file probing), so exceeding this is treated as a bug:
/// log + error-report dialog.
const Duration kVmPreflightBudget = Duration(minutes: 1);

/// Test seam for the per-segment database lookup.
typedef VmNodeReader = Future<MediaNode?> Function(VirtualSegment seg);

Future<MediaNode?> _defaultNodeReader(VirtualSegment seg) {
  return DbModule.mediaNodeRepo.getNodeByPath(
    storageId: seg.storageId,
    path: seg.path,
  );
}

/// Outcome of the blocking per-playback verification of one virtual group.
class VmVerifyOutcome {
  /// True when every segment re-checked feasible (DB row + positive duration).
  final bool ok;

  /// Extra failures found during verification (merged into the service fail
  /// map by the caller so the tile yellow-marks and playback falls back).
  final Map<String, VmFailInfo> extraFail;

  final Duration elapsed;
  final bool timedOut;

  /// True when the user cancelled the preflight (abort the whole playback).
  final bool cancelled;

  /// Human-readable report for the error dialog (timeout / hard error only).
  final String? report;

  const VmVerifyOutcome({
    required this.ok,
    required this.extraFail,
    required this.elapsed,
    this.timedOut = false,
    this.cancelled = false,
    this.report,
  });
}

/// Blocking preflight for one virtual group before playback.
///
/// Database-only by design: each segment's duration must already be known in
/// the database (or carried on the segment from the resolve stream). File
/// probing never happens here — it lives in the scan flow, which persists to
/// the database first and lets callers re-read (single source of truth).
/// Never throws (DB errors degrade to per-segment failures).
Future<VmVerifyOutcome> verifyVmGroupForPlayback(
  VirtualMediaItem group, {
  void Function(int done, int total, String name)? onProgress,
  // ignore: deprecated_member_use_from_same_package
  @Deprecated('Preflight is DB-only; probes live in the scan flow.')
  MediaProbeService? probeService,
  VmNodeReader? nodeReader,
  bool Function()? shouldCancel,
  AppLocalizations? l10n,
}) async {
  final stopwatch = Stopwatch()..start();
  final extraFail = <String, VmFailInfo>{};
  final readNode = nodeReader ?? _defaultNodeReader;
  // Default path prefetches all rows in one batched lookup so 100-segment
  // groups don't pay 100 serial UI-isolate queries; custom seams (tests)
  // keep per-segment behavior.
  Map<String, MediaNode?>? prefetched;
  if (nodeReader == null && group.segments.isNotEmpty) {
    try {
      final keys = {for (final s in group.segments) s.mediaKey};
      final nodes = await DbModule.mediaNodeRepo.nodesByMediaKeys(keys);
      prefetched = <String, MediaNode?>{};
      for (final n in nodes) {
        final key = n.maybeMap(
          file: (f) => '${f.storageId}:${f.path.join('/')}',
          orElse: () => '',
        );
        if (key.isNotEmpty) prefetched[key] = n;
      }
    } catch (_) {
      prefetched = null;
    }
  }

  VmVerifyOutcome finishCancelled() {
    stopwatch.stop();
    return VmVerifyOutcome(
      ok: false,
      extraFail: extraFail,
      elapsed: stopwatch.elapsed,
      cancelled: true,
    );
  }

  VmFailInfo fail(
    VirtualSegment seg,
    VmFailReason reason,
    String detail, {
    List<String> badNames = const [],
    String? errorText,
  }) =>
      VmFailInfo(
        reason: reason,
        detail: detail,
        badNames: badNames,
        errorText: errorText,
        scopeKey: group.scopeKey,
        ruleId: group.ruleId,
      );

  for (var i = 0; i < group.segments.length; i++) {
    if (shouldCancel?.call() == true) return finishCancelled();
    if (stopwatch.elapsed > kVmPreflightBudget) {
      stopwatch.stop();
      final t = l10n ?? AppLocalizationsEn();
      final report = t.vm_preflight_timeout(
          kVmPreflightBudget.inSeconds,
          group.ruleId,
          group.scopeKey,
          i,
          group.segments.length,
          group.segments[i].mediaKey);
      _log.e('[vm-preflight] TIMEOUT $report');
      for (var j = i; j < group.segments.length; j++) {
        final seg = group.segments[j];
        extraFail[seg.mediaKey] = fail(seg, VmFailReason.timeout, report);
      }
      return VmVerifyOutcome(
        ok: false,
        extraFail: extraFail,
        elapsed: stopwatch.elapsed,
        timedOut: true,
        report: report,
      );
    }

    final seg = group.segments[i];
    onProgress?.call(i, group.segments.length, seg.name);
    final t = l10n ?? AppLocalizationsEn();
    try {
      final MediaNode? node;
      if (prefetched != null) {
        node = prefetched.containsKey(seg.mediaKey)
            ? prefetched[seg.mediaKey]
            : null;
      } else {
        node = await readNode(seg);
      }
      if (shouldCancel?.call() == true) return finishCancelled();
      if (node == null) {
        extraFail[seg.mediaKey] = fail(
            seg, VmFailReason.missingNode, t.vm_fail_missing_node);
        _log.w('[vm-preflight] scope=${group.scopeKey} rule=${group.ruleId} '
            'reason=missingNode seg=${seg.mediaKey}: degraded to normal list');
        continue;
      }
      final dbDuration = node.maybeMap(
        file: (f) => f.durationMs,
        orElse: () => null,
      );
      final known = dbDuration ?? seg.durationMs;
      if (known != null && known > 0) continue;
      // Unknown duration: no probing here — the scan flow fills the DB.
      extraFail[seg.mediaKey] = fail(
          seg, VmFailReason.zeroDuration, t.vm_fail_zero_duration);
      _log.w('[vm-preflight] scope=${group.scopeKey} rule=${group.ruleId} '
          'reason=zeroDuration seg=${seg.mediaKey}: degraded to normal list');
    } catch (e) {
      extraFail[seg.mediaKey] = fail(seg, VmFailReason.missingNode,
          t.vm_fail_verify_error('$e'),
          errorText: '$e');
      _log.w('[vm-preflight] scope=${group.scopeKey} seg=${seg.mediaKey} '
          'verify error: $e');
    }
  }
  stopwatch.stop();
  onProgress?.call(
      group.segments.length, group.segments.length, group.displayName);
  return VmVerifyOutcome(
    ok: extraFail.isEmpty,
    extraFail: extraFail,
    elapsed: stopwatch.elapsed,
  );
}

/// Shows a blocking progress dialog while [verify] runs, then pops it.
///
/// The dialog offers 取消播放: cancelling aborts the whole playback (the
/// caller must not fall through to normal playback). Barrier is
/// non-dismissible; the back button cannot bypass the explicit choice.
Future<VmVerifyOutcome> verifyWithProgressDialog(
  NavigatorState navigator,
  VirtualMediaItem group,
  Future<VmVerifyOutcome> Function(
    void Function(int done, int total, String name) onProgress,
    bool Function() isCancelled,
  ) verify,
) async {
  final progress =
      ValueNotifier<({int done, int total, String name})>((done: 0, total: group.segments.length, name: group.displayName));
  var cancelled = false;
  BuildContext? dialogContext;
  var dialogDone = false;
  final dialogFuture = showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (context) {
      dialogContext = context;
      final t = getLocalizations(context);
      return AlertDialog(
        title: Text(t.vm_preflight_title),
        content: ValueListenableBuilder<({int done, int total, String name})>(
          valueListenable: progress,
          builder: (context, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: p.total <= 0 ? null : p.done / p.total,
              ),
              const SizedBox(height: 12),
              Text('${p.done}/${p.total} · ${p.name}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(context);
            },
            child: Text(t.vm_preflight_cancel),
          ),
        ],
      );
    },
  ).then((_) => dialogDone = true);
  try {
    final outcome = await verify(
      (done, total, name) {
        progress.value = (done: done, total: total, name: name);
      },
      () => cancelled,
    );
    if (cancelled && !outcome.cancelled) {
      return VmVerifyOutcome(
        ok: false,
        extraFail: outcome.extraFail,
        elapsed: outcome.elapsed,
        timedOut: outcome.timedOut,
        cancelled: true,
        report: outcome.report,
      );
    }
    return outcome;
  } finally {
    // The Cancel button already popped the dialog when cancelled==true.
    // Otherwise close via the dialog's own context — never pop blindly
    // (that would dismiss the underlying page). The route push is async,
    // so wait briefly for it to land when the task finished first.
    if (!cancelled && !dialogDone) {
      for (var i = 0; i < 100 && dialogContext == null && !dialogDone; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      } else if (navigator.mounted) {
        navigator.maybePop();
      }
    }
    await dialogFuture;
    // Dispose only after the route is fully gone: the exit animation may
    // still rebuild the ValueListenableBuilder, which re-subscribes.
    progress.dispose();
  }
}

/// Error-report dialog for preflight timeouts/hard errors (Dialog, never
/// SnackBar, per project feedback policy).
Future<void> showVmVerifyReportDialog(
  NavigatorState navigator,
  String report,
) {
  return showDialog<void>(
    context: navigator.context,
    builder: (context) {
      final t = getLocalizations(context);
      return AlertDialog(
        title: Text(t.vm_preflight_report_title),
        content: SelectableText(report),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.dlg_storage_info_got_it),
          ),
        ],
      );
    },
  );
}
