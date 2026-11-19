import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 书架的多选状态（LIB-03）。
///
/// 单独一个 provider 而不是塞进 `ShelfState`：多选是**纯 UI 状态**，
/// 和"该请求哪一页数据"无关；塞进去会让每次勾选都触发一次列表重建判断，
/// 也容易在刷新时被列表数据覆盖掉。
class ShelfSelectionState {
  const ShelfSelectionState({this.active = false, this.ids = const <String>{}});

  /// 是否处于多选态。注意它和"选了几项"是两件事：刚进多选时一项都没选。
  final bool active;
  final Set<String> ids;

  bool contains(String seriesId) => ids.contains(seriesId);

  ShelfSelectionState copyWith({bool? active, Set<String>? ids}) =>
      ShelfSelectionState(active: active ?? this.active, ids: ids ?? this.ids);
}

/// 多选状态机。
///
/// 为什么需要显式的 [enter]：长按在书架上是**系列菜单**（标记已读/置顶/详情），
/// 不能同时用来进多选。所以入口是顶部工具条的"选择"按钮——这一点与本项目
/// 的竞品（Panels）一致：长按出菜单，多选走选择按钮。
class ShelfSelection extends Notifier<ShelfSelectionState> {
  @override
  ShelfSelectionState build() => const ShelfSelectionState();

  void enter() {
    if (state.active) return;
    state = const ShelfSelectionState(active: true);
  }

  void exit() => state = const ShelfSelectionState();

  void toggle(String seriesId) {
    final next = Set<String>.of(state.ids);
    if (!next.remove(seriesId)) next.add(seriesId);
    state = state.copyWith(active: true, ids: next);
  }

  /// 全选当前列表里的系列。
  void selectAll(Iterable<String> seriesIds) =>
      state = ShelfSelectionState(active: true, ids: seriesIds.toSet());
}

final NotifierProvider<ShelfSelection, ShelfSelectionState>
shelfSelectionProvider = NotifierProvider<ShelfSelection, ShelfSelectionState>(
  ShelfSelection.new,
);
