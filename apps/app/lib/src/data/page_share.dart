import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把一页图片写到临时目录，再交给系统分享面板（UI-P3-6）。
///
/// 为什么用文件而不是 `XFile.fromData`：Android 的 `ACTION_SEND` 需要
/// `content://` URI，插件会为文件生成 FileProvider URI；直接传内存字节
/// 在部分接收方（笔记/邮件附件）会拿不到图。
///
/// 文件留在临时目录里不主动删：分享面板可能在 `share()` 返回后仍在读取；
/// 系统会按缓存策略清理。文件名带书/页，避免同名覆盖。
Future<ShareResult> sharePageImage(
  Uint8List bytes, {
  required String fileName,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'image/png')],
      title: fileName,
    ),
  );
}
