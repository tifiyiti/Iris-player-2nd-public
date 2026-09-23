import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/background_playback/store/bg_source_prefs.dart';
import 'package:iris/utils/get_localizations.dart';

/// Closable banner shown in the 副音 sources manager when NO source rule is
/// active (the built-in library pure-tag source takes over).
///
/// Hidden state persists via the `bg.sourceFallbackBanner` AUX row; the
/// meta-settings "Show the no-active-source hint" row restores it.
class BgSourceFallbackBanner extends HookWidget {
  const BgSourceFallbackBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final visible = useState(false);
    useEffect(() {
      var cancelled = false;
      BgSourcePrefs.fallbackBannerEnabled().then((v) {
        if (!cancelled) visible.value = v;
      });
      return () => cancelled = true;
    }, const []);

    if (!visible.value) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.bg_src_banner_fallback_title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  t.bg_src_banner_fallback_body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  t.bg_src_banner_refresh_body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t.vm_banner_dismiss,
            icon: const Icon(Icons.close, size: 16),
            onPressed: () async {
              visible.value = false;
              await BgSourcePrefs.setFallbackBannerEnabled(false);
            },
          ),
        ],
      ),
    );
  }
}
