import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/window_fit_mode.dart';

void main() {
  // 1920×1080 等仅为测试夹具（便于手算 right - width / bottom - height），
  // 生产代码取的是 getCurrentScreen().visibleFrame / scaleFactor 的真实工作区，
  // 对 2K/4K/带缩放屏自适应（见 use_keep_window_in_bounds.dart 与 window_fit_mode.dart）。
  group('clampWindowToVisibleBounds', () {
    test('window fully inside stays unchanged', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(100, 100, 800, 600);
      expect(clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible), win);
    });

    test('left overflow clamps to left', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(-200, 100, 800, 600);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.left, 0);
      expect(clamped.top, 100);
      expect(clamped.size, win.size);
    });

    test('right overflow clamps to right edge', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(1500, 100, 800, 600);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.left, 1920 - 800);
      expect(clamped.top, 100);
    });

    test('top overflow clamps to top', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(100, -50, 800, 600);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.top, 0);
      expect(clamped.left, 100);
    });

    test('bottom overflow clamps to bottom', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(100, 800, 800, 600);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.top, 1080 - 600);
    });

    test('corner overflow', () {
      const visible = Rect.fromLTWH(0, 0, 1920, 1080);
      const win = Rect.fromLTWH(-100, -100, 400, 300);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.left, 0);
      expect(clamped.top, 0);
    });

    test('window larger than visibleFrame pins to origin', () {
      const visible = Rect.fromLTWH(0, 0, 800, 600);
      const win = Rect.fromLTWH(100, 100, 1000, 800);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.left, 0);
      expect(clamped.top, 0);
      expect(clamped.size, win.size);
    });

    test('visibleFrame empty returns window unchanged', () {
      const visible = Rect.zero;
      const win = Rect.fromLTWH(100, 100, 800, 600);
      expect(clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible), win);
    });

    test('visibleFrame offset (multi-monitor simulation)', () {
      const visible = Rect.fromLTWH(1920, 0, 1920, 1080);
      const win = Rect.fromLTWH(1800, 100, 800, 600);
      final clamped = clampWindowToVisibleBounds(windowBounds: win, visibleFrame: visible);
      expect(clamped.left, 1920);
    });
  });
}
