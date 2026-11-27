import 'dart:io';
import 'dart:math' as math;

import 'package:yomu/src/data/local/local_import_cleanup.dart';

/// 单文件或单次会话上传体积超限时抛出的内部异常（映射为 HTTP 413）。
final class WifiPayloadTooLargeException implements Exception {
  const WifiPayloadTooLargeException(this.limitBytes);

  final int limitBytes;
}

/// 单次上传流持有的会话额度租约：支持已知 `Content-Length` 原子预占与分块流实时增量扣减。
final class WifiQuotaLease {
  WifiQuotaLease._(
    this._quota, {
    required this.perFileLimit,
    required int initialReserved,
  }) : _held = initialReserved;

  final WifiSessionQuota _quota;
  final int perFileLimit;
  int _held;
  int _written = 0;
  bool _settled = false;

  int get writtenBytes => _written;

  /// 为新到达的 [bytes] 申请单文件与整次会话额度；任一超限即返回 `false`。
  bool consume(int bytes) {
    if (_settled || bytes < 0) return false;
    final nextWritten = _written + bytes;
    if (nextWritten > perFileLimit) return false;
    if (nextWritten > _held) {
      final delta = nextWritten - _held;
      if (!_quota._tryReserve(delta)) return false;
      _held += delta;
    }
    _written = nextWritten;
    return true;
  }

  /// 上传落盘成功：将实际写入字节数转入永久已用额度，释放多余预占。
  void commit() {
    if (_settled) return;
    _settled = true;
    _quota._commit(heldBytes: _held, writtenBytes: _written);
    _held = 0;
  }

  /// 上传中止或失败：释放全部在途预占额度（对应半截文件已删除）。
  void release() {
    if (_settled) return;
    _settled = true;
    _quota._release(_held);
    _held = 0;
  }
}

/// Wi-Fi 传书会话级并发与流量额度管理器（P2-1）：
/// - 限制同时进行的上传请求数，防止无限并发撑爆磁盘与文件句柄；
/// - 原子预占（已知 `Content-Length`）+ 逐块实时扣减（`Transfer-Encoding: chunked`），
///   保证并发上传永远无法绕过 [maxSessionBytes] 上限。
final class WifiSessionQuota {
  WifiSessionQuota({
    required this.maxSessionBytes,
    required this.maxConcurrentUploads,
  });

  final int maxSessionBytes;
  final int maxConcurrentUploads;

  int _committedBytes = 0;
  int _reservedBytes = 0;
  int _activeUploads = 0;

  int get committedBytes => _committedBytes;
  int get reservedBytes => _reservedBytes;
  int get usedBytes => _committedBytes + _reservedBytes;
  int get remainingBytes => math.max(0, maxSessionBytes - usedBytes);
  int get activeUploads => _activeUploads;

  bool tryEnterUpload() {
    if (_activeUploads >= maxConcurrentUploads) return false;
    _activeUploads++;
    return true;
  }

  void leaveUpload() {
    if (_activeUploads > 0) _activeUploads--;
  }

  /// 为单次流式写入创建额度租约；若预声明长度已超单文件或剩余会话额度则立即抛出 [WifiPayloadTooLargeException]。
  WifiQuotaLease beginWrite({required int perFileLimit, int? declaredLength}) {
    if (perFileLimit <= 0 || remainingBytes <= 0) {
      throw WifiPayloadTooLargeException(
        math.min(perFileLimit, remainingBytes),
      );
    }
    var initialReserved = 0;
    if (declaredLength != null) {
      if (declaredLength < 0 || declaredLength > perFileLimit) {
        throw WifiPayloadTooLargeException(perFileLimit);
      }
      if (!_tryReserve(declaredLength)) {
        throw WifiPayloadTooLargeException(remainingBytes);
      }
      initialReserved = declaredLength;
    }
    return WifiQuotaLease._(
      this,
      perFileLimit: perFileLimit,
      initialReserved: initialReserved,
    );
  }

  bool _tryReserve(int bytes) {
    if (bytes <= 0) return true;
    if (_committedBytes + _reservedBytes + bytes > maxSessionBytes) {
      return false;
    }
    _reservedBytes += bytes;
    return true;
  }

  void _commit({required int heldBytes, required int writtenBytes}) {
    _reservedBytes = math.max(0, _reservedBytes - heldBytes);
    _committedBytes += writtenBytes;
  }

  void _release(int heldBytes) {
    _reservedBytes = math.max(0, _reservedBytes - heldBytes);
  }

  void reset() {
    _committedBytes = 0;
    _reservedBytes = 0;
    _activeUploads = 0;
  }
}

/// 未提交暂存文件夹的生命周期与过期清理器（P2-1）：
/// 防止客户端中途断连或放弃提交后，暂存图片在整个会话期间滞留磁盘。
final class WifiStagedFolderTracker {
  WifiStagedFolderTracker({required this.ttl, required DateTime Function() now})
    : _now = now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastTouched = <String, DateTime>{};
  final Map<String, int> _inFlight = <String, int>{};

  void enter(String folder) {
    _inFlight[folder] = (_inFlight[folder] ?? 0) + 1;
    _lastTouched[folder] = _now();
  }

  void leave(String folder, {bool committed = false}) {
    final next = (_inFlight[folder] ?? 1) - 1;
    if (next <= 0) {
      _inFlight.remove(folder);
    } else {
      _inFlight[folder] = next;
    }
    if (committed) {
      _lastTouched.remove(folder);
    } else {
      _lastTouched[folder] = _now();
    }
  }

  Future<bool> abort(Directory? staging, String folder) async {
    if ((_inFlight[folder] ?? 0) > 0) return false;
    _lastTouched.remove(folder);
    if (staging == null) return false;
    final dir = Directory('${staging.path}/folders/$folder');
    if (!await dir.exists()) return false;
    await tryDeleteImportDir(dir);
    return true;
  }

  Future<int> sweepExpired(Directory? staging) async {
    if (staging == null || _lastTouched.isEmpty) return 0;
    final now = _now();
    final expired = <String>[
      for (final entry in _lastTouched.entries)
        if ((_inFlight[entry.key] ?? 0) == 0 &&
            now.difference(entry.value) >= ttl)
          entry.key,
    ];
    var removed = 0;
    for (final folder in expired) {
      if ((_inFlight[folder] ?? 0) > 0) continue;
      _lastTouched.remove(folder);
      final dir = Directory('${staging.path}/folders/$folder');
      if (await dir.exists()) {
        await tryDeleteImportDir(dir);
        removed++;
      }
    }
    return removed;
  }

  void reset() {
    _lastTouched.clear();
    _inFlight.clear();
  }
}
