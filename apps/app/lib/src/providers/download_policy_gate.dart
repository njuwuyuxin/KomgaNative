import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_platform/komga_platform.dart';

/// 下载前的网络检查（DLD-01）。
///
/// 返回 null 表示可以下；返回文案表示被"仅 Wi-Fi"挡住了。
/// **判断不出网络类型时一律放行**（见 `NetworkKind.unknown`）：
/// 拿不到信息就把用户拦住，是最难排查的那种问题。
/// 标记已读之后，按策略删掉这一本的下载（DLD-01"读完自动删除"）。
///
/// 现在的触发点是**用户标记已读**（单本菜单 / 批量标记），不是"阅读进度自然读完"——
/// 那条路径在同步层，暂时没有回调点。这点写在 docs 里，不假装是全自动。
Future<void> maybeDeleteReadDownload(WidgetRef ref, Book book) async {
  try {
    final policy = ref.read(downloadPolicyProvider).value;
    if (policy == null || !policy.autoDeleteRead) return;
    final record = await ref.read(downloadedProvider(book.id).future);
    if (record == null) return;
    await ref.read(downloadsProvider.notifier).delete(book);
  } on Object {
    // 自动删除是"锦上添花"：失败不影响标记已读本身。
  }
}

Future<String?> downloadBlockReason(
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  try {
    // 用 `value` 而不是 `future`：策略还没读到时**放行**（见下面的注释），
    // 也让"点下载"不必等一次设置读取。
    final policy = ref.read(downloadPolicyProvider).value;
    if (policy == null || !policy.wifiOnly) return null;
    final kind = await ref.read(networkProbeProvider).current();
    return kind == NetworkKind.cellular ? l10n.downloadWifiOnlyBlocked : null;
  } on Object {
    // 设置读不出来就放行：下载不该因为"读不到设置"而不可用。
    return null;
  }
}
