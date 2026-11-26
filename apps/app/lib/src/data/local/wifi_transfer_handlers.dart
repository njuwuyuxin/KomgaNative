import 'dart:convert';
import 'dart:io';

import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/wifi_transfer_security.dart';
import 'package:yomu/src/data/local/wifi_transfer_server.dart';

/// 枚举本机可用的局域网 IPv4 地址（优先私有网段 `192.168.x.x` / `10.x.x.x` / `172.16-31.x.x`）。
Future<List<String>> discoverLanIpv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final privateAddrs = <String>[];
    final otherAddrs = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.isEmpty || ip.startsWith('127.') || ip.startsWith('169.254.')) {
          continue;
        }
        if (_isPrivateIpv4(ip)) {
          if (!privateAddrs.contains(ip)) privateAddrs.add(ip);
        } else {
          if (!otherAddrs.contains(ip)) otherAddrs.add(ip);
        }
      }
    }
    return <String>[...privateAddrs, ...otherAddrs];
  } on SocketException {
    return const <String>[];
  } on OSError {
    return const <String>[];
  }
}

bool _isPrivateIpv4(String ip) {
  if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
  if (ip.startsWith('172.')) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      final second = int.tryParse(parts[1]) ?? -1;
      return second >= 16 && second <= 31;
    }
  }
  return false;
}

typedef WifiEmitEvent = void Function(
  String fileName,
  WifiTransferEventKind kind, {
  int importedCount,
  String? errorDetail,
});

Future<({int importedCount, int bytesReceived})> handleWifiArchiveUpload({
  required HttpRequest request,
  required LocalComicImporter importer,
  required Directory staging,
  required WifiEmitEvent emit,
  required int maxBytes,
}) async {
  final rawName = request.uri.queryParameters['name']?.trim() ?? '';
  final fileName = sanitizeWifiSegment(
    rawName.isEmpty ? 'upload.cbz' : rawName,
  );
  final rawParent = request.uri.queryParameters['parent']?.trim();
  final parentName = (rawParent != null && rawParent.isNotEmpty)
      ? sanitizeWifiSegment(rawParent)
      : null;

  emit(fileName, WifiTransferEventKind.receiving);

  final tempFile = File(
    '${staging.path}/up_${DateTime.now().microsecondsSinceEpoch}_$fileName',
  );
  try {
    final received = await writeStreamToFileWithLimit(
      request,
      tempFile,
      maxBytes: maxBytes,
      declaredLength: request.contentLength >= 0 ? request.contentLength : null,
    );
    final result = await importer.importArchiveFiles(<PickedComicFile>[
      PickedComicFile.fromFile(tempFile, name: fileName),
    ], parentFolderName: parentName);

    if (result.importedCount > 0) {
      emit(
        fileName,
        WifiTransferEventKind.imported,
        importedCount: result.importedCount,
      );
      await writeWifiJson(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'importedCount': result.importedCount,
        'seriesIds': result.importedSeriesIds,
        'failures': <String>[for (final f in result.failures) f.reason.name],
      });
      return (importedCount: result.importedCount, bytesReceived: received);
    }

    final reason = result.failures.isNotEmpty
        ? result.failures.first.reason.name
        : 'import_failed';
    emit(fileName, WifiTransferEventKind.failed, errorDetail: reason);
    await writeWifiJson(
      request.response,
      HttpStatus.unprocessableEntity,
      <String, Object?>{'ok': false, 'error': reason},
    );
    return (importedCount: 0, bytesReceived: received);
  } on WifiPayloadTooLargeException {
    emit(
      fileName,
      WifiTransferEventKind.failed,
      errorDetail: 'payload_too_large',
    );
    await writeWifiJson(
      request.response,
      HttpStatus.requestEntityTooLarge,
      const <String, Object?>{'ok': false, 'error': 'payload_too_large'},
      closeConnection: true,
    );
    return (importedCount: 0, bytesReceived: 0);
  } finally {
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } on FileSystemException {
      // 清理临时上传文件失败不影响主流程。
    }
  }
}

Future<int> handleWifiImageUpload({
  required HttpRequest request,
  required Directory staging,
  required int maxBytes,
}) async {
  final folder = sanitizeWifiSegment(
    request.uri.queryParameters['folder']?.trim() ?? 'Uploaded Comic',
  );
  final relPath = sanitizeWifiRelativePath(
    request.uri.queryParameters['name']?.trim() ?? '',
  );
  if (relPath.isEmpty) {
    await writeWifiJson(
      request.response,
      HttpStatus.badRequest,
      const <String, Object?>{'ok': false, 'error': 'missing_name'},
    );
    return 0;
  }
  final dest = File('${staging.path}/folders/$folder/$relPath');
  await dest.parent.create(recursive: true);
  try {
    final received = await writeStreamToFileWithLimit(
      request,
      dest,
      maxBytes: maxBytes,
      declaredLength: request.contentLength >= 0 ? request.contentLength : null,
    );
    await writeWifiJson(
      request.response,
      HttpStatus.ok,
      const <String, Object?>{'ok': true},
    );
    return received;
  } on WifiPayloadTooLargeException {
    await writeWifiJson(
      request.response,
      HttpStatus.requestEntityTooLarge,
      const <String, Object?>{'ok': false, 'error': 'payload_too_large'},
      closeConnection: true,
    );
    return 0;
  }
}

Future<int> handleWifiCommitFolder({
  required HttpRequest request,
  required LocalComicImporter importer,
  required Directory? staging,
  required WifiEmitEvent emit,
}) async {
  final folder = sanitizeWifiSegment(
    request.uri.queryParameters['folder']?.trim() ?? 'Uploaded Comic',
  );
  emit(folder, WifiTransferEventKind.receiving);
  final dir = staging == null
      ? null
      : Directory('${staging.path}/folders/$folder');
  if (dir == null || !await dir.exists()) {
    emit(folder, WifiTransferEventKind.failed, errorDetail: 'not_found');
    await writeWifiJson(
      request.response,
      HttpStatus.notFound,
      const <String, Object?>{'ok': false, 'error': 'folder_not_found'},
    );
    return 0;
  }

  try {
    final result = await importer.importDirectory(dir.path);
    if (result.importedCount > 0) {
      emit(
        folder,
        WifiTransferEventKind.imported,
        importedCount: result.importedCount,
      );
      await writeWifiJson(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'importedCount': result.importedCount,
      });
      return result.importedCount;
    }
    final reason = result.failures.isNotEmpty
        ? result.failures.first.reason.name
        : 'import_failed';
    emit(folder, WifiTransferEventKind.failed, errorDetail: reason);
    await writeWifiJson(
      request.response,
      HttpStatus.unprocessableEntity,
      <String, Object?>{'ok': false, 'error': reason},
    );
    return 0;
  } finally {
    await tryDeleteImportDir(dir);
  }
}

Future<int> handleWifiSeriesCoverUpload({
  required HttpRequest request,
  required LocalComicImporter importer,
  required Directory staging,
  required WifiEmitEvent emit,
  required int maxBytes,
}) async {
  final rawSeriesId = request.uri.queryParameters['seriesId']?.trim();
  final seriesId = (rawSeriesId != null && rawSeriesId.isNotEmpty)
      ? rawSeriesId
      : null;
  final rawSeries = request.uri.queryParameters['series']?.trim();
  final seriesTitle = (rawSeries != null && rawSeries.isNotEmpty)
      ? sanitizeWifiSegment(rawSeries)
      : null;
  if (seriesId == null && seriesTitle == null) {
    await writeWifiJson(
      request.response,
      HttpStatus.badRequest,
      const <String, Object?>{'ok': false, 'error': 'missing_series'},
    );
    return 0;
  }
  final rawName = request.uri.queryParameters['name']?.trim() ?? '';
  final fileName = sanitizeWifiSegment(rawName.isEmpty ? 'cover.jpg' : rawName);
  final tempFile = File(
    '${staging.path}/cov_${DateTime.now().microsecondsSinceEpoch}_$fileName',
  );
  try {
    final received = await writeStreamToFileWithLimit(
      request,
      tempFile,
      maxBytes: maxBytes,
      declaredLength: request.contentLength >= 0 ? request.contentLength : null,
    );
    final bytes = await tempFile.readAsBytes();
    if (bytes.isEmpty) {
      await writeWifiJson(
        request.response,
        HttpStatus.badRequest,
        const <String, Object?>{'ok': false, 'error': 'empty_cover'},
      );
      return received;
    }
    final appliedId = await importer.applySeriesCoverImage(
      bytes,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
    );
    if (appliedId != null) {
      emit(fileName, WifiTransferEventKind.imported);
    }
    await writeWifiJson(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'applied': appliedId != null,
      if (appliedId != null) 'seriesId': appliedId,
    });
    return received;
  } on WifiPayloadTooLargeException {
    await writeWifiJson(
      request.response,
      HttpStatus.requestEntityTooLarge,
      const <String, Object?>{'ok': false, 'error': 'payload_too_large'},
      closeConnection: true,
    );
    return 0;
  } finally {
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } on FileSystemException {
      // 清理临时封面文件失败不影响主流程。
    }
  }
}

Future<void> writeWifiJson(
  HttpResponse response,
  int statusCode,
  Map<String, Object?> body, {
  bool closeConnection = false,
}) async {
  if (closeConnection) response.persistentConnection = false;
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await response.flush();
  await response.close();
}

String sanitizeWifiSegment(String raw) {
  final base = raw.replaceAll(r'\', '/').split('/').last.trim();
  final safe = base.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_');
  return safe.isEmpty || safe == '.' || safe == '..' ? 'comic' : safe;
}

String sanitizeWifiRelativePath(String raw) {
  final norm = raw.replaceAll(r'\', '/');
  final cleanParts = <String>[];
  for (final part in norm.split('/')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') continue;
    cleanParts.add(trimmed.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_'));
  }
  return cleanParts.join('/');
}
