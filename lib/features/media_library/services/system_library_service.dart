import 'package:iris/features/media_library/services/sync_default_system_library.dart';

class SystemLibraryService {
  static bool _initialized = false;

  static Future<void> ensureReady() async {
    if (_initialized) return;

    _initialized = true;

    await syncDefaultSystemLibrary();
  }

  static Future<void> refreshSources() async {
    await syncDefaultSystemLibrary();
  }
}
