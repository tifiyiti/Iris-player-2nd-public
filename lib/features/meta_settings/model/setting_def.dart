import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';

part 'setting_def.freezed.dart';

/// Declarative description of ONE setting — "what a setting is".
///
/// Pure data: no rendering, persistence, or behavior lives here. The generic
/// renderer consumes [widgetKind]; storage consumes [valueType] via ValueCodec;
/// visibility consumes [platforms]. Authority for these rows is the typed Dart
/// contribution lists; the DB mirror exists only to be queryable.
///
/// BEHAVIORAL METADATA ([writable], [clampMin], [clampMax], [mutatorKey]) is
/// intentionally NOT mirrored into the setting_defs table: the typed Dart
/// contributions are the single authority for behavior, and keeping these
/// columns out of the schema means contract evolution never needs a DB
/// migration.
@freezed
abstract class SettingDef with _$SettingDef {
  const factory SettingDef({
    /// Dotted namespace key, e.g. 'app.themeMode'.
    required String key,
    required SettingsSection section,
    required SettingValueType valueType,

    /// Whether the engine may mutate this field from metadata paths.
    /// false marks read-only / code-managed fields; absent defs are equally
    /// unwritable, this flag documents INTENTIONALLY locked known fields.
    @Default(true) bool writable,

    /// Inclusive numeric bounds enforced by ValueGuard on EVERY metadata-path
    /// write. Must stay in sync with the typed mutator's own clamp — the
    /// parity test asserts both derive identical results. Only valid on
    /// int/double valueType; null = unbounded on that side.
    num? clampMin,
    num? clampMax,

    /// Registry key of a post-write side effect (see EffectsRegistry). The
    /// effect receives the APPLIED state, letting metadata rows reproduce
    /// typed-mutator side effects (backend switching, cache invalidation)
    /// without the renderer knowing about them.
    ///
    /// RESERVED: no catalog def declares a mutatorKey today, so the engine's
    /// `EffectsRegistry.run(def.mutatorKey, ...)` is a no-op. The registry is
    /// still live — typed mutators call it directly (e.g.
    /// `toggleUseLegacyStoragePersistence`). Wire a def here only when a
    /// metadata-row write must reproduce a typed side effect.
    String? mutatorKey,

    /// ValueCodec-encoded default; null means "no default declared" and
    /// readers fall back to the typed facade default.
    String? defaultValue,

    /// Allowed enum value NAMES; required when valueType == enumeration.
    @Default(<String>[]) List<String> enumValues,
    required SettingWidgetKind widgetKind,

    /// Hand-written editor registry key; required for custom, else null.
    String? editorKey,

    /// Existing ARB key reused from the legacy catalog.
    required String titleKey,
    String? subtitleKey,

    /// Icon-map key resolved by the view layer (setting_icons.dart); null =
    /// generic-rendered rows draw no leading icon. Kept as a string so defs
    /// stay DB-serializable.
    String? iconKey,

    /// Group-label key; when non-null the renderer starts a new visual group
    /// at this def (divider + header above it).
    String? groupHeaderKey,

    /// Platform names ('android'|'windows'|'linux'|'macos'|'ios');
    /// empty = every platform.
    @Default(<String>[]) List<String> platforms,
    required int sortOrder,
  }) = _SettingDef;
}
