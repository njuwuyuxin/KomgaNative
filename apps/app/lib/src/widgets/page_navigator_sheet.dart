import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 缩略图跳页面板。
///
/// 为什么不用 Komga 的页缩略图接口：**它没有**。`/books/{id}/thumbnail` 是整本书的封面，
/// 页级只有 `/pages/{n}` 全尺寸图。所以这里用页面图 + `cacheWidth` 解码降采样；
/// 网格是懒构建的，只有滚到的页才会真正下载。
Future<void> showPageNavigator(
  BuildContext context, {
  required String bookId,
  required int total,
  required int currentPage,
  required ReaderPalette palette,
  required ValueChanged<int> onJump,
}) async {
  final page = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.background,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: PageNavigatorSheet(
        bookId: bookId,
        total: total,
        currentPage: currentPage,
        palette: palette,
      ),
    ),
  );
  if (page != null) onJump(page);
}

class PageNavigatorSheet extends StatelessWidget {
  const PageNavigatorSheet({
    required this.bookId,
    required this.total,
    required this.currentPage,
    required this.palette,
    super.key,
  });

  final String bookId;
  final int total;
  final int currentPage;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Pages',
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$currentPage / $total',
                  style: TextStyle(color: palette.muted),
                ),
                IconButton(
                  key: const Key('page-navigator-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: palette.foreground,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              key: const Key('page-navigator-grid'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                childAspectRatio: 0.66,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: total,
              itemBuilder: (BuildContext context, int index) {
                final page = index + 1;
                return _PageThumbnail(
                  key: Key('page-thumb-$page'),
                  bookId: bookId,
                  page: page,
                  current: page == currentPage,
                  palette: palette,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PageThumbnail extends ConsumerWidget {
  const _PageThumbnail({
    required this.bookId,
    required this.page,
    required this.current,
    required this.palette,
    super.key,
  });

  final String bookId;
  final int page;
  final bool current;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(
      readerPageImageProvider((bookId: bookId, page: page)),
    );
    final bytes = image.value;

    return InkWell(
      onTap: () => Navigator.of(context).pop(page),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(
            color: current ? palette.foreground : palette.outline,
            width: current ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (bytes != null)
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  gaplessPlayback: true,
                )
              else
                Center(
                  child: image.hasError
                      ? Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                          color: palette.muted,
                        )
                      : SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.muted,
                          ),
                        ),
                ),
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  color: palette.background.withValues(alpha: 0.7),
                  child: Text(
                    '$page',
                    style: TextStyle(color: palette.foreground, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
