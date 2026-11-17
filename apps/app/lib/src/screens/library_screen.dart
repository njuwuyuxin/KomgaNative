import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/sample_data.dart';

/// 书架页（M0 用示例数据，M1 接 `/api/v1/series`）。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sizeClass = WindowSizeClass.of(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: <Widget>[
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: sizeClass.gridColumns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.58,
        ),
        itemCount: kSampleSeries.length,
        itemBuilder: (BuildContext context, int index) {
          final Series series = kSampleSeries[index];
          return SeriesTile(
            series: series,
            onTap: () => context.push('/reader/b1'),
          );
        },
      ),
    );
  }
}
