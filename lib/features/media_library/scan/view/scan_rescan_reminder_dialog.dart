import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/scan/model/scan_rescan_reminder.dart';
import 'package:iris/utils/get_localizations.dart';

/// Opens the rescan-reminder window editor (HH 2-digit : MM 2-digit).
Future<void> openScanRescanReminder(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ScanRescanReminderDialog(),
  );
}

/// Two-cell HH:MM input for the "距上次完整扫描多久后提醒重扫" window.
///
/// - Hours: 2 digits (0-99), auto-advance to minutes on 2 digits or Enter.
/// - Minutes: 2 digits, over-length digits are dropped (分过长直接舍弃).
/// - 0 disables the reminder entirely.
class ScanRescanReminderDialog extends HookWidget {
  const ScanRescanReminderDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final minutes = useState<int?>(null);
    final hhCtrl = useTextEditingController();
    final mmCtrl = useTextEditingController();
    final hhNode = useFocusNode();
    final mmNode = useFocusNode();

    useEffect(() {
      var cancelled = false;
      ScanRescanReminder.load().then((v) {
        if (cancelled) return;
        minutes.value = v;
        hhCtrl.text = '${v ~/ 60}'.padLeft(2, '0');
        mmCtrl.text = '${v % 60}'.padLeft(2, '0');
      });
      return () => cancelled = true;
    }, const []);

    void commit() {
      final h = int.tryParse(hhCtrl.text) ?? 0;
      final m = int.tryParse(mmCtrl.text) ?? 0;
      minutes.value = (h.clamp(0, 99) * 60 + m.clamp(0, 59)).clamp(0, 24 * 60);
    }

    return AlertDialog(
      title: Text(t.scan_reminder_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.scan_reminder_body,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(t.scan_reminder_over, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: hhCtrl,
                  focusNode: hhNode,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (t) {
                    if (t.length == 2) mmNode.requestFocus();
                    commit();
                  },
                  onSubmitted: (_) {
                    mmNode.requestFocus();
                    commit();
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(':'),
              ),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: mmCtrl,
                  focusNode: mmNode,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (_) => commit(),
                  onSubmitted: (_) => commit(),
                ),
              ),
              const SizedBox(width: 8),
              Text(t.scan_reminder_hm, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            final v = minutes.value ?? ScanRescanReminder.defaultMinutes;
            await ScanRescanReminder.save(v);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(t.ok),
        ),
      ],
    );
  }
}
