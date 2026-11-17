import 'package:komga_design_system/komga_design_system.dart';
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

/// 顶部：返回 + 书名 + 页码 + 阅读模式。
class ReaderBar extends StatelessWidget {
  const ReaderBar({
    required this.title,
    required this.pageLabel,
    required this.onClose,
    required this.palette,
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final String title;

  /// 单页是 `3 / 12`，双页是 `3–4 / 12`。
  final String pageLabel;

  final VoidCallback onClose;
  final ReaderPalette palette;
  final ReadingMode mode;
  final ValueChanged<ReadingMode> onModeChanged;

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
          Text(pageLabel, style: TextStyle(color: palette.muted)),
          PopupMenuButton<ReadingMode>(
            key: const Key('reader-mode-button'),
            tooltip: 'Reading mode',
            icon: Icon(Icons.tune, color: palette.foreground),
            onSelected: onModeChanged,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<ReadingMode>>[
                  for (final option in ReadingMode.values)
                    PopupMenuItem<ReadingMode>(
                      key: Key('reader-mode-${option.name}'),
                      value: option,
                      child: Row(
                        children: <Widget>[
                          Icon(_iconFor(option), size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Text(_labelFor(option)),
                          if (option == mode) ...<Widget>[
                            const Spacer(),
                            const Icon(Icons.check, size: 18),
                          ],
                        ],
                      ),
                    ),
                ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(ReadingMode mode) => switch (mode) {
    ReadingMode.paged => Icons.crop_portrait,
    ReadingMode.doublePage => Icons.auto_stories_outlined,
    ReadingMode.verticalScroll => Icons.view_agenda_outlined,
  };

  static String _labelFor(ReadingMode mode) => switch (mode) {
    ReadingMode.paged => 'Single page',
    ReadingMode.doublePage => 'Double page',
    ReadingMode.verticalScroll => 'Vertical scroll',
  };
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
