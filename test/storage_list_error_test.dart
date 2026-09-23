import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/webdav.dart';

void main() {
  group('classifyStorageListFailure', () {
    test('the platform cleartext policy maps to httpBlocked', () {
      expect(
        classifyStorageListFailure(
          Exception('Insecure HTTP is not allowed by platform: http://x/'),
        ),
        StorageListErrorKind.httpBlocked,
      );
      expect(
        classifyStorageListFailure(
          Exception('Cleartext HTTP traffic to 192.168.1.4 not permitted'),
        ),
        StorageListErrorKind.httpBlocked,
      );
    });

    test('rejected credentials are distinguished from unreachability', () {
      expect(
        classifyStorageListFailure(Exception('HTTP status code 401')),
        StorageListErrorKind.unauthorized,
      );
      expect(
        classifyStorageListFailure(Exception('403 Forbidden')),
        StorageListErrorKind.unauthorized,
      );
    });

    test('timeouts and transport failures', () {
      expect(
        classifyStorageListFailure(TimeoutException('x')),
        StorageListErrorKind.timeout,
      );
      expect(
        classifyStorageListFailure(SocketException('Connection refused')),
        StorageListErrorKind.unreachable,
      );
      expect(
        classifyStorageListFailure(Exception('Failed host lookup: nas.local')),
        StorageListErrorKind.unreachable,
      );
    });

    test('anything else falls back to unknown', () {
      expect(
        classifyStorageListFailure(Exception('boom')),
        StorageListErrorKind.unknown,
      );
    });
  });

  group('FileListResult', () {
    test('an empty list with no kind is a successful empty directory', () {
      expect(FileListResult.empty.hasError, isFalse);
      expect(FileListResult.empty.items, isEmpty);
      expect(FileListResult.empty.errorKind, isNull);
    });

    test('a kind marks the listing as failed and carries the detail', () {
      const result = FileListResult(
        <FileItem>[],
        errorKind: StorageListErrorKind.httpBlocked,
        errorDetail: 'Insecure HTTP is not allowed by platform',
      );
      expect(result.hasError, isTrue);
      expect(result.items, isEmpty);
      expect(result.errorDetail, contains('Insecure HTTP'));
    });
  });
}
