import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/enums/breadcrumb_start_side.dart'
    show BreadcrumbStartSide, BreadcrumbStartSideLabel;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart' show getLocalizations;

Future<void> openBreadcrumbSettings(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const BreadcrumbSettingsDialog(),
  );
}

class BreadcrumbSettingsDialog extends HookWidget {
  const BreadcrumbSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final store = useAppStore();
    final t = getLocalizations(context);

    final portrait = useState(store.state.breadcrumbStartPortrait);
    final landscape = useState(store.state.breadcrumbStartLandscape);

    final navigator = Navigator.of(context); // capture before async

    return AlertDialog(
      title: Text(t.breadcrumb_start_side),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Portrait
            Text(
              t.portrait,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<BreadcrumbStartSide>(
              groupValue: portrait.value,
              onChanged: (v) => portrait.value = v!,
              child: Column(
                children: [
                  for (final v in BreadcrumbStartSide.values)
                    RadioListTile<BreadcrumbStartSide>(
                      value: v,
                      title: Text(v.label(t)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            /// Landscape
            Text(
              t.landscape,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<BreadcrumbStartSide>(
              groupValue: landscape.value,
              onChanged: (v) => landscape.value = v!,
              child: Column(
                children: [
                  for (final v in BreadcrumbStartSide.values)
                    RadioListTile<BreadcrumbStartSide>(
                      value: v,
                      title: Text(v.label(t)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: navigator.pop,
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            await store.updateBreadcrumbStartPortrait(portrait.value);
            await store.updateBreadcrumbStartLandscape(landscape.value);

            navigator.pop(); // safe, no context used
          },
          child: Text(t.ok),
        ),
      ],
    );
  }
}
