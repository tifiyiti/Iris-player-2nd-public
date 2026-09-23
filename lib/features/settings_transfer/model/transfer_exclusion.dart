// Items explicitly NOT transferable, shown as disabled info rows with reasons.
import 'package:iris/l10n/app_localizations.dart';

enum TransferExclusionKind {
  localStorages,
  mediaNodes,
  scanStates,
  playQueue,
  currentPlayback,
}

class TransferExclusion {
  const TransferExclusion(this.kind);

  final TransferExclusionKind kind;

  /// Legacy key (kept for compat with callers/tests that match on it).
  String get key => switch (kind) {
        TransferExclusionKind.localStorages => 'localStorages',
        TransferExclusionKind.mediaNodes => 'mediaNodes',
        TransferExclusionKind.scanStates => 'scanStates',
        TransferExclusionKind.playQueue => 'playQueue',
        TransferExclusionKind.currentPlayback => 'currentPlayback',
      };

  String label(AppLocalizations t) => switch (kind) {
        TransferExclusionKind.localStorages => t.transfer_excl_local,
        TransferExclusionKind.mediaNodes => t.transfer_excl_nodes,
        TransferExclusionKind.scanStates => t.transfer_excl_scan,
        TransferExclusionKind.playQueue => t.transfer_excl_queue,
        TransferExclusionKind.currentPlayback => t.transfer_excl_current,
      };

  String reason(AppLocalizations t) => switch (kind) {
        TransferExclusionKind.localStorages => t.transfer_excl_local_reason,
        TransferExclusionKind.mediaNodes => t.transfer_excl_nodes_reason,
        TransferExclusionKind.scanStates => t.transfer_excl_scan_reason,
        TransferExclusionKind.playQueue => t.transfer_excl_queue_reason,
        TransferExclusionKind.currentPlayback => t.transfer_excl_current_reason,
      };
}

const List<TransferExclusion> kTransferExclusions = [
  TransferExclusion(TransferExclusionKind.localStorages),
  TransferExclusion(TransferExclusionKind.mediaNodes),
  TransferExclusion(TransferExclusionKind.scanStates),
  TransferExclusion(TransferExclusionKind.playQueue),
  TransferExclusion(TransferExclusionKind.currentPlayback),
];
