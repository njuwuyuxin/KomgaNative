import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:material_ui/material_ui.dart';

/// 偏好快照的编解码：必须能扛住旧版本、手工改过、写坏的存档。
void main() {
  test('往返：所有字段都能原样读回', () {
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      forceEink: true,
      language: 'zh',
      haptics: false,
      view: ShelfView.list,
      coverSize: ShelfCoverSize.large,
      sort: SeriesSort.recentlyAdded,
      readStatus: SeriesReadStatus.unread,
      libraryFilters: <String, String>{'https://a.example': 'lib-1'},
    );

    final again = AppSettings.fromJson(settings.toJson());
    expect(again.themeMode, ThemeMode.dark);
    expect(again.forceEink, isTrue);
    expect(again.language, 'zh');
    expect(again.haptics, isFalse);
    expect(again.view, ShelfView.list);
    expect(again.coverSize, ShelfCoverSize.large);
    expect(again.sort, SeriesSort.recentlyAdded);
    expect(again.readStatus, SeriesReadStatus.unread);
    expect(again.libraryFilters, <String, String>{
      'https://a.example': 'lib-1',
    });
  });

  test('空对象 → 全默认', () {
    final settings = AppSettings.fromJson(const <String, Object?>{});
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.forceEink, isFalse);
    expect(settings.language, 'system');
    expect(settings.haptics, isTrue);
    expect(settings.view, ShelfView.grid);
    expect(settings.coverSize, ShelfCoverSize.medium);
    expect(settings.sort, isNull);
    expect(settings.readStatus, isNull);
    expect(settings.libraryFilters, isEmpty);
  });

  test('未知枚举回默认；可空枚举回 null', () {
    final settings = AppSettings.fromJson(const <String, Object?>{
      'theme': 'midnight',
      'shelfView': 'carousel',
      'coverSize': 'huge',
      'sort': 'bestMatch',
      'readStatus': 'someday',
    });
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.view, ShelfView.grid);
    expect(settings.coverSize, ShelfCoverSize.medium);
    expect(settings.sort, isNull);
    expect(settings.readStatus, isNull);
  });

  test('类型不对逐字段回默认，不整份丢掉', () {
    final settings = AppSettings.fromJson(const <String, Object?>{
      'theme': 1,
      'forceEink': 'true',
      'language': 42,
      'haptics': 0,
      'shelfView': const <String>[],
      'coverSize': null,
      'sort': true,
      'libraryFilters': 'nope',
    });
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.forceEink, isFalse);
    // 语言不是字符串 → 回 system（不是"英文"）。
    expect(settings.language, 'system');
    expect(settings.haptics, isTrue);
    expect(settings.coverSize, ShelfCoverSize.medium);
    expect(settings.libraryFilters, isEmpty);
  });

  test('libraryFilters 只收"非空字符串 → 非空字符串"', () {
    final settings = AppSettings.fromJson(const <String, Object?>{
      'libraryFilters': <String, Object?>{
        'https://a.example': 'lib-1',
        'https://b.example': '',
        'https://c.example': 3,
      },
    });
    expect(settings.libraryFilters, <String, String>{
      'https://a.example': 'lib-1',
    });
  });

  test('按服务器记住库筛选：写入、覆盖、清除', () {
    const key = 'https://a.example';
    const other = 'https://b.example';

    final first = AppSettings.defaults.withLibraryFilter(key, 'lib-1');
    expect(first.libraryFilterFor(key), 'lib-1');
    expect(first.libraryFilterFor(other), isNull);

    final second = first.withLibraryFilter(key, 'lib-2');
    expect(second.libraryFilterFor(key), 'lib-2');

    // null = "全部库"，同时要把这台服务器的记录删掉，别留一颗脏 id。
    final cleared = second.withLibraryFilter(key, null);
    expect(cleared.libraryFilterFor(key), isNull);
    expect(cleared.libraryFilters, isEmpty);

    // 两台服务器各记各的。
    final both = first.withLibraryFilter(other, 'lib-b');
    expect(both.libraryFilterFor(key), 'lib-1');
    expect(both.libraryFilterFor(other), 'lib-b');

    // 服务器身份未知时不读不写。
    expect(first.libraryFilterFor(null), isNull);
  });
}
