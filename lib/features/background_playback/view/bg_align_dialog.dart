import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/engine/background_queue_logic.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_default.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_mode.dart';
import 'package:iris/features/background_playback/model/enum/bg_exhausted_action.dart';
import 'package:iris/features/background_playback/services/background_alignment.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/virtual_media/interaction/controller/foreground_window_resolver.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:provider/provider.dart';

/// The ONE 副音 alignment editor, shared by two shells:
///
/// - the modal ask flow ([showBgAlignModal]) raised by the mandatory
///   remaining-time threshold or the 副音 menu;
/// - the quick-bar 对齐 floating card (`BgQuickPanel.align`), which stays
///   non-modal so playback keeps running underneath.
///
/// Which half of the editor a tap on one of the three shared modes targets.
///
/// Local-only UI state (never persisted): `update` seeks the running pair
/// right now, `saveDefault` only rewrites the persisted [BgAlignDefault] for
/// future alignments and leaves the running pair untouched.
enum _AlignScope { update, saveDefault }

/// It carries two semantic sections split right after the percent slider:
/// - 「对齐设置」: a scope switch (「更新对齐」 applies to the running pair
///   now vs 「默认对齐」 persists for future alignments only), the three
///   shared [BgAlignMode] anchors (00:00↔00:00, bg 00:00 at the current fg
///   moment, bg percent at the current fg moment), a hint row inside the
///   默认对齐 scope showing the current default, and a decoupled percent
///   slider (tune first, then pick the percent mode; dragging never seeks);
/// - 「其它设置」: the mandatory remaining-time threshold
///   (`alignAutoPauseRemainSec`) and the [BgExhaustedAction] taken when the
///   current 副音 file ends.
///
/// Both inline hints are dismissible forever (the X persists into
/// `AppState.suppressedWarnings`, restorable from Settings → Warning
/// dialogs), so a save stays visible at a glance with no popup until the
/// user opts out.
///
/// The content reads NO `MediaQuery` and owns no text field (the threshold
/// is still picked through a slider dialog), so it is safe in both non-modal
/// and modal shells on a phone.
class BgAlignContent extends HookWidget {
  const BgAlignContent({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final store = useBackgroundPlaybackStore();
    final engine = context.read<BackgroundPlaybackEngine>();
    useListenable(engine);

    final mode = store.select(context, (s) => s.alignMode);
    final def = store.select(context, (s) => s.alignDefault);
    // 副音 not active (gate closed): editing here is pre-configuration only —
    // hide the "update now" scope and keep the default ("takes effect next
    // alignment") surface, so the user can set it up before enabling.
    final gateOpen = store.select(context, (s) => s.gateOpen);
    final percent = store.select(context, (s) => s.alignPercent);
    final warnSec = store.select(context, (s) => s.alignAutoPauseRemainSec);
    final exhausted = store.select(context, (s) => s.bgExhaustedAction);
    // Dismiss-forever memory of the two inline hints (restorable from
    // Settings → Warning dialogs).
    final appStore = useAppStore();
    final suppressed = appStore.select(context, (s) => s.suppressedWarnings);
    final showDefaultHint =
        shouldShowWarning(suppressed, kWarningBgAlignDefaultHint);
    final showPercentHint =
        shouldShowWarning(suppressed, kWarningBgAlignPercentHint);

    // Scope + slider draft are local-only: switching scope or dragging the
    // slider rebuilds nothing outside this content and writes nothing until
    // the user commits (tap a mode / release the slider).
    final scope = useState(_AlignScope.update);
    // While the gate is shut the live "update" scope does not exist; the
    // effective scope is always the persisted default.
    final _AlignScope effective =
        gateOpen ? scope.value : _AlignScope.saveDefault;
    final percentDraft = useState(percent);
    // Re-sync when the persisted share changes elsewhere (e.g. the settings
    // page); a no-op while dragging since the store only changes on release.
    useEffect(() {
      percentDraft.value = percent;
      return null;
    }, [percent]);

    /// Applies [m] to the running pair RIGHT NOW: seeks the 副音 engine from
    /// the current physical foreground moment and records the session mode
    /// (the mirror swallows the landing). Never touches the persisted
    /// default.
    void applyUpdate(BgAlignMode m) {
      final int fgPos = fgPhysicalPositionNow(context);
      final int bgDur = engine.duration.inMilliseconds;
      // The user's alignment is AUTHORITATIVE: publish the offset BEFORE the
      // seek so the mirror keeps the pair on it instead of re-deriving one from
      // the landing (which would silently drop a non-zero offset). The linkage
      // level only decides whether bg follows the fg from here on.
      final int offset = resolveAlignmentOffsetMs(
        mode: m,
        currentFgMs: fgPos,
        bgDurMs: bgDur,
        percent: percent,
      );
      store.setAlignOffset(offset);
      store.setAlignMode(mode: m, percent: percent, rerun: false);
      // A 00:00-mode alignment whose mapped position lies BEYOND the current
      // file leaves the current fg moment with no bg: under nextBg the runtime
      // observer continues on the looping timeline (and explains it), instead of
      // parking the file at its tail.
      if (store.state.bgExhaustedAction == BgExhaustedAction.nextBg &&
          bgDur > 0 &&
          fgPos - offset >= bgDur) {
        store.noteSystemSeek();
        store.requestBgContinuation(fromAlign: true);
        return;
      }
      final int target = bgAlignTargetMs(
        mode: m,
        fgPosMs: fgPos,
        bgDurMs: bgDur,
        percent: percent,
      );
      store.noteSystemSeek();
      unawaited(engine.seek(Duration(milliseconds: target)));
      store.clearBgExhausted();
    }

    /// Persists [m] as the default for future alignments. Deliberately
    /// seek-free: the running pair keeps playing exactly as it was.
    void saveDefault(BgAlignMode m) {
      unawaited(store.setAlignDefault(defaultForAlignMode(m)));
    }

    void onModeTap(BgAlignMode m) {
      if (effective == _AlignScope.update) {
        applyUpdate(m);
      } else {
        saveDefault(m);
      }
    }

    // Each scope highlights its own current value, so the two never read as
    // duplicates: update shows the running mode, default shows the persisted
    // one.
    bool modeSelected(BgAlignMode m) => effective == _AlignScope.update
        ? mode == m
        : def == defaultForAlignMode(m);

    String defaultLabel() => switch (def) {
          BgAlignDefault.fgHead => t.bg_align_default_fg_head,
          BgAlignDefault.fgPosition => t.bg_align_default_fg_position,
          BgAlignDefault.bgPercent =>
            t.bg_align_mode_bg_percent_value(percent),
        };

    Future<void> editWarn() async {
      final v = await _showIntSliderDialog(
        context,
        title: t.bg_align_auto_pause_label,
        value: warnSec,
        min: kMinAlignWarnRemainSec,
        max: kMaxAlignWarnRemainSec,
        suffix: t.bg_align_percent_suffix_short,
      );
      if (v == null) return;
      await store.setAlignAutoPauseRemainSec(v);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, t.bg_align_section_align),
          // Gate shut: no 副音 is running, so the update-now scope is hidden —
          // only the persisted default (for the next activation) is editable.
          if (gateOpen)
            SegmentedButton<_AlignScope>(
              segments: [
                ButtonSegment(
                  value: _AlignScope.update,
                  label: Text(t.bg_align_scope_update),
                ),
                ButtonSegment(
                  value: _AlignScope.saveDefault,
                  label: Text(t.bg_align_scope_default),
                ),
              ],
              selected: {scope.value},
              onSelectionChanged: (s) => scope.value = s.first,
            ),
          const SizedBox(height: 8),
          _radio(
            context,
            selected: modeSelected(BgAlignMode.fromFgHead),
            title: t.bg_align_mode_from_fg_head,
            onTap: () => onModeTap(BgAlignMode.fromFgHead),
          ),
          const SizedBox(height: 4),
          _radio(
            context,
            selected: modeSelected(BgAlignMode.atFgPosition),
            title: t.bg_align_mode_at_position,
            onTap: () => onModeTap(BgAlignMode.atFgPosition),
          ),
          const SizedBox(height: 4),
          _radio(
            context,
            selected: modeSelected(BgAlignMode.bgPercent),
            title: t.bg_align_mode_bg_percent_value(percent),
            onTap: () => onModeTap(BgAlignMode.bgPercent),
          ),
          // The default hint lives only in the 默认对齐 scope: it explains
          // the pending default and makes a save visible at a glance, while
          // the 更新对齐 scope stays a pure seek surface. With the gate shut it
          // is ALWAYS shown (and its dismiss X removed): it carries the only
          // framing the user sees — this setting applies on the next start.
          if (effective == _AlignScope.saveDefault &&
              (showDefaultHint || !gateOpen)) ...[
            const SizedBox(height: 8),
            _defaultHint(
              context,
              current: t.bg_align_default_current(defaultLabel()),
              note: t.bg_align_default_effect_hint,
              hideTooltip: t.bg_align_hint_hide_forever,
              onHide: gateOpen
                  ? () => unawaited(
                        appStore.suppressWarning(kWarningBgAlignDefaultHint),
                      )
                  : null,
            ),
          ],
          const Divider(height: 24),

          _PercentSlider(
            draft: percentDraft.value,
            showHint: showPercentHint,
            hideTooltip: t.bg_align_hint_hide_forever,
            onChanged: (v) =>
                percentDraft.value = v.round().clamp(0, 100),
            onCommit: (v) => unawaited(
              store.setAlignPercent(v.round().clamp(0, 100)),
            ),
            onHideHint: () => unawaited(
              appStore.suppressWarning(kWarningBgAlignPercentHint),
            ),
          ),
          // Semantic boundary: everything above is 对齐设置, everything below
          // is 其它设置.
          const Divider(height: 24),
          _sectionTitle(context, t.bg_align_section_other),
          ListTile(
            key: const ValueKey('bg_align_warn_row'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.timer_outlined, size: 20),
            title: Text(t.bg_align_auto_pause_label),
            subtitle: Text(t.bg_align_auto_pause_desc),
            trailing: Text(t.bg_align_auto_pause_seconds(warnSec)),
            onTap: () => unawaited(editWarn()),
          ),
          const Divider(height: 24),

          _sectionTitle(context, t.bg_exhausted_section),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              t.bg_exhausted_section_note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          _radio(
            context,
            selected: exhausted == BgExhaustedAction.nextBg,
            title: t.bg_exhausted_next_bg,
            onTap: () => unawaited(
                store.setBgExhaustedAction(BgExhaustedAction.nextBg)),
          ),
          const SizedBox(height: 4),
          _radio(
            context,
            selected: exhausted == BgExhaustedAction.stopRestoreFg,
            title: t.bg_exhausted_stop_restore,
            onTap: () => unawaited(
                store.setBgExhaustedAction(BgExhaustedAction.stopRestoreFg)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  /// The default hint (默认对齐 scope only): shows the current persisted
  /// default plus the "next alignment, current playback untouched" note, so
  /// a save is visible at a glance with no popup. The X hides it forever
  /// (restorable from Settings → Warning dialogs).
  Widget _defaultHint(
    BuildContext context, {
    required String current,
    required String note,
    required String hideTooltip,
    VoidCallback? onHide,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(current, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onHide != null)
            _hintHideButton(
              key: const ValueKey('bg_align_default_hint_hide'),
              tooltip: hideTooltip,
              onHide: onHide,
            ),
        ],
      ),
    );
  }

  /// Compact 24px dismiss button shared by the inline hints: tap hides
  /// forever (persisted), long-press/hover explains where to bring it back.
  static Widget _hintHideButton({
    required Key key,
    required String tooltip,
    required VoidCallback onHide,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: onHide,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close_rounded, size: 16),
        ),
      ),
    );
  }

  Widget _radio(
    BuildContext context, {
    required bool selected,
    required String title,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// The decoupled percent tuner: dragging only moves the local [draft] (the
/// parent owns it, so ticks rebuild just this leaf), and the persisted
/// `alignPercent` is written once on release — Drift runs on the UI isolate,
/// so per-tick writes would jank phones. Picking the percent anchor mode
/// afterwards applies the committed share; the slider itself never seeks.
class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.draft,
    required this.showHint,
    required this.hideTooltip,
    required this.onChanged,
    required this.onCommit,
    required this.onHideHint,
  });

  final int draft;
  final bool showHint;
  final String hideTooltip;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;
  final VoidCallback onHideHint;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.percent_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.bg_align_percent_title,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '$draft${t.bg_align_percent_suffix_short}',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        Slider(
          key: const ValueKey('bg_align_percent_slider'),
          value: draft.clamp(0, 100).toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: '$draft${t.bg_align_percent_suffix_short}',
          onChanged: onChanged,
          onChangeEnd: onCommit,
        ),
        if (showHint)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.bg_align_percent_adjust_hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              BgAlignContent._hintHideButton(
                key: const ValueKey('bg_align_percent_hint_hide'),
                tooltip: hideTooltip,
                onHide: onHideHint,
              ),
            ],
          ),
      ],
    );
  }
}

/// Opens the alignment editor as a MODAL ask, pausing both runtimes for the
/// duration and restoring the previous transport on close.
Future<void> showBgAlignModal(
  BuildContext context, {
  required BackgroundPlaybackEngine engine,
  required MediaPlayer fgPlayer,
}) async {
  final store = useBackgroundPlaybackStore();
  final bool fgWasPlaying = fgPlayer.isPlaying;
  final bool bgWasPlaying = engine.isPlaying;
  // The file open under the prompt: natural completion may advance the queue
  // behind the dialog (the runtime observer stands down while it is up), in
  // which case the newcomer needs one alignment on close (see below).
  final String? entryKey =
      engine.file == null ? null : backgroundMediaKey(engine.file!);
  await engine.pause();
  await fgPlayer.pause();
  store.setPlaying(false);
  if (!context.mounted) {
    await _restoreModal(store, engine, fgPlayer,
        fgWasPlaying: fgWasPlaying, bgWasPlaying: bgWasPlaying);
    return;
  }
  final t = getLocalizations(context);
  // Beats any late open/autoplay that landed behind the dialog; cancelled when
  // it closes so it can never re-pause an already-restored pair.
  final pauseHold = Timer(const Duration(milliseconds: 150), () {
    unawaited(engine.pause());
    unawaited(fgPlayer.pause());
  });
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final w = MediaQuery.sizeOf(dialogContext).width;
        final h = MediaQuery.sizeOf(dialogContext).height;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (w - 24).clamp(0.0, 560.0),
              maxHeight: h * 0.9,
            ),
            // The content is provider-driven (engine + foreground player are
            // captured above and re-provided here, since the dialog's context
            // sits above the player subtree).
            child: Provider<MediaPlayer>.value(
              value: fgPlayer,
              child: ChangeNotifierProvider<BackgroundPlaybackEngine>.value(
                value: engine,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.bg_align_title,
                              style: Theme.of(dialogContext).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Flexible(child: BgAlignContent()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(),
                          child: Text(t.ok),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  } finally {
    pauseHold.cancel();
  }
  await _restoreModal(store, engine, fgPlayer,
      fgWasPlaying: fgWasPlaying, bgWasPlaying: bgWasPlaying);
  // A completion behind the dialog leaves the new file unaligned (the runtime
  // observer was stood down): align it once now, with the current mode.
  final String? exitKey =
      engine.file == null ? null : backgroundMediaKey(engine.file!);
  if (context.mounted &&
      modalCloseNeedsRealign(
        entryKey: entryKey,
        exitKey: exitKey,
        enabled: store.state.enabled,
        bgExhausted: store.state.bgExhausted,
      )) {
    final int target = bgAlignTargetMs(
      mode: store.state.alignMode,
      fgPosMs: fgPhysicalPositionNow(context),
      bgDurMs: engine.duration.inMilliseconds,
      percent: store.state.alignPercent,
    );
    if (target > 0) {
      store.noteSystemSeek();
      unawaited(engine.seek(Duration(milliseconds: target)));
    }
    store.clearBgExhausted();
  }
}

Future<void> _restoreModal(
  BackgroundPlaybackStore store,
  BackgroundPlaybackEngine engine,
  MediaPlayer fgPlayer, {
  required bool fgWasPlaying,
  required bool bgWasPlaying,
}) async {
  if (fgWasPlaying) await fgPlayer.play();
  if (shouldRestoreBgAfterModal(
    bgWasPlaying: bgWasPlaying,
    bgExhausted: store.state.bgExhausted,
    gateOpen: store.state.gateOpen,
  )) {
    store.setPlaying(true);
    await engine.play();
  }
}

/// A phone-safe integer slider dialog (no text field, no IME). Returns the
/// picked value, or null when cancelled.
Future<int?> _showIntSliderDialog(
  BuildContext context, {
  required String title,
  required int value,
  required int min,
  required int max,
  required String suffix,
}) {
  final t = getLocalizations(context);
  var draft = value.clamp(min, max);
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) {
        final w = MediaQuery.sizeOf(dialogContext).width;
        final h = MediaQuery.sizeOf(dialogContext).height;
        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          title: Text(title),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (w - 24).clamp(0.0, 560.0),
              maxHeight: h * 0.9,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$draft$suffix'),
                  Slider(
                    value: draft.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: (max - min) <= 0 ? null : (max - min),
                    label: '$draft$suffix',
                    onChanged: (v) =>
                        setLocal(() => draft = v.round().clamp(min, max)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(draft),
              child: Text(t.ok),
            ),
          ],
        );
      },
    ),
  );
}
