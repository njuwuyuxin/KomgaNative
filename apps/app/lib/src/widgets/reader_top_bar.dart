import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/widgets/page_navigator_sheet.dart';
import 'package:yomu/src/widgets/reader_bar.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_quick_settings_sheet.dart';
import 'package:yomu/src/widgets/reader_settings_sheet.dart';
import 'package:yomu/src/widgets/reader_toc_sheet.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器顶栏的接线：离线状态、缩略图面板、设置面板、返回。
///
/// [ReaderBar] 只管画；这里负责把它接到 provider 和两个面板上，
/// 让 `ReaderScreen` 只传"现在是哪本、第几页、跳页去哪"。
class ReaderTopBar extends ConsumerWidget {
  const ReaderTopBar({
    required this.bookId,
    this.seriesId,
    required this.title,
    required this.pageLabel,
    required this.palette,
    required this.mode,
    required this.page,
    required this.total,
    required this.onJump,
    this.direction = ReadingDirection.unknown,
    this.onGroupFrom,
    this.incognito = false,
    required this.onToggleIncognito,
    this.onSavePage,
    this.onSharePage,
    super.key,
  });

  final String bookId;

  /// 当前书的系列 id；设置面板用它决定是否显示"按系列记住"（UI-P3-2）。
  final String? seriesId;
  final String title;
  final String pageLabel;
  final ReaderPalette palette;
  final ReadingMode mode;

  /// 换书时沿用同一个阅读方向（RDR-02）。
  final ReadingDirection direction;

  /// 1 基当前页。
  final int page;
  final int total;

  /// 缩略图 / 设置面板选中某页（1 基）。
  final void Function(int page) onJump;

  /// 双页模式长按页缩略图：从这一页开始重新分组（UI-P3-5）。
  final void Function(int page)? onGroupFrom;

  final bool incognito;
  final VoidCallback onToggleIncognito;

  /// 直接保存当前屏图片（单页存单张，双页拼接保存）。
  final VoidCallback? onSavePage;

  /// 分享当前页（UI-P3-6）：菜单里的"分享本页"。
  final VoidCallback? onSharePage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocalBook = bookId.startsWith('local:') && seriesId != null;
    return ValueListenableBuilder<bool>(
      valueListenable: ref.watch(offlineProvider),
      builder: (BuildContext context, bool offline, Widget? _) => ReaderBar(
        title: title,
        pageLabel: pageLabel,
        palette: palette,
        mode: mode,
        offline: !isLocalBook && offline,
        incognito: incognito,
        onToggleIncognito: onToggleIncognito,
        onSavePage: onSavePage,
        onSharePage: onSharePage,
        onSetAsCover: isLocalBook
            ? () => unawaited(_setAsCover(context, ref))
            : null,
        // AA：只放读的时候真的会改的五项，改完立刻回到画面（RDR-03）。
        onOpenQuickSettings: () => showReaderQuickSettingsSheet(
          context,
          palette: palette,
          seriesId: seriesId,
        ),
        onOpenPages: () => unawaited(
          showPageNavigator(
            context,
            bookId: bookId,
            total: total,
            currentPage: page,
            palette: palette,
            onJump: onJump,
            onGroupFrom: onGroupFrom,
          ),
        ),
        // 目录（RDR-02）：本系列的书列表，点一本替换当前页。
        onOpenToc: seriesId == null
            ? null
            : () => showReaderTocSheet(
                context,
                seriesId: seriesId!,
                currentBookId: bookId,
                palette: palette,
                direction: direction,
              ),
        onOpenSettings: () => showReaderSettingsSheet(
          context,
          palette: palette,
          page: page,
          total: total,
          seriesId: seriesId,
          onJump: onJump,
        ),
        onClose: () => context.pop(),
      ),
    );
  }

  Future<void> _setAsCover(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await ref
          .read(localCatalogMutatorProvider)
          .setCustomCoverFromPageBytes(
            bookId: bookId,
            seriesId: seriesId!,
            pageNumber: page,
          );
      if (ok && messenger != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.coverUpdated)));
      }
    } on Object {
      // 设封面失败不阻断当前阅读会话。
    }
  }
}
