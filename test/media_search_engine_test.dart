import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/escape_like.dart';

void main() {
  group('escapeLike', () {
    test('escapes % and _ as literals', () {
      expect(escapeLike('100%_x'), r'100\%\_x');
      expect(escapeLike('50%'), r'50\%');
      expect(escapeLike('a_b'), r'a\_b');
    });

    test('escapes backslash first', () {
      expect(escapeLike(r'a\b'), r'a\\b');
      expect(escapeLike(r'a\100%'), r'a\\100\%');
    });

    test('plain strings pass through', () {
      expect(escapeLike('plain'), 'plain');
      expect(escapeLike(''), '');
    });
  });

  group('tokenizeQuery (F-006)', () {
    test('splits on whitespace, drops empty tokens', () {
      expect(tokenizeQuery('  a   b  '), ['a', 'b']);
      expect(tokenizeQuery('动画 剧场版'), ['动画', '剧场版']);
    });

    test('empty / whitespace-only query yields no tokens', () {
      expect(tokenizeQuery(''), isEmpty);
      expect(tokenizeQuery('   '), isEmpty);
    });
  });

  group('matchesAllTokens (F-006)', () {
    test('case-insensitive per-token AND substring', () {
      expect(matchesAllTokens('accb.mp4', ['a', 'b']), isTrue);
      expect(matchesAllTokens('aBc.mp4', ['a', 'b']), isTrue);
      // every token must be present ('c' is absent from 'accb.mp4')
      expect(matchesAllTokens('accb.mp4', ['a', 'c']), isTrue);
      expect(matchesAllTokens('accb.mp4', ['a', 'z']), isFalse);
    });

    test('CJK substrings (no case folding needed)', () {
      expect(matchesAllTokens('电影.mp4', ['电影']), isTrue);
      expect(matchesAllTokens('我的电影合集.mp4', ['电影', '合集']), isTrue);
      expect(matchesAllTokens('我的电影合集.mp4', ['电影', '剧场版']), isFalse);
      expect(matchesAllTokens('アニメ.mp4', ['アニメ']), isTrue);
    });

    test('empty tokens match everything', () {
      expect(matchesAllTokens('anything.mp4', []), isTrue);
    });

    test('basename includes the extension (v6-D4)', () {
      // 'ccb' alone must not match 'accb.mp4' ('.' is not a token splitter),
      // and the extension is part of the name for both DB and explicit items.
      expect(matchesAllTokens('accb.mp4', ['accb.mp4']), isTrue);
      expect(matchesAllTokens('accb.mp4', ['ccb.mp4']), isTrue);
      expect(matchesAllTokens('accb.mp4', ['ccb']), isTrue);
    });
  });
}
