import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/dialogs/show_slider_type_dialog.dart';

Widget _harness() {
  return StoreScope(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showSliderTypeDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'phone landscape: the settings card never covers the side panel slider',
      (tester) async {
    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 720); // logical 800 x 360
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    useAppStore().set(const AppState(
      useMetadataSettings: true,
      phoneLandscapeUseMode: PhoneLandscapeUseMode.rightSide,
      mobileSidePositionH: PhoneSidePositionH.right,
      sidewayPanelWidthPct: 40,
      sidewayPanelHeightPct: 90,
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final Rect card =
        tester.getRect(find.byKey(const Key('side-slider-panel-card')));
    // Right-handed phone landscape panel: bottom-right, 40% x 90%.
    final Rect panel = sidePanelRectForWindow(
      windowSize: const Size(800, 360),
      anchor: Alignment.bottomRight,
      isPhone: true,
      widthPct: 40,
      heightPct: 90,
      widthPx: 380,
      heightPx: 420,
    );
    expect(card.overlaps(panel), isFalse,
        reason: 'the side-type control slider must stay visible');
    expect(card.left + card.width, lessThanOrEqualTo(panel.left));

    // Switch the panel to the LEFT from inside the dialog: the card must
    // re-adjust to the opposite strip and stay off the panel.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey<String>('slider-phone-posH-segmented')),
      matching: find.text('左'),
    ));
    await tester.pumpAndSettle();

    final Rect moved =
        tester.getRect(find.byKey(const Key('side-slider-panel-card')));
    final Rect leftPanel = sidePanelRectForWindow(
      windowSize: const Size(800, 360),
      anchor: Alignment.bottomLeft,
      isPhone: true,
      widthPct: 40,
      heightPct: 90,
      widthPx: 380,
      heightPx: 420,
    );
    expect(moved.overlaps(leftPanel), isFalse);
    expect(moved.left, greaterThanOrEqualTo(leftPanel.right));
  });
}
