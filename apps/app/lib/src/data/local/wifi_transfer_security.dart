import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yomu/src/data/local/wifi_transfer_quota.dart';

export 'package:yomu/src/data/local/wifi_transfer_quota.dart';

/// 带硬字节上限与原子会话额度的流式落盘：边读边扣减，超限立即停止写盘、删半截文件并释放预占，
/// 同时最多优雅排空少量在途缓冲以避免内核 TCP RST 吞掉 HTTP 413 响应头。
Future<int> writeStreamToFileWithLimit(
  Stream<List<int>> stream,
  File dest, {
  required int maxBytes,
  WifiSessionQuota? quota,
  int? declaredLength,
  int maxDrainBytes = 256 * 1024,
}) async {
  WifiQuotaLease? lease;
  try {
    if (quota != null) {
      lease = quota.beginWrite(
        perFileLimit: maxBytes,
        declaredLength: declaredLength,
      );
    } else if (maxBytes <= 0 ||
        (declaredLength != null && declaredLength > maxBytes)) {
      throw WifiPayloadTooLargeException(maxBytes);
    }
  } on WifiPayloadTooLargeException {
    await drainUpToLimit(stream, maxDrainBytes: maxDrainBytes);
    rethrow;
  }

  await dest.parent.create(recursive: true);
  final sink = dest.openWrite();
  var written = 0;
  var overflowDrained = 0;
  var exceeded = false;
  var failed = false;
  try {
    await for (final chunk in stream) {
      if (exceeded) {
        overflowDrained += chunk.length;
        if (overflowDrained >= maxDrainBytes) break;
        continue;
      }
      final allowed = lease != null
          ? lease.consume(chunk.length)
          : (written + chunk.length <= maxBytes);
      if (!allowed) {
        exceeded = true;
        failed = true;
        overflowDrained += chunk.length;
        if (overflowDrained >= maxDrainBytes) break;
        continue;
      }
      written += chunk.length;
      sink.add(chunk);
    }
    if (exceeded) throw WifiPayloadTooLargeException(maxBytes);
    await sink.flush();
    lease?.commit();
    return written;
  } on Object {
    failed = true;
    lease?.release();
    rethrow;
  } finally {
    await sink.close();
    if (failed) {
      lease?.release();
      try {
        if (await dest.exists()) await dest.delete();
      } on FileSystemException {
        // 清理超限半截文件失败不影响响应 413。
      }
    }
  }
}

/// 在返回 413 前优雅排空少量已在途请求缓冲，避免内核发送 TCP RST 吞掉 413 响应头。
Future<void> drainUpToLimit(
  Stream<List<int>> stream, {
  int maxDrainBytes = 256 * 1024,
}) async {
  var drained = 0;
  try {
    await for (final chunk in stream) {
      drained += chunk.length;
      if (drained >= maxDrainBytes) break;
    }
  } on Object catch (error) {
    // 客户端已断开或流已被监听时安全忽略。
    debugPrint('WifiTransfer: drain stream ignored: $error');
  }
}

enum WifiPinStatus { ok, invalid, locked }

class _PinAttemptRecord {
  int failures = 0;
  DateTime? lockedUntil;
}

/// Wi-Fi 传书 PIN 鉴权守卫（P2-1）：
/// - 仅读 `X-Yomu-Pin` 请求头，拒绝 URL query 明文传 PIN；
/// - 常量时间字符串比对；
/// - 按客户端 IP 实施连续错误限流与定时锁定。
final class WifiPinGuard {
  WifiPinGuard({
    required this.maxFailures,
    required this.lockoutDuration,
    required DateTime Function() now,
  }) : _now = now;

  final int maxFailures;
  final Duration lockoutDuration;
  final DateTime Function() _now;
  final Map<String, _PinAttemptRecord> _attempts =
      <String, _PinAttemptRecord>{};

  void reset() => _attempts.clear();

  ({WifiPinStatus status, int retryAfterSeconds}) verify(
    HttpRequest request, {
    required String? expectedPin,
  }) {
    if (expectedPin == null || expectedPin.isEmpty) {
      return (status: WifiPinStatus.ok, retryAfterSeconds: 0);
    }
    final now = _now();
    final clientKey =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final record = _attempts[clientKey];
    if (record?.lockedUntil != null) {
      final remaining = record!.lockedUntil!.difference(now);
      if (remaining > Duration.zero) {
        return (
          status: WifiPinStatus.locked,
          retryAfterSeconds: math.max(
            1,
            (remaining.inMilliseconds / 1000).ceil(),
          ),
        );
      }
      record
        ..failures = 0
        ..lockedUntil = null;
    }

    final headerPin = request.headers.value('x-yomu-pin')?.trim() ?? '';
    if (_constantTimeEquals(headerPin, expectedPin)) {
      _attempts.remove(clientKey);
      return (status: WifiPinStatus.ok, retryAfterSeconds: 0);
    }

    final active = _attempts.putIfAbsent(clientKey, _PinAttemptRecord.new);
    active.failures++;
    if (active.failures >= maxFailures) {
      active.lockedUntil = now.add(lockoutDuration);
      return (
        status: WifiPinStatus.locked,
        retryAfterSeconds: math.max(1, lockoutDuration.inSeconds),
      );
    }
    return (status: WifiPinStatus.invalid, retryAfterSeconds: 0);
  }

  static bool _constantTimeEquals(String a, String b) {
    final aUnits = a.codeUnits;
    final bUnits = b.codeUnits;
    var diff = aUnits.length ^ bUnits.length;
    final maxLen = math.max(aUnits.length, bUnits.length);
    for (var i = 0; i < maxLen; i++) {
      final ca = i < aUnits.length ? aUnits[i] : 0;
      final cb = i < bUnits.length ? bUnits[i] : 0;
      diff |= ca ^ cb;
    }
    return diff == 0;
  }
}

/// 校验 POST 请求的 PIN 头并按结果写出 401/429 JSON 响应。
Future<bool> authorizeWifiPost(
  HttpRequest request,
  WifiPinGuard pinGuard, {
  required String? expectedPin,
}) async {
  final res = pinGuard.verify(request, expectedPin: expectedPin);
  if (res.status == WifiPinStatus.locked) {
    request.response.headers.set(
      HttpHeaders.retryAfterHeader,
      '${res.retryAfterSeconds}',
    );
    await writeWifiJson(
      request.response,
      HttpStatus.tooManyRequests,
      <String, Object?>{
        'ok': false,
        'error': 'too_many_attempts',
        'retryAfterSeconds': res.retryAfterSeconds,
      },
    );
    return false;
  }
  if (res.status == WifiPinStatus.invalid) {
    await writeWifiJson(
      request.response,
      HttpStatus.unauthorized,
      const <String, Object?>{'ok': false, 'error': 'invalid_pin'},
    );
    return false;
  }
  return true;
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
