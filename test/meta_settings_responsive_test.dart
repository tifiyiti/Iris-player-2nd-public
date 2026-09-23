import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/view/meta_settings_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:drift/native.dart';

import 'helpers/sqlite3_loader.dart';

/// Dual-end guard: the metadata settings page must render on a 360px-wide
/// phone with a large font scale without a RenderFlex overflow (the legacy
/// page had no width/breakpoint handling at all).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  testWidgets('360x640 with large font renders Play + General without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: MetaSettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Play tab must not overflow at 360px / 1.3x font');

    // Scroll the Play list to exercise below-the-fold rows.
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'General tab must not overflow at 360px / 1.3x font');
  });
}
