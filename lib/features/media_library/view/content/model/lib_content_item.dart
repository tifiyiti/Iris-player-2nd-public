import 'dart:math';

import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';

/// Unified abstraction for items displayed in the library content browser.
abstract class LibContentItem {
  String get id;
  String get title;
  String get subtitle;
  bool get isDirectory;
  int get mediaCount;
  int get dirCount;
  int get totalDurationMs;
}

/// Wraps a [MediaLibrarySource] as a [LibContentItem].
class SourceLibContentItem implements LibContentItem {
  final MediaLibrarySource source;
  final String? storageName;

  SourceLibContentItem(this.source, {this.storageName});

  @override
  String get id => 'source_${source.id}';

  @override
  String get title {
    if (source.name != null && source.name!.isNotEmpty) {
      return source.name!;
    }
    if (source.path != null && source.path!.isNotEmpty) {
      return source.path!.last;
    }
    return storageName ?? 'Root Storage';
  }

  @override
  String get subtitle {
    final parts = <String>[];
    parts.add('${source.totalDirCount} dirs');
    parts.add('${source.totalMediaCount} medias');
    if (source.totalSizeInBytes > 0) {
      parts.add(NodeLibContentItem.formatSize(source.totalSizeInBytes));
    }
    return parts.join(' | ');
  }

  @override
  bool get isDirectory => true;

  @override
  int get mediaCount => source.totalMediaCount;

  @override
  int get dirCount => source.totalDirCount;

  @override
  int get totalDurationMs => source.totalDurationMs;
}

/// Wraps a [MediaNode] as a [LibContentItem].
class NodeLibContentItem implements LibContentItem {
  final MediaNode node;

  NodeLibContentItem(this.node);

  @override
  String get id => 'node_${node.storageId}_${node.path}';

  @override
  String get title => node.name;

  @override
  String get subtitle {
    if (node.isDir) {
      final dir = node as MediaDirectory;
      final parts = <String>[];
      parts.add('${dir.totalDirCount} dirs');
      parts.add('${dir.totalMediaCount} medias');
      if (dir.totalSizeInBytes > 0) {
        parts.add(formatSize(dir.totalSizeInBytes));
      }
      return parts.join(' | ');
    }

    final file = node as MediaFile;
    final sizeStr = formatSize(file.sizeInBytes ?? 0);
    final durationStr = file.durationMs != null ? _formatDuration(file.durationMs!) : '';
    final dateStr = _formatDateShort(file.modifiedAt);
    final parts = <String>[sizeStr];
    if (durationStr.isNotEmpty) parts.add(durationStr);
    if (dateStr.isNotEmpty) parts.add(dateStr);
    return parts.join(' · ');
  }

  @override
  bool get isDirectory => node.isDir;

  @override
  int get mediaCount {
    if (node.isDir) {
      return (node as MediaDirectory).totalMediaCount;
    }
    return 1;
  }

  @override
  int get dirCount {
    if (node.isDir) {
      return (node as MediaDirectory).totalDirCount;
    }
    return 0;
  }

  @override
  int get totalDurationMs {
    if (node.isDir) {
      return (node as MediaDirectory).totalDurationMs;
    }
    return (node as MediaFile).durationMs ?? 0;
  }

  static String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  static String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static String formatDurationHumanReadable(int totalMs) {
    if (totalMs <= 0) return '0s';
    final duration = Duration(milliseconds: totalMs);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (seconds > 0 || parts.isEmpty) parts.add('${seconds}s');
    return parts.join(' ');
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static String formatDateTime(DateTime? dt) {
    if (dt == null) return 'N/A';
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)} '
        '${_pad2(dt.hour)}:${_pad2(dt.minute)}:${_pad2(dt.second)}';
  }

  static String _formatDateShort(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';
  }
}
