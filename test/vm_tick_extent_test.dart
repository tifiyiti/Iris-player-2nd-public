import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/rule/vm_tick_extent.dart';

void main() {
  test('default extent is 3px within 0-10 range', () {
    expect(kVmTickExtentDefaultPx, 3);
    expect(kVmTickExtentMinPx, 0);
    expect(kVmTickExtentMaxPx, 10);
  });

  test('sanitize clamps to 0-10, garbage degrades to default', () {
    expect(sanitizeVmTickExtentPx(null), kVmTickExtentDefaultPx);
    expect(sanitizeVmTickExtentPx(''), kVmTickExtentDefaultPx);
    expect(sanitizeVmTickExtentPx('garbage'), kVmTickExtentDefaultPx);
    expect(sanitizeVmTickExtentPx('3'), 3);
    expect(sanitizeVmTickExtentPx('0'), 0);
    expect(sanitizeVmTickExtentPx('10'), 10);
    expect(sanitizeVmTickExtentPx('-1'), 0);
    expect(sanitizeVmTickExtentPx('99'), 10);
  });

  test('label renders Npx', () {
    expect(vmTickExtentLabel(3), '3px');
    expect(vmTickExtentLabel(0), '0px');
  });
}
