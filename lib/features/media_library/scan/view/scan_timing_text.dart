import 'package:flutter/material.dart';
import 'package:iris/features/media_library/scan/model/scan_timing.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/format_duration_hms.dart';
import 'package:iris/utils/get_localizations.dart';

/// One-line "elapsed · remaining" readout for the scan progress overlays.
///
/// Two complete localized sentences rendered side by side — never concatenated
/// fragments, per the localization contract. Ticking text is excluded from
/// semantics (flutter/flutter#182444: decorative, constantly mutating strings
/// must not feed the engine's AXTree pipeline).
class ScanTimingText extends StatelessWidget {
  const ScanTimingText({super.key, required this.timing, this.style});

  final ScanTiming timing;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = getLocalizations(context);
    final String elapsed = t.scan_elapsed(formatDurationHms(timing.elapsed));
    final String eta = timing.eta == null
        ? t.scan_eta_estimating
        : t.scan_eta(formatDurationHms(timing.eta!));

    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              elapsed,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              eta,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
