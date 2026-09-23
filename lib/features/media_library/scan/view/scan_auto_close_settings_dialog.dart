import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';

Future<void> openScanAutoCloseSettings(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const ScanAutoCloseSettingsDialog(),
  );
}

class ScanAutoCloseSettingsDialog extends HookWidget {
  const ScanAutoCloseSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final scanStore = useRecursiveScanStore();
    final delay = useState(scanStore.state.autoCloseDelay);

    final navigator = Navigator.of(context);

    return AlertDialog(
      title: const Text('Scan auto-close'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Time to wait after scan completes before closing the progress bar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              delay.value <= 0
                  ? 'Close immediately'
                  : '${delay.value.toStringAsFixed(1)} seconds',
            ),
            Slider(
              value: delay.value,
              min: 0,
              max: 15,
              divisions: 30,
              label: delay.value <= 0
                  ? 'Immediate'
                  : '${delay.value.toStringAsFixed(1)}s',
              onChanged: (v) => delay.value = v,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: navigator.pop,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            await scanStore.updateAutoCloseDelay(delay.value);
            navigator.pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
