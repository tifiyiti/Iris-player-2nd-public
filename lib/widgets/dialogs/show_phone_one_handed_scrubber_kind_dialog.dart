import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';

/// [includeDial] opts the metadata-only Ring dial row in; the frozen legacy
/// settings path keeps omitting it (metadata-driven-first policy). The dial
/// row is additionally hidden on PORTRAIT phones (no side scrubber there).
/// [includeClassic] opts the "simple circle arc" (the classic circle slider)
/// row in — also metadata-only.
///
/// Requirement #6: the older arc/timeLens/snake designs are FULLY RETIRED —
/// they are never offered here again (old persisted values normalize to
/// classic on load), so this dialog offers ONLY dial + classic.
Future<void> showPhoneOneHandedScrubberKindDialog(
  BuildContext context, {
  bool includeDial = false,
  bool includeClassic = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => PhoneOneHandedScrubberKindDialog(
        includeDial: includeDial,
        includeClassic: includeClassic,
      ),
    );

class PhoneOneHandedScrubberKindDialog extends HookWidget {
  const PhoneOneHandedScrubberKindDialog({
    super.key,
    this.includeDial = false,
    this.includeClassic = false,
  });

  /// Whether the metadata-only Ring dial row is offered. Metadata-driven
  /// bindings pass true; the legacy settings path stays without it.
  final bool includeDial;

  /// Whether the metadata-only "simple circle arc" (classic circle slider)
  /// row is offered.
  final bool includeClassic;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final PhoneOneHandedScrubberKind selected =
        useAppStore().select(context, (state) => state.phoneOneHandedScrubberKind);
    Map<PhoneOneHandedScrubberKind, String> labelsOf() =>
        <PhoneOneHandedScrubberKind, String>{
          PhoneOneHandedScrubberKind.dial: t.scrub_dial_label,
          PhoneOneHandedScrubberKind.classic: t.scrub_classic_label,
        };
    Map<PhoneOneHandedScrubberKind, String> subtitlesOf() =>
        <PhoneOneHandedScrubberKind, String>{
          PhoneOneHandedScrubberKind.dial: t.scrub_dial_desc,
          PhoneOneHandedScrubberKind.classic: t.scrub_classic_desc,
        };
    final labels = labelsOf();
    final subtitles = subtitlesOf();

    void selectKind(PhoneOneHandedScrubberKind? value) {
      if (value == null) return;
      useAppStore().updatePhoneOneHandedScrubberKind(value);
      Navigator.pop(context);
    }

    bool visible(PhoneOneHandedScrubberKind kind) {
      switch (kind) {
        case PhoneOneHandedScrubberKind.dial:
          if (!includeDial) return false;
          // The ring dial needs a side slot; a portrait phone has none.
          if (isMobilePlatform &&
              MediaQuery.of(context).orientation == Orientation.portrait) {
            return false;
          }
          return true;
        case PhoneOneHandedScrubberKind.classic:
          return includeClassic;
        // Retired designs (arc/timeLens/snake) are never offered.
        default:
          return false;
      }
    }

    return AlertDialog(
      title: Text(t.scrub_kind_title),
      content: SingleChildScrollView(
        child: RadioGroup<PhoneOneHandedScrubberKind>(
          groupValue: selected,
          onChanged: selectKind,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PhoneOneHandedScrubberKind.values
                .where(visible)
                .map(
                  (PhoneOneHandedScrubberKind value) => ListTile(
                    title: Text(labels[value]!),
                    subtitle: Text(subtitles[value]!),
                    leading: Radio<PhoneOneHandedScrubberKind>(value: value),
                    onTap: () => selectKind(value),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.scrub_kind_close),
        ),
      ],
    );
  }
}
