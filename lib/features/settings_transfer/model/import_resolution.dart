// Per-section conflict resolution chosen by the user on import.
import 'package:iris/l10n/app_localizations.dart';

enum TransferResolution {
  skip, // ignore this section
  append, // add without touching existing (merge/append)
  overwrite, // replace existing with imported
}

extension TransferResolutionX on TransferResolution {
  String label(AppLocalizations t) => switch (this) {
        TransferResolution.skip => t.transfer_res_skip,
        TransferResolution.append => t.transfer_res_append,
        TransferResolution.overwrite => t.transfer_res_overwrite,
      };
}

// Supported resolutions per section — appSettings has no meaningful
// "append" (scalar settings), so the UI hides it.
const Map<String, List<TransferResolution>> kSectionResolutions = {
  'appSettings': [TransferResolution.skip, TransferResolution.overwrite],
  'history': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
  'favorites': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
  'scenarios': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
  'tagPlay': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
  'virtualMedia': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
  'networkStorages': [TransferResolution.skip, TransferResolution.append, TransferResolution.overwrite],
};

TransferResolution defaultResolutionFor(String sectionKey) {
  if (sectionKey == 'appSettings') return TransferResolution.overwrite;
  return TransferResolution.append;
}
