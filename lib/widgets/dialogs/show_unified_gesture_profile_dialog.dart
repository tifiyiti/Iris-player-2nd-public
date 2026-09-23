import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_entry.dart';
import 'package:iris/widgets/dialogs/show_reset_gesture_layout_dialog.dart';

Future<void> showUnifiedGestureProfileDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const UnifiedGestureProfileDialog(),
  );
}

class UnifiedGestureProfileDialog extends HookWidget {
  const UnifiedGestureProfileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final landscape = useAppStore().select(context, (s) => s.landscapeGestureProfile);
    final isLegacy = landscape == LandscapeGestureProfile.classic;
    final selected = useState<LandscapeGestureProfile>(isLegacy ? LandscapeGestureProfile.classic : landscape);
    // local legacy checkbox mirrors selected==classic
    final useLegacy = useState<bool>(isLegacy);

    void syncLegacy(bool v) {
      useLegacy.value = v;
      if (v) {
        selected.value = LandscapeGestureProfile.classic;
      } else {
        // restore to region if was classic
        if (selected.value == LandscapeGestureProfile.classic) {
          selected.value = LandscapeGestureProfile.region;
        }
      }
    }

    return AlertDialog(
      title: Text(t.gest_layout_title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.gest_portrait_label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(t.gest_portrait_desc,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            RadioListTile<bool>(
              value: false,
              groupValue: true,
              title: Text(t.gest_portrait_region),
              subtitle: Text(t.gest_portrait_only),
              selected: true,
              onChanged: null,
            ),
            const Divider(),
            Text(t.gest_landscape_label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<LandscapeGestureProfile>(
              groupValue: useLegacy.value ? LandscapeGestureProfile.classic : selected.value,
              onChanged: (LandscapeGestureProfile? v) { if (useLegacy.value) return; if (v != null) selected.value = v; },
              child: Column(
                children: [
                  RadioListTile<LandscapeGestureProfile>(
                    value: LandscapeGestureProfile.region,
                    title: Text(t.gest_region_normal),
                    subtitle: Text(t.gest_region_normal_desc),
                    enabled: !useLegacy.value,
                  ),
                  RadioListTile<LandscapeGestureProfile>(
                    value: LandscapeGestureProfile.rightSide,
                    title: Text(t.gest_region_right),
                    subtitle: Text(t.gest_region_right_desc),
                    enabled: !useLegacy.value,
                  ),
                  RadioListTile<LandscapeGestureProfile>(
                    value: LandscapeGestureProfile.leftSide,
                    title: Text(t.gest_region_left),
                    subtitle: Text(t.gest_region_left_desc),
                    enabled: !useLegacy.value,
                  ),
                ],
              ),
            ),
            const Divider(),
            CheckboxListTile(
              value: useLegacy.value,
              title: Text(t.gest_no_region),
              subtitle: Text(t.gest_no_region_desc),
              onChanged: (v) => syncLegacy(v ?? false),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.touch_app, size: 18),
                  label: Text(t.gest_edit_regions),
                  onPressed: () async {
                    Navigator.pop(context);
                    await openGestureRegionSettings(context);
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text(t.gest_reset),
                  onPressed: () async {
                    Navigator.pop(context);
                    // ignore: use_build_context_synchronously
                    showResetGestureLayoutDialog(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ElevatedButton(
          onPressed: () async {
            final store = useAppStore();
            if (useLegacy.value) {
              await store.updateLandscapeGestureProfile(LandscapeGestureProfile.classic);
              await store.updatePortraitGestureProfile(PortraitGestureProfile.classic);
            } else {
              // portrait always region when not legacy
              await store.updatePortraitGestureProfile(PortraitGestureProfile.region);
              await store.updateLandscapeGestureProfile(selected.value);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(t.gest_confirm),
        ),
      ],
    );
  }
}
