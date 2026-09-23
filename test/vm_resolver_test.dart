import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/resolver/vm_resolver.dart';
import 'package:iris/features/virtual_media/rule/vm_title_composer.dart';

VirtualSegment seg(String path,
    {int? durationMs, int? width, int? height, String storage = 'st1'}) {
  final parts = path.split('/');
  final name = parts.last;
  return VirtualSegment(
    mediaKey: '$storage:$path',
    storageId: storage,
    path: parts,
    name: name,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
    width: width,
    height: height,
  );
}

VirtualMediaRule rule({
  String id = 'r1',
  String name = '规则A',
  VmMatchMode matchMode = VmMatchMode.specifiedDir,
  List<String> paths = const [],
  List<VmPatternEntry> patterns = const [],
  VmSortField sortField = VmSortField.fileName,
  SortDirection sortDir = SortDirection.asc,
  VmBoundaryMode boundary = VmBoundaryMode.sameDirOnly,
  int maxDurationMinutes = 90,
  List<VmTitleTag> titleTags = const [VmTitleTag.dirName, VmTitleTag.seq],
  bool enabled = true,
  bool pinned = false,
}) {
  return VirtualMediaRule(
    id: id,
    name: name,
    matchMode: matchMode,
    paths: paths,
    patterns: patterns,
    sortField: sortField,
    sortDir: sortDir,
    boundary: boundary,
    maxDurationMinutes: maxDurationMinutes,
    titleTags: titleTags,
    enabled: enabled,
    pinned: pinned,
    // These tests exercise chunking/matching mechanics in isolation; the
    // per-file exclusion defaults are covered by vm_exclusion_rules_test.
    useExcludeOverlong: false,
    skipSingleSegment: false,
  );
}

void main() {
  group('指定目录 matching', () {
    test('non-recursive takes only direct media, natural name order', () {
      final items = resolveVirtualMedia(
        rules: [rule(paths: ['Shorts/A'])],
        library: [
          seg('Shorts/A/002.mp4', durationMs: 60000),
          seg('Shorts/A/001.mp4', durationMs: 60000),
          seg('Shorts/A/010.mp4', durationMs: 60000),
          seg('Shorts/A/sub/003.mp4'),
          seg('Shorts/B/001.mp4'),
        ],
      );
      expect(items, hasLength(1));
      expect(items.first.segments.map((s) => s.name).toList(),
          ['001.mp4', '002.mp4', '010.mp4']);
    });

    test('recursive pulls the whole subtree', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
              matchMode: VmMatchMode.specifiedDirRecursive,
              paths: ['Col'],
              boundary: VmBoundaryMode.ignoreDirs),
        ],
        library: [
          seg('Col/A/001.mp4'),
          seg('Col/B/002.mp4'),
          seg('Outside/003.mp4'),
        ],
      );
      expect(items, hasLength(1));
      expect(items.first.segments, hasLength(2));
    });

    test('multiple picked paths are a UNION', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
              boundary: VmBoundaryMode.ignoreDirs,
              paths: ['A', 'B'],
              titleTags: const [VmTitleTag.seq]),
        ],
        library: [seg('A/1.mp4'), seg('B/2.mp4'), seg('C/3.mp4')],
      );
      expect(items, hasLength(1));
      expect(items.first.segments, hasLength(2));
    });

    test('empty paths match nothing', () {
      final items = resolveVirtualMedia(
          rules: [rule(paths: [])], library: [seg('A/1.mp4')]);
      expect(items, isEmpty);
    });
  });

  group('匹配目录 AND semantics', () {
    VmPatternEntry p(VmPatternKind kind, String text,
            {bool activated = true, bool pinned = false}) =>
        VmPatternEntry(
            kind: kind, text: text, activated: activated, pinned: pinned);

    test('all activated entries must hold (suffix + contains)', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
            matchMode: VmMatchMode.patternDir,
            patterns: [p(VmPatternKind.suffix, '_dirs_as_virtual'),
                p(VmPatternKind.contains, 'anime')],
          ),
        ],
        library: [
          seg('V/x_anime_dirs_as_virtual/a.mp4'),
          seg('V/y_anime/b.mp4'),
          seg('V/z_dirs_as_virtual/c.mp4'),
        ],
      );
      expect(items, hasLength(1));
      expect(items.first.rootPath, 'V/x_anime_dirs_as_virtual');
    });

    test('deactivated entries are ignored', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
            matchMode: VmMatchMode.patternDir,
            patterns: [p(VmPatternKind.suffix, '_need'),
                p(VmPatternKind.contains, 'zzz', activated: false)],
          ),
        ],
        library: [seg('V/a_need/x.mp4'), seg('V/b/y.mp4')],
      );
      expect(items, hasLength(1));
      expect(items.first.rootPath, 'V/a_need');
    });

    test('zero activated entries never match', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
            matchMode: VmMatchMode.patternDir,
            patterns: [p(VmPatternKind.prefix, 'a', activated: false)],
          ),
        ],
        library: [seg('a_dir/x.mp4')],
      );
      expect(items, isEmpty);
    });

    test('recursive includes matched dirs and their subtrees', () {
      final items = resolveVirtualMedia(
        rules: [
          rule(
            matchMode: VmMatchMode.patternDirRecursive,
            patterns: [p(VmPatternKind.suffix, '_need')],
            boundary: VmBoundaryMode.ignoreDirs,
            titleTags: const [VmTitleTag.seq],
          ),
        ],
        library: [
          seg('V/X_need/a.mp4'),
          seg('V/X_need/deep/b.mp4'),
          seg('V/plain/c.mp4'),
        ],
      );
      expect(items, hasLength(1));
      expect(items.first.segments, hasLength(2));
    });

    test('four kinds + invalid regex fails closed', () {
      final lib = [
        seg('pre_a/x.mp4'),
        seg('b_suf/y.mp4'),
        seg('mid_zz/w.mp4'),
        seg('Rx9/z.mp4'),
        seg('unmatched/q.mp4'),
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
            id: 'kind',
            name: 'k',
            matchMode: VmMatchMode.patternDir,
            paths: const [],
            patterns: [p(VmPatternKind.prefix, 'pre_')],
            titleTags: const [VmTitleTag.dirName],
          ),
        ],
        library: lib,
      );
      expect(items.single.rootPath, 'pre_a');

      final suffix = resolveVirtualMedia(
          rules: [
            rule(
                matchMode: VmMatchMode.patternDir,
                patterns: [p(VmPatternKind.suffix, 'suf')],
                titleTags: const [VmTitleTag.dirName])
          ],
          library: lib);
      expect(suffix.single.rootPath, 'b_suf');

      final contains = resolveVirtualMedia(
          rules: [
            rule(
                matchMode: VmMatchMode.patternDir,
                patterns: [p(VmPatternKind.contains, 'zz')],
                titleTags: const [VmTitleTag.dirName])
          ],
          library: lib);
      expect(contains.single.rootPath, 'mid_zz');

      final regex = resolveVirtualMedia(
          rules: [
            rule(
                matchMode: VmMatchMode.patternDir,
                patterns: [p(VmPatternKind.regex, r'^rx\d+$')],
                titleTags: const [VmTitleTag.dirName])
          ],
          library: lib);
      expect(regex.single.rootPath, 'Rx9'); // case-insensitive

      final broken = resolveVirtualMedia(
          rules: [
            rule(
                matchMode: VmMatchMode.patternDir,
                patterns: [p(VmPatternKind.regex, '([bad')],
                titleTags: const [VmTitleTag.dirName])
          ],
          library: lib);
      expect(broken, isEmpty);
    });
  });

  group('排序', () {
    test('aspectRatio asc then unprobed last; mediaKey tie-break', () {
      final lib = [
        seg('S/a.mp4', width: 720, height: 1280), // 0.5625
        seg('S/b.mp4', width: 1920, height: 1080), // 1.777
        seg('S/c.mp4', width: 1920, height: 1080), // tie → mediaKey
        seg('S/d.mp4'), // unprobed → last
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
              paths: ['S'],
              sortField: VmSortField.aspectRatio,
              titleTags: const [VmTitleTag.seq]),
        ],
        library: lib,
      );
      expect(items.first.segments.map((s) => s.name).toList(),
          ['a.mp4', 'b.mp4', 'c.mp4', 'd.mp4']);
    });

    test('resolution desc puts 4K first, unprobed still last', () {
      final lib = [
        seg('S/a.mp4', width: 1920, height: 1080),
        seg('S/b.mp4', width: 3840, height: 2160),
        seg('S/c.mp4'),
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
              paths: ['S'],
              sortField: VmSortField.resolution,
              sortDir: SortDirection.desc),
        ],
        library: lib,
      );
      expect(items.first.segments.map((s) => s.name).toList(),
          ['b.mp4', 'a.mp4', 'c.mp4']);
    });

    test('width / height / duration numeric sorts', () {
      final lib = [
        seg('S/a.mp4', width: 1280, height: 720, durationMs: 50),
        seg('S/b.mp4', width: 1920, height: 1080, durationMs: 10),
        seg('S/c.mp4'),
      ];
      List<String> names(VmSortField f, SortDirection d) =>
          resolveVirtualMedia(
            rules: [rule(paths: ['S'], sortField: f, sortDir: d)],
            library: lib,
          ).first.segments.map((s) => s.name).toList();
      expect(names(VmSortField.width, SortDirection.asc),
          ['a.mp4', 'b.mp4', 'c.mp4']);
      expect(names(VmSortField.width, SortDirection.desc),
          ['b.mp4', 'a.mp4', 'c.mp4']);
      expect(names(VmSortField.height, SortDirection.desc),
          ['b.mp4', 'a.mp4', 'c.mp4']);
      expect(names(VmSortField.duration, SortDirection.asc),
          ['b.mp4', 'a.mp4', 'c.mp4']);
    });

    test('natural file name: 2 before 10', () {
      final items = resolveVirtualMedia(
          rules: [rule(paths: ['N'])],
          library: [seg('N/10.mp4'), seg('N/2.mp4')]);
      expect(items.first.segments.map((s) => s.name).toList(),
          ['2.mp4', '10.mp4']);
    });
  });

  group('分组', () {
    test('sameDirOnly never merges across directories', () {
      final lib = [
        seg('K/A/1.mp4', durationMs: 30 * 60000),
        seg('K/B/2.mp4', durationMs: 30 * 60000),
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
              matchMode: VmMatchMode.specifiedDirRecursive,
              paths: ['K'],
              boundary: VmBoundaryMode.sameDirOnly),
        ],
        library: lib,
      );
      expect(items, hasLength(2));
      expect(items[0].rootPath, 'K/A');
      expect(items[1].rootPath, 'K/B');
    });

    test('crossDirMerge continues a chunk into the next directory', () {
      final lib = [
        seg('K/B/2.mp4', durationMs: 30 * 60000),
        seg('K/A/1.mp4', durationMs: 30 * 60000),
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
              matchMode: VmMatchMode.specifiedDirRecursive,
              paths: ['K'],
              boundary: VmBoundaryMode.crossDirMerge),
        ],
        library: lib,
      );
      expect(items, hasLength(1));
      expect(items.first.segments.map((s) => s.name).toList(),
          ['1.mp4', '2.mp4']); // dir A natural-first, sorted inside
    });

    test('ignoreDirs sorts globally then chunks', () {
      final lib = [
        seg('K/B/2.mp4', durationMs: 10 * 60000),
        seg('K/A/9.mp4', durationMs: 10 * 60000),
        seg('K/A/1.mp4', durationMs: 10 * 60000),
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(
              matchMode: VmMatchMode.specifiedDirRecursive,
              paths: ['K'],
              boundary: VmBoundaryMode.ignoreDirs,
              maxDurationMinutes: 25),
        ],
        library: lib,
      );
      // Global natural-name order: 1(A), 2(B), 9(A) → [1,2] then [9].
      expect(items, hasLength(2));
      expect(items[0].segments.map((s) => s.name).toList(),
          ['1.mp4', '2.mp4']);
      expect(items[1].segments.single.name, '9.mp4');
    });

    test('duration cap never splits an oversized single file', () {
      final lib = [
        seg('D/1.mp4', durationMs: 90 * 60000),
        seg('D/2.mp4', durationMs: 90 * 60000),
        seg('D/big.mp4', durationMs: 5 * 60 * 60000),
      ];
      final items = resolveVirtualMedia(
        rules: [rule(paths: ['D'], maxDurationMinutes: 120)],
        library: lib,
      );
      expect(items, hasLength(3));
      expect(items[2].segments.single.name, 'big.mp4');
      expect(items[2].totalDurationMs, 5 * 60 * 60000);
    });

    test('unknown-duration files merge contributing zero', () {
      final lib = [
        seg('U/1.mp4', durationMs: 30 * 60000),
        seg('U/2.mp4'), // unknown — probed lazily at session start
        seg('U/3.mp4', durationMs: 30 * 60000),
      ];
      final items = resolveVirtualMedia(
        rules: [rule(paths: ['U'], maxDurationMinutes: 120)],
        library: lib,
      );
      expect(items, hasLength(1));
      expect(items.single.segments.map((s) => s.name).toList(),
          ['1.mp4', '2.mp4', '3.mp4']);
      expect(items.single.totalDurationMs, 60 * 60000);
    });
  });

  group('规则独立性', () {
    test('overlapping rules BOTH produce items (no claiming)', () {
      final lib = [
        seg('F/1.mp4', durationMs: 30 * 60000),
        seg('F/2.mp4', durationMs: 30 * 60000)
      ];
      final items = resolveVirtualMedia(
        rules: [
          rule(id: 'broad', paths: ['F']),
          rule(
              id: 'narrow',
              paths: ['F'],
              maxDurationMinutes: 1), // each file overflows the cap
        ],
        library: lib,
      );
      expect(items.where((i) => i.ruleId == 'broad'), hasLength(1));
      expect(items.where((i) => i.ruleId == 'narrow'), hasLength(2));
    });

    test('disabled rule contributes nothing', () {
      final items = resolveVirtualMedia(
        rules: [rule(id: 'off', enabled: false, paths: ['Shorts/A'])],
        library: [seg('Shorts/A/1.mp4')],
      );
      expect(items, isEmpty);
    });

    test('pinned does not affect resolution (display only)', () {
      final a = resolveVirtualMedia(
          rules: [rule(paths: ['F'])], library: [seg('F/1.mp4')]);
      final b = resolveVirtualMedia(
          rules: [rule(paths: ['F'], pinned: true)],
          library: [seg('F/1.mp4')]);
      expect(a.length, b.length);
    });
  });

  group('标题与键', () {
    test('default tags compose dirName · seq', () {
      final items = resolveVirtualMedia(
          rules: [rule(paths: ['Show'])],
          library: [seg('Show/1.mp4')]);
      expect(items.single.displayName, 'Show · 1');
    });

    test('lit order IS the concatenation order', () {
      final title = composeVmTitle(
        tags: const [
          VmTitleTag.seq,
          VmTitleTag.firstFile,
          VmTitleTag.resolution,
          VmTitleTag.duration,
        ],
        ruleName: 'R',
        dirName: 'D',
        firstFile: 'e01.mp4',
        lastFile: 'e02.mp4',
        seq: 3,
        totalDurationMs: 90 * 60000,
        width: null,
        height: null,
      );
      expect(title, '3 · e01 · 1h30m'); // resolution omitted when unknown
    });

    test('the title carries the CHUNK number, not the queue position', () {
      // The leading position column already counts every row; the seq tag must
      // carry something ELSE ("this is the Nth merged block") or it would be
      // pure duplication of the column beside it.
      final title = composeVmTitle(
        tags: const [VmTitleTag.dirName, VmTitleTag.seq],
        ruleName: 'R',
        dirName: 'D',
        firstFile: 'e01.mp4',
        lastFile: 'e02.mp4',
        seq: 2,
        totalDurationMs: 0,
        width: null,
        height: null,
      );
      expect(title, 'D · 2');
    });

    test('chunk numbers restart per directory when the rule keeps dirs apart',
        () {
      // sameDirOnly: a directory is the group's own scope, so its blocks are
      // numbered from 1 — a title reading `dirName · N` counts THAT
      // directory's blocks (the page's row order is a different space). If the
      // list later reorders or a file is excluded, the numbers do not renumber.
      final items = resolveVirtualMedia(
        rules: [rule(paths: ['A', 'B'])],
        library: [
          seg('A/1.mp4'),
          seg('A/2.mp4'),
          seg('B/3.mp4'),
        ],
      );
      expect(items.map((e) => e.displayIndex).toList(), [1, 1]);
      expect(items.map((e) => e.displayName).toList(), ['A · 1', 'B · 1']);
    });

    test('a cross-directory rule numbers within the RULE, not the directory',
        () {
      // One file per chunk (cap = 1 minute, 60s files) so the scope of the
      // numbering is visible: crossDirMerge has no directory bucket, so the
      // sequence continues across the A → B boundary.
      final items = resolveVirtualMedia(
        rules: [
          rule(
            paths: ['A', 'B'],
            boundary: VmBoundaryMode.crossDirMerge,
            maxDurationMinutes: 1,
          ),
        ],
        library: [
          seg('A/1.mp4', durationMs: 60000),
          seg('A/2.mp4', durationMs: 60000),
          seg('B/3.mp4', durationMs: 60000),
        ],
      );
      expect(items.map((e) => e.displayIndex).toList(), [1, 2, 3]);
      expect(items.map((e) => e.displayName).toList(),
          ['A · 1', 'A · 2', 'B · 3']);
    });

    test('two rules on one directory each number from 1 (scope is per rule)',
        () {
      // The numbering scope is the RULE (or its directory bucket): two rules
      // claiming the same folder both emit `Show · 1`. They stay distinct by
      // scopeKey (rule id) and, when the ruleName tag is lit, by the title.
      final items = resolveVirtualMedia(
        rules: [
          rule(id: 'r1', name: 'R1', paths: ['Show']),
          rule(id: 'r2', name: 'R2', paths: ['Show']),
        ],
        library: [seg('Show/1.mp4'), seg('Show/2.mp4')],
      );
      expect(
          items.map((e) => e.displayName).toList(), ['Show · 1', 'Show · 1']);
      expect(items.map((e) => e.displayIndex).toList(), [1, 1]);
      expect(
          items.map((e) => e.scopeKey).toList(), ['r1|Show|#1', 'r2|Show|#1']);
    });

    test('root-dir fallback name and scopeKey stability', () {
      final items = resolveVirtualMedia(
          rules: [rule(name: 'X', paths: [''])],
          library: [seg('1.mp4')]);
      expect(items.single.rootPath, '');
      expect(items.single.scopeKey, 'r1||#1');
    });
  });

  group('position mapping', () {
    test('locate maps virtual position to segment + local offset', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|k|1',
        rootPath: 'k',
        displayIndex: 1,
        displayName: 'k',
        segments: [
          seg('k/1.mp4', durationMs: 1000),
          seg('k/2.mp4', durationMs: 2000),
          seg('k/3.mp4', durationMs: 500),
        ],
      );
      expect(item.totalDurationMs, 3500);
      expect(item.locate(0), (0, 0));
      expect(item.locate(999), (0, 999));
      expect(item.locate(1000), (1, 0));
      expect(item.locate(2500), (1, 1500));
      expect(item.locate(3499), (2, 499));
      expect(item.locate(99999), (2, 500));
      expect(item.offsetOf(2), 3000);
      expect(item.indexOfSegmentKey('st1:k/2.mp4'), 1);
    });

    test('withDuration copies identity and flips estimated flag', () {
      final s = seg('k/1.mp4', durationMs: 100);
      final fixed = s.withDuration(5000);
      expect(fixed.mediaKey, s.mediaKey);
      expect(fixed.durationMs, 5000);
      expect(fixed.durationEstimated, isFalse);
      final nominal = s.withDuration(60000, durationEstimated: true);
      expect(nominal.durationEstimated, isTrue);
    });
  });
}
