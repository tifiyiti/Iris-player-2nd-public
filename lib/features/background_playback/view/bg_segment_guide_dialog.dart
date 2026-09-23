import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/layout_breakpoints.dart';

/// Opens the Sub Audio (副音) A/P/B mapping guide — a static explanation of the
/// three handles, the discarded-time readouts and the minimum segment length.
///
/// Adaptive: a scrollable bottom sheet on phones, a centered dialog on
/// desktop/tablet. No inputs, so no keyboard handling is needed.
Future<void> showBgSegmentGuideDialog(BuildContext context) async {
  final t = getLocalizations(context);
  final content = _guideBody(t);
  if (isMobileWidthLayout(context)) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: content,
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.bg_segment_guide_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.ok),
        ),
      ],
    ),
  );
}

Widget _guideBody(AppLocalizations t) => Text(
      t.bg_segment_guide_body,
      style: const TextStyle(height: 1.45),
    );
