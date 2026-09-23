import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 安装后显示名必须为「IRIS」，且技术标识保持 IRIS 不变。
///
/// 覆盖范围：Android launcher 标签、Windows 开始菜单/桌面快捷方式名、
/// MSIX display_name。其余（包名、进程名、产物文件名、应用内标题）不在此断言。
void main() {
  test('Android launcher label is IRIS', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    // The label is a localized string resource, not a literal: the manifest
    // points at @string/app_name so Android can pick the Chinese name on a
    // zh locale. Asserting the literal here would break the moment the label
    // was localized (it did).
    expect(manifest, contains('android:label="@string/app_name"'));

    final en = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    expect(en, contains('<string name="app_name">IRIS</string>'));

    // The zh name is product copy that may change; only lock that the resource
    // exists and carries a non-empty value, so this test cannot go stale again.
    final zh = File(
      'android/app/src/main/res/values-zh/strings.xml',
    ).readAsStringSync();
    expect(zh, matches(RegExp(r'<string name="app_name">\s*\S')));
  });

  test('Windows shortcuts display IRIS, technical names stay IRIS',
      () {
    final iss = File('inno.iss').readAsStringSync();
    expect(iss, contains('IRIS'));
    // 安装目录 / 注册表 / 卸载项的技术标识不动。
    expect(iss, contains('#define MyAppName "IRIS"'));
    expect(iss, contains(r'DefaultDirName={autopf}\{#MyAppName}'));
  });

  test('MSIX display name is IRIS, identity stays', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('display_name: IRIS'));
    expect(pubspec, contains('identity_name: 22P.IRISplayer'));
  });
}
