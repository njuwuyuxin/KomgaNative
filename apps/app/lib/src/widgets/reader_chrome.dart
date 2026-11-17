import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的失败页（书打不开 / 页列表加载失败）。
class ReaderFailure extends StatelessWidget {
  const ReaderFailure({
    required this.failure,
    required this.onRetry,
    this.title,
    super.key,
  });

  final Object failure;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Reader'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.broken_image_outlined,
                size: AppSpacing.xxl,
                color: Colors.white54,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title ?? message?.message ?? 'Failed to open this book',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              if (message?.hint != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!.hint!,
                  style: const TextStyle(color: Colors.white54),
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
  const PageError({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ShelfFailure ? error as ShelfFailure : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: AppSpacing.xl,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message?.message ?? 'Failed to load this page',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// 顶部：返回 + 书名 + 页码。
class ReaderBar extends StatelessWidget {
  const ReaderBar({
    required this.title,
    required this.page,
    required this.pagesCount,
    required this.onClose,
    super.key,
  });

  final String title;
  final int page;
  final int pagesCount;
  final VoidCallback onClose;

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
            color: Colors.white,
            tooltip: 'Close',
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$page / $pagesCount',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// 底部：上一页 / 页数 / 下一页。
class ReaderControls extends StatelessWidget {
  const ReaderControls({
    required this.page,
    required this.pagesCount,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final int page;
  final int pagesCount;
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
            color: Colors.white,
            disabledColor: Colors.white24,
            tooltip: 'Previous page',
          ),
          Text(
            '$pagesCount pages',
            style: const TextStyle(color: Colors.white54),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            color: Colors.white,
            disabledColor: Colors.white24,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}
