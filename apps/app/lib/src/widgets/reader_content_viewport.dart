import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/page_curl.dart';
import 'package:yomu/src/features/reader/reader_layout.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_vertical_view.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器正文视口：根据模式切换条漫纵向滚动与翻页绘制，并统一应用图像滤镜（P3-1）。
class ReaderContentViewport extends StatelessWidget {
  const ReaderContentViewport({
    required this.bookId,
    required this.isEink,
    required this.pages,
    required this.config,
    required this.layout,
    required this.palette,
    required this.rightToLeft,
    required this.jumpToken,
    required this.jumpPage,
    required this.pagedKey,
    required this.onVerticalPageChanged,
    required this.onPagedTurn,
    required this.onToggleChrome,
    super.key,
  });

  final String bookId;
  final bool isEink;
  final List<PageInfo> pages;
  final ReaderConfig config;
  final ReaderLayout layout;
  final ReaderPalette palette;
  final bool rightToLeft;
  final int jumpToken;
  final int jumpPage;
  final GlobalKey<ReaderPagedViewState> pagedKey;
  final ValueChanged<int> onVerticalPageChanged;
  final ValueChanged<int> onPagedTurn;
  final VoidCallback onToggleChrome;

  @override
  Widget build(BuildContext context) {
    final mode = layout.mode;
    final Widget content;
    if (mode == ReadingMode.verticalScroll) {
      content = ReaderVerticalView(
        bookId: bookId,
        pages: pages,
        initialPage: layout.page,
        jumpToken: jumpToken,
        jumpPage: jumpPage,
        palette: palette,
        trimBorders: config.trimBorders,
        autoScrollSpeed: config.autoScrollSpeed,
        autoScrollAllowed: !isEink,
        onPageChanged: onVerticalPageChanged,
        onToggleChrome: onToggleChrome,
      );
    } else {
      content = ReaderPagedView(
        key: pagedKey,
        bookId: bookId,
        pages: pages,
        spread: layout.spread,
        rightToLeft: rightToLeft,
        palette: palette,
        fit: config.fit.fit,
        doublePage: mode == ReadingMode.doublePage,
        lockZoom: config.lockZoom,
        trimBorders: config.trimBorders,
        tapZone: config.tapZone,
        invertTapZones: config.invertTapZones,
        doubleTapZoom: config.doubleTapZoom,
        nextSpread: layout.neighbour(1),
        previousSpread: layout.neighbour(-1),
        pageHalf: layout.currentFrameHalf,
        nextPageHalf: layout.splitNeighbour(1)?.half ?? PageHalf.full,
        previousPageHalf: layout.splitNeighbour(-1)?.half ?? PageHalf.full,
        style: PageTurnStyle.resolve(
          choice: config.pageTurn,
          eink: isEink,
          disableAnimations:
              MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          duration: AppMotion.of(context).emphasized,
        ),
        onTurn: onPagedTurn,
        onToggleChrome: onToggleChrome,
      );
    }

    if (config.imageFilter.isIdentity) return content;
    return ColorFiltered(
      key: const Key('reader-image-filter'),
      colorFilter: ColorFilter.matrix(
        buildImageFilterMatrix(config.imageFilter),
      ),
      child: content,
    );
  }
}
