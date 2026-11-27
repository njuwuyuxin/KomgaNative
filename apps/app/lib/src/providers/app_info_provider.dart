import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 构建产物里真实的版本信息（FIX-09）。
///
/// 以前设置页写死 `0.1.0 (v1)`：`pubspec.yaml` 改了版本，界面还是旧号，
/// 用户据此判断"装的是不是新版"就会判断错。见 ADR 0007。
class AppInfo {
  const AppInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  /// 设置页那一行的文案：`0.1.0 (1)`；没有构建号时只显示版本。
  String get label => buildNumber.isEmpty ? version : '$version ($buildNumber)';
}

/// 读不到构建信息时的兜底版本（与 `pubspec.yaml` 的 `version:` 手工保持一致）。
///
/// 只用于"平台通道不可用"这种情况（测试环境、异常系统镜像）：
/// 界面上宁可显示一个略旧的版本号，也不能显示空白。
const String kFallbackAppVersion = '0.2.1';

/// 版本信息。读失败不抛错——"关于"页不该因为读不到版本号就整块报错。
final FutureProvider<AppInfo> appInfoProvider = FutureProvider<AppInfo>((
  Ref ref,
) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      version: info.version.isEmpty ? kFallbackAppVersion : info.version,
      buildNumber: info.buildNumber,
    );
  } on Object {
    return const AppInfo(version: kFallbackAppVersion, buildNumber: '');
  }
});
