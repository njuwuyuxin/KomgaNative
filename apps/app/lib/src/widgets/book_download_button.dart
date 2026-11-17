import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 一本书的下载按钮：未下载 / 下载中（可取消）/ 已下载（可删除）。
///
/// 单独成文件：系列详情已经很长，而"下载状态 → 图标"的映射还要在阅读器复用。
class BookDownloadButton extends ConsumerWidget {
  const BookDownloadButton({required this.book, super.key});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(downloadsProvider)[book.id];
    final downloaded = ref.watch(downloadedProvider(book.id)).value;
    final controller = ref.read(downloadsProvider.notifier);

    if (status?.isRunning ?? false) {
      final progress = status!.progress!;
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: 'Cancel download',
        onPressed: () => controller.cancel(book.id),
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: progress.fraction,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final error = status?.error;
    if (error != null) {
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: '$error · tap to retry',
        onPressed: () {
          controller.dismiss(book.id);
          unawaited(controller.start(book));
        },
        icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
      );
    }

    if (downloaded != null) {
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: 'Downloaded · tap to remove',
        onPressed: () => _confirmDelete(context, controller),
        icon: Icon(Icons.download_done, color: theme.colorScheme.primary),
      );
    }

    return IconButton(
      key: Key('book-download-${book.id}'),
      tooltip: 'Download for offline reading',
      onPressed: () => unawaited(controller.start(book)),
      icon: const Icon(Icons.download_outlined),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DownloadsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove download?'),
        content: const Text(
          'The cached pages for this book will be deleted. '
          'You can still read it online.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.delete(book);
  }
}
