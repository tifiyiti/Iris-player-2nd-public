import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';

class MockItemEntity {
  final String id;
  final String title;
  final int sizeBytes;
  final bool isDirectory;

  const MockItemEntity({
    required this.id,
    required this.title,
    required this.sizeBytes,
    this.isDirectory = false,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() => title;
}

class _DirNode {
  final String id;
  final String name;
  final List<_DirNode> subdirs;
  final List<MockItemEntity> files;

  _DirNode({
    required this.id,
    required this.name,
    List<_DirNode>? subdirs,
    List<MockItemEntity>? files,
  })  : subdirs = subdirs ?? [],
        files = files ?? [];
}

class MockBrowserDataSource extends PaginatedBrowserDataSource<MockItemEntity> {
  int _currentPage = 0;
  int _pageSize = 15;
  bool _isLoading = false;
  bool _isError = false;

  final List<String> _currentPath = [];
  _DirNode? _rootDir;

  List<MockItemEntity> _currentItems = [];

  SortOption _activeSort = const SortOption(label: 'Name A-Z');

  List<MockItemEntity> _searchResults = [];
  bool _isSearchMode = false;

  static final _random = Random(42);

  MockBrowserDataSource() {
    _rootDir = _buildDirectoryTree();
    _loadCurrentDir();
  }

  // ─── DIRECTORY TREE GENERATION ──────────────────────────────────

  _DirNode _buildDirectoryTree() {
    final root = _DirNode(id: 'root', name: 'Internal Storage');

    final categories = [
      ('Documents', ['Work', 'Personal', 'Archive']),
      ('Music', ['Rock', 'Jazz', 'Classical', 'Podcasts']),
      ('Videos', ['Movies', 'Clips', 'Tutorials']),
      ('Photos', ['2024', '2023', 'Vacation']),
      ('Downloads', ['Temp', 'Installers']),
      ('Projects', ['Flutter', 'Web', 'Scripts']),
    ];

    for (int i = 0; i < categories.length; i++) {
      final (dirName, subDirs) = categories[i];
      final dirNode = _DirNode(id: 'dir_$i', name: dirName);

      // Add files at this level
      final fileCount = _random.nextInt(8) + 3;
      for (int j = 0; j < fileCount; j++) {
        dirNode.files.add(_generateFile('dir_${i}_file_$j', dirName));
      }

      // Add subdirectories (depth 2)
      for (int s = 0; s < subDirs.length; s++) {
        final subDirNode = _DirNode(
          id: 'dir_${i}_sub_$s',
          name: subDirs[s],
        );

        // Add files at depth 2
        final subFileCount = _random.nextInt(6) + 2;
        for (int f = 0; f < subFileCount; f++) {
          subDirNode.files.add(_generateFile('dir_${i}_sub_${s}_file_$f', subDirs[s]));
        }

        // Add depth-3 subdirs occasionally
        if (_random.nextBool()) {
          final depth3Names = ['Drafts', 'Final', 'Backup', 'Raw'];
          final d3Name = depth3Names[_random.nextInt(depth3Names.length)];
          final d3Node = _DirNode(
            id: 'dir_${i}_sub_${s}_d3',
            name: d3Name,
          );
          final d3FileCount = _random.nextInt(4) + 1;
          for (int f = 0; f < d3FileCount; f++) {
            d3Node.files.add(_generateFile('dir_${i}_sub_${s}_d3_file_$f', d3Name));
          }
          subDirNode.subdirs.add(d3Node);
        }

        dirNode.subdirs.add(subDirNode);
      }

      root.subdirs.add(dirNode);
    }

    return root;
  }

  MockItemEntity _generateFile(String id, String category) {
    final extensions = ['.mp4', '.mkv', '.mp3', '.pdf', '.jpg', '.png'];
    final adj = _adjectives[_random.nextInt(_adjectives.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    final ext = extensions[_random.nextInt(extensions.length)];
    final title = '$adj $noun$ext';

    return MockItemEntity(
      id: id,
      title: title,
      sizeBytes: 1024 * 1024 * (_random.nextInt(3800) + 20),
    );
  }

  static final List<String> _adjectives = [
    'Bright', 'Dark', 'Fast', 'Slow', 'Smooth', 'Rough', 'Warm', 'Cool',
    'Loud', 'Quiet', 'Deep', 'Shallow', 'Open', 'Closed', 'Round',
    'Flat', 'Wild', 'Tame', 'Fresh', 'Stale', 'Crisp', 'Soft',
    'Royal', 'Vital', 'Prime', 'Ultra', 'Hyper', 'Turbo', 'Mega',
  ];

  static final List<String> _nouns = [
    'Sunset', 'Wave', 'Mountain', 'River', 'Forest', 'Ocean', 'Meadow',
    'Cloud', 'Storm', 'Shadow', 'Light', 'Rainbow', 'Valley', 'Summit',
    'Harbor', 'Temple', 'Garden', 'Castle', 'Desert', 'Island', 'Galaxy',
  ];

  // ─── DIRECTORY NAVIGATION ───────────────────────────────────────

  _DirNode? _resolveCurrentDir() {
    _DirNode current = _rootDir!;
    for (final dirId in _currentPath) {
      final found = current.subdirs.where((d) => d.id == dirId);
      if (found.isEmpty) return null;
      current = found.first;
    }
    return current;
  }

  void _loadCurrentDir() {
    final dir = _resolveCurrentDir();
    if (dir == null) {
      _currentItems = [];
      return;
    }

    final items = <MockItemEntity>[];

    // Directories first
    for (final sub in dir.subdirs) {
      items.add(MockItemEntity(
        id: sub.id,
        title: sub.name,
        sizeBytes: 0,
        isDirectory: true,
      ));
    }

    // Then files
    items.addAll(dir.files);

    _sortItems(items);
    _currentItems = items;
  }

  void _sortItems(List<MockItemEntity> items) {
    if (_activeSort.label == 'Name A-Z') {
      items.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.title.compareTo(b.title);
      });
    } else if (_activeSort.label == 'Name Z-A') {
      items.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return b.title.compareTo(a.title);
      });
    } else if (_activeSort.label == 'Size Small-Large') {
      items.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    } else if (_activeSort.label == 'Size Large-Small') {
      items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
  }

  bool _navigateIntoDir(String dirId) {
    final dir = _resolveCurrentDir();
    if (dir == null) return false;
    final found = dir.subdirs.where((d) => d.id == dirId);
    if (found.isEmpty) return false;
    _currentPath.add(dirId);
    _currentPage = 0;
    _loadCurrentDir();
    return true;
  }

  // ─── ABSTRACT IMPLEMENTATIONS ───────────────────────────────────

  @override
  int get totalItems => _isSearchMode ? _searchResults.length : _currentItems.length;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => (totalItems / pageSize).ceil().clamp(1, 999);

  @override
  int get pageSize => _pageSize;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get isError => _isError;

  @override
  List<MockItemEntity> get items {
    final source = _isSearchMode ? _searchResults : _currentItems;
    if (source.isEmpty) return [];
    final start = _currentPage * _pageSize;
    if (start >= source.length) return [];
    final end = (start + _pageSize).clamp(0, source.length);
    return source.sublist(start, end);
  }

  @override
  String getItemId(MockItemEntity item) => item.id;

  @override
  List<String>? get currentBreadcrumbs {
    if (_isSearchMode) return null;
    final crumbs = <String>['Internal Storage'];
    final dir = _rootDir;
    if (dir == null) return crumbs;

    _DirNode current = dir;
    for (final dirId in _currentPath) {
      final found = current.subdirs.where((d) => d.id == dirId);
      if (found.isEmpty) break;
      current = found.first;
      crumbs.add(current.name);
    }
    return crumbs;
  }

  @override
  bool get isRightToLeftBreadcrumbs => false;

  // ─── PAGING & NAVIGATION ────────────────────────────────────────

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {
    _isLoading = true;
    _pageSize = currentSize;
    _isError = false;

    await Future.delayed(const Duration(milliseconds: 300));

    if (targetPage >= 0 && targetPage < totalPages) {
      _currentPage = targetPage;
    } else {
      _isError = true;
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> changePageSize(int newSize) async {
    if (newSize < 1) return;
    newSize = clampPageSize(newSize);
    _pageSize = newSize;
    _currentPage = 0;
    await fetchPage(0, _pageSize);
  }

  @override
  Future<void> changeSort(SortOption sortOption) async {
    _isLoading = true;
    await Future.delayed(const Duration(milliseconds: 150));

    _activeSort = sortOption;
    _loadCurrentDir();
    _currentPage = 0;

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<bool> handleNavigationBack() async {
    if (_isSearchMode) {
      _isSearchMode = false;
      _searchResults = [];
      _currentPage = 0;
      notifyListeners();
      return true;
    }

    if (_currentPath.isNotEmpty) {
      _currentPath.removeLast();
      _currentPage = 0;
      _loadCurrentDir();
      notifyListeners();
      return true;
    }

    return false;
  }

  @override
  Future<void> handleNavigationHome() async {
    _isSearchMode = false;
    _searchResults = [];
    _currentPath.clear();
    _currentPage = 0;
    _loadCurrentDir();
    notifyListeners();
  }

  @override
  Future<void> navigateToCrumb(int index) async {
    if (_isSearchMode) return;
    // index 0 = root, index 1 = first level, etc.
    final targetDepth = index;
    if (targetDepth < _currentPath.length) {
      _currentPath.removeRange(targetDepth, _currentPath.length);
      _currentPage = 0;
      _loadCurrentDir();
      notifyListeners();
    }
  }

  // ─── SORT MENU ──────────────────────────────────────────────────

  final List<SortOption> _sortOptions = const [
    SortOption(label: 'Name A-Z'),
    SortOption(label: 'Name Z-A'),
    SortOption(label: 'Size Small-Large'),
    SortOption(label: 'Size Large-Small'),
  ];

  @override
  Widget buildSortMenu(BuildContext context) {
    return PopupMenuButton<SortOption>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Sort',
      onSelected: (option) {
        final found = _sortOptions.firstWhere((s) => s.label == option.label);
        changeSort(found);
      },
      itemBuilder: (_) {
        return _sortOptions.map((option) {
          final cur = _activeSort.label;
          final isActive = option.label == cur;
          return PopupMenuItem<SortOption>(
            value: option,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(option.label),
                if (isActive)
                  const Icon(Icons.check, size: 18, color: Colors.blue),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  // ─── SEARCH ─────────────────────────────────────────────────────

  @override
  Future<void> openSearchDialog(BuildContext context, VoidCallback onSearchInitiated) async {
    final result = await showDialog<_MockSearchPayload>(
      context: context,
      builder: (_) => const _MockSearchDialog(),
    );

    if (result != null && result.query.trim().isNotEmpty) {
      _isSearchMode = true;
      _performSearch(
        query: result.query,
        caseSensitive: result.caseSensitive,
        isRegex: result.isRegex,
      );
      _currentPage = 0;
      notifyListeners();
      onSearchInitiated();
    }
  }

  void _performSearch({required String query, bool caseSensitive = false, bool isRegex = false}) {
    _searchResults = [];
    _searchInDir(_rootDir!, query, caseSensitive, isRegex);
  }

  void _searchInDir(_DirNode dir, String query, bool caseSensitive, bool isRegex) {
    for (final file in dir.files) {
      final title = caseSensitive ? file.title : file.title.toLowerCase();
      final search = caseSensitive ? query : query.toLowerCase();
      try {
        if (isRegex) {
          final regex = RegExp(search, caseSensitive: caseSensitive);
          if (regex.hasMatch(title)) _searchResults.add(file);
        } else {
          if (title.contains(search)) _searchResults.add(file);
        }
      } catch (_) {}
    }
    for (final sub in dir.subdirs) {
      _searchInDir(sub, query, caseSensitive, isRegex);
    }
  }

  // ─── TILE CONTENT ───────────────────────────────────────────────

  @override
  Widget? buildItemLeading(BuildContext context, MockItemEntity item) {
    return Icon(
      item.isDirectory ? Icons.folder_rounded : Icons.movie_rounded,
      size: 20,
      color: item.isDirectory ? Colors.amber : Colors.blue,
    );
  }

  @override
  String? buildItemTitle(MockItemEntity item) => item.title;

  @override
  Widget? buildItemSubtitle(BuildContext context, MockItemEntity item) {
    if (item.isDirectory) {
      // Count children
      final dir = _resolveDirById(item.id);
      final childCount = dir != null ? dir.subdirs.length + dir.files.length : 0;
      return Text(
        '$childCount items',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Text(
      item.sizeFormatted,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  _DirNode? _resolveDirById(String id) {
    return _findDir(_rootDir!, id);
  }

  _DirNode? _findDir(_DirNode node, String id) {
    if (node.id == id) return node;
    for (final sub in node.subdirs) {
      final found = _findDir(sub, id);
      if (found != null) return found;
    }
    return null;
  }

  @override
  bool handleItemTap(BuildContext context, MockItemEntity item) {
    if (item.isDirectory) {
      final success = _navigateIntoDir(item.id);
      if (success) {
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  @override
  Widget buildTileInfoDialog(BuildContext context, MockItemEntity item) {
    return AlertDialog(
      title: Text(item.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.isDirectory ? Icons.folder_rounded : Icons.movie_rounded,
                size: 24,
                color: item.isDirectory ? Colors.amber : Colors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Type', item.isDirectory ? 'Directory' : 'File'),
          _infoRow('Size', item.isDirectory ? '--' : item.sizeFormatted),
          _infoRow('ID', item.id),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget buildTileContent(BuildContext context, MockItemEntity item) {
    return Row(
      children: [
        Icon(
          item.isDirectory ? Icons.folder_rounded : Icons.movie_rounded,
          size: 20,
          color: item.isDirectory ? Colors.amber : Colors.blue,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (!item.isDirectory)
          Text(
            item.sizeFormatted,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  // ─── ITEM TRAILING ACTIONS ──────────────────────────────────────

  @override
  List<GenericItemAction<MockItemEntity>> getItemTrailingActions(
    BuildContext context,
    MockItemEntity item,
  ) {
    return [
      GenericItemAction(
        label: 'Info',
        icon: const Icon(Icons.info_outline, size: 16),
        onPressed: (ctx, i) {
          showDialog(
            context: ctx,
            builder: (_) => buildTileInfoDialog(ctx, i),
          );
        },
      ),
      if (!item.isDirectory)
        GenericItemAction(
          label: 'Rename',
          icon: const Icon(Icons.edit, size: 16),
          onPressed: (ctx, i) async {
            final newName = await showDialog<String>(
              context: ctx,
              builder: (_) => _RenameDialog(currentName: i.title),
            );
            if (newName != null && newName.trim().isNotEmpty) {
              _renameFile(i.id, newName.trim());
            }
          },
        ),
      GenericItemAction(
        label: 'Delete',
        icon: const Icon(Icons.delete, color: Colors.red, size: 16),
        onPressed: (ctx, i) async {
          final confirmed = await showDialog<bool>(
            context: ctx,
            builder: (_) => AlertDialog(
              title: const Text('Confirm Delete'),
              content: Text('Delete "${i.title}"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            _deleteItem(i.id);
          }
        },
      ),
    ];
  }

  void _renameFile(String id, String newName) {
    final dir = _resolveCurrentDir();
    if (dir == null) return;
    for (int i = 0; i < dir.files.length; i++) {
      if (dir.files[i].id == id) {
        dir.files[i] = MockItemEntity(
          id: id,
          title: newName,
          sizeBytes: dir.files[i].sizeBytes,
        );
        _loadCurrentDir();
        notifyListeners();
        return;
      }
    }
  }

  void _deleteItem(String id) {
    final dir = _resolveCurrentDir();
    if (dir == null) return;
    dir.files.removeWhere((f) => f.id == id);
    dir.subdirs.removeWhere((d) => d.id == id);
    _loadCurrentDir();
    notifyListeners();
  }

  // ─── CUSTOM PAGE ACTIONS ────────────────────────────────────────

  @override
  List<PageAction> buildCustomPageActions(BuildContext context) {
    if (_isSearchMode) {
      return [
        PageAction(
          icon: const Icon(Icons.search_off),
          label: 'Exit Search',
          onPressed: () {
            _isSearchMode = false;
            _searchResults = [];
            _currentPage = 0;
            notifyListeners();
          },
        ),
      ];
    }
    return [
      PageAction(
        icon: const Icon(Icons.info_outline),
        label: 'Info',
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Info'),
              content: Text('$totalItems items across $totalPages pages'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
      ),
    ];
  }

  @override
  List<CustomSelectionAction<MockItemEntity>> buildCustomSelectionActions(BuildContext context) {
    return [
      CustomSelectionAction<MockItemEntity>(
        icon: const Icon(Icons.favorite_outline),
        label: 'Bookmark',
        onPressed: (ctx, selected) async {
          await showDialog(
            context: ctx,
            builder: (_) => AlertDialog(
              title: const Text('Bookmark'),
              content: Text('Bookmarked ${selected.length} item(s)'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return false;
        },
      ),
    ];
  }
}

// ─── PRIVATE HELPER WIDGETS ──────────────────────────────────────

class _MockSearchPayload {
  final String query;
  final bool caseSensitive;
  final bool isRegex;
  const _MockSearchPayload({required this.query, required this.caseSensitive, required this.isRegex});
}

class _MockSearchDialog extends HookWidget {
  const _MockSearchDialog();

  @override
  Widget build(BuildContext context) {
    final textController = useTextEditingController();
    final caseSensitive = useState(false);
    final isRegex = useState(false);
    final error = useState<String?>(null);
    final history = useState<List<String>>([]);

    return AlertDialog(
      title: const Text('Search'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter search query...',
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) {
              if (isRegex.value && v.trim().isNotEmpty) {
                try {
                  RegExp(v);
                  error.value = null;
                } catch (e) {
                  error.value = 'Invalid regex: ${e.toString().split('\n').first}';
                }
              } else {
                error.value = null;
              }
            },
          ),
          if (error.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MaterialBanner(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                backgroundColor: Colors.red.shade50,
                leading: const Icon(Icons.warning_amber, color: Colors.red),
                content: Text(error.value!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                actions: [SizedBox.shrink()],
              ),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: caseSensitive.value,
            onChanged: (v) => caseSensitive.value = v ?? false,
            title: const Text('Case sensitive', style: TextStyle(fontSize: 14)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          SwitchListTile(
            value: isRegex.value,
            onChanged: (v) => isRegex.value = v,
            title: const Text('Regular expression', style: TextStyle(fontSize: 14)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (history.value.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView(
                children: history.value.map((h) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text(h, style: const TextStyle(fontSize: 13)),
                    onTap: () {
                      textController.text = h;
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final query = textController.text.trim();
            if (query.isEmpty) return;
            if (isRegex.value && error.value != null) {
              error.value = 'Fix regex error before searching';
              return;
            }

            final list = history.value;
            list.remove(query);
            list.insert(0, query);
            if (list.length > 10) list.removeLast();
            history.value = list;

            Navigator.pop(
              context,
              _MockSearchPayload(query: query, caseSensitive: caseSensitive.value, isRegex: isRegex.value),
            );
          },
          child: const Text('Search'),
        ),
      ],
    );
  }
}

class _RenameDialog extends HookWidget {
  final String currentName;
  const _RenameDialog({required this.currentName});

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: currentName);
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'New name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Rename')),
      ],
    );
  }
}
