// Part of editor_bindings.dart - row widgets for the tag-play store.
part of '../editor_bindings.dart';

/// Input-bar row for tag play: phones can toggle it (default off — the rows
/// are tappable), desktop is locked ON because the numpad entry keys need it.
class _TagPlayInputBarTile extends HookWidget {
  const _TagPlayInputBarTile();

  @override
  Widget build(BuildContext context) {
    final store = useTagPlayStore();
    final bool stored = store.select(context, (s) => s.inputBarEnabled);
    final t = getLocalizations(context);
    final bool value =
        resolveTagPlayInputBarEnabled(stored: stored, isDesktop: isDesktop);

    return ListTile(
      leading: const Icon(Icons.keyboard_rounded),
      title: Text(SettingTexts.title('set_tag_play_input_bar', t)),
      subtitle: Text(isDesktop
          ? t.set_tag_play_input_bar_forced
          : SettingTexts.subtitle('set_tag_play_input_bar_desc', t)),
      trailing: Switch(
        value: value,
        onChanged: isDesktop
            ? null
            : (bool v) => unawaited(store.setInputBarEnabled(v)),
      ),
      // Locked rows must still explain themselves: the greyed switch is the
      // point, but a dead tap target reads as a broken row.
      onTap: isDesktop
          ? () => showMessageDialog(
                Navigator.of(context, rootNavigator: true),
                message: t.set_tag_play_input_bar_forced,
                type: MessageDialogType.info,
              )
          : () => unawaited(store.setInputBarEnabled(!value)),
    );
  }
}

/// Hint-banner row: toggling it off is the banner's "permanently close"
/// outcome; turning it back on lifts the session-only dismissal too.
class _TagPlayHintTile extends HookWidget {
  const _TagPlayHintTile();

  @override
  Widget build(BuildContext context) {
    final store = useTagPlayStore();
    final bool enabled = store.select(context, (s) => s.inputHintEnabled);
    final t = getLocalizations(context);

    return ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: Text(SettingTexts.title('set_tag_play_input_hint', t)),
      subtitle: Text(SettingTexts.subtitle('set_tag_play_input_hint_desc', t)),
      trailing: Switch(
        value: enabled,
        onChanged: (bool v) => unawaited(store.setInputHintEnabled(v)),
      ),
      onTap: () => unawaited(store.setInputHintEnabled(!enabled)),
    );
  }
}

/// "Previous view" return row: opt-in. OFF by default because the sheet's
/// radio already shows the active tag, so jumping back is optional.
class _TagPlayViewStackTile extends HookWidget {
  const _TagPlayViewStackTile();

  @override
  Widget build(BuildContext context) {
    final store = useTagPlayStore();
    final bool enabled = store.select(context, (s) => s.viewStackEnabled);
    final t = getLocalizations(context);

    return ListTile(
      leading: const Icon(Icons.undo_rounded),
      title: Text(SettingTexts.title('set_tag_play_view_stack', t)),
      subtitle: Text(SettingTexts.subtitle('set_tag_play_view_stack_desc', t)),
      trailing: Switch(
        value: enabled,
        onChanged: (bool v) => unawaited(store.setViewStackEnabled(v)),
      ),
      onTap: () => unawaited(store.setViewStackEnabled(!enabled)),
    );
  }
}
