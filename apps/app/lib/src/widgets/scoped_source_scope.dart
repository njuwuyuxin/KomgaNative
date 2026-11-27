import 'package:material_ui/material_ui.dart';

/// 为跨源直达页面（如从「正在读」或「阅读历史」打开另一源的阅读器/系列详情）
/// 向下传递该页面所属内容源的 `sourceKey`。
///
/// 不使用嵌套 `ProviderScope` 覆盖全局仓库：Riverpod 3 中未声明 `dependencies:`
/// 的派生 family 会越过子作用域回落到根容器；所有跨源读取统一改为显式按
/// `(sourceKey, id)` 经 `source_scoped_providers.dart` 寻址。
class ScopedSourceScope extends InheritedWidget {
  const ScopedSourceScope({
    required this.sourceKey,
    required super.child,
    super.key,
  });

  final String? sourceKey;

  /// 读取最近的祖先作用域携带的 `sourceKey`（未包裹时返回 `null`）。
  static String? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ScopedSourceScope>()
      ?.sourceKey;

  /// 读取不建立依赖关系的当前 `sourceKey`（用于 `initState` 或一次性事件回调）。
  static String? readOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ScopedSourceScope>()?.sourceKey;

  @override
  bool updateShouldNotify(ScopedSourceScope oldWidget) =>
      sourceKey != oldWidget.sourceKey;
}
