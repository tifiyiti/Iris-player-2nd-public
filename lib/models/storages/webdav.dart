import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/get_subtitle_map.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/storage_path_guard.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Classifies a listing/probe failure so the UI can explain WHY it failed
/// instead of rendering an empty directory.
StorageListErrorKind classifyStorageListFailure(Object error) {
  final text = error.toString().toLowerCase();

  // Platform cleartext policy (Android targetSdk >= 28 / iOS ATS).
  if (text.contains('insecure http') ||
      text.contains('cleartext') ||
      text.contains('not allowed by platform')) {
    return StorageListErrorKind.httpBlocked;
  }

  if (text.contains('401') ||
      text.contains('403') ||
      text.contains('unauthorized') ||
      text.contains('forbidden')) {
    return StorageListErrorKind.unauthorized;
  }

  if (error is TimeoutException ||
      text.contains('timeout') ||
      text.contains('timed out')) {
    return StorageListErrorKind.timeout;
  }

  if (error is SocketException ||
      error is HttpException ||
      text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable') ||
      text.contains('host unreachable')) {
    return StorageListErrorKind.unreachable;
  }

  return StorageListErrorKind.unknown;
}

bool isIPv4WildcardHost(String host) {
  if (!host.contains('*')) return false;

  final parts = host.split('.');
  if (parts.length != 4) return false;

  int wildcardCount = 0;

  for (final p in parts) {
    if (p == '*') {
      wildcardCount++;
    } else {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
  }

  return wildcardCount <= 2;
}

Future<bool> testWebDAV(WebDAVStorage storage) async {
  final host = storage.host;
  final port = storage.port;
  final username = storage.username;
  final password = storage.password;
  final https = storage.https;
  final basePath = storage.basePath;

  try {
    var client = webdav.newClient(
      "http${https ? 's' : ''}://$host:$port",
      user: username,
      password: password,
      debug: false,
    );

    client.setHeaders({'accept-charset': 'utf-8'});
    client.setConnectTimeout(4000);
    client.setSendTimeout(4000);
    client.setReceiveTimeout(4000);

    // await client.ping();
    await client.readDir(basePath.join('/'));
    return true;
  } catch (e) {
    areaKeyLog.e(e.toString());
    return false;
  }
}

Future<List<FileItem>> getWebDAVFiles(
  WebDAVStorage storage,
  List<String> path,
) async =>
    (await getWebDAVFilesResult(storage, path)).items;

/// Lists [path], reporting failures through [FileListResult] instead of
/// collapsing them into an empty list (which made every failure — unreachable
/// host, rejected credentials, blocked cleartext — look like an empty folder).
Future<FileListResult> getWebDAVFilesResult(
  WebDAVStorage storage,
  List<String> path,
) async {
  if (hasUnsafeRemotePathSegment(path)) {
    areaKeyLog.w('getWebDAVFiles rejected traversal path: $path');
    return const FileListResult(<FileItem>[],
        errorKind: StorageListErrorKind.unknown);
  }
  final id = storage.id;
  final host = storage.host;
  final port = storage.port;
  final username = storage.username;
  final password = storage.password;
  final https = storage.https;

  var client = webdav.newClient(
    "http${https ? 's' : ''}://$host:$port",
    user: username,
    password: password,
    debug: false,
  );

  client.setHeaders({'accept-charset': 'utf-8'});
  client.setConnectTimeout(8000);
  client.setSendTimeout(8000);
  client.setReceiveTimeout(8000);

  List<webdav.File> files;
  try {
    files = await client.readDir(path.join('/'));
  } catch (e) {
    areaKeyLog.w('getWebDAVFiles readDir failed for $path: $e');
    return FileListResult(
      const <FileItem>[],
      errorKind: classifyStorageListFailure(e),
      errorDetail: e.toString(),
    );
  }

  final cleanPathSegments = path.map((e) => e.replaceAll('/', '')).toList();
  final baseUri = Uri(
    scheme: storage.https ? 'https' : 'http',
    host: storage.host,
    port: int.tryParse(storage.port),
    pathSegments: cleanPathSegments,
  );
  final baseUriString = baseUri.toString();

  String getUri(String fileName) {
    if (fileName.contains('/') || fileName == '..' || fileName == '.') {
      areaKeyLog.w('getWebDAVFiles skip traversal file: $fileName');
      return '$baseUriString/${Uri.encodeComponent(fileName)}';
    }
    try {
      final dirUri = Uri.parse(baseUriString.endsWith('/') ? baseUriString : '$baseUriString/');
      return dirUri.resolve(Uri.encodeComponent(fileName)).toString();
    } catch (e) {
      final separator = baseUriString.endsWith('/') ? '' : '/';
      return '$baseUriString$separator${Uri.encodeComponent(fileName)}';
    }
  }

  final subtitleMap = getSubtitleMap<webdav.File>(
    files: files,
    getName: (file) => file.name ?? '',
    getUri: (file) => getUri(file.name ?? ''),
  );

  List<FileItem> fileItems = [];

  for (final file in files) {
    final fileName = file.name;

    if (fileName == null) continue;

    final isDir = file.isDir;
    final basename = p.basenameWithoutExtension(fileName).split('.').first;
    fileItems.add(FileItem(
      storageId: id,
      storageType: StorageType.webdav,
      name: fileName,
      uri: getUri(fileName),
      path: [...path, fileName],
      isDir: isDir ?? false,
      size: file.size ?? 0,
      lastModified: file.mTime,
      type: isDir ?? false ? ContentType.other : checkContentType(fileName),
      subtitles: isVideoFile(fileName) ? subtitleMap[basename] ?? [] : [],
    ));
  }

  return FileListResult(fileItems);
}

String getWebDAVAuth(WebDAVStorage storage) =>
    'Basic ${base64Encode(utf8.encode('${storage.username}:${storage.password}'))}';
