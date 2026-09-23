import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/store/use_app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // AppStore.onReady touches DbModule-backed stores; bootstrap a memory DB.
  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  Offset pos(double dx, double dy) => Offset(dx, dy);

  group('desktop double-tap dispatch-first', () {
    test('tagPlay layout maps the top center to playPause',
        () async {
      final layouts = defaultGestureLayoutProfiles[kLayoutRegion]!;
      final action = resolveAction(
        intent: GestureIntent.doubleTap,
        normalizedPos: pos(0.5, 0.1),
        layouts: layouts,
      );
      expect(action.type, GestureActionType.playPause);
    });

    test('the meta default layout has partitioned openTags region at bottom center (33-67% width, bottom 20%)',
        () async {
      final layouts = defaultGestureLayoutProfiles[kLayoutRegion]!;
      // Top center should be playPause
      expect(
          resolveAction(intent: GestureIntent.doubleTap, normalizedPos: pos(0.5, 0.1), layouts: layouts).type,
          GestureActionType.playPause);
      // Bottom middle tag (x: 0.5, y: 0.85)
      expect(
          resolveAction(intent: GestureIntent.doubleTap, normalizedPos: pos(0.5, 0.85), layouts: layouts).type,
          GestureActionType.openTagPlaySheet);
      // Middle playPause should not be openTags
      expect(
          resolveAction(intent: GestureIntent.doubleTap, normalizedPos: pos(0.5, 0.4), layouts: layouts).type,
          GestureActionType.playPause);
    });

    test('auto-follow: meta unified tag layout exposes openTags at bottom center regardless of active view',
        () async {
      useAppStore();
      await useAppStore().initialized;
      final app = useAppStore();
      app.set(app.state.copyWith(useMetadataSettings: true));
      addTearDown(() {
        app.set(app.state.copyWith(useMetadataSettings: false));
        useTagPlayStore().set(useTagPlayStore().state.copyWith(
              activeViewTagId: null,
              viewStackTagIds: const [],
            ));
      });

      GestureActionType bottomCenterAction(AppState state) {
        final resolved =
            useAppStore().resolveActiveGestureLayouts(state, Orientation.portrait);
        return resolveAction(
          intent: GestureIntent.doubleTap,
          normalizedPos: pos(0.5, 0.85),
          layouts: resolved,
        ).type;
      }

      // Meta unified: bottom center always openTags regardless of active view
      expect(bottomCenterAction(app.state), GestureActionType.openTagPlaySheet);

      useTagPlayStore()
          .set(useTagPlayStore().state.copyWith(activeViewTagId: 7));
      expect(bottomCenterAction(app.state), GestureActionType.openTagPlaySheet);
    });
  });
}
