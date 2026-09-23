import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/def_visibility.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/view/widgets/editor_bindings.dart';
import 'package:iris/features/meta_settings/view/widgets/setting_editors.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';

void main() {
  group('tag_play meta rows', () {
    test('catalog carries the custom rows and merges without conflicts', () {
      // Reading the catalog runs the fail-fast merger — duplicates or invalid
      // defs throw here.
      final keys = SettingsCatalog.defs
          .where((d) => d.key.startsWith('tagplay.'))
          .toList();
      expect(keys, hasLength(3));
      expect(
        keys.map((d) => d.key),
        containsAll([
          'tagplay.inputBar',
          'tagplay.inputHint',
          'tagplay.viewStackEnabled',
        ]),
      );
      for (final d in keys) {
        expect(d.widgetKind, SettingWidgetKind.custom,
            reason: 'non-app.* rows must never use the generic renderers');
        expect(d.editorKey, isNotNull);
      }
      // Exactly one row leads the group (a second leader would be a merge bug).
      expect(keys.where((d) => d.groupHeaderKey != null), hasLength(1));
      expect(keys.first.groupHeaderKey, 'group_tag_play');
    });

    test('the return-stack row ships OFF by default', () {
      final def = SettingsCatalog.defs
          .firstWhere((d) => d.key == 'tagplay.viewStackEnabled');
      expect(def.defaultValue, 'false');
      expect(def.editorKey, 'tagplay_view_stack');

      // The gate both the controller and the sheet read follows the store.
      final store = useTagPlayStore();
      store.set(store.state.copyWith(viewStackEnabled: false));
      expect(TagPlayGate.viewStackEnabled, isFalse);
      store.set(store.state.copyWith(viewStackEnabled: true));
      expect(TagPlayGate.viewStackEnabled, isTrue);
      store.set(store.state.copyWith(viewStackEnabled: false));
    });

    test('the hint row ships desktop-only; the bar and the return stack '
        'stay available to phones', () {
      final hint = SettingsCatalog.defs
          .firstWhere((d) => d.key == 'tagplay.inputHint');
      expect(hint.platforms, containsAll(['windows', 'linux', 'macos']));
      expect(hint.platforms, isNot(contains('android')));
      expect(hint.platforms, isNot(contains('ios')));
      // The phone-side opt-in and the cross-platform return stack keep no
      // platform gate.
      final bar = SettingsCatalog.defs
          .firstWhere((d) => d.key == 'tagplay.inputBar');
      expect(bar.platforms, isEmpty);
      final stack = SettingsCatalog.defs
          .firstWhere((d) => d.key == 'tagplay.viewStackEnabled');
      expect(stack.platforms, isEmpty);
    });

    test('every tag_play editor key has a registered binding', () {
      EditorBindings.ensureRegistered();
      for (final key in [
        'tagplay_input_bar',
        'tagplay_input_hint',
        'tagplay_view_stack',
      ]) {
        expect(SettingEditors.lookup(key), isNotNull,
            reason: '$key must have a hand-written editor binding');
      }
    });

    test('DefVisibility prefix gates the rows on the feature gate', () {
      DefVisibility.registerPrefix('tagplay.', () => TagPlayGate.enabled);
      // A registered prefix never hides other keys…
      expect(DefVisibility.isVisible('gesture.x'), isTrue);
      // …and the predicate is evaluated lazily per render (flip + re-check).
      var on = true;
      DefVisibility.registerPrefix('tagplay.', () => on);
      expect(DefVisibility.isVisible('tagplay.viewStackEnabled'), isTrue);
      on = false;
      expect(DefVisibility.isVisible('tagplay.viewStackEnabled'), isFalse);
      DefVisibility.registerPrefix('tagplay.', () => true);
    });
  });
}
