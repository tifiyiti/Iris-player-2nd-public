import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_quick_bar.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';
import 'package:iris/globals.dart' show sidePanelKeyNotifier;
import 'package:iris/hooks/use_published_global_key.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';

/// Sideway one-handed panel: dial + wrapping button bar, anchored by the
/// meta 9-grid position (`resolveSidePanelAlignment`).
///
/// Total panel size is % of screen (phone 40%W/90%H, desktop 35%W/40%H — see
/// applySliderRows). Slider (dial/classic) fills `span = totalH - buttonsH - gap`
/// by its own style pct (ringDialHeightPct / circleSliderScale) — 100% means
/// it occupies the whole remaining space, so dragging the total panel resizes
/// the slider indirectly. Edges NOT on the window border are draggable (all
/// platforms when one-handed).
class CircleSliderLayout extends HookWidget {
  const CircleSliderLayout({
    super.key,
    required this.width,
    required this.panelPercent,
    required this.controls,
    required this.scrubberBuilder,
    this.showControl,
  });

  final double width;
  final int panelPercent;
  final ControlBarControls controls;

  /// Called on hover/drag inside the total panel (and rings) to refresh the
  /// auto-hide timer — forwarded from player.dart so drags obey the same
  /// lifecycle as global hover.
  final void Function()? showControl;

  /// Builds the top scrubber slot. [availableSpan] is the measured vertical
  /// span inside the total panel (null when unbounded); [dialHeightPx] is the
  /// dial's pixel height inside that span (null when unbounded).
  final Widget Function(double? availableSpan, double? dialHeightPx) scrubberBuilder;

  // Why 初始估算取偏大(3 行 Wrap ≈150)而非单行 76：首帧 buttonsKey 尚未实测，
  // 用 76 会使 span=totalH-76-gap 偏大，dialPx 随之偏大，首帧 Column 高
  // =dial+gap+实测按钮(≈144) 比 totalH 多 68 溢出（draglog 252×384 案例）。
  // 偏大估算（3 行 48*3+12≈156）使首帧即偏保守，次帧 postFrame 校正后回正确值，无溢出闪烁。
  static const double _kButtonsEstimate = 150;
  static const double _kGap = 8;

  static const double _kEdgeHit = 10;
  static const double _kCornerHit = 22;
  static const double _kClassicMin = 100;
  static const double _kClassicMax = 260;

  // Stable slot keys: the shell always renders a 3-child Row, but the quick
  // column flips sides with the 9-grid anchor. Without keys that reorder can
  // re-parent the tooltip-bearing panel inside this `LayoutBuilder`'s layout
  // callback (type-in-place matches `SizedBox` at the old index), moving its
  // keyed subtree while a Tooltip OverlayPortal may be open — the
  // `_RenderLayoutBuilder was mutated in performLayout` class. Keyed slots keep
  // both elements in place across the flip.
  static const Key _kPanelSlotKey = ValueKey('side_panel_slot');
  static const Key _kQuickSlotKey = ValueKey('side_quick_slot');

  @override
  Widget build(BuildContext context) {
    final GlobalKey buttonsKey = useMemoized(GlobalKey.new, const <Object?>[]);
    // Per-mount panel-box key, published for the style popovers (see
    // `usePublishedGlobalKey`): a shared key would let a new panel element
    // re-take the old one and re-activate its OverlayPortals mid-layout.
    final GlobalKey panelKey = usePublishedGlobalKey(sidePanelKeyNotifier);
    final ValueNotifier<double> buttonsH = useState(_kButtonsEstimate);

    // No keys on purpose: re-measure on EVERY build. The buttons Wrap
    // re-wraps when the window resizes (more rows on a narrower window),
    // so a once-only measurement goes stale and the stale span overflows
    // the Column by the row delta (draglog: 46px after 3840→3438). The
    // 0.5px threshold settles: no update once measured height is stable.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final double? h = buttonsKey.currentContext?.size?.height;
        if (h != null && (h - buttonsH.value).abs() > 0.5) {
          buttonsH.value = h;
          // Publish the REAL measured bar height so the APB editor can lock its
          // two slots to the same values (never a hardcoded guess).
          sidewayBarHeight.value = h;
        }
      });
      return null;
    });

    final AppStore store = useAppStore();
    final AppState app = store.select(context, (s) => s);
    // 副音 quick column visibility (第 4 轮): gated OUTSIDE the panel so a
    // disabled quick bar reserves no space and leaves no gap. Independent of
    // whether 副音 currently runs — the bar's power switch must stay reachable.
    final bool bgQuickBarVisible = useBackgroundPlaybackStore().select(
      context,
      (s) => s.quickBarEnabled,
    );
    // Bottom control group: playback (legacy Wrap) vs 副音 quick controls.
    // Desktop ignores the stored group until the phone-mode opt-in, so a
    // desktop user who never enables it always sees the playback row.
    final PlayerControlGroup controlGroup =
        useControlGroupStore().select(context, (s) => s.group);
    final bool controlGroupSupported =
        isMobilePlatform || app.desktopCenterZonePhoneMode;
    final bool showingBackgroundGroup =
        controlGroupSupported &&
            controlGroup == PlayerControlGroup.background;
    // Anchor of the total panel — the caller aligns the panel box with the very
    // same value. It also decides which way the bottom button rows face: the bar
    // is built for one thumb, so its rows hug the edge that faces the screen
    // centre instead of centring inside the panel.
    final Alignment panelAnchor = resolveControlPanelAnchor(
      app,
      isLandscape: isLandscapeOrientation(
        runtimeOrientation: app.runtimeOrientation,
        realOrientation: MediaQuery.orientationOf(context),
      ),
      width: width,
    );
    final bool showHandles = app.phoneLandscapeUseMode.usesOneHandedControls;
    final bool isDial = app.phoneOneHandedScrubberKind == PhoneSideScrubberKind.dial;
    final double circlePosX = app.circlePosX;
    final double circlePosY = app.circlePosY;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size screen = MediaQuery.sizeOf(context);
        final double windowW = screen.width;
        final double windowH = screen.height;

        // Total panel size: phone = screen % (isMobilePlatform), desktop = absolute px
        // (1080p default 380×420, min 260×320, max window*0.8 to leave video visible)
        // Why 屏% vs 视频%：显示器屏幕 % 才是可用空间，视频画面 % 会随分辨率切变导致重叠
        final bool isPhone = isMobilePlatform;
        double totalW, totalH;
        if (isPhone) {
          final double widthPct = app.sidewayPanelWidthPct.clamp(10, 100);
          final double heightPct = app.sidewayPanelHeightPct.clamp(10, 100);
          totalW = pxForPercent(widthPct, windowW);
          totalH = pxForPercent(heightPct, windowH);
          totalW = totalW.clamp(200, m.max(200, windowW - 16));
          totalH = totalH.clamp(160, m.max(160, windowH - 16));
        } else {
          // Desktop absolute px — 1080p notebook habit 380×420, min 260×320, max window*0.8
          totalW = app.sidewayPanelWidthPx.clamp(260, m.max(260, windowW * 0.8));
          totalH = app.sidewayPanelHeightPx.clamp(320, m.max(320, windowH * 0.8));
        }

        final double span = spanForTotalHeight(totalH, buttonsH.value, _kGap);
        // dialPx 双 clamp：span 不足 kMinDiameter 时退化为 span 而非强行 150，
        // 否则 Column 高 =span+gap+buttons 会超 totalH。Boundary: 任意 span≥0。
        final double dialPxRaw = dialPxForSpan(
          span: span,
          panelW: totalW,
          isDial: isDial,
          ringDialHeightPct: app.ringDialHeightPct,
          classicScale: app.circleSliderScale,
          kMinDiameter: PhoneRingDialMath.kMinDiameter,
          kClassicMin: _kClassicMin,
          kClassicMax: _kClassicMax,
          kGap: _kGap,
        );
        final double dialPx = span < PhoneRingDialMath.kMinDiameter
            ? span.clamp(0, totalW).toDouble()
            : dialPxRaw;

        // Enforce width floor: panel never narrower than its dial.
        final double panelW = effectivePanelWidth(
          draggedWidth: totalW,
          dialDiameter: dialPx,
          maxWindowWidth: windowW,
        );
        // If floor pushed width, span unchanged (height drives dial, width only floors).
        // Keep panelW as computed; totalH stays as persisted.

        // Window-resize overflow fix: measure buttons synchronously via
        // CustomMultiChildLayout (no postFrame stale). First lays out Wrap
        // with panelW, gets its height, then dial gets leftover
        // totalH - buttonsH - gap (clamped). No Flex overflow even on
        // 3840→3438 switch (draglog 46px).
        final Widget panelCore = ClipRect(
          child: SizedBox(
            key: panelKey,
            width: panelW,
            height: totalH,
            child: CustomMultiChildLayout(
              delegate: _PanelDelegate(
                totalH: totalH,
                gap: _kGap,
                isDial: isDial,
                circlePosX: circlePosX,
                circlePosY: circlePosY,
                totalW: totalW,
                ringDialHeightPct: app.ringDialHeightPct,
                classicScale: app.circleSliderScale,
              ),
              children: [
                LayoutId(
                  id: _PanelSlot.dial,
                  child: Builder(
                    builder: (context) {
                      // Dial will be laid out with tight constraints from delegate;
                      // scrubberBuilder receives actual available span/dial height
                      // via LayoutBuilder inside delegate's tight box (see delegate).
                      // For dial the slot is full panel width (corridor), for
                      // classic it stays a centered square.
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final double availForDial = constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : span;
                          // Dial slot is now full panel width × availH so the
                          // corridor has slack; classic keeps the square box.
                          final bool useFullWidth =
                              constraints.maxWidth > constraints.maxHeight + 0.5;
                          if (useFullWidth) {
                            // availH is the full leftover span; dialBox will
                            // derive the bottom-anchored diameter from it via
                            // heightPct. Align bottom so the ring stays flush
                            // against the button bar like before.
                            return SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: scrubberBuilder(availForDial, null),
                              ),
                            );
                          }
                          final double dialForBuilder = constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : dialPx;
                          return SizedBox(
                            width: dialForBuilder,
                            height: dialForBuilder,
                            child: scrubberBuilder(availForDial, dialForBuilder),
                          );
                        },
                      );
                    },
                  ),
                ),
                LayoutId(
                  id: _PanelSlot.buttons,
                  child: Padding(
                    key: buttonsKey,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    // Group 2 (副音 controls) replaces the whole row set; it
                    // ignores the standalone quick-bar switch by design.
                    child: showingBackgroundGroup
                        ? BackgroundQuickBar(
                            axis: Axis.horizontal,
                            alignment:
                                sidewayButtonRowAlignForAnchor(panelAnchor),
                            forceVisible: true,
                            color: controls.color,
                            overlayColor: controls.overlayColor,
                          )
                        : Wrap(
                            alignment: sidewayButtonAlignForAnchor(panelAnchor),
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              controls.repeat,
                              controls.prev,
                              controls.playPause,
                              controls.next,
                              controls.stop,
                              controls.shuffle,
                              if (controls.showFit) controls.fit,
                              controls.rotateOrVolume,
                              controls.backgroundPlaybackMenu,
                              controls.playQueue,
                              controls.storage,
                              if (isDesktop) controls.fullscreen,
                              if (isWindows && isDial)
                                controls.playlistDockMode,
                              controls.more,
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );

        // 副音 quick column (第 4 轮修正): MAGNETICALLY attached OUTSIDE the
        // panel, on the side that faces the screen centre — never overlaid on
        // top of it, which used to cover the dial and the button wrap.
        // Wrapping happens AFTER the resize-handle stack below so the handle
        // geometry (which is relative to the panel box) stays untouched.
        final bool quickOnLeft = panelAnchor.x > 0;
        const double kQuickGap = 4;
        const double kQuickMinW = 40;
        // The combined panel (side panel + quick grid) must fit the zone the
        // bar is actually laid out in — NOT the raw screen width, which
        // overestimates when the playlist dock shrinks the video area. These
        // constraints already sit INSIDE the container's 8px padding, so only a
        // small safety margin is subtracted. The grid shrink-wraps to the 1-2
        // columns it needs, so `quickAvail` is only its upper bound.
        final double layoutW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : windowW;
        final double quickAvail = layoutW - 8 - panelW - kQuickGap;
        // 自适应: the grid widens toward two columns while space allows, and is
        // dropped entirely (rather than squashed) below its minimum.
        // Phones never show the standalone column (the bottom group switch
        // owns 副音 there); desktop hides it while group 2 is active.
        final bool showQuickBar =
            bgQuickBarVisible &&
            !isMobilePlatform &&
            !showingBackgroundGroup &&
            quickAvail >= kQuickMinW;

        // STRUCTURAL STABILITY (flutter/flutter #177693 / #188500, the
        // #182444 family): the tooltip-bearing [panel] lives under the
        // LayoutBuilder above. Returning a different SHAPE (bare child vs Row,
        // child count changes) re-activates its Tooltip OverlayPortals while
        // the LayoutBuilder is laying out, which trips
        // "_RenderLayoutBuilder was mutated in performLayout" and then poisons
        // the whole element tree. Always render the SAME shape: a 3-child Row
        // whose quick slot collapses to zero, around a Stack that may hold no
        // resize affordance.
        Widget withQuickBar(Widget core) {
          final Widget quick = showQuickBar
              ? SizedBox(
                  height: totalH,
                  child: BackgroundQuickBar(
                    axis: Axis.vertical,
                    width: quickAvail,
                    // Primary column always faces the panel/thumb side.
                    mirrorColumns: quickOnLeft,
                    color: controls.color,
                    overlayColor: controls.overlayColor,
                  ),
                )
              : const SizedBox.shrink();
          final double gapW = showQuickBar ? kQuickGap : 0;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: quickOnLeft
                ? [
                    // Height follows the panel so the column scrolls instead of
                    // growing past it (in a Row the height would be unbounded
                    // and the scroll view could never engage).
                    KeyedSubtree(key: _kQuickSlotKey, child: quick),
                    SizedBox(width: gapW),
                    KeyedSubtree(key: _kPanelSlotKey, child: core),
                  ]
                : [
                    KeyedSubtree(key: _kPanelSlotKey, child: core),
                    SizedBox(width: gapW),
                    KeyedSubtree(key: _kQuickSlotKey, child: quick),
                  ],
          );
        }

        final Widget panel = panelCore;

        if (!showHandles) {
          return withQuickBar(Stack(
            clipBehavior: Clip.none,
            children: <Widget>[panel],
          ));
        }

        final Alignment anchor = panelAnchor;
        final SidewayResizePlan plan = resizePlanForAnchor(anchor);
        final double edgeInset = m.max(0.0, (totalH - 2 * _kCornerHit) / 2);

        // Drag-time mutual-exclusion limits (更窄/更矮即限位而非溢出)
        // Why 260×320：环150+条30+走廊6+2*inset+Wrap余量，拖至将要遮挡即停
        final double dragMinW = m.max(
          isPhone ? 200 : 260,
          PhoneRingDialMath.minPanelWidthForRingAndStrip(
            diameter: PhoneRingDialMath.kMinDiameter,
          ),
        );
        final double dragMinH = m.max(
          isPhone ? 160 : 320,
          PhoneRingDialMath.minPanelHeightForContent(
            diameter: PhoneRingDialMath.kMinDiameter,
            buttonsH: buttonsH.value,
          ),
        );
        final double dragMaxW = isPhone ? windowW - 16 : windowW * 0.8;
        final double dragMaxH = isPhone ? windowH - 16 : windowH * 0.8;

        // Drag frames mutate MEMORY only; the DB write happens once on
        // `onPanEnd` via [AppStore.persistSidewayPanelGeometry]. Persisting per
        // frame rewrote rows (and, for the legacy percent mirror, the whole
        // snapshot + blob) on the UI isolate every phone frame.
        void dragWidth(DragUpdateDetails d, {required bool fromLeft}) {
          showControl?.call();
          final double grow = fromLeft ? -d.delta.dx : d.delta.dx;
          final double newW = (totalW + grow).clamp(dragMinW, dragMaxW);
          if (isPhone) {
            final double newPct = (newW / windowW * 100).clamp(10, 100);
            // ignore: discarded_futures
            store.updateSidewayPanelWidthPct(newPct, persist: false);
            final int legacy = (newPct).round().clamp(30, 90);
            // ignore: discarded_futures
            store.updateCircleLandscapePercent(legacy, persist: false);
          } else {
            // ignore: discarded_futures
            store.updateSidewayPanelWidthPx(newW, persist: false);
          }
        }

        void dragHeight(DragUpdateDetails d, {required bool fromTop}) {
          showControl?.call();
          final double grow = fromTop ? -d.delta.dy : d.delta.dy;
          final double newH = (totalH + grow).clamp(dragMinH, dragMaxH);
          if (isPhone) {
            final double newPct = (newH / windowH * 100).clamp(10, 100);
            // ignore: discarded_futures
            store.updateSidewayPanelHeightPct(newPct, persist: false);
          } else {
            // ignore: discarded_futures
            store.updateSidewayPanelHeightPx(newH, persist: false);
          }
        }

        void commitGeometry() {
          // ignore: discarded_futures
          store.persistSidewayPanelGeometry();
        }

        // Windows + meta uses visible rings instead of invisible edge strips.
        final bool showRings = isWindows && app.useMetadataSettings && showHandles;
        if (showRings) {
          final double rawRadiusH = app.sidewayHandleRadiusH.clamp(4.0, 16.0).toDouble();
          final double rawRadiusV = app.sidewayHandleRadiusV.clamp(4.0, 16.0).toDouble();
          final double radiusH = clampHandleRadius(rawRadiusH, panelW, totalH);
          final double radiusV = clampHandleRadius(rawRadiusV, panelW, totalH);
          final double insetH = app.sidewayHandleInsetH;
          final double insetV = app.sidewayHandleInsetV;

          Widget ringWidget(RingSpec spec) {
            // Visual ring + larger hit area (hot zone ≈ 24px diam).
            // Hit covers whole disk, visual is transparent interior.
            final double r = spec.radius;
            final double hitR = m.max(r + 6, 12);
            final MouseCursor cursor = switch (spec.edge) {
              RingEdge.left => SystemMouseCursors.resizeLeft,
              RingEdge.right => SystemMouseCursors.resizeRight,
              RingEdge.top => SystemMouseCursors.resizeUp,
              RingEdge.bottom => SystemMouseCursors.resizeDown,
            };
            return MouseRegion(
              cursor: cursor,
              onEnter: (_) => showControl?.call(),
              onHover: (_) => showControl?.call(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanEnd: (_) => commitGeometry(),
                onPanUpdate: (DragUpdateDetails d) {
                  showControl?.call();
                  // Tangential (along edge) → inset; normal (perp) → panel size.
                  switch (spec.edge) {
                    case RingEdge.left:
                      final double newInsetV = applyInsetVDelta(
                          anchor: anchor, insetV: app.sidewayHandleInsetV, deltaDy: d.delta.dy, panelH: totalH, radiusV: radiusV);
                      if ((newInsetV - app.sidewayHandleInsetV).abs() > 0.5) {
                        // ignore: discarded_futures
                        store.updateSidewayHandleInsetV(newInsetV, persist: false);
                      }
                      dragWidth(d, fromLeft: true);
                      break;
                    case RingEdge.right:
                      final double newInsetV2 = applyInsetVDelta(
                          anchor: anchor, insetV: app.sidewayHandleInsetV, deltaDy: d.delta.dy, panelH: totalH, radiusV: radiusV);
                      if ((newInsetV2 - app.sidewayHandleInsetV).abs() > 0.5) {
                        // ignore: discarded_futures
                        store.updateSidewayHandleInsetV(newInsetV2, persist: false);
                      }
                      dragWidth(d, fromLeft: false);
                      break;
                    case RingEdge.top:
                      final double newInsetH = applyInsetHDelta(
                          anchor: anchor, insetH: app.sidewayHandleInsetH, deltaDx: d.delta.dx, panelW: panelW, radiusH: radiusH);
                      if ((newInsetH - app.sidewayHandleInsetH).abs() > 0.5) {
                        // ignore: discarded_futures
                        store.updateSidewayHandleInsetH(newInsetH, persist: false);
                      }
                      dragHeight(d, fromTop: true);
                      break;
                    case RingEdge.bottom:
                      final double newInsetH2 = applyInsetHDelta(
                          anchor: anchor, insetH: app.sidewayHandleInsetH, deltaDx: d.delta.dx, panelW: panelW, radiusH: radiusH);
                      if ((newInsetH2 - app.sidewayHandleInsetH).abs() > 0.5) {
                        // ignore: discarded_futures
                        store.updateSidewayHandleInsetH(newInsetH2, persist: false);
                      }
                      dragHeight(d, fromTop: false);
                      break;
                  }
                },
                child: Container(
                  width: hitR * 2,
                  height: hitR * 2,
                  alignment: Alignment.center,
                  color: Colors.transparent,
                  child: Container(
                    width: r * 2,
                    height: r * 2,
                    // Hit covers the whole disk (outer hitR transparent box),
                    // visual is a thin ring with fully transparent interior
                    // so the video beneath shows through.
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.70), width: 1.2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 1, offset: const Offset(0, 1))],
                    ),
                  ),
                ),
              ),
            );
          }

          final List<RingSpec> rings = ringCentersForAnchor(
            anchor: anchor,
            panelW: panelW,
            panelH: totalH,
            insetH: insetH,
            insetV: insetV,
            radiusH: radiusH,
            radiusV: radiusV,
          );

          final List<Widget> ringWidgets = rings.map((RingSpec s) {
            final double hitHalf = m.max(s.radius + 6, 12);
            return Positioned(
              left: s.center.dx - hitHalf,
              top: s.center.dy - hitHalf,
              width: hitHalf * 2,
              height: hitHalf * 2,
              child: ringWidget(s),
            );
          }).toList();

          return withQuickBar(Stack(
            clipBehavior: Clip.none,
            children: <Widget>[panel, ...ringWidgets],
          ));
        }

        Widget hitZone({
          required MouseCursor cursor,
          required void Function(DragUpdateDetails) onUpdate,
          required Widget child,
        }) {
          return MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onUpdate,
              onPanEnd: (_) => commitGeometry(),
              child: child,
            ),
          );
        }

        final List<Widget> zones = <Widget>[
          if (plan.leftEdge)
            Positioned(
              left: 0,
              top: edgeInset,
              bottom: edgeInset,
              width: _kEdgeHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeLeft,
                onUpdate: (d) => dragWidth(d, fromLeft: true),
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.rightEdge)
            Positioned(
              right: 0,
              top: edgeInset,
              bottom: edgeInset,
              width: _kEdgeHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeRight,
                onUpdate: (d) => dragWidth(d, fromLeft: false),
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.topEdge)
            Positioned(
              top: 0,
              left: edgeInset,
              right: edgeInset,
              height: _kEdgeHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeUp,
                onUpdate: (d) => dragHeight(d, fromTop: true),
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.bottomEdge)
            Positioned(
              bottom: 0,
              left: edgeInset,
              right: edgeInset,
              height: _kEdgeHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeDown,
                onUpdate: (d) => dragHeight(d, fromTop: false),
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.cornerTL != null)
            Positioned(
              left: 0,
              top: 0,
              width: _kCornerHit,
              height: _kCornerHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeUpLeft,
                onUpdate: (d) {
                  if (plan.cornerTL!.w) dragWidth(d, fromLeft: true);
                  if (plan.cornerTL!.h) dragHeight(d, fromTop: true);
                },
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.cornerTR != null)
            Positioned(
              right: 0,
              top: 0,
              width: _kCornerHit,
              height: _kCornerHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeUpRight,
                onUpdate: (d) {
                  if (plan.cornerTR!.w) dragWidth(d, fromLeft: false);
                  if (plan.cornerTR!.h) dragHeight(d, fromTop: true);
                },
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.cornerBL != null)
            Positioned(
              left: 0,
              bottom: 0,
              width: _kCornerHit,
              height: _kCornerHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeDownLeft,
                onUpdate: (d) {
                  if (plan.cornerBL!.w) dragWidth(d, fromLeft: true);
                  if (plan.cornerBL!.h) dragHeight(d, fromTop: false);
                },
                child: const SizedBox.expand(),
              ),
            ),
          if (plan.cornerBR != null)
            Positioned(
              right: 0,
              bottom: 0,
              width: _kCornerHit,
              height: _kCornerHit,
              child: hitZone(
                cursor: SystemMouseCursors.resizeDownRight,
                onUpdate: (d) {
                  if (plan.cornerBR!.w) dragWidth(d, fromLeft: false);
                  if (plan.cornerBR!.h) dragHeight(d, fromTop: false);
                },
                child: const SizedBox.expand(),
              ),
            ),
        ];

        return withQuickBar(Stack(
          clipBehavior: Clip.none,
          children: <Widget>[panel, ...zones],
        ));
      },
    );
  }
}

enum _PanelSlot { dial, buttons }

class _PanelDelegate extends MultiChildLayoutDelegate {
  _PanelDelegate({
    required this.totalH,
    required this.gap,
    required this.isDial,
    required this.circlePosX,
    required this.circlePosY,
    required this.totalW,
    required this.ringDialHeightPct,
    required this.classicScale,
  });

  final double totalH;
  final double gap;
  final bool isDial;
  final double circlePosX;
  final double circlePosY;
  final double totalW;
  final double ringDialHeightPct;
  final double classicScale;

  @override
  void performLayout(Size size) {
    // Buttons first: Wrap with maxWidth = size.width (synchronous, no postFrame stale)
    final Size buttonsSize = layoutChild(
      _PanelSlot.buttons,
      BoxConstraints(maxWidth: size.width),
    );
    // Dial available height = totalH - buttons - gap (actual, not stale buttonsH)
    final double availH = (size.height - buttonsSize.height - gap).clamp(0.0, size.height);
    // Compute dialPx from actual availH (not stale span) — ensures no overflow on window resize
    final double dialPxRaw = dialPxForSpan(
      span: availH,
      panelW: size.width,
      isDial: isDial,
      ringDialHeightPct: ringDialHeightPct,
      classicScale: classicScale,
      kMinDiameter: PhoneRingDialMath.kMinDiameter,
      kClassicMin: CircleSliderLayout._kClassicMin,
      kClassicMax: CircleSliderLayout._kClassicMax,
      kGap: gap,
    );
    final double dialPxActual = availH < PhoneRingDialMath.kMinDiameter
        ? availH.clamp(0.0, size.width).toDouble()
        : dialPxRaw;
    final double shownDialH = dialPxActual.clamp(0.0, availH);
    final double dialW = shownDialH;
    if (isDial) {
      // Dial corridor needs the full panel width (ring + axis strip walk
      // inside box.width == panelW). Slot covers the whole leftover span
      // (availH); the inner scrubber's box (diameter ~ span*heightPct) is
      // bottom-anchored inside it so the ring stays flush against the
      // button bar like before, but now has horizontal slack.
      layoutChild(
        _PanelSlot.dial,
        BoxConstraints.tightFor(width: size.width, height: availH),
      );
      positionChild(_PanelSlot.buttons,
          Offset((size.width - buttonsSize.width) / 2, size.height - buttonsSize.height));
      positionChild(_PanelSlot.dial, const Offset(0, 0));
    } else {
      layoutChild(
        _PanelSlot.dial,
        BoxConstraints.tightFor(width: dialW, height: shownDialH),
      );
      // Position buttons at bottom
      positionChild(_PanelSlot.buttons, Offset((size.width - buttonsSize.width) / 2, size.height - buttonsSize.height));
      // Position dial in leftover slot
      final double dialY = (availH - shownDialH) * circlePosY.clamp(0.0, 1.0);
      final double dialX = (size.width - dialW) * circlePosX.clamp(0.0, 1.0);
      positionChild(_PanelSlot.dial, Offset(dialX, dialY));
    }
  }

  @override
  bool shouldRelayout(covariant _PanelDelegate oldDelegate) =>
      oldDelegate.totalH != totalH ||
      oldDelegate.gap != gap ||
      oldDelegate.isDial != isDial ||
      oldDelegate.circlePosX != circlePosX ||
      oldDelegate.circlePosY != circlePosY ||
      oldDelegate.totalW != totalW ||
      oldDelegate.ringDialHeightPct != ringDialHeightPct ||
      oldDelegate.classicScale != classicScale;
}
