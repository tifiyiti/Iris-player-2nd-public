import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/file_size_convert.dart';

void main() {
  group('formatFileSize', () {
    test('returns 0 B for zero and negative input', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(-1), '0 B');
    });

    test('keeps sub-KB values in bytes with an explicit unit', () {
      expect(formatFileSize(1), '1.00 B');
      expect(formatFileSize(512), '512.00 B');
      expect(formatFileSize(1023), '1023.00 B');
    });

    test('scales to KB / MB / GB / TB at the 1024 boundaries', () {
      expect(formatFileSize(1024), '1.00 KB');
      expect(formatFileSize(1536), '1.50 KB');
      expect(formatFileSize(1024 * 1024), '1.00 MB');
      expect(formatFileSize(1572864), '1.50 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.00 GB');
      expect(formatFileSize(1024 * 1024 * 1024 * 1024), '1.00 TB');
    });

    test('every non-zero result carries a unit suffix', () {
      for (final bytes in [1, 512, 1024, 1572864, 1024 * 1024 * 1024]) {
        expect(formatFileSize(bytes), matches(r'^[\d.]+ (B|KB|MB|GB|TB)$'));
      }
    });

    test('clamps oversized input to the largest known unit', () {
      expect(formatFileSize(1024 * 1024 * 1024 * 1024 * 1024), '1024.00 TB');
    });
  });
}
