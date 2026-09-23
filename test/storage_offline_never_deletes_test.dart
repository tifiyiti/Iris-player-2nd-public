import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/storages/ftp.dart';

// RED tests for the offline-means-grey policy:
// - unreachable is classified, never mistaken for an empty directory;
// - FTP failures will carry a FileListResult kind (see P0 implementation).
void main() {
  group('offline never deletes', () {
    test('FTP transport failure maps to unreachable (not empty success)', () {
      expect(
        classifyFtpListFailure(
          const SocketException('Connection refused, host=192.168.1.2'),
        ),
        StorageListErrorKind.unreachable,
      );
    });

    test('FTP auth failure maps to unauthorized', () {
      expect(
        classifyFtpListFailure(Exception('530 Login incorrect')),
        StorageListErrorKind.unauthorized,
      );
    });

    test('FTP timeout maps to timeout', () {
      expect(
        classifyFtpListFailure(Exception('TimeoutException after 0:00:15')),
        StorageListErrorKind.timeout,
      );
    });
  });
}
