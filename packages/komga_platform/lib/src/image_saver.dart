import 'package:flutter/services.dart';

/// 保存图片到系统默认相册 / 图片目录的结果。
sealed class ImageSaveResult {
  const ImageSaveResult();
}

final class ImageSaveSuccess extends ImageSaveResult {
  const ImageSaveSuccess({this.location});

  /// 原生侧返回的落地标识（例如 MediaStore URI 或相册名），仅用于诊断/日志。
  final String? location;
}

enum ImageSaveFailureKind { permissionDenied, unsupported, ioError }

final class ImageSaveFailure extends ImageSaveResult {
  const ImageSaveFailure(this.kind, {this.message});

  final ImageSaveFailureKind kind;
  final String? message;
}

/// 将图片字节直接写入设备默认图片存储位置（Android 系统相册 `Pictures/Yomu`，
/// iOS 系统相册 `Photos`）。
abstract interface class ImageSaver {
  Future<ImageSaveResult> saveImage(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  });
}

class ChannelImageSaver implements ImageSaver {
  ChannelImageSaver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('komganative/device');

  final MethodChannel _channel;

  @override
  Future<ImageSaveResult> saveImage(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'saveImage',
        <String, Object?>{
          'bytes': bytes,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      return ImageSaveSuccess(location: response?['location'] as String?);
    } on MissingPluginException {
      return const ImageSaveFailure(ImageSaveFailureKind.unsupported);
    } on PlatformException catch (error) {
      final kind = error.code == 'PERMISSION_DENIED'
          ? ImageSaveFailureKind.permissionDenied
          : ImageSaveFailureKind.ioError;
      return ImageSaveFailure(kind, message: error.message);
    }
  }
}
