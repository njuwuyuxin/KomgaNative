import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 页列表的三种"还不能读"：加载中 / 失败 / 空书。都过了才调用 [builder]。
///
/// 从 `ReaderScreen` 拆出来，页面只处理"有页可读"的情况。
/// 按 `hasError` / `value` 判断，不用 `switch` 匹配 `AsyncError`
/// （Riverpod 3 首次失败给的是 `AsyncLoading` + `hasError`，见 AGENTS.md）。
class ReaderPagesGate extends StatelessWidget {
  const ReaderPagesGate({
    required this.pages,
    required this.palette,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<List<PageInfo>> pages;
  final ReaderPalette palette;
  final VoidCallback onRetry;
  final Widget Function(List<PageInfo> pages) builder;

  @override
  Widget build(BuildContext context) {
    final error = pages.error;
    final value = pages.value;
    if (error != null) {
      return ReaderFailure(failure: error, palette: palette, onRetry: onRetry);
    }
    if (value == null) {
      return Scaffold(
        backgroundColor: palette.background,
        body: Center(
          child: CircularProgressIndicator(color: palette.onBackgroundMuted),
        ),
      );
    }
    if (value.isEmpty) {
      return ReaderFailure(
        failure: const ProtocolFailure(),
        palette: palette,
        title: AppLocalizations.of(context).readerNoPages,
        onRetry: onRetry,
      );
    }
    return builder(value);
  }
}
