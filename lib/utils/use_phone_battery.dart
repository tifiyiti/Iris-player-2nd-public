import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/platform.dart';

int useBatteryLevel() {
  if (!isMobilePlatform) return 0; //  no hook work on desktop

  final battery = useMemoized(() => Battery());
  final level = useState<int>(-1);

  useEffect(() {
    bool mounted = true;

    Future<void> load() async {
      try {
        final v = await battery.batteryLevel;
        if (mounted) level.value = v;
      } catch (_) {
        if (mounted) level.value = -1;
      }
    }

    final sub = battery.onBatteryStateChanged.listen((_) => load());

    load();

    return () {
      mounted = false;
      sub.cancel();
    };
  }, [battery]);

  return level.value < 0 ? 0 : level.value;
}
