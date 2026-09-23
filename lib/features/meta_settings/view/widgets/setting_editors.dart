import 'package:flutter/material.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// Builder signature for hand-written editors (custom rows).
///
/// Receives the def so one builder can serve several keys; returns the row
/// widget itself (typically a ListTile whose onTap opens a legacy dialog).
typedef SettingEditorBuilder = Widget Function(
  BuildContext context,
  SettingDef def,
);

/// Registry of hand-written editors, keyed by `editorKey`.
///
/// Wiring code (editor_bindings.dart) populates this at startup; the renderer
/// only looks entries up. A missing entry renders an inert placeholder tile —
/// never a crash — so defs and bindings can land in separate commits.
abstract final class SettingEditors {
  static final Map<String, SettingEditorBuilder> _builders =
      <String, SettingEditorBuilder>{};

  static void register(String editorKey, SettingEditorBuilder builder) =>
      _builders[editorKey] = builder;

  static void registerAll(Map<String, SettingEditorBuilder> builders) =>
      _builders.addAll(builders);

  static SettingEditorBuilder? lookup(String? editorKey) =>
      editorKey == null ? null : _builders[editorKey];

  /// Every registered editorKey — used by the stale-binding guard test.
  static Iterable<String> get registeredKeys => _builders.keys;
}
