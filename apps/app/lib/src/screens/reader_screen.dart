import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/data/sample_data.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 阅读器占位页。
///
/// M0 的作用不是"能看漫画"，而是把**布局计算链路**接进真实 Widget：
/// 页面尺寸 → [computePagedLayout] → 绘制矩形。M2 会把中间换成真实的页图管线。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  final String bookId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  int _page = 1;

  static const int _pageWidth = 1000;
  static const int _pageHeight = 1500;

  @override
  Widget build(BuildContext context) {
    final book = sampleBook(widget.bookId);
    final pagesCount = book?.pagesCount ?? 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ReaderBar(
              title: book?.name ?? widget.bookId,
              page: _page,
              pagesCount: pagesCount,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final viewport = SizeD(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final layout = computePagedLayout(
                    pageWidth: _pageWidth,
                    pageHeight: _pageHeight,
                    viewport: viewport,
                  );
                  return Stack(
                    children: <Widget>[
                      Positioned(
                        left: layout.content.left,
                        top: layout.content.top,
                        width: layout.content.width,
                        height: layout.content.height,
                        child: _PagePlaceholder(page: _page),
                      ),
                    ],
                  );
                },
              ),
            ),
            _ReaderControls(
              page: _page,
              pagesCount: pagesCount,
              onPrevious: _page > 1 ? () => setState(() => _page--) : null,
              onNext: _page < pagesCount ? () => setState(() => _page++) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBar extends StatelessWidget {
  const _ReaderBar({
    required this.title,
    required this.page,
    required this.pagesCount,
  });

  final String title;
  final int page;
  final int pagesCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
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
        ],
      ),
    );
  }
}

class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF2F2F2)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: AppSpacing.sm),
            Text('Page $page', style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.page,
    required this.pagesCount,
    this.onPrevious,
    this.onNext,
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
