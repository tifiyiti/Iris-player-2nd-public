import 'dart:async';

import 'package:flutter/services.dart';
import 'package:iris/utils/logger.dart';
import 'package:uuid/uuid.dart';

final _log = AreaKeyLog(LogKeys.appIdentity);

/// Result of the Android shortcut capability probe.
class ShortcutCapability {
  const ShortcutCapability({
    required this.sdkOk,
    required this.launcherSupportsPin,
  });

  final bool sdkOk;
  final bool launcherSupportsPin;

  bool get pinAvailable => sdkOk && launcherSupportsPin;
}

/// Dart wrapper of the native `iris/app_identity` MethodChannel (Android).
///
/// Pins/updates home-screen shortcuts and re-emits entry-launch intents
/// (cold + warm start) through [entryLaunchStream]. All failures surface as
/// [ShortcutChannelException] so callers can show explanatory dialogs.
///
/// Global singleton: the native `setMethodCallHandler` and the broadcast
/// [entryLaunchStream] must be shared by every caller (startup probe, Home
/// warm-start listener, editor apply). A per-call instance would re-register
/// the handler and let `onEntryLaunch` events land on an unsubscribed
/// controller, silently breaking warm-start activation.
class ShortcutChannelService {
  ShortcutChannelService._();

  static final ShortcutChannelService _instance = ShortcutChannelService._();

  /// The one shared instance; `ShortcutChannelService()` resolves to it so
  /// existing call sites keep working unchanged.
  static ShortcutChannelService get instance => _instance;

  factory ShortcutChannelService() => _instance;

  static const MethodChannel _channel = MethodChannel('iris/app_identity');

  /// Prefix shared with MainActivity.SHORTCUT_ID_PREFIX.
  static const String shortcutIdPrefix = 'iris_entry_';

  final StreamController<String> _launchController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  /// Broadcast stream of shortcut-tap launches (warm start included).
  Stream<String> get entryLaunchStream => _launchController.stream;

  /// Idempotently installs the native→Dart launch listener.
  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onEntryLaunch':
          final args = call.arguments as Map?;
          final id = args?['entryId'];
          if (id is String && id.isNotEmpty) {
            _log.i('entry launch: $id');
            _launchController.add(id);
          }
          return null;
        default:
          throw MissingPluginException('unknown method ${call.method}');
      }
    });
  }

  Future<ShortcutCapability> capability() async {
    try {
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('capability');
      return ShortcutCapability(
        sdkOk: raw?['sdkOk'] == true,
        launcherSupportsPin: raw?['launcherSupportsPin'] == true,
      );
    } on MissingPluginException {
      return const ShortcutCapability(sdkOk: false, launcherSupportsPin: false);
    } on PlatformException catch (e) {
      _log.w('capability probe failed: ${e.message}');
      return const ShortcutCapability(sdkOk: false, launcherSupportsPin: false);
    }
  }

  /// Pops the buffered cold-start entry id (null when absent). The native
  /// side clears its buffer on read, so this must be called exactly once.
  Future<String?> popInitialEntry() async {
    try {
      return await _channel.invokeMethod<String>('popInitialEntry');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      _log.w('popInitialEntry failed: ${e.message}');
      return null;
    }
  }

  /// Pins a NEW home-screen shortcut (system confirmation dialog appears).
  Future<void> pinShortcut({
    required String entryId,
    required String name,
    required Uint8List png,
  }) async {
    try {
      await _channel.invokeMethod<bool>('pinShortcut', {
        'id': entryId,
        'name': name,
        'png': png,
      });
    } on PlatformException catch (e) {
      throw ShortcutChannelException(e.code, e.message ?? 'pin failed');
    }
  }

  /// Updates an ALREADY-PINNED shortcut in place (no confirmation dialog).
  ///
  /// Passing a null [png] keeps the existing icon; the label always updates.
  /// Returns true when a pinned shortcut was found and updated, false when
  /// there was nothing pinned to update (the caller must not report success).
  Future<bool> updateShortcut({
    required String entryId,
    required String name,
    Uint8List? png,
  }) async {
    try {
      final updated = await _channel.invokeMethod<bool>('updateShortcut', {
        'id': entryId,
        'name': name,
        if (png != null) 'png': png,
      });
      return updated == true;
    } on PlatformException catch (e) {
      throw ShortcutChannelException(e.code, e.message ?? 'update failed');
    }
  }

  /// Returns the set of entry ids whose shortcuts are currently pinned on
  /// the home screen. Used by the manager dialog to show a live
  /// present/absent badge and offer re-generation for missing ones.
  Future<Set<String>> queryPinned() async {
    try {
      final raw = await _channel
          .invokeMethod<List<dynamic>>('queryPinned');
      final ids = raw?.whereType<String>().toList() ?? const <String>[];
      return ids.toSet();
    } on MissingPluginException {
      return const <String>{};
    } on PlatformException catch (e) {
      _log.w('queryPinned failed: ${e.message}');
      return const <String>{};
    }
  }

  /// Generates a fresh entry id (stable across edits).
  static String newEntryId() => const Uuid().v4();
}

class ShortcutChannelException implements Exception {
  const ShortcutChannelException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ShortcutChannelException($code): $message';
}
