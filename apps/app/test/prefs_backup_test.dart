import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/prefs_backup.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';

/// SET-02：偏好导出/导入。
void main() {
  const reader = ReaderPrefs(
    global: ReaderConfig(
      mode: ReaderModeChoice.double,
      pageTurn: ReaderPageTurnChoice.fade,
      showSessionTime: false,
    ),
    spreadFrom: <String, int>{'b1': 3},
  );

  final settings = const AppSettings().copyWith(
    language: 'zh',
    forceEink: true,
    view: ShelfView.list,
    coverSize: ShelfCoverSize.large,
    searchHistory: <String>['frieren'],
    downloadWifiOnly: true,
    downloadConcurrency: 3,
  );

  test('导出 → 解析回来：阅读设置、应用设置与置顶列表都还原', () {
    final encoded = PrefsBackup.of(
      reader: reader,
      settings: settings,
      pinnedSeries: const <String>['s1', 's2'],
    ).encode();
    final backup = PrefsBackup.decode(encoded);

    final restoredReader = backup.toReaderPrefs();
    expect(restoredReader.global.mode, ReaderModeChoice.double);
    expect(restoredReader.global.pageTurn, ReaderPageTurnChoice.fade);
    expect(restoredReader.global.showSessionTime, isFalse);
    expect(restoredReader.spreadFrom, <String, int>{'b1': 3});
    expect(backup.pinnedSeries, const <String>['s1', 's2']);

    final restoredSettings = backup.toAppSettings();
    expect(restoredSettings.language, 'zh');
    expect(restoredSettings.forceEink, isTrue);
    expect(restoredSettings.view, ShelfView.list);
    expect(restoredSettings.coverSize, ShelfCoverSize.large);
    expect(restoredSettings.searchHistory, <String>['frieren']);
    expect(restoredSettings.downloadWifiOnly, isTrue);
    expect(restoredSettings.downloadConcurrency, 3);
  });

  test('导出内容里没有凭据字段', () {
    final encoded = PrefsBackup.of(reader: reader, settings: settings).encode();
    final lower = encoded.toLowerCase();
    // 这几个词出现在备份里就说明有人把登录信息塞进来了。
    for (final forbidden in <String>[
      'apikey',
      'api_key',
      'password',
      'token',
      'secret',
      'authorization',
    ]) {
      expect(lower.contains(forbidden), isFalse, reason: '不该出现 $forbidden');
    }
    // 邮箱/服务器地址也不该在。
    expect(lower.contains('@'), isFalse);
    expect(lower.contains('http'), isFalse);
  });

  test('坏 JSON：报错而不是静默接受', () {
    expect(
      () => PrefsBackup.decode('{not json'),
      throwsA(isA<PrefsBackupException>()),
    );
    expect(
      () => PrefsBackup.decode('[]'),
      throwsA(isA<PrefsBackupException>()),
    );
  });

  test('缺 version / 版本不兼容：拒绝', () {
    expect(
      () => PrefsBackup.decode(
        jsonEncode(<String, Object?>{
          'reader': <String, Object?>{},
          'settings': <String, Object?>{},
        }),
      ),
      throwsA(isA<PrefsBackupException>()),
    );
    expect(
      () => PrefsBackup.decode(
        jsonEncode(<String, Object?>{
          'version': kPrefsBackupVersion + 1,
          'reader': <String, Object?>{},
          'settings': <String, Object?>{},
        }),
      ),
      throwsA(isA<PrefsBackupException>()),
    );
  });

  test('缺段：拒绝', () {
    expect(
      () => PrefsBackup.decode(
        jsonEncode(<String, Object?>{'version': kPrefsBackupVersion}),
      ),
      throwsA(isA<PrefsBackupException>()),
    );
  });

  test('字段类型乱写不会崩，回默认值', () {
    final backup = PrefsBackup.decode(
      jsonEncode(<String, Object?>{
        'version': kPrefsBackupVersion,
        'reader': <String, Object?>{'mode': 'nonsense', 'brightness': 'x'},
        'settings': <String, Object?>{'language': 42, 'view': 'nope'},
      }),
    );
    // 解析得出（不抛），坏字段回默认。
    expect(backup.toReaderPrefs().global.mode, isA<ReaderModeChoice>());
    expect(backup.toAppSettings().language, isA<String>());
    expect(backup.toAppSettings().view, isA<ShelfView>());
  });
}
