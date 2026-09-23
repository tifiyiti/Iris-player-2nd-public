/// Scenario playback log channels.
///
/// Key naming: `log.<domain>.<sub>` — the `log.` prefix marks a logger name as
/// a channel (mirrors Android tags / node-logger namespaces). Dot-separated
/// names are hierarchical in `package:logging`: setting a level on [group]
/// (`log.scenario`) applies to every `log.scenario.*` child that does not set
/// its own level.
///
/// NEVER hardcode a key string at a call site — always reference these
/// constants, so gating tooling (`Log.only` / `Log.setEnabled`) sees one
/// stable registry of channels.
abstract final class ScenarioLogKeys {
  /// Parent channel — enabling this enables every `log.scenario.*` child.
  static const String group = 'log.scenario';

  /// Scenario DB writes + in-memory occurrence mirror.
  static const String store = 'log.scenario.store';

  /// Playback provider: current-item locate, next/previous stepping.
  static const String playback = 'log.scenario.playback';

  /// Queue page rendering + current-item highlight.
  static const String queue = 'log.scenario.queue';

  /// Resolver effective-queue matching.
  static const String resolve = 'log.scenario.resolve';
}

/// Development diag channels for the scenario playback feature are enabled by
/// default (debug builds) so the current fix can be verified on-device. Set to
/// `false` once verified to silence them WITHOUT touching any call site.
// CLOSE_DEBUG_LOG: set to false to silence all log.scenario.* diag channels.
const bool scenarioDiagLogsEnabled = true;
