import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/windows/desktop_control_bar/controller/resolve_desktop_control_bar_layout.dart';
import 'package:iris/models/store/app_state.dart';

/// Degradation contract for the desktop control-bar layout setting.
///
/// Mirrors resolveKeyboardScheme: the SHIPPED default is the new `stacked`
/// bar, but while the metadata gate is OFF any stored selection degrades to
/// the classic single-line bar instead of leaking new behavior to
/// legacy-blob users.
void main() {
  group('shipped default polarity', () {
    test('fresh AppState defaults to stacked (meta-era default)', () {
      expect(
        const AppState().desktopControlBarLayout,
        DesktopControlBarLayout.stacked,
      );
    });

    test('contribution def default matches the shipped AppState default',
        () {
      final def = SettingsCatalog.defs
          .singleWhere((d) => d.key == 'app.desktopControlBarLayout');
      expect(def.defaultValue, 'stacked');
    });
  });

  group('resolveDesktopControlBarLayout', () {
    test('gate OFF forces singleLine regardless of stored value', () {
      expect(
        resolveDesktopControlBarLayout(
          stored: DesktopControlBarLayout.stacked,
          metadataEnabled: false,
        ),
        DesktopControlBarLayout.singleLine,
      );
      expect(
        resolveDesktopControlBarLayout(
          stored: DesktopControlBarLayout.singleLine,
          metadataEnabled: false,
        ),
        DesktopControlBarLayout.singleLine,
      );
    });

    test('gate ON honors the stored layout', () {
      expect(
        resolveDesktopControlBarLayout(
          stored: DesktopControlBarLayout.stacked,
          metadataEnabled: true,
        ),
        DesktopControlBarLayout.stacked,
      );
      expect(
        resolveDesktopControlBarLayout(
          stored: DesktopControlBarLayout.singleLine,
          metadataEnabled: true,
        ),
        DesktopControlBarLayout.singleLine,
      );
    });
  });
}
