import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/view/setting_texts.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Text-coverage guard: every catalog def's titleKey (and subtitleKey, when
/// present) MUST resolve to a real ARB-backed string. A missing mapping makes
/// the row render an English prettified key (no Chinese) — a silent UX bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every def titleKey / subtitleKey / groupHeaderKey has ARB text',
      () async {
    final t = await AppLocalizations.delegate.load(const Locale('en'));
    final missingTitles = <String>[];
    final missingSubtitles = <String>[];
    final missingGroups = <String>[];

    for (final d in SettingsCatalog.defs) {
      if (SettingTexts.titleOrNull(d.titleKey, t) == null) {
        missingTitles.add('${d.key} -> ${d.titleKey}');
      }
      final sk = d.subtitleKey;
      if (sk != null && SettingTexts.subtitleOrNull(sk, t) == null) {
        missingSubtitles.add('${d.key} -> $sk');
      }
      final gk = d.groupHeaderKey;
      if (gk != null && SettingTexts.groupLabel(gk, t).isEmpty) {
        missingGroups.add('${d.key} -> $gk');
      }
    }

    expect(missingTitles, isEmpty, reason: 'untitled rows render raw keys');
    expect(missingSubtitles, isEmpty, reason: 'subtitles fall back to empty');
    expect(missingGroups, isEmpty, reason: 'group headers fall back to empty');
  });
}
