import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';

/// 为跨源直达页面（如从「正在读」或「阅读历史」打开另一源的阅读器/系列页）注入局部源作用域。
///
/// - 当 [sourceKey] 为空或等于当前书架激活源时，零开销直接返回 [child]；
/// - 当单测已手动 override 顶层 `libraryRepositoryProvider` 时，保留测试 override 不覆盖；
/// - 否则从 [sourceRegistryProvider] 解析目标源的 [SourceBundle] 注入局部 `ProviderScope`。
class ScopedSourceScope extends ConsumerWidget {
  const ScopedSourceScope({
    required this.sourceKey,
    required this.child,
    super.key,
  });

  final String? sourceKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = sourceKey;
    if (key == null || key.isEmpty) return child;

    final active = ref.watch(activeSourceProvider);
    if (key == active.sourceKey) return child;

    final currentLib = ref.watch(libraryRepositoryProvider);
    final activeBundle = ref.watch(activeSourceBundleProvider);
    if (!identical(currentLib, activeBundle.library)) {
      return child;
    }

    final bundle = ref.watch(sourceRegistryProvider).bundleFor(key);
    return ProviderScope(
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(bundle.library),
        readerRepositoryProvider.overrideWithValue(bundle.reader),
        collectionsRepositoryProvider.overrideWithValue(bundle.collections),
        readStatusRepositoryProvider.overrideWithValue(bundle.readStatus),
        activeServerKeyProvider.overrideWithValue(bundle.source.sourceKey),
      ],
      child: child,
    );
  }
}
