import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系列内书列表的多选状态（SER-02）。
///
/// 与书架的 `ShelfSelection` 分开：两边可以同时存在（宽屏两栏时甚至同屏），
/// 共用一个 provider 会让"在书架勾了两个系列"串到系列页的书上。
class BookSelectionState {
  const BookSelectionState({this.active = false, this.ids = const <String>{}});

  final bool active;
  final Set<String> ids;

  bool contains(String bookId) => ids.contains(bookId);

  BookSelectionState copyWith({bool? active, Set<String>? ids}) =>
      BookSelectionState(active: active ?? this.active, ids: ids ?? this.ids);
}

class BookSelection extends Notifier<BookSelectionState> {
  @override
  BookSelectionState build() => const BookSelectionState();

  void enter() {
    if (state.active) return;
    state = const BookSelectionState(active: true);
  }

  void exit() => state = const BookSelectionState();

  void toggle(String bookId) {
    final next = Set<String>.of(state.ids);
    if (!next.remove(bookId)) next.add(bookId);
    state = state.copyWith(active: true, ids: next);
  }

  void selectAll(Iterable<String> bookIds) =>
      state = BookSelectionState(active: true, ids: bookIds.toSet());
}

final NotifierProvider<BookSelection, BookSelectionState>
bookSelectionProvider = NotifierProvider<BookSelection, BookSelectionState>(
  BookSelection.new,
);
