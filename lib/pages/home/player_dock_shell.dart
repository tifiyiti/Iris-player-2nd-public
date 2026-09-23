import 'package:flutter/material.dart';

/// Structural shell for the player area plus the optional right playlist dock.
///
/// WHY a dedicated widget (flutter/flutter #177693 / #188500, the #182444
/// family): the player subtree owns GlobalKeys (`sidePanelKey` in
/// `lib/globals.dart`, used by the one-handed side panel) and Tooltip
/// `OverlayPortal`s. Returning a different SHAPE for the dock on/off states
/// (`Stack` vs `Row > Expanded > Stack`, which is what `Home` used to do)
/// deactivates the whole player subtree and mounts a new one. The new panel box
/// then re-takes the still-inactive GlobalKey element
/// (`Element._retakeInactiveElement`), and re-activating that element traverses
/// into an OPEN Tooltip's `OverlayPortal` — which grafts its deferred child into
/// the root overlay from inside a `LayoutBuilder` layout callback:
/// `_RenderLayoutBuilder was mutated in performLayout`, then the element tree is
/// poisoned (`Lost connection to device`, bogus `RenderFlex overflowed by
/// 97890 pixels`).
///
/// This shell keeps ONE shape in every state: a dock toggle only adds/removes
/// trailing children, so the player element survives and nothing is ever
/// re-activated.
class PlayerDockShell extends StatelessWidget {
  const PlayerDockShell({
    super.key,
    required this.playerArea,
    this.dockSlots = const <Widget>[],
    this.overlay,
  });

  /// The player surface (video/audio + overlays): always the leading, expanded
  /// child.
  final Widget playerArea;

  /// Trailing dock chrome (hairline divider, drag splitter, playlist panel)
  /// while the dock is shown; empty otherwise.
  final List<Widget> dockSlots;

  /// Picture-fullscreen right-edge dock overlay, stacked ABOVE the player/
  /// dock row so it can occlude the video. Null in every other state.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    // The shell ALWAYS wraps the row in the same Stack shape, so toggling the
    // overlay only adds/removes a trailing child — the leading row and its
    // player subtree are never deactivated (see the class doc above).
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Row(
          // Stretch so the player area keeps the TIGHT height the Scaffold body
          // used to hand it. Each dock slot re-centers itself at its own
          // intrinsic size so the dock chrome keeps its previous geometry.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: playerArea),
            for (final Widget slot in dockSlots)
              Align(alignment: Alignment.center, child: slot),
          ],
        ),
        if (overlay != null) Positioned.fill(child: overlay!),
      ],
    );
  }
}
