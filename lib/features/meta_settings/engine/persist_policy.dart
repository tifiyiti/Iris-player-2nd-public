/// Write-path policy of the metadata settings subsystem — the SINGLE place
/// that decides where a state change is persisted.
///
/// Two switches on [AppState] drive it:
///  - master gate `useMetadataSettings`: which side READS are authoritative
///    (DB rows when ON, legacy blob when OFF);
///  - sync gate `syncLegacyBlob` (only meaningful while the master gate is
///    ON): whether writes ALSO mirror into the legacy blob.
///
/// Matrix:
///   master OFF            → blob only            (byte-for-byte legacy)
///   master ON + sync ON   → blob + rows          (default, rollback-safe)
///   master ON + sync OFF  → rows only            (blob frozen)
///
/// EXCEPTION — gate transitions ignore the sync gate and always write the
/// blob: boot-time gate discovery reads ONLY the blob, so an enable/disable
/// that skipped the blob could silently vanish across a restart.
library;

import 'package:iris/models/store/app_state.dart';

abstract final class PersistPolicy {
  static const String masterGateField = 'useMetadataSettings';
  static const String syncGateField = 'syncLegacyBlob';

  /// Persistence targets for a mutation producing [next].
  static ({bool writeBlob, bool writeRows}) targets(AppState next) {
    if (!next.useMetadataSettings) {
      return (writeBlob: true, writeRows: false);
    }
    return (writeBlob: next.syncLegacyBlob, writeRows: true);
  }
}
