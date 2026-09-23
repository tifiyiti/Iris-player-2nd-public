import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/services/open_with_service.dart';
import 'package:iris/models/storages/storage.dart';

void main() {
  group('isOpenWithActionVisible', () {
    test('android + device-local storage + playable file path → true', () {
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.internal,
          playable: true,
          uri: '/storage/emulated/0/Movies/a.mp4',
        ),
        isTrue,
      );
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.usb,
          playable: true,
          uri: '/mnt/usb/a.mkv',
        ),
        isTrue,
      );
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.sdcard,
          playable: true,
          uri: '/sdcard/a.flac',
        ),
        isTrue,
      );
    });

    test('remote storages are browse-only → false', () {
      for (final type in [
        StorageType.webdav,
        StorageType.ftp,
        StorageType.network,
        StorageType.none,
      ]) {
        expect(
          isOpenWithActionVisible(
            onAndroid: true,
            storageType: type,
            playable: true,
            uri: '/x/a.mp4',
          ),
          isFalse,
          reason: '$type must not offer open-with',
        );
      }
    });

    test('non-android platforms never offer it', () {
      expect(
        isOpenWithActionVisible(
          onAndroid: false,
          storageType: StorageType.internal,
          playable: true,
          uri: 'D:/Movies/a.mp4',
        ),
        isFalse,
      );
    });

    test('http(s) and empty uris are excluded', () {
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.internal,
          playable: true,
          uri: 'http://example.com/a.mp4',
        ),
        isFalse,
      );
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.internal,
          playable: true,
          uri: '',
        ),
        isFalse,
      );
    });

    test('directories / non-media items are excluded', () {
      expect(
        isOpenWithActionVisible(
          onAndroid: true,
          storageType: StorageType.internal,
          playable: false,
          uri: '/storage/a.txt',
        ),
        isFalse,
      );
    });
  });
}
