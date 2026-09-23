import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves storage locations for app-identity artifacts (prepared icons).
///
/// Initialized once during startup; before that [filePath] returns '' and
/// callers render placeholders instead of crashing.
abstract final class AppIdentityPaths {
  static String? _root;

  /// Idempotent init (called from completeStartupInitialization).
  static Future<void> ensureInitialized() async {
    if (_root != null) return;
    final docs = await getApplicationDocumentsDirectory();
    _root = p.join(docs.path, 'identity');
  }

  /// Root directory holding all prepared icons ('' before initialization).
  static String get root => _root ?? '';

  /// Absolute path of a stored icon from its relative [ref].
  static String filePath(String ref) =>
      (_root == null || ref.isEmpty) ? '' : p.join(_root!, ref);
}
