import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart'
    show kBackgroundTargetColor;
import 'package:iris/models/store/title_overlay_config.dart';
import 'package:iris/pages/player/title_prefix.dart' show kNoTagSuffix;
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/use_phone_battery.dart';

class TitleOverlayView extends HookWidget {
  const TitleOverlayView({
    super.key,
    required this.config,
    required this.title,
    this.queueLabel,
    this.tagSuffix,
    this.bgTitleSuffix,
    this.bgTitleNoMedia = false,
    required this.queueIndex,
    this.showIcon = false,
  });

  final TitleOverlayConfig config;
  final String title;

  /// `[cur/total]` prefix rendered before the title (only in the bar).
  final String? queueLabel;

  /// Trailing tag label: a tag name (primary) or the [kNoTagSuffix]
  /// sentinel (muted, rendered localized).
  final String? tagSuffix;

  /// 副音 on-marker (accent color) appended after the tag suffix — never a
  /// replacement for [title].
  final String? bgTitleSuffix;

  /// 副音 is on but no media is loaded — the marker renders muted (gray).
  final bool bgTitleNoMedia;
  final int? queueIndex;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final battery = useBatteryLevel();

    // Auto-update time every minute
    final now = useState(DateTime.now());

    useEffect(() {
      final timer = Timer.periodic(const Duration(minutes: 1), (_) {
        now.value = DateTime.now();
      });
      return timer.cancel;
    }, const []);

    final timeText = DateFormat.Hm().format(now.value);

    final style = TextStyle(
      fontSize: config.fontSize,
      color: Colors.white,
      decoration: TextDecoration.none,
      shadows: const [
        Shadow(color: Colors.black, blurRadius: 1),
      ],
    );

    final parts = <Widget>[];

    if (config.showAppIcon && showIcon) {
      parts.add(
        Image.asset(
          'assets/images/logo_transparent.png',
          width: 32,
          height: 32,
        ),
      );
    }

    if (config.showBattery && isMobilePlatform) {
      parts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BatteryIndicator(level: battery),
            const SizedBox(width: 4),
            Text('$battery%', style: style),
          ],
        ),
      );
    }

    if (config.showTime) {
      parts.add(Text(timeText, style: style));
    }

    if (config.showQueueIndex && queueIndex != null) {
      parts.add(Text('#$queueIndex', style: style));
    }

    if (queueLabel != null) {
      parts.add(Text(
        queueLabel!,
        style: style.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }

    if (config.showMediaName) {
      parts.add(
        Expanded(
          child: Text(
            title,
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    if (tagSuffix != null) {
      final bool isNoTag = tagSuffix == kNoTagSuffix;
      parts.add(Text(
        '· ${isNoTag ? getLocalizations(context).tag_no_tag : tagSuffix}',
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(
          fontSize: (config.fontSize - 2).clamp(10, 16),
          color: isNoTag
              ? Colors.white54
              : Theme.of(context).colorScheme.primary,
          fontWeight: isNoTag ? FontWeight.w400 : FontWeight.w600,
        ),
      ));
    }

    // 副音 marker — appended after the tag suffix so "副音 is on" reads at a
    // glance. Additive by design: the title above is untouched. Uses the
    // title's own style (size/weight) with only the color differing; muted
    // when 副音 is on but no media is loaded. Flexible so a long name
    // ellipsizes instead of overflowing a narrow bar (phones).
    if (bgTitleSuffix != null) {
      parts.add(Flexible(
        child: Text(
          bgTitleSuffix!,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(
            color: bgTitleNoMedia ? Colors.white54 : kBackgroundTargetColor,
          ),
        ),
      ));
    }

    return Row(
      children: parts.map((w) {
        // Flex children must stay direct children of the Row.
        if (w is Expanded || w is Flexible) {
          return w;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: w,
        );
      }).toList(),
    );
  }
}

class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({
    super.key,
    required this.level,
    this.height = 12,
    this.width = 22,
    this.strokeWidth = 1.5,
    this.color = Colors.white,
  });

  final int level; // 0–100
  final double height;
  final double width;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = level.clamp(0, 100);
    final fillWidth = (width - 4) * (clamped / 100);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            // Battery body
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: color, width: strokeWidth),
              ),
            ),
            // Fill
            Positioned(
              left: 2,
              top: 2,
              bottom: 2,
              child: Container(
                width: fillWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: color,
                ),
              ),
            ),
          ],
        ),
        // Battery head
        Container(
          margin: const EdgeInsets.only(left: 2),
          width: 2.5,
          height: height / 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}
