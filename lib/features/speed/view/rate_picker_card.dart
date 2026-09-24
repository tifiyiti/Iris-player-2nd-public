import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/speed/model/speed_rate_scale_math.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/draggable_dialog_shell.dart';

/// What a picker body may do with the rate.
class RatePickerHandles {
  const RatePickerHandles({
    required this.current,
    required this.preview,
    required this.apply,
  });

  /// Live store rate; the body rebuilds as it changes.
  final double current;

  /// Applies [value] to playback WITHOUT persisting. The card commits it on
  /// Save and rolls it back on Cancel, the barrier tap or Esc.
  final ValueChanged<double> preview;

  /// Persists [value] and closes at once — no Save step and no rollback. The
  /// flat list has always applied on tap and must not gain a confirmation.
  final ValueChanged<double> apply;
}

/// Opens [card] in the shared draggable shell, restoring the remembered spot.
///
/// All picker shapes go through here, so a position the user parks applies to
/// whichever picker is current.
Future<void> showDraggableRateCard(BuildContext context, Widget card) {
  final AppStore store = useAppStore();
  final Offset initial = store.state.speedRateDialogOffset;
  final String label = getLocalizations(context).playback_speed;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.black38,
    pageBuilder: (_, __, ___) => DraggableDialogShell(
      initialFraction: initial,
      onCommit: (Offset f) {
        // ignore: discarded_futures
        store.updateSpeedRateDialogOffset(f);
      },
      child: card,
    ),
  );
}

/// Horizontal space kept clear on each side of the card.
///
/// The card stretches to its constraint, so without this it runs edge to edge
/// on a phone and stops reading as a dialog at all.
const double kRateCardSideMargin = 32.0;

/// Widest the card may ever get, however much room is on offer.
const double kRateCardMaxWidth = 420.0;

/// Tallest the card may get, as a share of the viewport.
const double kRateCardMaxHeightFactor = 0.60;

/// Opacity of the card surface.
///
/// The card floats over live video, where an opaque panel reads as a foreign
/// slab. Deliberately WITHOUT a `BackdropFilter`, which is what the control
/// bar does too: it is a plain scrim, and a blur would re-composite the whole
/// card area on every frame while the video keeps playing.
const double kRateCardSurfaceOpacity = 0.82;

/// Alpha of the hairline that defines the card edge.
///
/// The border, not a drop shadow, is what separates a translucent surface from
/// the video behind it — a heavy shadow under translucency reads as a dark
/// halo (see `lib/widgets/card.dart`, which draws no shadow at all).
const double kRateCardBorderAlpha = 0.125;

/// The card every playback-speed picker renders in: a draggable title row, the
/// variant's own controls, and the action row.
///
/// The rate is PREVIEWED live while the controls move, so the new speed is
/// audible immediately, but it never reaches storage until Save. Cancel, the
/// barrier tap and Esc all roll back to the rate the card opened with, in ONE
/// place (the unmount cleanup) — including `rateBeforeReset`, which
/// `applyRateChange` rewrites on every non-1.0 write.
class RatePickerCard extends HookWidget {
  const RatePickerCard({
    super.key,
    required this.buildContent,
    this.actionsBuilder,
    this.maxWidth,
  });

  /// Builds the controls under the title row.
  final Widget Function(BuildContext context, RatePickerHandles handles)
      buildContent;

  /// Replaces the default Cancel / Save row — the flat list offers Cancel
  /// alone, because a tap already applies.
  final List<Widget> Function(BuildContext context)? actionsBuilder;

  /// Narrows the card further than [kRateCardMaxWidth] allows.
  ///
  /// The label slider wants every pixel of its track, but a wheel column only
  /// ever holds one or two digits and looks stretched when it gets the same
  /// width — so the wheel variant asks for less.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final ThemeData theme = Theme.of(context);
    final Size viewport = MediaQuery.sizeOf(context);
    final AppStore store = useAppStore();
    final double current = store.select(context, (s) => s.rate);
    // Captured once, on the first build: the rate (and the Z-key restore
    // memory, which every non-1.0 write rewrites) as they were on arrival.
    final ValueNotifier<({double rate, double rateBeforeReset})> origin =
        useState<({double rate, double rateBeforeReset})>(
      (rate: store.state.rate, rateBeforeReset: store.state.rateBeforeReset),
    );
    final ValueNotifier<bool> settled = useState<bool>(false);

    // Covers EVERY dismissal path — Cancel, barrier tap, Esc — without having
    // to mirror the logic in each one. Save and apply set `settled` first so
    // the cleanup stands down.
    useEffect(
      () => () {
        if (settled.value) return;
        store.rollbackRatePreview(
          rate: origin.value.rate,
          rateBeforeReset: origin.value.rateBeforeReset,
        );
      },
      const <Object?>[],
    );

    void preview(double value) => store.updateRateLive(value);

    void apply(double value) {
      settled.value = true;
      unawaited(store.updateRate(value));
      Navigator.pop(context);
    }

    Future<void> save() async {
      settled.value = true;
      await store.commitRate();
      if (context.mounted) Navigator.pop(context);
    }

    final RatePickerHandles handles = RatePickerHandles(
      current: current,
      preview: preview,
      apply: apply,
    );

    final List<Widget> actions = actionsBuilder?.call(context) ?? <Widget>[
      TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () => Navigator.pop(context),
        child: Text(t.cancel),
      ),
      FilledButton(
        // Compact density trims ~4px of padding per side, which is what lets
        // the narrowed wheel card keep both buttons on one line.
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: save,
        child: Text(t.save),
      ),
    ];

    return Material(
      key: const ValueKey('rate_picker_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.onSurfaceVariant
              .withValues(alpha: kRateCardBorderAlpha),
        ),
      ),
      color: theme.colorScheme.surfaceContainerHigh
          .withValues(alpha: kRateCardSurfaceOpacity),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            maxWidth ?? kRateCardMaxWidth,
            math.max(160.0, viewport.width - kRateCardSideMargin * 2),
          ),
          maxHeight: viewport.height * kRateCardMaxHeightFactor,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CardHeader(
                title: t.rate_picker_title(formatSpeedLabel(current)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: buildContent(context, handles),
                ),
              ),
              const SizedBox(height: 12),
              // Wrap, not Row: the buttons' natural width is locale- and
              // text-scale-dependent (the wheel card is deliberately narrow,
              // and German action labels alone need ~210px). Wrapping is the
              // graceful outcome; overflowing is not. With room to spare it
              // lays out exactly like a right-aligned Row.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The title row, which doubles as the drag surface.
///
/// One row rather than a separate grab bar above the title: the repo's other
/// draggable dialogs (`DraggableFloatingCard`, the side-panel editor) already
/// put the handle inline with their title, and a dedicated bar wasted a whole
/// row of height on a phone.
///
/// A descendant of the shell rather than the card itself, so a pan here can
/// never steal a slider drag or a wheel spin from the controls below.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DraggableDialogScope? scope = DraggableDialogScope.maybeOf(context);
    final Widget row = Row(
      children: <Widget>[
        Icon(
          Icons.drag_indicator_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    // Vertical padding is what makes the row a real touch target; the icon
    // itself is only 18px tall.
    const EdgeInsets pad = EdgeInsets.symmetric(vertical: 6);
    if (scope == null) return Padding(padding: pad, child: row);
    return Semantics(
      label: getLocalizations(context).rate_picker_drag,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          key: const ValueKey('rate_picker_drag_handle'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (DragUpdateDetails details) =>
              scope.onDragUpdate(details.delta),
          onPanEnd: (_) => scope.onDragEnd(),
          onPanCancel: scope.onDragEnd,
          child: Padding(padding: pad, child: row),
        ),
      ),
    );
  }
}
