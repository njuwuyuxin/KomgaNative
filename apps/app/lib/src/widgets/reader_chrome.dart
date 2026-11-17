import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的失败页（书打不开 / 页列表加载失败）。
class ReaderFailure extends StatelessWidget {
  const ReaderFailure({
    required this.failure,
    required this.onRetry,
    required this.palette,
    this.title,
    super.key,
  });

  final Object failure;
  final VoidCallback onRetry;
  final ReaderPalette palette;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.foreground,
        title: const Text('Reader'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.broken_image_outlined,
                size: AppSpacing.xxl,
                color: palette.muted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title ?? message?.message ?? 'Failed to open this book',
                style: TextStyle(color: palette.foreground),
                textAlign: TextAlign.center,
              ),
              if (message?.hint != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!.hint!,
                  style: TextStyle(color: palette.muted),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单页加载失败时的占位（还能翻页/退出）。
class PageError extends StatelessWidget {
  const PageError({
    required this.error,
    required this.onRetry,
    required this.palette,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final message = error is ShelfFailure ? error as ShelfFailure : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.broken_image_outlined,
          color: palette.muted,
          size: AppSpacing.xl,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message?.message ?? 'Failed to load this page',
          style: TextStyle(color: palette.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// 顶部：返回 + 书名 + 页码 + 阅读设置。
class ReaderBar extends StatelessWidget {
  const ReaderBar({
    required this.title,
    required this.pageLabel,
    required this.onClose,
    required this.palette,
    required this.mode,
    required this.onOpenSettings,
    required this.onOpenPages,
    this.offline = false,
    super.key,
  });

  final String title;

  /// 单页是 `3 / 12`，双页是 `3–4 / 12`。
  final String pageLabel;

  final VoidCallback onClose;
  final ReaderPalette palette;

  /// 当前生效的模式：图标跟着它变，用户一眼知道自己在什么模式。
  final ReadingMode mode;
  final VoidCallback onOpenSettings;

  /// 打开缩略图跳页面板。
  final VoidCallback onOpenPages;

  /// 当前内容可能来自缓存（断网/服务端不可用）。只在顶栏放一个小图标：
  /// 阅读区里放横幅会挤掉画面，而翻页本身照常。
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back),
            color: palette.foreground,
            tooltip: 'Close',
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (offline) ...<Widget>[
            Tooltip(
              message: 'Offline · showing saved pages',
              child: Icon(
                Icons.cloud_off_outlined,
                size: 16,
                color: palette.muted,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(pageLabel, style: TextStyle(color: palette.muted)),
          IconButton(
            key: const Key('reader-pages-button'),
            onPressed: onOpenPages,
            icon: const Icon(Icons.grid_view_outlined),
            color: palette.foreground,
            tooltip: 'Page thumbnails',
          ),
          IconButton(
            key: const Key('reader-settings-button'),
            onPressed: onOpenSettings,
            icon: Icon(iconForMode(mode)),
            color: palette.foreground,
            tooltip: 'Reading settings',
          ),
        ],
      ),
    );
  }
}

/// 模式图标：顶栏按钮与设置面板共用，避免两处各写一份。
IconData iconForMode(ReadingMode mode) => switch (mode) {
  ReadingMode.paged => Icons.crop_portrait,
  ReadingMode.doublePage => Icons.auto_stories_outlined,
  ReadingMode.verticalScroll => Icons.view_agenda_outlined,
};

/// 书末：告诉用户"读完了"，并给出下一步（下一本 / 回系列）。
///
/// 不用弹窗：弹窗会打断"翻到最后一页想再看一眼"的动作，而且每次进阅读器
/// 都弹一次很烦。条状常驻，只在完成态出现。
class ReaderFinishedBar extends StatelessWidget {
  const ReaderFinishedBar({
    required this.palette,
    required this.onBack,
    this.nextBook,
    this.onNext,
    super.key,
  });

  final ReaderPalette palette;
  final Book? nextBook;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final next = nextBook;
    final label = next == null
        ? 'Finished'
        : 'Finished · next ${next.number.isEmpty ? next.name : '#${next.number}'}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        key: const Key('reader-finished'),
        children: <Widget>[
          Icon(Icons.check_circle_outline, size: 18, color: palette.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.foreground),
            ),
          ),
          if (next != null)
            TextButton(
              key: const Key('reader-next-book'),
              style: TextButton.styleFrom(foregroundColor: palette.foreground),
              onPressed: onNext,
              child: const Text('Next book'),
            ),
          TextButton(
            key: const Key('reader-back-series'),
            style: TextButton.styleFrom(foregroundColor: palette.muted),
            onPressed: onBack,
            child: const Text('Series'),
          ),
        ],
      ),
    );
  }
}

/// 底部：上一页 / 页数 / 下一页。
class ReaderControls extends StatelessWidget {
  const ReaderControls({
    required this.pagesCount,
    required this.palette,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final int pagesCount;
  final ReaderPalette palette;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            color: palette.foreground,
            disabledColor: palette.outline,
            tooltip: 'Previous page',
          ),
          Text('$pagesCount pages', style: TextStyle(color: palette.muted)),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            color: palette.foreground,
            disabledColor: palette.outline,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}
