import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/model/enum/bg_quick_panel.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/bg_align_dialog.dart';

/// Opens the 对齐方式 card — the persistent, always-reachable entry of the
/// shared alignment editor (quick-bar "对齐" button).
Future<void> showBgAlignmentPanel(BuildContext context) async {
  useBackgroundPlaybackStore().toggleQuickPanel(BgQuickPanel.align);
}

/// Non-modal shell of [BgAlignContent] for the quick-bar 对齐 floating card.
///
/// The card is hosted inside the player subtree, so the content resolves the
/// engine and the foreground player from the ambient providers; playback stays
/// live underneath (no `ModalBarrier`).
class BgAlignmentPanelContent extends StatelessWidget {
  const BgAlignmentPanelContent({super.key});

  @override
  Widget build(BuildContext context) => const BgAlignContent();
}
