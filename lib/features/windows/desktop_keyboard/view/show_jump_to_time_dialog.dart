import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/get_localizations.dart';

/// Jump-to-position dialog (PotPlayer `G` parity, SRS §7).
///
/// Accepts `SS`, `MM:SS`, `HH:MM:SS`.
///
/// The player is constructor-injected: this route lives on the ROOT navigator
/// where no `Provider<MediaPlayer>` exists (it is provided inside PlayerView).
Future<void> showJumpToTimeDialog(BuildContext context, MediaPlayer player) =>
    showDialog<void>(
      context: context,
      builder: (context) => JumpToTimeDialog(player: player),
    );

/// Parses `SS` / `MM:SS` / `HH:MM:SS`; null on any malformed input.
/// No per-segment or total capping — large values are allowed and normalize
/// via [Duration] (e.g. `100:00` => 100 minutes). Used for paste dispatch.
Duration? parseJumpToTimeInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) return null;
  final values = <int>[];
  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value < 0) return null;
    values.add(value);
  }
  try {
    if (values.length == 1) return Duration(seconds: values[0]);
    if (values.length == 2) {
      return Duration(minutes: values[0], seconds: values[1]);
    }
    return Duration(hours: values[0], minutes: values[1], seconds: values[2]);
  } catch (_) {
    return null;
  }
}

/// Composes a [Duration] from three hour/minute/second text fields.
///
/// Empty string is treated as `0`. No per-field capping — `mm`/`ss` may be
/// >=60 and will normalize via [Duration] (e.g. `0:100:0` => 1h40m). Returns
/// null only on non-numeric or negative input or on construction overflow.
Duration? tryComposeHMS(String hStr, String mStr, String sStr) {
  int parseOrZero(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final v = int.tryParse(t);
    if (v == null) throw const FormatException();
    return v;
  }

  try {
    final hh = parseOrZero(hStr);
    final mm = parseOrZero(mStr);
    final ss = parseOrZero(sStr);
    if (hh < 0 || mm < 0 || ss < 0) return null;
    return Duration(hours: hh, minutes: mm, seconds: ss);
  } catch (_) {
    return null;
  }
}

String _formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class JumpToTimeDialog extends HookWidget {
  const JumpToTimeDialog({super.key, required this.player});

  final MediaPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = getLocalizations(context);
    final hController = useTextEditingController();
    final mController = useTextEditingController();
    final sController = useTextEditingController();
    final hFocus = useFocusNode();
    final mFocus = useFocusNode();
    final sFocus = useFocusNode();
    final hInput = useState('');
    final mInput = useState('');
    final sInput = useState('');

    useEffect(() {
      hFocus.requestFocus();
      return null;
    }, []);

    final duration = player.duration;

    Duration? target() => tryComposeHMS(hInput.value, mInput.value, sInput.value);

    // Paste dispatch: if the freshly typed value contains ':', parse it as a
    // colon time and spread into the three boxes.
    void handlePasteDispatch(String raw, TextEditingController host) {
      if (!raw.contains(':')) return;
      final parsed = parseJumpToTimeInput(raw);
      if (parsed == null) return;
      final hh = parsed.inHours;
      final mm = parsed.inMinutes.remainder(60);
      final ss = parsed.inSeconds.remainder(60);
      // If the original had only mm:ss and hh==0, keep hour box empty/0 for
      // compactness — but filling 0 is equally clear and avoids ambiguity.
      hController.text = hh.toString();
      mController.text = mm.toString();
      sController.text = ss.toString();
      hInput.value = hController.text;
      mInput.value = mController.text;
      sInput.value = sController.text;
      // Move focus to the last box so the user can immediately press Go.
      sFocus.requestFocus();
    }

    Future<void> confirm() async {
      final seekTarget = target();
      if (seekTarget == null) return;
      // Overflow guard: beyond media length → warn with cancel-to-stay.
      // Millisecond comparison: second-truncation would zero out any media
      // under 2s and misjudge sub-second totals.
      if (duration > Duration.zero && seekTarget > duration) {
        final endMinus1 = duration.inMilliseconds <= 1000
            ? Duration.zero
            : duration - const Duration(seconds: 1);
        final navigator = Navigator.of(context);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final l10n = getLocalizations(ctx);
            return AlertDialog(
              content: Text(l10n.jump_overflow_body(
                  _formatClock(seekTarget),
                  _formatClock(duration),
                  _formatClock(endMinus1))),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.jump_cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.jump_continue),
                ),
              ],
            );
          },
        );
        if (proceed != true) {
          sFocus.requestFocus();
          return;
        }
        navigator.pop();
        try {
          await player.seek(endMinus1);
        } catch (_) {}
        return;
      }
      final navigator = Navigator.of(context);
      navigator.pop();
      try {
        await player.seek(seekTarget);
      } catch (_) {}
    }

    return AlertDialog(
      // No title — saves vertical space for landscape + keyboard.
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: hController,
                    focusNode: hFocus,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '0',
                      labelText: 'HH',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.contains(':')) {
                        handlePasteDispatch(value, hController);
                        return;
                      }
                      hInput.value = value;
                    },
                    onSubmitted: (_) => mFocus.requestFocus(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: mController,
                    focusNode: mFocus,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '00',
                      labelText: 'MM',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.contains(':')) {
                        handlePasteDispatch(value, mController);
                        return;
                      }
                      mInput.value = value;
                    },
                    onSubmitted: (_) => sFocus.requestFocus(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: sController,
                    focusNode: sFocus,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '00',
                      labelText: 'SS',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.contains(':')) {
                        handlePasteDispatch(value, sController);
                        return;
                      }
                      sInput.value = value;
                    },
                    onSubmitted: (_) => confirm(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              duration > Duration.zero
                  ? l10n.jump_current_prefix(
                      _formatClock(player.position), _formatClock(duration))
                  : l10n.jump_current_only(_formatClock(player.position)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.jump_cancel),
        ),
        FilledButton(
          onPressed: target() == null ? null : confirm,
          child: Text(l10n.jump_go),
        ),
      ],
    );
  }
}
