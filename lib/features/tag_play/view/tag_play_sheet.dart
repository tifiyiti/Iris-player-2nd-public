import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/tag_play/model/domain/tag_command.dart';
import 'package:iris/features/tag_play/model/domain/tag_media_counts.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_ordering.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/features/tag_play/playback/tag_command_runner.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/features/tag_play/playback/tag_play_input_policy.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/features/tag_play/view/dialogs/show_create_tag_dialog.dart';
import 'package:iris/features/tag_play/view/dialogs/show_pin_preset_dialog.dart';
import 'package:iris/features/tag_play/view/dialogs/show_tag_management_dialog.dart';
import 'package:iris/features/tag_play/view/widgets/tag_input_bar.dart';
import 'package:iris/features/tag_play/view/widgets/tag_input_hint_banner.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart' show ContentType, FileItem;
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_inset_padder.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

/// The tag play sheet: the tag list, plus (on desktop, and on phones that opt
/// in) a numeric command bar.
///
/// Every row leads with a RADIO — selecting it makes that tag's play view the
/// exclusive active one, and row 0 ("no tag") is the default selection,
/// mirroring the original scenario list. The row body toggles the CURRENT
/// video's membership instead, so switching views and tagging never share one
/// tap target (the old dual-zone "play" half read as ambiguous).
///
/// `initialCommand` prefills the command bar when a numpad entry key opens the
/// sheet; every other door opens it empty.
class TagPlaySheet extends HookWidget {
  const TagPlaySheet({
    super.key,
    this.initialCommand,
    this.openViaShortcut = false,
  });

  final String? initialCommand;

  /// True when the numpad entry keys opened this sheet — the ONLY door that
  /// prefills the command bar. The "close after a command" opt-in applies to
  /// this door alone; the More button and the phone tag gesture open the sheet
  /// without it.
  final bool openViaShortcut;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final repo = DbModule.tagPlayRepo;
    final revision = useState(0);
    final tagsState = useState<List<TagPlayTag>?>(null);
    final memberships = useState<Set<int>>(<int>{});
    final counts = useState<Map<int, TagMediaCounts>>(const {});
    final inputError = useState<String?>(null);

    final store = useTagPlayStore();
    final pinned = store.select(context, (s) => s.pinnedTagIds);
    final activeViewTagId = store.select(context, (s) => s.activeViewTagId);
    final viewStack = store.select(context, (s) => s.viewStackTagIds);
    final viewStackEnabled = store.select(context, (s) => s.viewStackEnabled);
    final inputBarStored = store.select(context, (s) => s.inputBarEnabled);
    final hintEnabled = store.select(context, (s) => s.inputHintEnabled);
    final ignoreScenario = store.select(context, (s) => s.ignoreScenario);
    final autoClose = store.select(context, (s) => s.autoCloseOnSubmit);
    final hintDismissed = useState(TagPlayStore.sessionHintHidden);

    final inputController =
        useTextEditingController(text: initialCommand ?? '');
    final inputFocus = useFocusNode();
    // A prefilled operator must leave the caret AFTER it, ready for digits.
    useEffect(() {
      if (inputController.text.isNotEmpty) {
        inputController.selection =
            TextSelection.collapsed(offset: inputController.text.length);
      }
      return null;
    }, const []);

    // Resolved during build: a hook's FIRST effect invocation runs inside its
    // init callback, where inherited-widget lookups are forbidden (flutter_hooks
    // asserts on them), so the route must be read here and only USED below.
    final routeAnimation = isDesktop ? ModalRoute.of(context)?.animation : null;

    // The Popup route installs an autofocus KeyboardListener (Escape-to-close)
    // whose node wins focus: Flutter applies `autofocus` from a microtask that
    // runs AFTER post-frame callbacks, so a first-frame claim is overwritten in
    // the same frame. Wait for the route's entrance transition to COMPLETE
    // (autofocus has long resolved by then) and claim focus there.
    // Desktop only: phones must never pop their software keyboard on their own.
    useEffect(() {
      if (!isDesktop) return null;

      void claim() {
        if (inputFocus.context != null) inputFocus.requestFocus();
      }

      void claimNextFrame() {
        WidgetsBinding.instance.addPostFrameCallback((_) => claim());
      }

      final animation = routeAnimation;
      if (animation == null || animation.isCompleted) {
        claimNextFrame();
        return null;
      }

      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed) claimNextFrame();
      }

      animation.addStatusListener(onStatus);
      return () => animation.removeStatusListener(onStatus);
    }, const []);

    final queue = usePlayQueueStore();
    final currentFile = _currentFileOf(queue);

    final showInputBar = resolveTagPlayInputBarEnabled(
      stored: inputBarStored,
      isDesktop: isDesktop,
    );
    // Desktop-only chrome: the banner advertises the hardware-key `*/+-`
    // command grammar, which phones never offer (their opt-in input bar is
    // typed on a software keyboard, with no banner). A desktop IME (tablet
    // touch keyboard) still leaves little room, so the (tallest) banner
    // folds itself away while it is up (see [_KeyboardFoldingHint]).
    // Reading the inset HERE would rebuild the whole sheet on every keyboard
    // frame, so the decision lives in that leaf.
    final showHint =
        !isMobilePlatform && hintEnabled && !hintDismissed.value;

    /// `TextInputAction.done` makes the engine unfocus after a submit; the
    /// command bar is a multi-shot surface, so desktop re-claims the field once
    /// the platform's unfocus has landed. Phones never re-focus on their own —
    /// that would pop the software keyboard back up.
    void keepTyping() {
      if (!isDesktop || !showInputBar) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (inputFocus.context != null) inputFocus.requestFocus();
      });
    }

    /// Sheet-wide key scope. The global player pipeline (which owns the numpad
    /// entry keys) is muted while this popup route is on top, so the sheet has
    /// to accept those keys itself; `/` cancels the whole interaction.
    KeyEventResult onSheetKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      final keyboard = HardwareKeyboard.instance;
      // `/` (numpad divide included): discard the pending input and close the
      // UI only — playback is untouched, exactly like the barrier/Esc close.
      if ((key == LogicalKeyboardKey.slash ||
              key == LogicalKeyboardKey.numpadDivide) &&
          !keyboard.isControlPressed &&
          !keyboard.isAltPressed) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      // Operators are the command MODE, not characters: they restart the line
      // so commands can be chained without re-opening the sheet.
      final operator = switch (key) {
        LogicalKeyboardKey.numpadAdd => '+',
        LogicalKeyboardKey.numpadSubtract => '-',
        LogicalKeyboardKey.numpadMultiply => '*',
        _ => null,
      };
      // Hidden bar (phones without the opt-in) has no line to fill.
      if (operator == null || !showInputBar) return KeyEventResult.ignored;
      inputController.text = operator;
      inputController.selection = const TextSelection.collapsed(offset: 1);
      inputError.value = null;
      inputFocus.requestFocus();
      return KeyEventResult.handled;
    }

    Future<void> refresh() async {
      final tags = await repo.tags();
      tagsState.value = tags;
      if (currentFile != null &&
          currentFile.storageId.isNotEmpty &&
          currentFile.path.isNotEmpty) {
        memberships.value = await repo.membershipsOf(
          storageId: currentFile.storageId,
          pathSegments: currentFile.path,
        );
      } else {
        memberships.value = <int>{};
      }
      try {
        counts.value = await PlaybackProviderRegistry.tagPlay.mediaCounts();
      } catch (_) {
        counts.value = const {};
      }
    }

    useEffect(() {
      refresh();
      return null;
    }, [revision.value]);

    final tags = tagsState.value ?? const <TagPlayTag>[];
    final ordered = tagPlayDisplayOrder(tags, pinned);

    /// Surfaces [message] and clears the line for a fresh attempt while
    /// KEEPING the operator: it is the mode the shortcut just pre-selected, so
    /// re-typing it would be pure friction. Only the digits are dropped.
    void fail(String message) {
      inputError.value = message;
      final cleaned =
          inputController.text.replaceAll(kTagCommandIgnoredChars, '');
      final operator =
          cleaned.isNotEmpty && kTagCommandOperators.contains(cleaned[0])
              ? cleaned[0]
              : '';
      inputController.text = operator;
      inputController.selection =
          TextSelection.collapsed(offset: operator.length);
      keepTyping();
    }

    Future<void> submit(String raw) async {
      final result = parseTagCommand(raw);
      if (result is TagCommandInvalid) {
        fail(_errorText(t, result.error));
        return;
      }
      final command = (result as TagCommandParsed).command;

      final outcome = await TagCommandRunner(repo: repo).run(command);
      if (!context.mounted) return;

      if (outcome.viewSwitchingUnavailable) {
        fail(t.tag_input_err_view_unavailable);
        return;
      }
      if (outcome.emptyView) {
        fail(t.tag_input_err_empty_view);
        return;
      }
      if (outcome.bookmarkLost) {
        // The tag view IS shown, but its stored file vanished. Report it as a
        // dialog; the Play button then starts from the top of the list.
        await _showBookmarkLostDialog(context);
        return;
      }
      if (outcome.noCurrentFile) {
        fail(t.tag_input_err_no_file);
        return;
      }
      if (outcome.unknownOrdinals.isNotEmpty) {
        fail(t.tag_input_err_unknown(
          outcome.unknownOrdinals.map((o) => '$o').join(', '),
        ));
        return;
      }

      inputError.value = null;
      if (outcome.appliedTagIds.isNotEmpty &&
          command.kind != TagCommandKind.play) {
        // Membership changes are reflected in place; the active-view highlight
        // comes from the store and rebuilds on its own, so no full reload.
        final next = {...memberships.value};
        if (command.kind == TagCommandKind.add) {
          next.addAll(outcome.appliedTagIds);
        } else {
          next.removeAll(outcome.appliedTagIds);
        }
        memberships.value = next;
      }
      // A shortcut-opened sheet with the opt-in closes itself once the command
      // has actually applied, so the user never dismisses it by hand. Every
      // other door (and a disabled opt-in) keeps the multi-shot line below.
      if (openViaShortcut && !isMobilePlatform && autoClose) {
        Navigator.of(context).pop();
        return;
      }
      // A run ends the line, not the session: start the next command from an
      // empty field so the operator keys are immediately meaningful again.
      inputController.clear();
      keepTyping();
    }

    Future<void> closeHint() async {
      final choice = await showTagInputHintCloseDialog(context);
      if (choice == null) return;
      if (choice == TagInputHintCloseChoice.session) {
        TagPlayStore.sessionHintHidden = true;
      } else {
        await useTagPlayStore().setInputHintEnabled(false);
      }
      hintDismissed.value = true;
    }

    Future<void> toggleMember(int tagId) async {
      final file = currentFile;
      if (file == null || file.storageId.isEmpty || file.path.isEmpty) return;
      if (memberships.value.contains(tagId)) {
        await repo.removeMember(
          tagId: tagId,
          storageId: file.storageId,
          pathSegments: file.path,
        );
      } else {
        await repo.addMember(
          tagId: tagId,
          storageId: file.storageId,
          pathSegments: file.path,
        );
      }
      revision.value++;
    }

    return SizedBox(
      width: 340,
      // Single keyboard consumer: the software keyboard shrinks the list
      // instead of pushing the footer/input off the popup. The padder is a
      // leaf, so keyboard frames never rebuild the sheet content.
      child: KeyboardInsetPadder(
        // Opaque absorber: the Popup route dismisses when a tap reaches its
        // barrier, which would otherwise close the sheet on a tap into a gap
        // (or when tapping back into the input after losing focus). Rows,
        // buttons and the field sit above this and keep their own hit testing.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          // Inert node: it never takes focus itself, it only collects the keys
          // that bubble up from the field / rows so +/-/* and `/` keep working
          // whichever of them holds focus.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onSheetKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                  child: Row(
                    children: [
                      Text('Tag Play',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      // Explicit close affordance: without it the only exits
                      // were Esc and a tap on the playing area, neither of
                      // which is discoverable.
                      IconButton(
                        key: const ValueKey('tagSheetClose'),
                        // No key hint on phones: Escape is desktop-only.
                        tooltip: isMobilePlatform
                            ? t.close
                            : t.entry_close_esc,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                if (showHint) _KeyboardFoldingHint(onClose: closeHint),
                if (showInputBar)
                  TagInputBar(
                    controller: inputController,
                    focusNode: inputFocus,
                    errorText: inputError.value,
                    onSubmit: submit,
                    onChanged: (_) {
                      if (inputError.value != null) inputError.value = null;
                    },
                  ),
                // A plain scroll view (not a lazy ListView): the tag list is
                // small, and every row must exist in the tree even when the
                // sheet is short (no lazy window to scroll out of view).
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sits with the list so the fixed chrome above stays
                        // small enough for a 360x640 phone.
                        if (TagPlayGate.viewSwitchingEnabled)
                          CheckboxListTile(
                            key: const ValueKey('tagIgnoreScenarioToggle'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: ignoreScenario,
                            // Always settable, even with no tag view active:
                            // the switch is a preference that can be prepared
                            // up front. It only steers a TAG view's resolution
                            // — playback without a tag keeps the scenario's own
                            // sources.
                            onChanged: (value) async {
                              await store.setIgnoreScenario(value ?? false);
                              await PlaybackProviderRegistry.tagPlay
                                  .refreshActiveView();
                              revision.value++;
                            },
                            title: Text(
                              t.tag_sheet_ignore_scenario,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            subtitle: Text(
                              t.tag_sheet_ignore_scenario_hint,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                        // Desktop only: the shortcut door (numpad entry keys)
                        // does not exist on phones, so the option is hidden
                        // there rather than shown as an inert row.
                        if (!isMobilePlatform)
                          CheckboxListTile(
                            key: const ValueKey('tagAutoCloseToggle'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: autoClose,
                            // Only a shortcut-opened sheet can auto-close; the
                            // More button / gesture doors ignore the flag.
                            onChanged: (value) async {
                              await store.setAutoCloseOnSubmit(value ?? false);
                              // `select` never rebuilds on its own here
                              // (flutter_zustand re-runs the selector against
                              // the build-time state it captured, so provider
                              // sees no change), which would leave the toggle
                              // visually stale AND the submit closure holding
                              // the old value. Nudge the sheet like the
                              // ignore-scenario row does.
                              revision.value++;
                            },
                            title: Text(
                              t.tag_sheet_auto_close,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            subtitle: Text(
                              t.tag_sheet_auto_close_hint,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                        _NoTagRow(
                          selected: activeViewTagId == null,
                          onTap: () async {
                            Navigator.of(context).pop();
                            await PlaybackProviderRegistry.tagPlay
                                .exitToNoTag();
                          },
                        ),
                        // Jump-back row: only when the user opted into the
                        // return stack (`tagplay.viewStackEnabled`). The radio
                        // already shows the active tag, so this is opt-in.
                        if (viewStackEnabled && viewStack.isNotEmpty)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.undo_rounded),
                            title: Text(
                                '${t.tag_sheet_prev_view} · #${viewStack.last}'),
                            subtitle: Text(t.tag_sheet_prev_hint),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await PlaybackProviderRegistry.tagPlay.popView();
                            },
                          ),
                        const Divider(height: 1),
                        for (var i = 0; i < ordered.length; i++)
                          _TagRow(
                            ordinal: i + 1,
                            tag: ordered[i],
                            counts: counts.value[ordered[i].id],
                            canActivate: _canActivateTag(
                              counts.value[ordered[i].id],
                              ignoreScenario,
                            ),
                            pinned: pinned.contains(ordered[i].id),
                            member: memberships.value.contains(ordered[i].id),
                            active: activeViewTagId == ordered[i].id,
                            canTagCurrent: currentFile != null,
                            onTogglePin: () async {
                              await useTagPlayStore().togglePin(ordered[i].id);
                            },
                            onToggleMember: () => toggleMember(ordered[i].id),
                            onActivate: () async {
                              await PlaybackProviderRegistry.tagPlay
                                  .enterView(ordered[i].id);
                              if (PlaybackProviderRegistry
                                  .tagPlay.isBookmarkLost) {
                                if (context.mounted) {
                                  await _showBookmarkLostDialog(context);
                                }
                              }
                              revision.value++;
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(t.tag_new),
                  onTap: () async {
                    await showCreateTagDialog(context);
                    revision.value++;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.style_outlined, size: 18),
                          label: Text(t.tag_sheet_manage),
                          onPressed: () async {
                            await showTagManagementDialog(context);
                            revision.value++;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.push_pin_outlined, size: 18),
                          label: Text(t.tag_sheet_pin_presets),
                          onPressed: () => showPinPresetDialog(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Whether a tag's radio can start a view. With "ignore scenario" OFF a tag
  /// needs media inside the current scenario; with it ON only its own
  /// membership matters. Counts not loaded yet stay enabled (no flicker).
  /// Offline-grey audit: tag rows are collection-level DB objects (membership
  /// + counts are all local) with no per-row storage state, so they stay
  /// enabled while offline. File-level failures inside a view surface at the
  /// player with its existing error UI — front-blocking here would misfire on
  /// mixed online/offline tags.
  bool _canActivateTag(TagMediaCounts? counts, bool ignoreScenario) {
    if (counts == null) return true;
    return ignoreScenario ? counts.totalCount > 0 : counts.scenarioCount > 0;
  }

  String _errorText(AppLocalizations t, TagCommandError error) =>
      switch (error) {
        TagCommandError.empty => t.tag_input_err_empty,
        TagCommandError.missingOperator => t.tag_input_err_missing_operator,
        TagCommandError.noOrdinals => t.tag_input_err_no_ordinals,
        TagCommandError.playNeedsSingle => t.tag_input_err_play_single,
      };

  /// Mirrors the player page's derivation of the currently loaded media.
  FileItem? _currentFileOf(UnifiedPlayQueueStore queue) {
    final playQueue = queue.state.playQueue;
    if (playQueue.isEmpty) return null;
    final idx =
        playQueue.indexWhere((e) => e.index == queue.state.currentIndex);
    if (idx < 0) return null;
    final file = playQueue[idx].file;
    // Non-media payloads (e.g. opened links) are not taggable targets.
    if (checkContentType(file.name) == ContentType.other &&
        file.storageId.isEmpty) {
      return null;
    }
    return file;
  }
}

/// Radio affordance shared by the selection rows. Hand-rolled (not [Radio])
/// because "no tag" is a real nullable option and the widget-level
/// `groupValue` API is deprecated in this SDK.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected, this.enabled = true});

  final bool selected;

  /// False for a tag with no media to play: the ring greys out further so the
  /// non-jumpable rows are visibly distinct from merely unselected ones.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color color;
    if (!enabled) {
      color = colorScheme.outlineVariant;
    } else {
      color = selected ? colorScheme.primary : colorScheme.outline;
    }
    return Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      size: 20,
      color: color,
    );
  }
}

class _NoTagRow extends StatelessWidget {
  const _NoTagRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: selected,
      leading: _SelectDot(selected: selected),
      title: Text(t.tag_sheet_no_tag),
      subtitle: Text(t.tag_sheet_seq_zero),
      trailing: selected
          ? Icon(Icons.check_rounded, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.ordinal,
    required this.tag,
    required this.counts,
    required this.canActivate,
    required this.pinned,
    required this.member,
    required this.active,
    required this.canTagCurrent,
    required this.onTogglePin,
    required this.onToggleMember,
    required this.onActivate,
  });

  /// 1-based position in the sheet's display order — the number the command
  /// bar expects. Surfaced so keyboard and touch stay in sync.
  final int ordinal;
  final TagPlayTag tag;

  /// `scenarioCount / totalCount`, or null before the first load.
  final TagMediaCounts? counts;

  /// Whether the radio may start this tag's view (false = greyed, not tappable).
  final bool canActivate;
  final bool pinned;
  final bool member;

  /// Whether this tag's view is the exclusive active one.
  final bool active;
  final bool canTagCurrent;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleMember;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: ValueKey('tagRow-${tag.id}'),
      decoration: active
          ? BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: InkWell(
        // The row body toggles membership — the frequent action here; the
        // leading radio is the exclusive view switch.
        onTap: canTagCurrent ? onToggleMember : null,
        child: Row(
          children: [
            IconButton(
              key: ValueKey('tagRowActivate-${tag.id}'),
              tooltip: canActivate
                  ? t.tag_row_activate
                  : t.tag_row_activate_disabled,
              icon: _SelectDot(selected: active, enabled: canActivate),
              onPressed: canActivate ? onActivate : null,
            ),
            IconButton(
              tooltip: pinned ? t.tag_sheet_unpin : t.tag_sheet_pin,
              icon: Icon(
                pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 18,
                color: pinned ? colorScheme.primary : colorScheme.outline,
              ),
              onPressed: onTogglePin,
            ),
            // Command ordinal: the number the command bar expects.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 20),
              child: Text(
                '$ordinal',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tag.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                  // Availability on its own sub-title line: in-scenario /
                  // whole membership.
                  Text(
                    t.tag_media_count(
                      counts?.scenarioCount ?? 0,
                      counts?.totalCount ?? 0,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (tag.description.isNotEmpty)
                    Text(tag.description,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colorScheme.outline)),
                ],
              ),
            ),
            IconButton(
              tooltip: member ? t.tag_row_remove : t.tag_row_tag,
              icon: Icon(
                member ? Icons.remove_circle_outline : Icons.add_circle_outline,
                size: 20,
                color: !canTagCurrent
                    ? colorScheme.outline
                    : (member ? colorScheme.primary : null),
              ),
              onPressed: canTagCurrent ? onToggleMember : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports a tag bookmark whose file is gone. The view stays on screen; the
/// Play button then starts from the top of the list.
Future<void> _showBookmarkLostDialog(BuildContext context) {
  final t = getLocalizations(context);
  return showMessageDialog(
    Navigator.of(context, rootNavigator: true),
    title: t.tag_bookmark_lost_title,
    message: t.tag_bookmark_lost_body,
  );
}

/// The tag-input hint banner, folded to nothing while an IME is up (a desktop
/// touch keyboard leaves as little room as a phone's). The `viewInsets` read
/// lives HERE, in a leaf, so keyboard frames never rebuild the sheet's
/// list/input chrome.
class _KeyboardFoldingHint extends StatelessWidget {
  const _KeyboardFoldingHint({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    return TagInputHintBanner(onClose: onClose);
  }
}
