import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/services/shortcut_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('iris/app_identity');

  group('ShortcutChannelService singleton', () {
    test('factory returns the same instance every time', () {
      final a = ShortcutChannelService();
      final b = ShortcutChannelService();
      final c = ShortcutChannelService.instance;
      expect(identical(a, b), isTrue,
          reason: 'a per-call instance would re-register the method channel '
              'handler and break warm-start launch routing');
      expect(identical(a, c), isTrue);
    });

    test('launch stream is broadcast (shared controller, multiple listeners)',
        () {
      // BroadcastStreamController.stream creates a fresh Stream wrapper per
      // call, but they all feed the SAME underlying controller — a single
      // subscription on any access point receives every launch event. The
      // non-single-subscription nature is the contract Home relies on.
      final s1 = ShortcutChannelService();
      final s2 = ShortcutChannelService();
      expect(s1.entryLaunchStream.isBroadcast, isTrue);
      expect(s2.entryLaunchStream.isBroadcast, isTrue);
    });

    test('newEntryId is stable per call and unique across calls', () {
      final a = ShortcutChannelService.newEntryId();
      final b = ShortcutChannelService.newEntryId();
      expect(a, isNotEmpty);
      expect(a, isNot(b));
    });
  });

  group('ShortcutChannelService.updateShortcut result', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns false when no pinned shortcut was updated (native false)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'updateShortcut');
        return false;
      });
      final updated = await ShortcutChannelService()
          .updateShortcut(entryId: 'e', name: 'E');
      expect(updated, isFalse,
          reason: 'a no-op update must not be reported as success, otherwise '
              'the UI claims an icon was regenerated when none exists');
    });

    test('returns true when a pinned shortcut was updated', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      final updated = await ShortcutChannelService()
          .updateShortcut(entryId: 'e', name: 'E');
      expect(updated, isTrue);
    });
  });
}
