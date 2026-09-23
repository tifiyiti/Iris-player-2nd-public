import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/rule/vm_tick_color.dart';

void main() {
  test('default tick color is opaque white', () {
    expect(kVmTickColorDefaultArgb, 0xFFFFFFFF);
    expect(kVmTickColorPresets, contains(kVmTickColorDefaultArgb));
  });

  test('presets are non-empty opaque 32-bit colors', () {
    expect(kVmTickColorPresets, isNotEmpty);
    for (final c in kVmTickColorPresets) {
      expect(c & 0xFF000000, isNot(0),
          reason: 'preset ${c.toRadixString(16)} must carry alpha');
    }
  });

  test('sanitize accepts decimal ARGB, rejects out-of-range/garbage', () {
    expect(sanitizeVmTickColorArgb(null), kVmTickColorDefaultArgb);
    expect(sanitizeVmTickColorArgb(''), kVmTickColorDefaultArgb);
    expect(sanitizeVmTickColorArgb('garbage'), kVmTickColorDefaultArgb);
    expect(sanitizeVmTickColorArgb('4294967295'), 0xFFFFFFFF);
    expect(sanitizeVmTickColorArgb('4278190080'), 0xFF000000);
    expect(sanitizeVmTickColorArgb('4294967296'), kVmTickColorDefaultArgb);
    expect(sanitizeVmTickColorArgb('-1'), kVmTickColorDefaultArgb);
  });

  test('sanitize accepts #RRGGBB / #AARRGGBB hex', () {
    expect(sanitizeVmTickColorArgb('#FFFFFF'), 0xFFFFFFFF);
    expect(sanitizeVmTickColorArgb('#FF0000'), 0xFFFF0000);
    expect(sanitizeVmTickColorArgb('#80FF0000'), 0x80FF0000);
    expect(sanitizeVmTickColorArgb('#GGGGGG'), kVmTickColorDefaultArgb);
  });

  test('label renders uppercase #AARRGGBB', () {
    expect(vmTickColorLabel(0xFFFFFFFF), '#FFFFFFFF');
    expect(vmTickColorLabel(0xFFFF0000), '#FFFF0000');
  });
}
