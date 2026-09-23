import 'package:flutter/material.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/scan/vm_db_durations.dart'
    show VmDbDurationReader, defaultVmDbDurationReader;
import 'package:iris/utils/get_localizations.dart';

// Single choke point for the duration-scan data contract: scans persist
// incrementally to the database, consumers re-read the database and never
// trust in-memory scan claims directly (single source of truth).

/// Applies DB durations onto [segments], returning a new list.
List<VirtualSegment> applyDbDurationsToSegments(
  List<VirtualSegment> segments,
  Map<String, int?> dbByKey,
) {
  return [
    for (final s in segments)
      if (!dbByKey.containsKey(s.mediaKey))
        s
      else if (dbByKey[s.mediaKey] != null && dbByKey[s.mediaKey]! > 0)
        s.withDuration(dbByKey[s.mediaKey])
      else
        // Missing/unknown DB rows never wash a positive stream duration.
        s,
  ];
}

/// Keys that are both claimed by a scan AND confirmed positive in the DB.
Set<String> healedKeysFromDb(
  List<VirtualSegment> segments,
  Set<String> claimedKeys,
  Map<String, int?> dbByKey,
) {
  final ids = {for (final s in segments) s.mediaKey};
  final out = <String>{};
  for (final k in claimedKeys) {
    if (!ids.contains(k)) continue;
    final d = dbByKey[k];
    if (d != null && d > 0) out.add(k);
  }
  return out;
}

/// True when a slow (media_kit harvest) follow-up is worth offering.
bool shouldOfferSlowScan(List<String> leftoverKeys) {
  if (leftoverKeys.isEmpty) return false;
  return true;
}

/// Re-reads the DB and keeps only scan claims confirmed there.
Future<Set<String>> filterScanHealedByDb(
  List<VirtualSegment> segments,
  Set<String> claimedKeys, {
  VmDbDurationReader? readDb,
}) async {
  if (claimedKeys.isEmpty) return <String>{};
  final reader = readDb ?? defaultVmDbDurationReader;
  final db = await reader(segments);
  return healedKeysFromDb(segments, claimedKeys, db);
}

/// User decision at the slow-scan gate (Shell fast scan already persisted).
enum VmSlowScanChoice {
  /// Play the group normally, keep the yellow mark.
  playNormal,

  /// Run the slow background harvest.
  slowScan,

  /// Abort the whole playback.
  abort,
}

/// Second confirm before the slow harvest (Shell-first policy: the slow path
/// never starts unprompted). Barrier taps count as normal playback (null at
/// the call site maps to [VmSlowScanChoice.playNormal]).
Future<VmSlowScanChoice?> showVmSlowScanConfirmDialog(
  NavigatorState navigator, {
  required String groupName,
  required List<String> leftoverNames,
}) async {
  if (!navigator.mounted) return VmSlowScanChoice.playNormal;
  return showDialog<VmSlowScanChoice>(
    context: navigator.context,
    builder: (context) {
      final t = getLocalizations(context);
      final shown = leftoverNames.take(3).join(', ');
      final names = leftoverNames.length > 3
          ? '$shown, ${t.vm_sheet_more_items(leftoverNames.length)}'
          : shown;
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: Text(t.vm_slow_title),
        content: Text(
          t.vm_slow_body(groupName, leftoverNames.length, names),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, VmSlowScanChoice.abort),
            child: Text(t.vm_preflight_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, VmSlowScanChoice.playNormal),
            child: Text(t.vm_slow_normal),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, VmSlowScanChoice.slowScan),
            child: Text(t.vm_slow_continue),
          ),
        ],
      );
    },
  );
}
