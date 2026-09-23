import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/osd/engine/osd_texts.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Base-step adjust OSD (Ctrl+↑/↓ / Ctrl+Shift+↑/↓): localized title + seconds.
void main() {
  test('seekStep OSD shows the title and seconds', () async {
    final t = await lookupAppLocalizations(const Locale('en'));
    final entry = OsdTexts.seekStep(10, t);

    expect(entry.line1, t.osd_seek_step);
    expect(entry.line2, '10s');
  });
}
